import Core
import CoreLocation
import Foundation
import Observation
import os
import Persistence
import SwiftData
import UIKit

/// One moment with a place on the map.
struct MapMoment: Equatable, Identifiable {
    var item: MemoryItem
    var latitude: Double
    var longitude: Double
    var place: String?

    var id: UUID { item.id }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// P04: what the map shows. Days are yyyymmdd in each moment's own zone, like the timeline (§H20).
struct MapFilters: Equatable {
    var kind = SearchFilters.Kind.all
    var from: Int?
    var to: Int?
    var favoritesOnly = false
    var collection: UUID?

    var count: Int { [kind != .all, from != nil, to != nil, favoritesOnly, collection != nil].filter(\.self).count }
    var isEmpty: Bool { count == 0 }

    /// P04's first switch.
    enum Period: Hashable {
        case allTime
        case thisYear
        case custom
    }

    func period(thisYear: Int) -> Period {
        switch (from, to) {
        case (nil, nil): .allTime
        case (thisYear * 10_000 + 101, nil): .thisYear
        default: .custom
        }
    }
}

/// Moments taken at one place: same place name, or (without one) within about a kilometre.
struct MapPlace: Equatable, Identifiable {
    var id: String
    var label: String?
    /// Newest first.
    var moments: [MapMoment]

    var coordinate: CLLocationCoordinate2D {
        let count = Double(moments.count)
        return CLLocationCoordinate2D(
            latitude: moments.map(\.latitude).reduce(0, +) / count,
            longitude: moments.map(\.longitude).reduce(0, +) / count
        )
    }

    /// First and last day, yyyymmdd.
    var span: (first: Int, last: Int) {
        (moments.map(\.item.localDay).min() ?? 0, moments.map(\.item.localDay).max() ?? 0)
    }
}

/// P01-P06: every alive moment with coordinates, grouped into places and narrowed by P04's filters.
@MainActor
@Observable
final class MapModel {
    private(set) var moments: [MapMoment] = []
    /// Alive moments without coordinates (P05 says how many).
    private(set) var unlocatedCount = 0
    private(set) var isLoaded = false
    private(set) var images: [UUID: UIImage] = [:]
    /// A video's length, read with its picture (P02's `Badge / Video`).
    private(set) var durations: [UUID: Double] = [:]
    var filters = MapFilters() {
        didSet { if filters.collection != oldValue.collection { readCollection() } }
    }

    let library: MediaLibrary
    private var collectionMembers: Set<UUID>?
    private let logger = Logger(subsystem: "MimoDays", category: "Map")

    init(library: MediaLibrary) {
        self.library = library
    }

    /// The moments the filters leave.
    var filtered: [MapMoment] { moments.filter { Self.passes($0, filters, members: collectionMembers) } }

    /// The filtered moments by place, the place with most moments first (the accessible list's order).
    var places: [MapPlace] { Self.places(filtered) }

    /// P01's Recent places: the place visited last first.
    var recentPlaces: [MapPlace] {
        places.sorted { ($0.moments.first?.item.capturedAt ?? .distantPast) > ($1.moments.first?.item.capturedAt ?? .distantPast) }
    }

    func place(_ id: String) -> MapPlace? { places.first { $0.id == id } }

    /// P04's "Show N moments" for filters not applied yet.
    func count(with filters: MapFilters) -> Int {
        let members = filters.collection == self.filters.collection ? collectionMembers : Self.members(of: filters.collection, in: library.context)
        return moments.count { Self.passes($0, filters, members: members) }
    }

    var hasLocatedMoments: Bool { !moments.isEmpty }

    func refresh() {
        var descriptor = FetchDescriptor<MomentLocation>(predicate: #Predicate { $0.latitude != nil && $0.longitude != nil })
        descriptor.relationshipKeyPathsForPrefetching = [\.moment]
        do {
            moments = try library.context.fetch(descriptor).compactMap { location -> MapMoment? in
                guard let moment = location.moment, moment.deletedAt == nil,
                      let latitude = location.latitude, let longitude = location.longitude else { return nil }
                return MapMoment(
                    item: MemoryItem(
                        id: moment.id, localDay: moment.localDay, capturedAt: moment.capturedAt, timeZoneID: moment.timeZoneID,
                        mediaType: moment.mediaType, origin: moment.origin, isFavorite: moment.isFavorite
                    ),
                    latitude: latitude, longitude: longitude, place: location.placeLabel
                )
            }
            .sorted { $0.item.capturedAt > $1.item.capturedAt }
            let alive = try library.context.fetchCount(FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt == nil }))
            unlocatedCount = alive - moments.count
            readCollection()
        } catch {
            logger.error("Reading the map failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoaded = true
    }

    /// The place's picture, once.
    func load(_ id: UUID) async {
        guard images[id] == nil else { return }
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let moment = try? library.context.fetch(descriptor).first else { return }
        if moment.mediaType == .video { durations[id] = moment.media.compactMap(\.duration).max() }
        guard let path = moment.media.first(where: { $0.role == .thumbnail })?.relativePath,
              let url = try? library.store.url(for: path),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: MemoriesModel.tilePixels) else { return }
        images[id] = UIImage(cgImage: image)
    }

    private func readCollection() {
        collectionMembers = Self.members(of: filters.collection, in: library.context)
    }

    private static func members(of collection: UUID?, in context: ModelContext) -> Set<UUID>? {
        guard let collection else { return nil }
        return Set((try? CollectionStore(context: context).collection(collection))?.orderedMoments.map(\.id) ?? [])
    }

    // MARK: Grouping

    static func passes(_ moment: MapMoment, _ filters: MapFilters, members: Set<UUID>?) -> Bool {
        switch filters.kind {
        case .all: break
        case .photos: guard moment.item.mediaType == .photo else { return false }
        case .videos: guard moment.item.mediaType == .video else { return false }
        }
        if let from = filters.from, moment.item.localDay < from { return false }
        if let to = filters.to, moment.item.localDay > to { return false }
        if filters.favoritesOnly, !moment.item.isFavorite { return false }
        if let members, !members.contains(moment.id) { return false }
        return true
    }

    /// Same name → one place; no name → the same ~1 km cell. Most moments first, then the most recent.
    static func places(_ moments: [MapMoment]) -> [MapPlace] {
        let groups = Dictionary(grouping: moments) { moment in
            if let place = moment.place, !place.isEmpty { return "name:" + place.lowercased() }
            return "cell:\((moment.latitude * 100).rounded()),\((moment.longitude * 100).rounded())"
        }
        return groups.map { key, moments in
            MapPlace(id: key, label: moments.first { $0.place?.isEmpty == false }?.place, moments: moments.sorted { $0.item.capturedAt > $1.item.capturedAt })
        }
        .sorted {
            $0.moments.count != $1.moments.count
                ? $0.moments.count > $1.moments.count
                : ($0.moments.first?.item.capturedAt ?? .distantPast) > ($1.moments.first?.item.capturedAt ?? .distantPast)
        }
    }
}
