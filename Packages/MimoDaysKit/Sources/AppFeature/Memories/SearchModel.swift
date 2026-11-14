import Core
import Foundation
import Observation
import os
import Persistence
import SwiftData
import UIKit

/// M08b: what narrows the search. Days are yyyymmdd in each moment's own zone, like the timeline (§H20).
struct SearchFilters: Equatable {
    enum Kind: Hashable {
        case all
        case photos
        case videos
    }

    var kind = Kind.all
    var from: Int?
    var to: Int?
    var hasVoiceNote = false
    var hasWrittenNote = false
    var favoritesOnly = false
    /// A place picked from the Places section.
    var place: String?

    /// "Filters · N".
    var count: Int {
        [kind != .all, from != nil, to != nil, hasVoiceNote, hasWrittenNote, favoritesOnly, place != nil].filter(\.self).count
    }

    var isEmpty: Bool { count == 0 }
}

/// One moment as search reads it: the timeline item and every word it can be found by.
struct SearchEntry: Equatable {
    var item: MemoryItem
    var caption: String?
    var note: String?
    var transcript: String?
    var place: String?
    var hasVoiceNote: Bool
}

/// Where the words were found, in the order a row names it.
enum SearchField: Equatable {
    case caption
    case note
    case voiceNote
    case place
}

/// A row in M08's Moments: the moment, what to show of it and where it matched (nil when only filters apply).
struct SearchHit: Equatable, Identifiable {
    var entry: SearchEntry
    var text: String?
    var field: SearchField?

    var id: UUID { entry.item.id }
}

/// A row in M08's Places: a place whose name matches, how many moments it has and the year it was last visited.
struct PlaceHit: Equatable, Identifiable {
    var label: String
    var count: Int
    var latestYear: Int

    var id: String { label }
}

/// M08/M09: offline search over captions, notes, voice-note words and places, then filters (M08b).
/// Every word typed has to be found somewhere in the moment.
@MainActor
@Observable
final class SearchModel {
    var query = ""
    var filters = SearchFilters()
    private(set) var entries: [SearchEntry] = []
    private(set) var isLoaded = false
    private(set) var images: [UUID: UIImage] = [:]

    private let library: MediaLibrary
    private let clock: any DateProvider
    private let calendar: () -> Calendar
    private var imageOrder: [UUID] = []
    private let logger = Logger(subsystem: "MimoDays", category: "Search")

    init(library: MediaLibrary, clock: any DateProvider = SystemDateProvider(), calendar: @escaping () -> Calendar = { .current }) {
        self.library = library
        self.clock = clock
        self.calendar = calendar
    }

    /// Dates in this year leave the year out.
    var thisYear: Int { LocalDay(clock.now(), in: calendar().timeZone).key / 10_000 }

    /// Something to look for: words or a filter.
    var isSearching: Bool { !Self.words(query).isEmpty || !filters.isEmpty }

    var hits: [SearchHit] { isSearching ? Self.hits(entries, query: query, filters: filters) : [] }

    var places: [PlaceHit] { Self.places(entries, query: query, filters: filters) }

    /// Moments the current filters leave, before any words (M08b's "Show N moments").
    var filteredCount: Int { entries.count(where: { Self.passes($0, filters) }) }

