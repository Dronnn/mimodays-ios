@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// The ribbon's status (T02-T07), from the schedule, its prompts and the newest capture.
struct SurpriseStatusTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 14, minute: 40))!

    private func prompt(minutesAgo: Double, _ outcome: PromptOutcome = .pending) -> SurprisePrompt {
        let planned = now.addingTimeInterval(-minutesAgo * 60)
        let prompt = SurprisePrompt(plannedAt: planned, expiresAt: planned.addingTimeInterval(15 * 60), notificationRequestID: "")
        prompt.outcome = outcome
        return prompt
    }

    private func status(
        _ schedule: SurpriseSchedule? = SurpriseSchedule(), _ prompts: [SurprisePrompt] = [], allowed: Bool = true,
        latestCapture: Date? = nil
    ) -> SurpriseStatus {
        SurpriseStatus(
            schedule: schedule, prompts: prompts, notificationsAllowed: allowed, latestCapture: latestCapture,
            now: now, calendar: Self.calendar
        )
    }

    @Test func aPromptStillOpenIsReadyEvenWhenSurprisesWereSwitchedOff() {
        let ready = prompt(minutesAgo: 3)
        let schedule = SurpriseSchedule()
        schedule.isEnabled = false
        #expect(status(schedule, [ready], allowed: false) == .ready(promptID: ready.id))
    }

    @Test func offWithoutAScheduleWhenDisabledOrWithoutNotifications() {
        let disabled = SurpriseSchedule()
        disabled.isEnabled = false
        #expect(status(nil) == .off)
        #expect(status(disabled) == .off)
        #expect(status(allowed: false) == .off)
    }

    @Test func pausedUntilADateOrUntilResumed() {
        let until = SurpriseSchedule()
        until.pausedUntil = now.addingTimeInterval(86400)
        let indefinitely = SurpriseSchedule()
        indefinitely.isPausedIndefinitely = true
        let ended = SurpriseSchedule()
        ended.pausedUntil = now.addingTimeInterval(-60)
        #expect(status(until) == .paused(until: now.addingTimeInterval(86400)))
        #expect(status(indefinitely) == .paused(until: nil))
        #expect(status(ended) == .onItsWay)
    }

    @Test func todaysMissedPromptHasPassedUntilSomethingIsCaught() {
        #expect(status(.init(), [prompt(minutesAgo: 60, .expired)]) == .passed)
        // Expired by the clock before anything marked it.
        #expect(status(.init(), [prompt(minutesAgo: 20)]) == .passed)
        #expect(status(.init(), [prompt(minutesAgo: 60, .expired)], latestCapture: now.addingTimeInterval(-10 * 60)) == .onItsWay)
    }

    @Test func otherwiseTheNextOneIsOnItsWay() {
        #expect(status() == .onItsWay)
        // Yesterday's miss is old news; answered and cancelled ones don't count; the next is still ahead.
        #expect(status(.init(), [prompt(minutesAgo: 24 * 60, .expired)]) == .onItsWay)
        #expect(status(.init(), [prompt(minutesAgo: 60, .captured)]) == .onItsWay)
        #expect(status(.init(), [prompt(minutesAgo: 60, .cancelled)]) == .onItsWay)
        #expect(status(.init(), [prompt(minutesAgo: -60)]) == .onItsWay)
    }
}

