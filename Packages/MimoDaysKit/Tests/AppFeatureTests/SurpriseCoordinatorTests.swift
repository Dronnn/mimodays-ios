@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

@MainActor
struct SurpriseCoordinatorTests {
    /// Lets a test move the device to another time zone.
    final class DeviceCalendar {
        var calendar: Calendar
        init(_ zone: String) {
            calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            calendar.firstWeekday = 2
        }
    }

    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let notifications = FakeNotificationScheduler()
    private let device = DeviceCalendar("Europe/Berlin")
    private let clock: TestDateProvider
    private let schedule = SurpriseSchedule()

    init() {
        clock = TestDateProvider()
        clock.set(date("2026-11-11 06:00")) // Wednesday, before the window opens
        container.mainContext.insert(schedule)
    }

    private var context: ModelContext { container.mainContext }

    private func date(_ string: String) -> Date {
        let parts = string.split(whereSeparator: { "- :".contains($0) }).map { Int($0)! }
        return device.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4]))!
    }

    private func coordinator(_ permission: PermissionStatus = .granted, seed: UInt64 = 1) -> SurpriseCoordinator {
        let device = device
        return SurpriseCoordinator(
            context: context, notifications: notifications, permissions: PresetPermissionService(status: permission),
            clock: clock, calendar: { device.calendar }, generator: SeededRandomNumberGenerator(seed: seed)
        )
    }

    private func prompts(_ outcome: PromptOutcome? = nil) throws -> [SurprisePrompt] {
        try context.fetch(FetchDescriptor<SurprisePrompt>(sortBy: [SortDescriptor(\.plannedAt)]))
            .filter { outcome == nil || $0.outcome == outcome }
    }

    private func minute(of date: Date) -> Int {
        let parts = device.calendar.dateComponents([.hour, .minute], from: date)
        return parts.hour! * 60 + parts.minute!
    }

    // MARK: Plan and notifications

    @Test func firstRefreshPlansTwoWeeksAndSchedulesEveryPrompt() async throws {
        await coordinator().refresh()
        let planned = try prompts(.pending)
        #expect(planned.count == 14)
        let pending = await notifications.pending()
        #expect(pending.map(\.id) == planned.map(\.notificationRequestID))
        #expect(pending.map(\.fireDate) == planned.map(\.plannedAt))
        #expect(planned.allSatisfy { $0.notificationRequestID == $0.id.uuidString })
        #expect(planned.allSatisfy { $0.expiresAt == $0.plannedAt.addingTimeInterval(15 * 60) })
        let bodies = Set(SurpriseCoordinator.bodies.map { String(localized: $0) })
        #expect(pending.allSatisfy { $0.title == "A little moment is happening." && bodies.contains($0.body) })
    }

    @Test func refreshingAgainOrAfterARelaunchAddsNothing() async throws {
        await coordinator().refresh()
        let first = try prompts().map(\.id)
        let firstPending = await notifications.pending()
        await coordinator().refresh()
        await coordinator(seed: 42).refresh()
        #expect(try prompts().map(\.id) == first)
        #expect(await notifications.pending() == firstPending)
    }

    @Test func overlappingRefreshesDoNotDuplicate() async throws {
        let coordinator = coordinator()
        async let first: Void = coordinator.refresh()
        async let second: Void = coordinator.refresh()
        _ = await (first, second)
        #expect(try prompts().count == 14)
        #expect(await notifications.pending().count == 14)
    }

    @Test func threeADayStaysUnderTheSystemLimit() async throws {
        schedule.frequency = .threeADay
        await coordinator().refresh()
        #expect(try prompts(.pending).count == 42)
        #expect(await notifications.pending().count <= SurpriseCoordinator.notificationLimit)
    }

    @Test func onlyTheNextSixtyAreHandedToIOS() async throws {
        schedule.frequency = .threeADay
        // 70 prompts today, 10 minutes apart, ahead of the 39 drawn for the other days.
        for offset in 0..<70 {
            let time = date("2026-11-11 08:00").addingTimeInterval(Double(offset) * 10 * 60)
            context.insert(SurprisePrompt(plannedAt: time, expiresAt: .distantFuture, notificationRequestID: "p\(offset)"))
        }
        await coordinator().refresh()
        let pending = await notifications.pending()
        #expect(pending.count == SurpriseCoordinator.notificationLimit)
        #expect(pending.map(\.id) == (0..<60).map { "p\($0)" })
    }

    @Test func strayRequestsAreRemovedAndLostOnesRestored() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        let lost = try #require(try prompts().first)
        await notifications.cancel(ids: [lost.notificationRequestID])
        try await notifications.schedule(SurpriseNotification(id: "stray", fireDate: date("2026-11-12 10:00")))
        await coordinator.refresh()
        let ids = await notifications.pending().map(\.id)
        let expected = try prompts(.pending).map(\.notificationRequestID)
        #expect(ids == expected)
    }

    // MARK: Lifecycle

    @Test func aMissedPromptExpiresAndItsDayIsNotRedrawn() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        let first = try #require(try prompts().first)
        clock.set(first.expiresAt.addingTimeInterval(1))
        await coordinator.refresh()
        #expect(first.outcome == .expired)
        #expect(try prompts(.pending).count == 13)
        #expect(await !notifications.pending().contains { $0.id == first.notificationRequestID })
    }

    @Test func aPromptThatJustFiredStaysAnswerable() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        let first = try #require(try prompts().first)
        clock.set(first.plannedAt.addingTimeInterval(5 * 60))
        await coordinator.refresh()
        #expect(first.outcome == .pending)
    }

    @Test func openingInTimeMakesItASurpriseAndClosingKeepsItAnswerable() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        let prompt = try #require(try prompts().first)
        clock.set(prompt.plannedAt.addingTimeInterval(60))
        #expect(coordinator.open(promptID: prompt.id))
        let opened = try #require(prompt.openedAt)
        // Camera closed without saving, opened again from Today a few minutes later.
        clock.advance(by: 10 * 60)
        #expect(coordinator.open(promptID: prompt.id))
        #expect(prompt.openedAt == opened)
        #expect(prompt.outcome == .pending)
    }

    @Test func openingTooLateIsAPlainCapture() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        let prompt = try #require(try prompts().first)
        clock.set(prompt.expiresAt)
        #expect(!coordinator.open(promptID: prompt.id))
        #expect(prompt.outcome == .expired)
        #expect(prompt.openedAt == nil)
    }

    @Test func unknownOrCancelledPromptsDoNotOpen() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        #expect(!coordinator.open(promptID: UUID()))
        schedule.isEnabled = false
        await coordinator.refresh()
        let cancelled = try #require(try prompts(.cancelled).first)
        clock.set(cancelled.plannedAt)
        #expect(!coordinator.open(promptID: cancelled.id))
    }

    @Test func aMomentSavedAfterOpeningInTimeAnswersThePrompt() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        let prompt = try #require(try prompts().first)
        clock.set(prompt.plannedAt.addingTimeInterval(14 * 60))
        #expect(coordinator.open(promptID: prompt.id))
        // Reviewing takes a while; the window closes before the save.
        clock.advance(by: 5 * 60)
        await coordinator.refresh()
        #expect(prompt.outcome == .expired)
        let moment = UUID()
        coordinator.captured(promptID: prompt.id, momentID: moment)
        #expect(prompt.outcome == .captured)
        #expect(prompt.capturedMomentID == moment)
    }

    @Test func aPromptThatWasNeverOpenedIsNotAnswered() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        let prompt = try #require(try prompts().first)
        coordinator.captured(promptID: prompt.id, momentID: UUID())
        #expect(prompt.outcome == .pending)
        #expect(prompt.capturedMomentID == nil)
    }

    // MARK: Turning surprises off

    @Test(arguments: [PermissionStatus.denied, .notDetermined, .restricted])
    func noUsableNotificationPermissionCancelsThePlan(status: PermissionStatus) async throws {
        await coordinator().refresh()
        await coordinator(status).refresh()
        #expect(try prompts(.pending).isEmpty)
        #expect(await notifications.pending().isEmpty)
        // Allowed again: the same days are planned anew.
        await coordinator().refresh()
        #expect(try prompts(.pending).count == 14)
        #expect(await notifications.pending().count == 14)
    }

    @Test func disabledOrPausedIndefinitelyPlansNothing() async throws {
        schedule.isEnabled = false
        await coordinator().refresh()
        #expect(try prompts().isEmpty)
        schedule.isEnabled = true
        schedule.isPausedIndefinitely = true
        await coordinator().refresh()
        #expect(try prompts().isEmpty)
        #expect(await notifications.pending().isEmpty)
    }

    @Test func aPauseKeepsSurprisesAwayUntilItEnds() async throws {
        await coordinator().refresh()
        let resume = date("2026-11-14 00:00")
        schedule.pausedUntil = resume
        await coordinator().refresh()
        let upcoming = try prompts(.pending)
        #expect(!upcoming.isEmpty)
        #expect(upcoming.allSatisfy { $0.plannedAt >= resume })
        #expect(await notifications.pending().allSatisfy { $0.fireDate >= resume })
    }

    // MARK: Changes

    @Test func newSettingsReplaceTheFuturePlan() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        schedule.frequency = .twiceADay
        await coordinator.settingsChanged()
        let upcoming = try prompts(.pending)
        #expect(upcoming.count == 28)
        #expect(try prompts(.cancelled).count == 14)
        #expect(await notifications.pending().map(\.id) == upcoming.map(\.notificationRequestID))
    }

    @Test func aPlanOutsideTheNewHoursIsRedrawnEvenWithoutAnExplicitChange() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        schedule.earliestMinute = 12 * 60
        schedule.latestMinute = 13 * 60
        await coordinator.refresh()
        let upcoming = try prompts(.pending)
        #expect(upcoming.count == 14)
        #expect(upcoming.allSatisfy { (12 * 60...13 * 60).contains(minute(of: $0.plannedAt)) })
    }

    @Test func movingToAnotherTimeZoneKeepsTheLocalWindow() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        device.calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        await coordinator.refresh()
        let upcoming = try prompts(.pending)
        #expect(!upcoming.isEmpty)
        #expect(upcoming.allSatisfy { (8 * 60...22 * 60).contains(minute(of: $0.plannedAt)) })
        #expect(await notifications.pending().map(\.id) == upcoming.map(\.notificationRequestID))
    }

    @Test func aFixedTimeZoneIgnoresTheDevice() async throws {
        schedule.timeZonePolicy = .fixed
        schedule.fixedTimeZoneID = "America/New_York"
        await coordinator().refresh()
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        for prompt in try prompts() {
            let parts = newYork.dateComponents([.hour, .minute], from: prompt.plannedAt)
            #expect((8 * 60...22 * 60).contains(parts.hour! * 60 + parts.minute!))
        }
    }

    @Test func frequenciesMapToCadences() {
        #expect(SurpriseFrequency.threeAWeek.cadence == .weekly(3))
        #expect(SurpriseFrequency.onceADay.cadence == .daily(1))
        #expect(SurpriseFrequency.twiceADay.cadence == .daily(2))
        #expect(SurpriseFrequency.threeADay.cadence == .daily(3))
    }
}

