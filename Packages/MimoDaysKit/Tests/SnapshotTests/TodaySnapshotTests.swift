@testable import AppFeature
@testable import Core
import DesignSystem
import Foundation
import Persistence
import SwiftData
import SwiftUI
import Testing
import TestSupport

/// Today (T01-T07, X01): real moments saved from the simulated camera, pictures decoded before the snapshot.
/// The system tab bar is Liquid Glass and doesn't render offscreen, so these are the tab's content (UI tests cover the bar).
@MainActor
@Suite(.tags(.snapshot))
struct TodaySnapshotTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store = try! MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "TodaySnapshots-\(UUID().uuidString)"))
    private let clock = TestDateProvider()
    private let schedule = SurpriseSchedule()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Today's `.task` refresh can still run after a test returns; its store must outlive the test.
    private static var stores: [ModelContainer] = []

    init() {
        clock.set(Self.date(2026, 11, 11, 14, 40)) // Wednesday afternoon
        container.mainContext.insert(schedule)
        Self.stores.append(container)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func save(at date: Date, place: String? = nil, surprise: Bool = false) async throws {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let photo = try await engine.capturePhoto(flash: false, silent: true)
        let capture = CaptureResult(media: .photo(photo), window: .init(), capturedAt: CaptureTime(instant: date, timeZone: .gmt))
        let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))
        let saver = MomentSaver(context: container.mainContext, store: store, clock: clock, freeBytes: { nil })
        _ = try await saver.save(MomentDraft(
            capture: capture, caption: "", window: window, promptID: surprise ? UUID() : nil,
            place: place.map { ReviewPlace(label: $0, latitude: 40.18, longitude: 44.51, precision: .city, source: .gps) }
        ))
    }

    /// November so far, the latest this afternoon in Yerevan, and one from a year ago today.
    private func populate(latestIsSurprise: Bool = false) async throws {
        try await save(at: Self.date(2025, 11, 11, 9, 15))
        try await save(at: Self.date(2026, 11, 3))
        try await save(at: Self.date(2026, 11, 8))
        try await save(at: Self.date(2026, 11, 10, 18, 42))
        try await save(at: Self.date(2026, 11, 11, 14, 37), place: "Yerevan, Armenia", surprise: latestIsSurprise)
    }

    private func today(_ notifications: PermissionStatus = .granted) async -> TodayModel {
        let permissions = PresetPermissionService(status: notifications)
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

    private func screen(_ model: TodayModel) -> some View {
        NavigationStack { TodayView(model: model) }.environment(AppRouter())
    }

    // MARK: Screens

    @Test func empty() async {
        assertScreenSnapshots(of: screen(await today()), variants: Self.variants)
    }

    @Test func populated() async throws {
        try await populate()
        assertScreenSnapshots(of: screen(await today()), variants: Self.variants)
    }

    /// The standard set plus X01, iPad landscape in two columns.
    private static let variants = SnapshotVariant.standard + [SnapshotVariant(.iPadLandscape, .light), SnapshotVariant(.iPadLandscape, .dark)]

    /// T03: the prompt fired three minutes ago; the latest moment was a surprise too.
    @Test func surpriseReady() async throws {
        try await populate(latestIsSurprise: true)
        let now = clock.now()
        container.mainContext.insert(SurprisePrompt(plannedAt: now.addingTimeInterval(-180), expiresAt: now.addingTimeInterval(720), notificationRequestID: "t03"))
        assertScreenSnapshots(of: screen(await today()), variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark)])
    }

    // MARK: Pieces

    /// T02-T07 ribbons, as wide as on iPhone.
    @Test func ribbons() {
        let now = clock.now()
        let statuses: [SurpriseStatus] = [
            .onItsWay, .ready(promptID: UUID()), .passed, .paused(until: Self.date(2026, 11, 12, 0, 0)),
            .paused(until: Self.date(2026, 11, 16, 0, 0)), .paused(until: Self.date(2026, 11, 18, 0, 0)), .paused(until: nil), .off,
        ]
        let view = VStack(spacing: 14) {
            ForEach(Array(statuses.enumerated()), id: \.offset) { _, status in
                SurpriseRibbon(status: status, now: now) {}
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ColorToken.canvas.color)
        assertScreenSnapshots(of: view, variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge)])
    }

    /// T06 with the rest of the scroll: this month, On this day, the movie card.
    @Test func onThisDay() async throws {
        try await populate()
        let model = await today()
        #expect(model.onThisDay?.yearsAgo == 1 && model.onThisDay?.count == 1)
        assertScreenSnapshots(
            of: NavigationStack { TodayView(model: model).defaultScrollAnchor(.bottom) }.environment(AppRouter()),
            variants: [SnapshotVariant(.iPhone, .light)]
        )
    }
}
