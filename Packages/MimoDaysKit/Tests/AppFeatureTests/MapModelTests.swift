@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 10.x Map: located moments, grouped into places, narrowed by P04's filters.
@MainActor
struct MapModelTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Map-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// A bare moment straight in the store; the map reads only rows.
    @discardableResult
    private func insert(
        _ date: Date, at coordinate: (Double, Double)?, place: String? = nil, video: Bool = false, favorite: Bool = false
    ) throws -> UUID {
        let moment = Moment(capturedAt: date, timeZoneID: "UTC", localDay: LocalDay(date, in: .gmt).key, origin: .manual, mediaType: video ? .video : .photo)
        moment.isFavorite = favorite
        context.insert(moment)
        if let coordinate {
            moment.location = MomentLocation(latitude: coordinate.0, longitude: coordinate.1, precision: .exact, source: .gps, placeLabel: place)
        } else if let place {
            moment.location = MomentLocation(latitude: nil, longitude: nil, precision: .city, source: .manual, placeLabel: place)
        }
        try context.save()
        return moment.id
    }

    private func model() -> MapModel {
        let model = MapModel(library: library)
        model.refresh()
        return model
    }

    @Test func onlyAliveMomentsWithCoordinatesAreOnTheMap() throws {
        let located = try insert(Self.date(2026, 11, 1), at: (40.18, 44.51), place: "Yerevan")
        try insert(Self.date(2026, 11, 2), at: nil)
        try insert(Self.date(2026, 11, 3), at: nil, place: "Somewhere typed")
        let gone = try insert(Self.date(2026, 11, 4), at: (40.18, 44.51), place: "Yerevan")
        try DeletionStore(context: context, store: store).moveToRecentlyDeleted([gone])

        let model = model()
        #expect(model.moments.map(\.id) == [located])
        #expect(model.unlocatedCount == 2)
        #expect(model.hasLocatedMoments && model.isLoaded)
    }

    @Test func placesGroupByNameElseByNearbyCellMostMomentsFirst() throws {
        let old = try insert(Self.date(2024, 3, 1), at: (40.180, 44.510), place: "Yerevan")
        let new = try insert(Self.date(2026, 11, 1), at: (40.200, 44.530), place: "yerevan")
        let lakeA = try insert(Self.date(2025, 6, 1), at: (37.8044, -122.2590))
        let lakeB = try insert(Self.date(2025, 6, 2), at: (37.8046, -122.2588))
        let far = try insert(Self.date(2025, 6, 3), at: (37.90, -122.30))

        let places = model().places
        #expect(places.count == 3)
        #expect(places[0].moments.map(\.id) == [new, old] && places[0].label?.lowercased() == "yerevan")
        #expect(places[1].moments.map(\.id) == [lakeB, lakeA] && places[1].label == nil)
        #expect(places[2].moments.map(\.id) == [far])
        #expect(places[0].span.first == 20240301 && places[0].span.last == 20261101)
        #expect(abs(places[1].coordinate.latitude - 37.8045) < 0.0001)
    }

    @Test func filtersNarrowByKindDaysFavouritesAndCollection() throws {
        let photo = try insert(Self.date(2025, 1, 10), at: (40.18, 44.51), favorite: true)
        let video = try insert(Self.date(2026, 5, 10), at: (40.18, 44.51), video: true)
        let late = try insert(Self.date(2026, 11, 10), at: (41.0, 45.0))
        let collection = try #require(try CollectionStore(context: context).create("Trips", with: [video, late]))

        let model = model()
        model.filters.kind = .videos
        #expect(model.filtered.map(\.id) == [video])
        model.filters = MapFilters(from: 20260101)
        #expect(model.filtered.map(\.id) == [late, video])
        model.filters = MapFilters(to: 20251231)
        #expect(model.filtered.map(\.id) == [photo])
        model.filters = MapFilters(favoritesOnly: true)
        #expect(model.filtered.map(\.id) == [photo])
        model.filters = MapFilters(collection: collection)
        #expect(model.filtered.map(\.id) == [late, video])
        #expect(model.filters.count == 1)
        model.filters = MapFilters()
        #expect(model.filtered.count == 3 && model.filters.isEmpty)
    }

    /// P05b: only moments without coordinates (a name alone isn't a place on the map); a chosen place goes to the
    /// ticked ones, which then join the map, and the choice is forgotten.
    @Test func momentsWithoutAPlaceGetOneByHand() throws {
        let located = try insert(Self.date(2026, 11, 1), at: (40.18, 44.51), place: "Yerevan")
        let bare = try insert(Self.date(2026, 11, 2), at: nil)
        let named = try insert(Self.date(2026, 11, 3), at: nil, place: "Grandma's")
        let other = try insert(Self.date(2026, 11, 4), at: nil)
        let unplaced = UnplacedModel(library: library, places: .simulated)
        unplaced.refresh()
        #expect(unplaced.items.map(\.id) == [other, named, bare])
        #expect(!unplaced.items.contains { $0.id == located })

        #expect(!unplaced.applyChosenPlace(to: [bare]))
        unplaced.choose(ReviewPlace(label: "Lake Merritt", latitude: 37.80, longitude: -122.26, precision: .exact, source: .manual))
        #expect(unplaced.applyChosenPlace(to: [bare, named]))
        #expect(unplaced.items.map(\.id) == [other])
        #expect(unplaced.place == nil && !unplaced.placeWasChosen)
        let map = model()
        #expect(map.place(map.places.first { $0.label == "Lake Merritt" }?.id ?? "")?.moments.count == 2)
    }
}
