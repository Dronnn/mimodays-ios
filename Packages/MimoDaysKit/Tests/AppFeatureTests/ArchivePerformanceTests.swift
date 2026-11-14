@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 9.12: Memories, search and On this day stay quick on a 10,000-moment archive (about 27 years of a moment a day).
/// Budgets are generous so a slow CI machine passes; a regression to per-moment faulting blows far past them.
@MainActor
@Suite(.timeLimit(.minutes(2)))
struct ArchivePerformanceTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore
    private static let count = 10_000
    private static let places = ["Yerevan", "Lake Merritt", "Grandma's garden", "Tbilisi", "The beach", "School"]
    private static let captions = ["First snow", "Walk to school", "Pancakes", "Rainy walk, muddy boots", "Birthday", "Lena laughing"]

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Archive-\(UUID().uuidString)"))
        try seed()
    }

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static let now = utc.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!

    /// One moment a day going back from today; every third has a place, every fourth a caption, every tenth a heart.
    private func seed() throws {
        for index in 0..<Self.count {
            let date = Self.now.addingTimeInterval(-Double(index) * 86_400 - 3_600)
            let moment = Moment(
                capturedAt: date, timeZoneID: "UTC", localDay: LocalDay(date, in: .gmt).key,
                origin: index % 5 == 0 ? .randomPrompt : .manual, mediaType: index % 7 == 0 ? .video : .photo
            )
            if index % 4 == 0 { moment.title = Self.captions[index / 4 % Self.captions.count] }
            if index % 10 == 0 { moment.isFavorite = true }
            context.insert(moment)
            if index % 3 == 0 {
                moment.location = MomentLocation(
                    latitude: 40.18, longitude: 44.51, precision: .city, source: .gps, placeLabel: Self.places[index / 3 % Self.places.count]
                )
            }
        }
        try context.save()
    }

    private func time(_ work: () -> Void) -> Duration {
        ContinuousClock().measure(work)
    }

    @Test func memoriesTimelineReadsTheArchive() {
        let model = MemoriesModel(context: context, store: store, thumbnails: ThumbnailPipeline(), clock: TestDateProvider(Self.now), calendar: { Self.utc })
        let elapsed = time { model.refresh() }
        #expect(model.allIDs.count == Self.count)
        #expect(elapsed < .seconds(5), "Memories refresh took \(elapsed)")
        let favorites = time { _ = model.favorites }
        #expect(favorites < .seconds(1), "Favorites took \(favorites)")
    }

    @Test func searchIndexesAndAnswersQuickly() {
        let model = SearchModel(library: library, clock: TestDateProvider(Self.now), calendar: { Self.utc })
        let indexing = time { model.refresh() }
        #expect(indexing < .seconds(5), "Search indexing took \(indexing)")
        model.query = "rainy muddy"
        var hits: [SearchHit] = []
        let answering = time { hits = model.hits }
        #expect(hits.count == (0..<Self.count).count { $0 % 4 == 0 && $0 / 4 % Self.captions.count == 3 })
        #expect(answering < .seconds(1), "Search took \(answering)")
        model.query = "lake"
        let places = time { _ = model.places }
        #expect(model.places.first?.label == "Lake Merritt")
        #expect(places < .seconds(1), "Places took \(places)")
    }

    @Test func onThisDayFindsEveryEarlierYear() async {
        let model = OnThisDayModel(library: library, clock: TestDateProvider(Self.now), calendar: Self.utc)
        let clock = ContinuousClock()
        let start = clock.now
        await model.refresh()
        let elapsed = clock.now - start
        #expect(model.years.count == 27)
        #expect(elapsed < .seconds(2), "On this day took \(elapsed)")
    }
}
