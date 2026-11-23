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

    private let container = try! TestStore.container()
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
        let moment = shot(at: clock.now())
        // Reviewing takes a while; the window closes before the save.
        clock.advance(by: 5 * 60)
        await coordinator.refresh()
        #expect(prompt.outcome == .expired)
        coordinator.captured(promptID: prompt.id, momentID: moment)
        #expect(prompt.outcome == .captured)
        #expect(prompt.capturedMomentID == moment)
    }

    /// The camera opened in time but the shutter pressed after the window: a plain capture (Help › Surprises).
    @Test func aShotAfterTheWindowDoesntAnswerThePrompt() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        let prompt = try #require(try prompts().first)
        clock.set(prompt.plannedAt.addingTimeInterval(14 * 60))
        #expect(coordinator.open(promptID: prompt.id))
        #expect(coordinator.expiry(of: prompt.id) == prompt.expiresAt)
        clock.set(prompt.expiresAt.addingTimeInterval(5 * 60))
        coordinator.captured(promptID: prompt.id, momentID: shot(at: clock.now()))
        #expect(prompt.outcome != .captured)
    }

    @Test func aLaterSurpriseDoesntOpenEarly() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        let prompt = try #require(try prompts().first)
        #expect(clock.now() < prompt.plannedAt)
        #expect(!coordinator.open(promptID: prompt.id))
        #expect(prompt.outcome == .pending && prompt.openedAt == nil)
    }

    private func shot(at date: Date) -> UUID {
        let moment = Moment(captured: CaptureTime(instant: date, timeZone: device.calendar.timeZone), origin: .randomPrompt, mediaType: .photo, createdAt: date)
        context.insert(moment)
        return moment.id
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

    @Test func pausingForTodayResumesTomorrowMorning() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        await coordinator.pause(.today)
        let tomorrow = date("2026-11-12 00:00")
        #expect(schedule.pausedUntil == tomorrow)
        let upcoming = try prompts(.pending)
        // Today's surprise is dropped; the two weeks now start tomorrow.
        #expect(upcoming.count == 14)
        #expect(upcoming.allSatisfy { $0.plannedAt >= tomorrow })
        #expect(await notifications.pending().map(\.id) == upcoming.map(\.notificationRequestID))
    }

    @Test func pausingForAWeekSkipsSevenCalendarDays() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        await coordinator.pause(.week)
        let end = date("2026-11-18 00:00")
        #expect(schedule.pausedUntil == end)
        #expect(try prompts(.pending).allSatisfy { $0.plannedAt >= end })
        #expect(await notifications.pending().allSatisfy { $0.fireDate >= end })
    }

    @Test func anIndefinitePauseLastsUntilResumed() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        await coordinator.pause(.indefinitely)
        clock.advance(by: 30 * 24 * 3600)
        await coordinator.refresh()
        #expect(try prompts(.pending).isEmpty)
        #expect(await notifications.pending().isEmpty)
        await coordinator.resume()
        #expect(!schedule.isPausedIndefinitely)
        #expect(try prompts(.pending).count == 14)
        #expect(await notifications.pending().count == 14)
    }

    @Test func aWeekChosenAfterAnIndefinitePauseEndsInAWeek() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        await coordinator.pause(.indefinitely)
        await coordinator.pause(.week)
        #expect(!schedule.isPausedIndefinitely)
        #expect(schedule.pausedUntil == date("2026-11-18 00:00"))
        await coordinator.pause(.indefinitely)
        #expect(schedule.isPausedIndefinitely && schedule.pausedUntil == nil)
    }

    @Test func resumingEarlyPlansTodayAgain() async throws {
        let coordinator = coordinator()
        await coordinator.refresh()
        await coordinator.pause(.today)
        await coordinator.resume()
        #expect(schedule.pausedUntil == nil)
        #expect(try prompts(.pending).contains { device.calendar.isDate($0.plannedAt, inSameDayAs: date("2026-11-11 12:00")) })
    }

    @Test func aPauseThatEndedIsCleared() async {
        let coordinator = coordinator()
        await coordinator.pause(.today)
        clock.set(date("2026-11-12 07:00"))
        await coordinator.refresh()
        #expect(schedule.pausedUntil == nil)
    }

    // MARK: Changes

    @Test func sendingOneNowArrivesInSecondsAndStaysThroughAReplan() async throws {
        clock.set(date("2026-11-11 23:30")) // outside the hours
        let coordinator = coordinator()
        await coordinator.refresh()
        #expect(await coordinator.sendNow())
        let now = try #require(try prompts(.pending).first)
        #expect(now.plannedAt == date("2026-11-11 23:30").addingTimeInterval(10))
        #expect(now.expiresAt == now.plannedAt.addingTimeInterval(15 * 60))
        await coordinator.settingsChanged()
        #expect(try prompts(.pending).first?.id == now.id)
        let pending = await notifications.pending()
        #expect(pending.first?.id == SurpriseCoordinator.sendNowPrefix + now.id.uuidString)
        #expect(pending.first?.promptID == now.id.uuidString)
        #expect(pending.first?.fireDate == now.plannedAt)
        clock.set(now.plannedAt.addingTimeInterval(5))
        #expect(coordinator.open(promptID: now.id))
    }

    /// A pause stops even the surprise due in a few seconds: nothing more comes once the person said so.
    @Test func aPauseStopsASurpriseDueWithinTheMinute() async throws {
        clock.set(date("2026-11-11 23:30"))
        let coordinator = coordinator()
        await coordinator.refresh()
        #expect(await coordinator.sendNow())
        let soon = try #require(try prompts(.pending).first)
        await coordinator.pause(.today)
        #expect(soon.outcome == .cancelled)
        #expect(await !notifications.pending().contains { $0.id == soon.notificationRequestID })
    }

    @Test func aSecondTapSendsNoSecondSurprise() async throws {
        clock.set(date("2026-11-11 23:30"))
        let coordinator = coordinator()
        await coordinator.refresh()
        #expect(await coordinator.sendNow())
        #expect(await coordinator.sendNow())
        let soon = clock.now().addingTimeInterval(SurpriseCoordinator.sendNowDelay)
        #expect(try prompts(.pending).count { $0.plannedAt <= soon } == 1)
    }

    /// P5.2: one due within the second that iOS never took won't come: it is dropped, not left beside the new one.
    /// One whose second has begun may just have been shown, so it stays.
    @Test func aSurpriseIOSNeverTookDueWithinTheSecondIsDropped() async throws {
        let now = date("2026-11-11 23:30").addingTimeInterval(0.7)
        clock.set(now)
        let coordinator = coordinator()
        await coordinator.refresh()
        let lost = SurprisePrompt(plannedAt: now.addingTimeInterval(0.5), expiresAt: now.addingTimeInterval(900), notificationRequestID: "lost")
        let shown = SurprisePrompt(plannedAt: now.addingTimeInterval(0.2), expiresAt: now.addingTimeInterval(900), notificationRequestID: "shown")
        context.insert(lost)
        context.insert(shown)
        try context.save()
        #expect(await coordinator.sendNow())
        #expect(lost.outcome == .cancelled)
        #expect(shown.outcome == .pending)
    }

    /// iOS turned the request down: Settings doesn't say it's on its way, and Today doesn't wait for it.
    @Test func aSendIOSRefusesIsNotReportedAsSent() async throws {
        clock.set(date("2026-11-11 23:30"))
        let coordinator = coordinator()
        await coordinator.refresh()
        await notifications.setScheduleError(.unavailable)
        #expect(await !coordinator.sendNow())
        let soon = clock.now().addingTimeInterval(SurpriseCoordinator.sendNowDelay)
        #expect(try prompts(.pending).count { $0.plannedAt <= soon } == 0)
    }

    @Test func sendingOneNowNeedsNotifications() async throws {
        #expect(await coordinator(.denied).sendNow() == false)
        #expect(try prompts().isEmpty)
    }

    /// "Send a surprise now" is extra: a replan later that day (a new language, new settings) still plans the day's own.
    @Test func aSurpriseSentNowDoesntTakeTheDaysPlace() async throws {
        clock.set(date("2026-11-11 10:00"))
        let coordinator = coordinator()
        await coordinator.refresh()
        #expect(await coordinator.sendNow())
        clock.set(date("2026-11-11 10:05"))
        await coordinator.settingsChanged()
        let today = try prompts(.pending).filter { device.calendar.isDate($0.plannedAt, inSameDayAs: date("2026-11-11 10:00")) }
        #expect(today.contains { $0.plannedAt > date("2026-11-11 10:05") })
    }

    /// A replan keeps what already came today and plans the rest of the day's count.
    @Test func aReplanTopsUpADayThatHadOneAlready() async throws {
        schedule.frequency = .threeADay
        clock.set(date("2026-11-11 07:00"))
        let coordinator = coordinator()
        await coordinator.refresh()
        let first = try #require(try prompts(.pending).first)
        clock.set(first.expiresAt.addingTimeInterval(60))
        await coordinator.settingsChanged()
        let day = try prompts().filter { $0.outcome != .cancelled && device.calendar.isDate($0.plannedAt, inSameDayAs: first.plannedAt) }
        #expect(day.count > 1)
        let times = day.map(\.plannedAt).sorted()
        #expect(zip(times, times.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= 120 * 60 })
    }

    // MARK: The first surprise (P2)

    /// P2.1-P2.3: seconds after the reminders step, counted for its day: once a day, nothing else comes today.
    @Test func theFirstSurpriseComesInSecondsAndIsTheDaysOne() async throws {
        clock.set(date("2026-11-11 10:00"))
        let coordinator = coordinator()
        #expect(await coordinator.remindersChosen(firstSurprise: true))
        let first = try #require(coordinator.firstSurprise())
        #expect(first.plannedAt == date("2026-11-11 10:00").addingTimeInterval(SurpriseCoordinator.sendNowDelay))
        #expect(first.expiresAt == first.plannedAt.addingTimeInterval(15 * 60))
        let today = try prompts(.pending).filter { device.calendar.isDate($0.plannedAt, inSameDayAs: first.plannedAt) }
        #expect(today.map(\.id) == [first.promptID])
        #expect(await notifications.pending().contains { $0.id == SurpriseCoordinator.firstPrefix + first.promptID.uuidString })
        #expect(try prompts(.pending).count == 14)
        // Settings saved again later keep it and still count it.
        await coordinator.settingsChanged()
        #expect(coordinator.firstSurprise() == first)
        #expect(try prompts(.pending).filter { device.calendar.isDate($0.plannedAt, inSameDayAs: first.plannedAt) }.count == 1)
    }

    @Test func thereIsOnlyEverOneFirstSurprise() async throws {
        clock.set(date("2026-11-11 10:00"))
        let coordinator = coordinator()
        _ = await coordinator.remindersChosen(firstSurprise: true)
        let first = coordinator.firstSurprise()
        _ = await coordinator.remindersChosen(firstSurprise: true)
        #expect(coordinator.firstSurprise() == first)
        #expect(try prompts().count { $0.notificationRequestID.hasPrefix(SurpriseCoordinator.firstPrefix) } == 1)
        _ = await coordinator.remindersChosen(firstSurprise: false)
        #expect(coordinator.firstSurprise() == first)
    }

    /// P2.4: "Maybe later" (surprises off) or notifications off: the first surprise stays, for the app to show.
    /// With notifications allowed but surprises off, iOS doesn't bring it either.
    @Test(arguments: [PermissionStatus.denied, .notDetermined, .granted])
    func withoutNotificationsTheFirstSurpriseStaysInTheApp(permission: PermissionStatus) async throws {
        clock.set(date("2026-11-11 10:00"))
        schedule.isEnabled = false
        let coordinator = coordinator(permission)
        #expect(await !coordinator.remindersChosen(firstSurprise: true))
        await coordinator.refresh()
        let first = try #require(coordinator.firstSurprise())
        #expect(try prompts(.pending).map(\.id) == [first.promptID])
        #expect(await notifications.pending().isEmpty)
        clock.set(first.plannedAt.addingTimeInterval(1))
        #expect(coordinator.open(promptID: first.promptID))
    }

    @Test func aFirstSurpriseIOSRefusesIsShownInTheApp() async throws {
        clock.set(date("2026-11-11 10:00"))
        await notifications.setScheduleError(.unavailable)
        let coordinator = coordinator()
        #expect(await !coordinator.remindersChosen(firstSurprise: true))
        #expect(coordinator.firstSurprise() != nil)
    }

    /// Relaunched between the reminders step and the surprise: it's still there, and gone once it expires.
    @Test func theFirstSurpriseOutlivesARelaunchUntilItExpires() async throws {
        clock.set(date("2026-11-11 10:00"))
        _ = await coordinator().remindersChosen(firstSurprise: true)
        let relaunched = coordinator(seed: 2)
        await relaunched.refresh()
        let first = try #require(relaunched.firstSurprise())
        clock.set(first.expiresAt)
        #expect(relaunched.firstSurprise() == nil)
        clock.set(first.plannedAt.addingTimeInterval(5))
        #expect(relaunched.open(promptID: first.promptID))
    }

    /// Another language rewords what iOS has and keeps the plan: late in the day a redraw would find no time left.
    @Test func aNewLanguageKeepsThePlan() async throws {
        clock.set(date("2026-11-11 21:50"))
        let coordinator = coordinator()
        await coordinator.refresh()
        let before = try prompts(.pending).map(\.id)
        await coordinator.languageChanged()
        #expect(try prompts(.pending).map(\.id) == before)
        #expect(try prompts(.cancelled).isEmpty)
        #expect(await notifications.pending().map(\.id) == before.map(\.uuidString))
    }

    /// A narrow window keeps its count through a replan: the top-up uses the day's gap, not the full two hours.
    @Test func aReplanInANarrowWindowKeepsTheCount() async throws {
        schedule.frequency = .threeADay
        schedule.earliestMinute = 8 * 60
        schedule.latestMinute = 9 * 60
        clock.set(date("2026-11-11 07:00"))
        let coordinator = coordinator()
        await coordinator.refresh()
        let first = try #require(try prompts(.pending).first)
        clock.set(first.plannedAt.addingTimeInterval(60))
        schedule.expiryMinutes = 30
        await coordinator.settingsChanged()
        let day = try prompts().filter { $0.outcome != .cancelled && device.calendar.isDate($0.plannedAt, inSameDayAs: first.plannedAt) }
        #expect(day.count == 3)
        let later = try prompts(.pending).filter { !device.calendar.isDate($0.plannedAt, inSameDayAs: first.plannedAt) }
        #expect(Set(later.map { minute(of: $0.plannedAt) }).count > 3) // still random, not the same three times
    }

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
    private let container = try! TestStore.container()
    private let notifications = FakeNotificationScheduler()

    private func flow(answer: PermissionStatus) -> OnboardingFlow {
        let permissions = PresetPermissionService(status: .notDetermined, requestResult: answer)
        let surprises = SurpriseCoordinator(
            context: container.mainContext, notifications: notifications, permissions: permissions,
            clock: TestDateProvider(), calendar: { DeviceCalendar("Europe/Berlin").calendar },
            generator: SeededRandomNumberGenerator(seed: 1)
        )
        let flow = OnboardingFlow(
            permissions: permissions, store: SwiftDataOnboardingStore(context: container.mainContext),
            surprises: OnboardingSurprises(surprises)
        )
        flow.finishIntro()
        return flow
    }

    private var prompts: [SurprisePrompt] { (try? container.mainContext.fetch(FetchDescriptor<SurprisePrompt>())) ?? [] }

    /// The plan and the first surprise, which takes one of its day's places.
    @Test func enablingRemindersPlansTheFirstSurprises() async {
        let flow = flow(answer: .granted)
        flow.schedule.frequency = .twiceADay
        await flow.enableReminders()
        #expect(prompts.count == 28)
        #expect(await notifications.pending().count == 28)
        #expect(prompts.count { $0.notificationRequestID.hasPrefix(SurpriseCoordinator.firstPrefix) } == 1)
    }

    /// Denied or "Maybe later": no plan, only the first surprise, shown in the app.
    @Test func deniedOrLaterPlansOnlyTheFirstSurprise() async {
        await flow(answer: .denied).enableReminders()
        #expect(prompts.count == 1)
        flow(answer: .granted).remindLater()
        for _ in 0..<50 { await Task.yield() }
        #expect(prompts.count == 1)
        #expect(prompts.allSatisfy { $0.notificationRequestID.hasPrefix(SurpriseCoordinator.firstPrefix) })
    }
}

@MainActor
struct SurpriseNotificationHandlerTests {
    @Test func aTapBeforeTheUIListensWaitsForIt() {
        let handler = SurpriseNotificationHandler()
        let id = UUID()
        handler.deliver(id)
        var opened: [UUID] = []
        handler.listen { opened.append($0) }
        #expect(opened == [id])
        // Delivered once, then straight through.
        let next = UUID()
        handler.deliver(next)
        #expect(opened == [id, next])
    }
}

/// rev-app 10: the background wake-up the app asks iOS for, to plan surprises while it isn't opened.
struct SurpriseBackgroundRefreshTests {
    @Test func theWakeUpIsAskedForHalfADayOnUnderItsPermittedName() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let request = SurpriseBackgroundRefresh.request(now: now)
        #expect(request.identifier == "com.mrmaier.MimoDays.surprises")
        #expect(request.earliestBeginDate == now.addingTimeInterval(12 * 60 * 60))
    }
}
