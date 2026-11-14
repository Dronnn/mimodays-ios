import Core
import Foundation
import Observation
import os
import Persistence
import SwiftData
import UIKit

/// One moment in the grid: only what grouping and the tile's words need.
struct MemoryItem: Equatable, Identifiable {
    var id: UUID
    /// The day in the moment's own time zone, yyyymmdd (§H20).
    var localDay: Int
    var capturedAt: Date
    var timeZoneID: String
    var mediaType: MediaType
    var origin: MomentOrigin
    var isFavorite: Bool

    var captured: CaptureTime { CaptureTime(instant: capturedAt, timeZoneID: timeZoneID) }
}

/// What a tile shows beyond the item, read when the tile first appears.
struct TileDetail: Equatable {
    var thumbnailPath: String?
    /// Videos: the clip's length.
    var duration: Double?
    var hasVoiceNote: Bool
}

/// The timeline as rows: a month's title, then its days, newest first. Flat, so the list stays lazy
/// and a day can be the scroll anchor.
enum MemoryRow: Equatable, Identifiable {
    /// yyyymm and how many moments it holds.
    case month(Int, count: Int)
    /// yyyymmdd and its moments, newest first.
    case day(Int, [MemoryItem])

    var id: Int {
        switch self {
        case let .month(key, _): key
        case let .day(key, _): key
        }
    }
}

enum MemoriesMode: Hashable {
    case timeline
    case calendar
}

/// The calendar shows a month (M02) or a whole year of dots (M03).
enum CalendarScale: Hashable {
    case month
    case year
}

/// Memories (M01): every moment, grouped by month and by each moment's own local day.
/// Rows are light; tiles fetch their thumbnail, length and voice note when they appear.
@MainActor
@Observable
final class MemoriesModel {
    private(set) var rows: [MemoryRow] = []
    private(set) var isLoaded = false
    private(set) var details: [UUID: TileDetail] = [:]
    private(set) var images: [UUID: UIImage] = [:]
    /// The day row at the top. Kept while the app runs, so leaving and coming back finds the same place.
    var scrolledRow: Int?
    /// Moments by local day (yyyymmdd), newest first, for the calendar.
    private(set) var days: [Int: [MemoryItem]] = [:]
    var mode = MemoriesMode.timeline
    var scale = CalendarScale.month
    /// The month (yyyymm) or, at year scale, the year the calendar shows.
    private(set) var shownMonth: Int
    private(set) var shownYear: Int
    /// The day under the calendar, yyyymmdd.
    var selectedDay: Int?

    static let tilePixels = 360
    /// Decoded tiles kept at once; the oldest go first.
    static let imageLimit = 400

    private let context: ModelContext
    private let store: MediaStore
    private let thumbnails: ThumbnailPipeline
    private let clock: any DateProvider
    private let calendar: () -> Calendar
    private var imageOrder: [UUID] = []
    private var loading: Set<UUID> = []
    private let logger = Logger(subsystem: "MimoDays", category: "Memories")

    init(
        context: ModelContext, store: MediaStore, thumbnails: ThumbnailPipeline, clock: any DateProvider = SystemDateProvider(),
        calendar: @escaping () -> Calendar = { .current }
    ) {
        self.context = context
        self.store = store
        self.thumbnails = thumbnails
        self.clock = clock
        self.calendar = calendar
        let today = LocalDay(clock.now(), in: calendar().timeZone).key
        shownMonth = today / 100
        shownYear = today / 10_000
        selectedDay = today
    }

    var isEmpty: Bool { isLoaded && rows.isEmpty }
    /// Every moment in timeline order, for swiping in the viewer.
    private(set) var allIDs: [UUID] = []
    var now: Date { clock.now() }
    /// Today on this device, yyyymmdd.
    var today: Int { LocalDay(clock.now(), in: calendar().timeZone).key }
    var thisMonth: Int { today / 100 }
    /// The first month with a moment; the calendar goes no further back.
    var earliestMonth: Int { min(rows.last.map { $0.id > 999_999 ? $0.id / 100 : $0.id } ?? thisMonth, thisMonth) }