    /// Every moment, newest first, with its words. Three flat reads instead of a fault per moment.
    func refresh() {
        var descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [
            \.id, \.localDay, \.capturedAt, \.timeZoneID, \.mediaTypeRaw, \.originRaw, \.isFavorite, \.title, \.note,
        ]
        do {
            let moments = try library.context.fetch(descriptor)
            var places: [UUID: String] = [:]
            for location in try library.context.fetch(FetchDescriptor<MomentLocation>(predicate: #Predicate { $0.placeLabel != nil })) {
                if let id = location.moment?.id { places[id] = location.placeLabel }
            }
            var voices: [UUID: String] = [:]
            for voice in try library.context.fetch(FetchDescriptor<MomentVoiceNote>()) {
                if let id = voice.moment?.id { voices[id] = voice.transcript ?? "" }
            }
            entries = moments.map { moment in
                SearchEntry(
                    item: MemoryItem(
                        id: moment.id, localDay: moment.localDay, capturedAt: moment.capturedAt, timeZoneID: moment.timeZoneID,
                        mediaType: moment.mediaType, origin: moment.origin, isFavorite: moment.isFavorite
                    ),
                    caption: moment.title, note: moment.note,
                    transcript: voices[moment.id].flatMap { $0.isEmpty ? nil : $0 },
                    place: places[moment.id], hasVoiceNote: voices[moment.id] != nil
                )
            }
        } catch {
            logger.error("Reading moments for search failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoaded = true
    }

    /// A Places row: its moments, without the words that found it.
    func show(place: String) {
        filters.place = place
        query = ""
    }

    /// M09's "Search all moments": the words stay, the filters go.
    func clearFilters() {
        filters = SearchFilters()
    }

    /// The row's picture, once.
    func load(_ id: UUID) async {
        guard images[id] == nil else { return }
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let moment = try? library.context.fetch(descriptor).first,
              let path = moment.media.first(where: { $0.role == .thumbnail })?.relativePath,
              let url = try? library.store.url(for: path),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: MemoriesModel.tilePixels) else { return }
        images[id] = UIImage(cgImage: image)
        imageOrder.append(id)
        if imageOrder.count > MemoriesModel.imageLimit { images[imageOrder.removeFirst()] = nil }
    }

    // MARK: Matching

    static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func passes(_ entry: SearchEntry, _ filters: SearchFilters) -> Bool {
        switch filters.kind {
        case .all: break
        case .photos: if entry.item.mediaType != .photo { return false }
        case .videos: if entry.item.mediaType != .video { return false }
        }
        if let from = filters.from, entry.item.localDay < from { return false }
        if let to = filters.to, entry.item.localDay > to { return false }
        if filters.hasVoiceNote, !entry.hasVoiceNote { return false }
        if filters.hasWrittenNote, entry.note?.isEmpty ?? true { return false }
        if filters.favoritesOnly, !entry.item.isFavorite { return false }
        if let place = filters.place, entry.place != place { return false }
        return true
    }

    /// Moments with every word somewhere, newest first, each with the first field the first word is in.
    static func hits(_ entries: [SearchEntry], query: String, filters: SearchFilters) -> [SearchHit] {
        let words = words(query)
        return entries.compactMap { entry in
            guard passes(entry, filters) else { return nil }
            let fields: [(SearchField, String?)] = [
                (.caption, entry.caption), (.note, entry.note), (.voiceNote, entry.transcript), (.place, entry.place),
            ]
            guard let first = words.first else {
                return SearchHit(entry: entry, text: entry.caption ?? entry.note.map { snippet($0, around: nil) }, field: nil)
            }
            for word in words where !fields.contains(where: { $0.1.map { contains($0, word) } ?? false }) { return nil }
            guard let field = fields.first(where: { $0.1.map { contains($0, first) } ?? false }) else { return nil }
            let text: String? = switch field.0 {
            case .caption: entry.caption
            case .note: entry.note.map { snippet($0, around: first) }
            case .voiceNote: entry.transcript.map { "“" + snippet($0, around: first) + "”" }
            case .place: entry.caption ?? entry.note.map { snippet($0, around: nil) } ?? entry.place
            }
            return SearchHit(entry: entry, text: text, field: field.0)
        }
    }

    /// Places whose name has every word, the most visited first, among moments the filters leave.
    static func places(_ entries: [SearchEntry], query: String, filters: SearchFilters) -> [PlaceHit] {
        let words = words(query)
        guard !words.isEmpty, filters.place == nil else { return [] }
        var byLabel: [String: PlaceHit] = [:]
        for entry in entries where passes(entry, filters) {
            guard let label = entry.place, words.allSatisfy({ contains(label, $0) }) else { continue }
            let year = entry.item.localDay / 10_000
            var hit = byLabel[label] ?? PlaceHit(label: label, count: 0, latestYear: year)
            hit.count += 1
            hit.latestYear = max(hit.latestYear, year)
            byLabel[label] = hit
        }
        return byLabel.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
    }

    /// Ignores case and accents, as people type them.
    static func contains(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The text from a little before the word, with "…" where it was cut.
    static func snippet(_ text: String, around word: String?, lead: Int = 24) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard let word, let range = flat.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]),
              flat.distance(from: flat.startIndex, to: range.lowerBound) > lead else { return flat }
        var start = flat.index(range.lowerBound, offsetBy: -lead)
        // Start on a word, not inside one.
        if let space = flat[start..<range.lowerBound].firstIndex(of: " ") { start = flat.index(after: space) }
        return "…" + flat[start...]
    }
}