/// The onboarding reminders choice plans surprises right away (same store as the app).
@MainActor
struct OnboardingSurprisesTests {
    typealias DeviceCalendar = SurpriseCoordinatorTests.DeviceCalendar
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
    private let notifications = FakeNotificationScheduler()

    private func flow(answer: PermissionStatus) -> OnboardingFlow {
        let permissions = PresetPermissionService(status: .notDetermined, requestResult: answer)
        let surprises = SurpriseCoordinator(
            context: container.mainContext, notifications: notifications, permissions: permissions,
            clock: TestDateProvider(), calendar: { DeviceCalendar("Europe/Berlin").calendar },
            generator: SeededRandomNumberGenerator(seed: 1)
        )
        let flow = OnboardingFlow(
            permissions: permissions, store: SwiftDataOnboardingStore(context: container.mainContext)
        ) { await surprises.settingsChanged() }
        flow.finishIntro()
        return flow
    }

    private var prompts: [SurprisePrompt] { (try? container.mainContext.fetch(FetchDescriptor<SurprisePrompt>())) ?? [] }

    @Test func enablingRemindersPlansTheFirstSurprises() async {
        let flow = flow(answer: .granted)
        flow.schedule.frequency = .twiceADay
        await flow.enableReminders()
        #expect(prompts.count == 28)
        #expect(await notifications.pending().count == 28)
    }

    @Test func deniedOrLaterPlansNothing() async {
        await flow(answer: .denied).enableReminders()
        #expect(prompts.isEmpty)
        flow(answer: .granted).remindLater()
        #expect(prompts.isEmpty)
        #expect(await notifications.pending().isEmpty)
    }
}
