@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 7.4: the place (C11). City level by default, never the exact fix; a pick always wins over a late fix.
@MainActor
struct PlaceTests {
    /// No city name comes back, as when offline.
    private struct OfflineLookup: PlaceLookup {
        func city(at _: GeoPoint) async -> String? { nil }
        func nearby(_: GeoPoint) async -> [PlaceSuggestion] { [] }
        func search(_: String, near _: GeoPoint?) async -> [PlaceSuggestion] { [] }
    }

    private let time = CaptureTime(instant: Date(timeIntervalSince1970: 1_794_407_820), timeZoneID: "Asia/Yerevan")
    private let fix = GeoPoint(latitude: 40.181112, longitude: 44.513617, horizontalAccuracy: 12)

    private func capture() async throws -> CaptureResult {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        return CaptureResult(media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(), capturedAt: time)
    }

    private func places(location: GeoPoint? = nil, lookup: any PlaceLookup = SimulatedPlaceLookup(), recents: [RecentPlace] = []) -> PlaceServices {
        PlaceServices(location: FakeLocationProvider(location: location), lookup: lookup, recents: { recents })
    }

    @Test func aNewCaptureTakesTheCityRoundedToAboutAKilometre() async throws {
        let review = ReviewModel(capture: try await capture(), places: places(location: fix))
        defer { review.discard() }
        await review.locate()
        let place = try #require(review.place)
        #expect(place == review.currentPlace)
        #expect(place.label == "Yerevan" && place.precision == .city && place.source == .gps)
        #expect(place.latitude == 40.18 && place.longitude == 44.51)
        #expect(!review.placeWasChosen)
    }

    @Test func offlineKeepsTheRoundedPointWithoutAName() async throws {
        let review = ReviewModel(capture: try await capture(), places: places(location: fix, lookup: OfflineLookup()))
        defer { review.discard() }
        await review.locate()
        #expect(review.place?.label == nil && review.place?.latitude == 40.18)
    }

    @Test func noFixMeansNoPlace() async throws {
        let review = ReviewModel(capture: try await capture(), places: places(location: nil))
        defer { review.discard() }
        await review.locate()
        #expect(review.place == nil && review.currentPlace == nil)
    }

    @Test func aPickBeforeTheFixIsKept() async throws {
        let review = ReviewModel(capture: try await capture(), places: places(location: fix))
        defer { review.discard() }
        review.choose(nil)
        await review.locate()
        #expect(review.place == nil && review.placeWasChosen)
        #expect(review.currentPlace?.label == "Yerevan")
    }

    @Test func aPlacePickedByNameIsWhereThatPlaceIs() async throws {
        let review = ReviewModel(capture: try await capture(), places: places(location: fix))
        defer { review.discard() }
        await review.locate()
        await review.loadNearby()
        let cascade = try #require(review.nearby.first)
        review.choose(.picked(cascade))
        #expect(review.place?.label == "Cascade Complex" && review.place?.source == .manual && review.place?.precision == .exact)
        #expect(review.place?.latitude == cascade.latitude)
        #expect(await review.searchPlaces("sevan").map(\.name) == ["Lake Sevan"])
    }

    @Test func aRestoredReviewKeepsItsPlaceAndDoesNotLookAgain() async throws {
        let drafts = ReviewDraftStore(root: FileManager.default.temporaryDirectory.appending(path: "PlaceTests-\(UUID().uuidString)"))
        defer { drafts.clear() }
        let review = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts, places: places(location: fix))
        review.choose(nil)

        let restored = ReviewModel(draft: try #require(drafts.load()), drafts: drafts, places: places(location: fix))
        #expect(restored.place == nil && restored.placeWasChosen)

        // Nothing picked: a relaunch elsewhere doesn't fill in where the iPhone is now.
        let untouched = ReviewModel(capture: try drafts.adopt(try await capture()), drafts: drafts, places: places(location: fix))
        let relaunched = ReviewModel(draft: try #require(drafts.load()), drafts: drafts, places: places(location: fix))
        await relaunched.locate()
        #expect(relaunched.place == nil && relaunched.currentPlace != nil)
        untouched.discard()
    }

    @Test func savingWritesTheLocationAsChosen() async throws {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        let store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "PlaceTests-media-\(UUID().uuidString)"))
        let review = ReviewModel(capture: try await capture(), places: places(location: fix))
        await review.locate()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        let moment = try await saver.save(review.momentDraft)
        let location = try #require(moment.location)
        #expect(location.placeLabel == "Yerevan" && location.precision == .city && location.source == .gps)
        #expect(location.latitude == 40.18 && location.longitude == 44.51)

        let none = ReviewModel(capture: try await capture(), places: places(location: fix))
        none.choose(nil)
        #expect(try await saver.save(none.momentDraft).location == nil)
    }

    @Test func recentPlacesAreTheMostUsedNamedOnes() throws {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        let context = container.mainContext
        func moment(_ label: String?, day: Double) {
            let moment = Moment(captured: CaptureTime(instant: Date(timeIntervalSince1970: day * 86_400), timeZone: .gmt), origin: .manual, mediaType: .photo, createdAt: .now)
            context.insert(moment)
            moment.location = MomentLocation(latitude: 40.2, longitude: 44.5, precision: .city, source: .gps, placeLabel: label)
        }
        moment("Grandma's house", day: 1)
        moment("Grandma's house", day: 2)
        moment("Yerevan", day: 5)
        moment("Lake Sevan", day: 3)
        moment(nil, day: 6)
        try context.save()
        let recents = RecentPlace.load(from: context, limit: 3)
        #expect(recents.map(\.id) == ["Grandma's house", "Yerevan", "Lake Sevan"])
        #expect(recents.first?.uses == 2)
    }
}
