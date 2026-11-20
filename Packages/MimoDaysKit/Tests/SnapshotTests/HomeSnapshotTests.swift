@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// The home's two sides (U10, U13-U15): Today with its switch and page corner, and the Mosaic. Real moments from the
/// simulated camera, thumbnails decoded before the snapshot. The tab bar doesn't render offscreen (see Today).
@MainActor
@Suite(.tags(.snapshot))
struct HomeSnapshotTests {
    private let container = try! TestStore.container()
    private let store = try! MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "HomeSnapshots-\(UUID().uuidString)"))
    private let clock = TestDateProvider()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The views' `.task` refreshes can still run after a test returns; the store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() {
        clock.set(Self.date(2026, 11, 11, 15))
        container.mainContext.insert(SurpriseSchedule())
        Self.stores.append(container)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// `count` moments a day apart back from today; every fourth a favorite, the newest a video when asked.
    private func populate(_ count: Int, video: Bool = false) async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let saver = MomentSaver(context: container.mainContext, store: store, clock: clock, freeBytes: { nil })
        for index in 0..<count {
            let media: CaptureResult.Media = video && index == 0
                ? .video(try await engine.record(limit: .seconds(1)))
                : .photo(try await engine.capturePhoto(flash: .off, silent: true))
            let at = Self.date(2026, 11, 11, 14).addingTimeInterval(-Double(index) * 86_400 * 2.5)
            let capture = CaptureResult(media: media, window: .init(), capturedAt: CaptureTime(instant: at, timeZone: .gmt))
            let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))
            let moment = try await saver.save(MomentDraft(capture: capture, caption: "", window: window, promptID: nil))
            moment.isFavorite = index % 4 == 1
            // The Mosaic's layout comes from the ids: fixed ones keep the snapshot the same on every run.
            moment.id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!
        }
        try container.mainContext.save()
    }

    private func makeMosaic() async -> MemoriesModel {
        let model = MemoriesModel(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline(), clock: clock, calendar: { Self.calendar }, separatesWindow: true)
        model.refresh()
        for id in model.allIDs { await model.load(id) }
        return model
    }

    private func makeToday() async -> TodayModel {
        let permissions = PresetPermissionService(status: .granted)
        let surprises = SurpriseCoordinator(
            context: container.mainContext, notifications: FakeNotificationScheduler(), permissions: permissions,
            clock: clock, calendar: { Self.calendar }
        )
        let model = TodayModel(
            context: container.mainContext, surprises: surprises, permissions: permissions, store: store,
            thumbnails: ThumbnailPipeline(), clock: clock, calendar: { Self.calendar }
        )
        await model.refresh()
        return model
    }

    private func home(_ side: HomeSide) async -> some View {
        let preferences = HomePreferences.home(nil)
        preferences.value.side = side
        let view = HomeView(today: await makeToday(), mosaic: await makeMosaic())
        return NavigationStack { view }
            .environment(AppRouter())
            .environment(Home(preferences: preferences))
    }

    /// U10: Today with the side switch.
    @Test func today() async throws {
        try await populate(4)
        assertScreenSnapshots(of: await home(.today), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    /// U13, U15: two months of pieces, favorites and the video in the larger ones; iPad puts blocks side by side.
    @Test func mosaic() async throws {
        try await populate(16, video: true)
        assertScreenSnapshots(of: await home(.mosaic), variants: [
            SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge),
            SnapshotVariant(.iPhone, .light, rightToLeft: true), SnapshotVariant(.iPad, .light), SnapshotVariant(.iPadLandscape, .light),
        ])
    }

    /// U14: the first few moments, and the note that it grows.
    @Test func mosaicFirstFew() async throws {
        try await populate(3, video: true)
        assertScreenSnapshots(of: await home(.mosaic), variants: [SnapshotVariant(.iPhone, .light)])
    }
}
