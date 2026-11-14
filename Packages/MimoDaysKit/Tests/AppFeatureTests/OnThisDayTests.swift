@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 9.10 On this day (M14): today's month and day in every earlier year, nearest first, each year oldest first.
@MainActor
struct OnThisDayTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "OnThisDay-\(UUID().uuidString)"))
    }

    private var context: ModelContext { container.mainContext }
    private var library: MediaLibrary { MediaLibrary(context: context, store: store, thumbnails: ThumbnailPipeline()) }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func save(at date: Date) async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let capture = CaptureResult(
            media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
            capturedAt: CaptureTime(instant: date, timeZone: .gmt)
        )
        let draft = MomentDraft(
            capture: capture, caption: "",
            window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
            promptID: nil
        )
        return try await MomentSaver(context: context, store: store, clock: TestDateProvider(), freeBytes: { nil }).save(draft).id
    }

    private func model() -> OnThisDayModel {
        OnThisDayModel(library: library, clock: TestDateProvider(Self.date(2026, 11, 11, 15)), calendar: Self.utc)
    }

    @Test func earlierYearsNearestFirstEachOldestFirst() async throws {
        let older = try await save(at: Self.date(2023, 11, 11, 9))
        let evening = try await save(at: Self.date(2025, 11, 11, 19))
        let morning = try await save(at: Self.date(2025, 11, 11, 8))
        _ = try await save(at: Self.date(2026, 11, 11, 10))
        _ = try await save(at: Self.date(2025, 11, 10))
        let deleted = try await save(at: Self.date(2024, 11, 11))
        try DeletionStore(context: context, store: store).moveToRecentlyDeleted([deleted])

        let model = model()
        await model.refresh()
        #expect(model.years.map(\.year) == [2025, 2023])
        #expect(model.years.map(\.yearsAgo) == [1, 3])
        #expect(model.ids == [morning, evening, older])
        #expect(model.image(model.years.first?.moments.first?.mainPath) != nil)
    }

    @Test func nothingEarlierIsEmptyOnceLoaded() async throws {
        _ = try await save(at: Self.date(2026, 11, 11, 10))
        let model = model()
        #expect(!model.isLoaded)
        await model.refresh()
        #expect(model.isLoaded && model.years.isEmpty)
    }
}
