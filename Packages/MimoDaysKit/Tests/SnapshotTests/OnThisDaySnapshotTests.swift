@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// On this day (M14).
@MainActor
@Suite(.tags(.snapshot))
struct OnThisDaySnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store: MediaStore

    /// The view's `.task` can still run after a test returns; its store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "OnThisDaySnapshots-\(UUID().uuidString)"))
        Self.stores.append(container)
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func model(_ moments: [(year: Int, caption: String)]) async throws -> OnThisDayModel {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: TestDateProvider(), freeBytes: { nil })
        for moment in moments {
            let date = Self.utc.date(from: DateComponents(year: moment.year, month: 11, day: 11, hour: 12))!
            let capture = CaptureResult(
                media: .photo(try await engine.capturePhoto(flash: false, silent: true)), window: .init(),
                capturedAt: CaptureTime(instant: date, timeZone: .gmt)
            )
            let draft = MomentDraft(
                capture: capture, caption: moment.caption,
                window: SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536)),
                promptID: nil
            )
            _ = try await saver.save(draft)
        }
        let now = Self.utc.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))!
        let model = OnThisDayModel(library: library, clock: TestDateProvider(now), calendar: Self.utc)
        await model.refresh()
        return model
    }

    /// M14.
    @Test func years() async throws {
        let model = try await model([(2025, "First day at the new school"), (2023, "Rainy walk, muddy boots")])
        assertScreenSnapshots(of: NavigationStack { OnThisDayView(model: model) }, variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true), SnapshotVariant(.iPad, .light),
        ])
    }

    @Test func empty() async throws {
        let model = try await model([])
        assertScreenSnapshots(of: NavigationStack { OnThisDayView(model: model) }, variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }
}
