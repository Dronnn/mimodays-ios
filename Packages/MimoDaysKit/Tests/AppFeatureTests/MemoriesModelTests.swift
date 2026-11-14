@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// Memories (M01): grouping by each moment's own local day, and what a tile reads.
@MainActor
struct MemoriesModelTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store = try! MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Memories-\(UUID().uuidString)"))
    private let clock = TestDateProvider()

    private var context: ModelContext { container.mainContext }

    init() {
        clock.set(Self.date(2026, 11, 11, 14, 40))
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @discardableResult
    private func save(at date: Date, zone: String = "UTC", video: Bool = false) async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let media: CaptureResult.Media = video
            ? .video(try await engine.record(limit: .seconds(1)))
            : .photo(try await engine.capturePhoto(flash: false, silent: true))
        let capture = CaptureResult(media: media, window: .init(), capturedAt: CaptureTime(instant: date, timeZone: TimeZone(identifier: zone)!))
        let saver = MomentSaver(context: context, store: store, clock: clock, freeBytes: { nil })
        return try await saver.save(MomentDraft(capture: capture, caption: "", window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)), promptID: nil, place: nil)).id
    }

    private func model() -> MemoriesModel {
        let model = MemoriesModel(context: context, store: store, thumbnails: ThumbnailPipeline(), clock: clock, calendar: { Self.utc })
        model.refresh()
        return model
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private func item(_ day: Int, _ hour: Int = 12) -> MemoryItem {
        MemoryItem(
            id: UUID(), localDay: day, capturedAt: Self.date(day / 10_000, day / 100 % 100, day % 100, hour),
            timeZoneID: "UTC", mediaType: .photo, origin: .manual, isFavorite: false
        )
    }

    @Test func rowsAreMonthsThenTheirDaysNewestFirst() {
        let items = [item(20261111, 14), item(20261111, 9), item(20261109), item(20261031), item(20251111)]
        let rows = MemoriesModel.rows(items)
        #expect(rows.map(\.id) == [202611, 20261111, 20261109, 202610, 20261031, 202511, 20251111])
        #expect(rows.first == .month(202611, count: 3))
        #expect(rows[1] == .day(20261111, Array(items[0...1])))
        #expect(MemoriesModel.rows([]).isEmpty)
    }

    @Test func anEmptyArchiveSaysSoOnlyOnceLoaded() {
        let model = MemoriesModel(context: context, store: store, thumbnails: ThumbnailPipeline(), clock: clock, calendar: { Self.utc })
        #expect(!model.isEmpty)
        model.refresh()
        #expect(model.isEmpty)
    }

    /// 11 PM in Los Angeles on Nov 10 is Nov 11 in UTC; it stays on Nov 10, where it was taken.
    @Test func aMomentStaysOnTheDayWhereItWasTaken() async throws {
        let late = try await save(at: Self.date(2026, 11, 11, 7), zone: "America/Los_Angeles")
        let morning = try await save(at: Self.date(2026, 11, 11, 9))
        let rows = model().rows
        #expect(rows.map(\.id) == [202611, 20261111, 20261110])
        guard case let .day(_, nov11) = rows[1], case let .day(_, nov10) = rows[2] else { Issue.record("rows"); return }
        #expect(nov11.map(\.id) == [morning] && nov10.map(\.id) == [late])
    }

    @Test func deletedMomentsAreLeftOut() async throws {
        let kept = try await save(at: Self.date(2026, 11, 9))
        let deleted = try await save(at: Self.date(2026, 11, 11))
        try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == deleted })).first?.deletedAt = clock.now()
        try context.save()
        let rows = model().rows
        #expect(rows.count == 2 && rows.first == .month(202611, count: 1))
        guard case let .day(day, items) = rows.last else { Issue.record("rows"); return }
        #expect(day == 20261109 && items.map(\.id) == [kept])
    }

    @Test func aTileReadsItsThumbnailLengthAndVoiceNote() async throws {
        let photo = try await save(at: Self.date(2026, 11, 9))
        let video = try await save(at: Self.date(2026, 11, 10), video: true)
        let model = model()
        await model.load(photo)
        await model.load(video)
        #expect(model.details[photo] == TileDetail(thumbnailPath: model.details[photo]?.thumbnailPath, duration: nil, hasVoiceNote: false))
        #expect(model.details[photo]?.thumbnailPath != nil && model.images[photo] != nil)
        #expect((model.details[video]?.duration ?? 0) > 0.5)
        #expect(model.images[video] != nil)
    }

    @Test func favoritesAreMarkedOnTheirItems() async throws {
        let id = try await save(at: Self.date(2026, 11, 9))
        try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first?.isFavorite = true
        try context.save()
        guard case let .day(_, items) = model().rows.last else { Issue.record("rows"); return }
        #expect(items.first?.isFavorite == true)
    }

    /// M10: favourites only, newest first, across months.
    @Test func favoritesListOnlyHeartsInTimelineOrder() async throws {
        let older = try await save(at: Self.date(2026, 10, 2))
        try await save(at: Self.date(2026, 11, 1))
        let newer = try await save(at: Self.date(2026, 11, 9))
        #expect(model().favorites.isEmpty)
        for moment in try context.fetch(FetchDescriptor<Moment>()) where [older, newer].contains(moment.id) {
            moment.isFavorite = true
        }
        try context.save()
        #expect(model().favorites.map(\.id) == [newer, older])
    }

    // MARK: Select (M13)

    @Test func selectedMomentsGoToRecentlyDeletedTogether() async throws {
        let a = try await save(at: Self.date(2026, 10, 2))
        let b = try await save(at: Self.date(2026, 11, 1), video: true)
        let c = try await save(at: Self.date(2026, 11, 9))
        let model = model()
        #expect(model.mediaType(of: [b]) == .video && model.mediaType(of: [a]) == .photo && model.mediaType(of: [a, b]) == nil)
        #expect(model.movieDrafts(using: [a, b]) == 0)
        #expect(model.delete([a, b]))
        model.refresh()
        #expect(model.allIDs == [c])
        #expect(try context.fetchCount(FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt != nil })) == 2)
    }

    @Test func selectedMomentsJoinEachChosenCollectionInTimelineOrder() async throws {
        let older = try await save(at: Self.date(2026, 10, 2))
        let newer = try await save(at: Self.date(2026, 11, 9))
        let collections = CollectionStore(context: context)
        let walks = try #require(try collections.create("Walks"))
        let firsts = try #require(try collections.create("Firsts", with: [older]))
        model().collect([older, newer], into: [walks, firsts])
        #expect(try collections.collection(walks)?.orderedMoments.map(\.id) == [newer, older])
        #expect(try collections.collection(firsts)?.orderedMoments.map(\.id) == [older, newer])
    }

    // MARK: Calendar

    @Test func monthsAddAcrossYears() {
        #expect(MemoriesModel.month(202611, adding: 1) == 202612)
        #expect(MemoriesModel.month(202612, adding: 1) == 202701)
        #expect(MemoriesModel.month(202601, adding: -1) == 202512)
        #expect(MemoriesModel.month(202611, adding: -23) == 202412)
    }

    @Test func theCalendarOpensOnTodayAndStaysBetweenTheFirstMomentAndNow() async throws {
        try await save(at: Self.date(2026, 9, 14))
        try await save(at: Self.date(2026, 9, 20))
        let model = model()
        #expect(model.shownMonth == 202611 && model.selectedDay == 20261111)
        #expect(model.earliestMonth == 202609 && !model.canGoForward && model.canGoBack)
        model.step(-1)
        model.step(-1)
        // September: its newest day with moments is chosen.
        #expect(model.shownMonth == 202609 && model.selectedDay == 20260920 && !model.canGoBack)
        model.step(-1)
        #expect(model.shownMonth == 202609)
        model.show(month: 202703)
        #expect(model.shownMonth == 202611)
    }

    @Test func theYearOpensAMonth() async throws {
        try await save(at: Self.date(2025, 3, 2))
        let model = model()
        model.show(year: 2026)
        #expect(model.scale == .year && model.canGoBack && !model.canGoForward)
        model.step(-1)
        #expect(model.shownYear == 2025 && !model.canGoBack)
        model.show(month: 202503)
        #expect(model.scale == .month && model.selectedDay == 20250302 && model.days[20250302]?.count == 1)
    }

    /// 9.15: pinching closed shows the month's year; open, the month again - or a year's first month after
    /// stepping to another year.
    @Test func pinchingMovesBetweenAMonthAndItsYear() async throws {
        try await save(at: Self.date(2025, 3, 2))
        let model = model()
        model.zoomIn()
        #expect(model.scale == .month && model.shownMonth == 202611)
        model.zoomOut()
        #expect(model.scale == .year && model.shownYear == 2026)
        model.zoomOut()
        #expect(model.scale == .year)
        model.zoomIn()
        #expect(model.scale == .month && model.shownMonth == 202611)
        model.zoomOut()
        model.step(-1)
        model.zoomIn()
        #expect(model.scale == .month && model.shownMonth == 202503)
    }

    @Test func aDayListsItsMomentsOldestFirstWithItsPlaces() async throws {
        let morning = try await save(at: Self.date(2026, 11, 11, 8))
        let evening = try await save(at: Self.date(2026, 11, 11, 18))
        try await save(at: Self.date(2026, 11, 10))
        let day = model().dayModel(20261111)
        await day.refresh()
        #expect(day.moments.map(\.id) == [morning, evening])
        #expect(day.places.isEmpty)
        #expect(day.image(day.moments.first?.mainPath) != nil)
    }
}