    func dayModel(_ day: Int) -> DayModel {
        DayModel(day: day, context: context, store: store, thumbnails: thumbnails)
    }

    var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: thumbnails) }

    // MARK: Calendar

    /// A month (yyyymm), with the day under it: today there, else its newest day with moments.
    func show(month: Int) {
        shownMonth = min(max(month, earliestMonth), thisMonth)
        shownYear = shownMonth / 100
        scale = .month
        selectedDay = shownMonth == thisMonth ? today : days.keys.filter { $0 / 100 == shownMonth }.max()
    }

    func show(year: Int) {
        shownYear = min(max(year, earliestMonth / 100), today / 10_000)
        scale = .year
    }

    var canGoBack: Bool { scale == .month ? shownMonth > earliestMonth : shownYear > earliestMonth / 100 }
    var canGoForward: Bool { scale == .month ? shownMonth < thisMonth : shownYear < today / 10_000 }

    func step(_ direction: Int) {
        switch scale {
        case .month: show(month: Self.month(shownMonth, adding: direction))
        case .year: show(year: shownYear + direction)
        }
    }

    /// yyyymm plus or minus whole months.
    static func month(_ key: Int, adding months: Int) -> Int {
        let index = (key / 100) * 12 + (key % 100 - 1) + months
        return (index / 12) * 100 + index % 12 + 1
    }

    func refresh() {
        var descriptor = FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.localDay, order: .reverse), SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.propertiesToFetch = [\.id, \.localDay, \.capturedAt, \.timeZoneID, \.mediaTypeRaw, \.originRaw, \.isFavorite]
        do {
            let items = try context.fetch(descriptor).map {
                MemoryItem(
                    id: $0.id, localDay: $0.localDay, capturedAt: $0.capturedAt, timeZoneID: $0.timeZoneID,
                    mediaType: $0.mediaType, origin: $0.origin, isFavorite: $0.isFavorite
                )
            }
            rows = Self.rows(items)
            days = Dictionary(grouping: items, by: \.localDay)
            allIDs = items.map(\.id)
        } catch {
            logger.error("Reading moments failed: \(error.localizedDescription, privacy: .public)")
        }
        // An edit can change a voice note or a video's length; tiles read them again.
        details = [:]
        isLoaded = true
    }

    /// Months, then days, from items sorted newest day first and newest first within a day.
    static func rows(_ items: [MemoryItem]) -> [MemoryRow] {
        var rows: [MemoryRow] = []
        var start = 0
        while start < items.count {
            let month = items[start].localDay / 100
            var end = start
            while end < items.count, items[end].localDay / 100 == month { end += 1 }
            rows.append(.month(month, count: end - start))
            var dayStart = start
            while dayStart < end {
                let day = items[dayStart].localDay
                var dayEnd = dayStart
                while dayEnd < end, items[dayEnd].localDay == day { dayEnd += 1 }
                rows.append(.day(day, Array(items[dayStart..<dayEnd])))
                dayStart = dayEnd
            }
            start = end
        }
        return rows
    }

    /// The tile's details and picture, once.
    func load(_ id: UUID) async {
        guard details[id] == nil || images[id] == nil, loading.insert(id).inserted else { return }
        defer { loading.remove(id) }
        let detail = details[id] ?? fetchDetail(id)
        guard let detail else { return }
        details[id] = detail
        guard images[id] == nil, let path = detail.thumbnailPath, let url = try? store.url(for: path),
              let image = try? await thumbnails.thumbnail(for: url, maxPixelSize: Self.tilePixels) else { return }
        images[id] = UIImage(cgImage: image)
        imageOrder.append(id)
        if imageOrder.count > Self.imageLimit { images[imageOrder.removeFirst()] = nil }
    }

    private func fetchDetail(_ id: UUID) -> TileDetail? {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let moment = try? context.fetch(descriptor).first else { return nil }
        return TileDetail(
            thumbnailPath: moment.media.first { $0.role == .thumbnail }?.relativePath,
            duration: moment.mediaType == .video ? moment.media.compactMap(\.duration).max() : nil,
            hasVoiceNote: !moment.voiceNotes.isEmpty
        )
    }
}