/// What Today reads from the store, and its actions.
@MainActor
struct TodayModelTests {
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let store = try! MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "TodayModel-\(UUID().uuidString)"))
    private let clock = TestDateProvider()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    init() {
        clock.set(Self.date(2026, 11, 11, 14, 40))
    }

    private var context: ModelContext { container.mainContext }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @discardableResult
    private func save(at date: Date, place: String? = nil) async throws -> UUID {
        let engine = SimulatedCaptureEngine()
        _ = await engine.start()
        let photo = try await engine.capturePhoto(flash: false, silent: true)
        let capture = CaptureResult(media: .photo(photo), window: .init(), capturedAt: CaptureTime(instant: date, timeZone: .gmt))
        let window = SelfieWindowFrame(frame: CGRect(x: 266.7, y: 111.1, width: 112, height: 150), preview: CGSize(width: 402, height: 536))
        let saver = MomentSaver(context: context, store: store, clock: clock, freeBytes: { nil })
        return try await saver.save(MomentDraft(
            capture: capture, caption: "", window: window, promptID: nil,
            place: place.map { ReviewPlace(label: $0, latitude: 40.18, longitude: 44.51, precision: .city, source: .gps) }
        )).id
    }

    private func model(_ notifications: PermissionStatus = .granted, requestResult: PermissionStatus = .granted) -> TodayModel {
        let permissions = PresetPermissionService(status: notifications, requestResult: requestResult)
        let surprises = SurpriseCoordinator(
            context: context, notifications: FakeNotificationScheduler(), permissions: permissions,
            clock: clock, calendar: { Self.calendar }
        )
        return TodayModel(
            context: context, surprises: surprises, permissions: permissions, store: store,
            thumbnails: ThumbnailPipeline(), clock: clock, calendar: { Self.calendar }
        )
    }

    private func schedule() throws -> SurpriseSchedule? {
        try context.fetch(FetchDescriptor<SurpriseSchedule>()).first
    }

    @Test func anEmptyStoreShowsNothingMadeUp() async {
        let today = model()
        await today.refresh()
        #expect(today.isEmpty)
        #expect(today.count == 0 && today.month.isEmpty && today.onThisDay == nil)
    }

    @Test func theLatestMomentThisMonthAndTheCount() async throws {
        try await save(at: Self.date(2026, 10, 31))
        try await save(at: Self.date(2026, 11, 1, 0, 30))
        try await save(at: Self.date(2026, 11, 8))
        let latest = try await save(at: Self.date(2026, 11, 11, 14, 37), place: "Yerevan, Armenia")
        let today = model()
        await today.refresh()
        #expect(today.latest?.id == latest)
        #expect(today.latest?.place == "Yerevan, Armenia")
        #expect(today.latest?.mainPath != nil && today.latest?.selfiePath != nil)
        #expect(today.count == 4)
        #expect(today.month.map(\.captured.instant) == [Self.date(2026, 11, 11, 14, 37), Self.date(2026, 11, 8), Self.date(2026, 11, 1, 0, 30)])
        #expect(today.image(today.latest?.mainPath, TodayModel.heroPixels) != nil)
        #expect(today.month.allSatisfy { today.image($0.thumbnailPath, TodayModel.tilePixels) != nil })
    }

    @Test func thisMonthStopsAtTwelve() async throws {
        for day in 1...11 {
            try await save(at: Self.date(2026, 11, day, 9))
            try await save(at: Self.date(2026, 11, day, 10))
        }
        let today = model()
        await today.refresh()
        #expect(today.month.count == TodayModel.monthLimit)
        #expect(today.month.first?.captured.instant == Self.date(2026, 11, 11, 10))
        #expect(today.count == 22)
    }

    @Test func deletedMomentsAreLeftOut() async throws {
        let older = try await save(at: Self.date(2026, 11, 8))
        let newest = try await save(at: Self.date(2026, 11, 11, 9))
        let yearAgo = try await save(at: Self.date(2025, 11, 11))
        for id in [newest, yearAgo] {
            try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first?.deletedAt = clock.now()
        }
        try context.save()
        let today = model()
        await today.refresh()
        #expect(today.latest?.id == older)
        #expect(today.count == 1 && today.month.map(\.id) == [older])
        #expect(today.onThisDay == nil)
    }

    @Test func onThisDayIsTheNearestEarlierYear() async throws {
        try await save(at: Self.date(2023, 11, 11))
        try await save(at: Self.date(2024, 11, 11, 8))
        let cover = try await save(at: Self.date(2024, 11, 11, 19))
        try await save(at: Self.date(2025, 11, 12))
        let today = model()
        await today.refresh()
        #expect(today.onThisDay == OnThisDay(yearsAgo: 2, count: 2, cover: try #require(today.onThisDay?.cover)))
        #expect(today.onThisDay?.cover.id == cover)
    }

    @Test func captureFromTodayAnswersAReadySurprise() async throws {
        let now = clock.now()
        let prompt = SurprisePrompt(plannedAt: now.addingTimeInterval(-180), expiresAt: now.addingTimeInterval(720), notificationRequestID: "ready")
        context.insert(SurpriseSchedule())
        context.insert(prompt)
        let today = model()
        await today.refresh()
        #expect(today.surprise == .ready(promptID: prompt.id))
        #expect(today.surpriseChangesAt == prompt.expiresAt)
        #expect(today.captureRequest() == prompt.id)
        #expect(prompt.openedAt != nil)
    }

    @Test func captureWithoutASurpriseIsAnOrdinaryMoment() async {
        context.insert(SurpriseSchedule())
        let today = model()
        await today.refresh()
        #expect(today.captureRequest() == nil)
    }

    @Test func turnOnAsksForNotificationsAndStartsTheSchedule() async throws {
        let today = model(.notDetermined)
        await today.refresh()
        #expect(today.surprise == .off)
        #expect(await today.turnOn())
        #expect(try schedule()?.isEnabled == true)
        #expect(today.surprise == .onItsWay)
    }

    @Test func turnOnEnablesAndUnpausesASchedule() async throws {
        let existing = SurpriseSchedule()
        existing.isEnabled = false
        existing.isPausedIndefinitely = true
        context.insert(existing)
        let today = model()
        #expect(await today.turnOn())
        #expect(existing.isEnabled && !existing.isPausedIndefinitely)
        #expect(try context.fetchCount(FetchDescriptor<SurpriseSchedule>()) == 1)
    }

    @Test func turnOnRespectsANoGivenJustNow() async throws {
        let today = model(.notDetermined, requestResult: .denied)
        #expect(await today.turnOn())
        #expect(try schedule() == nil)
    }

    @Test func turnOnNeedsSettingsOnceNotificationsWereDenied() async throws {
        let today = model(.denied)
        #expect(await !today.turnOn())
        #expect(try schedule() == nil)
    }

    @Test func resumeEndsAPause() async throws {
        let paused = SurpriseSchedule()
        paused.pausedUntil = clock.now().addingTimeInterval(86400)
        context.insert(paused)
        let today = model()
        await today.refresh()
        #expect(today.surprise == .paused(until: paused.pausedUntil))
        await today.resume()
        #expect(today.surprise == .onItsWay)
    }
}
