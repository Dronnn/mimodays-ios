@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// P8.7: "Remind me later" on a surprise's notification brings the same surprise back once, later the same day.
@MainActor
struct RemindLaterTests {
    private let container = try! TestStore.container()
    private let notifications = FakeNotificationScheduler()
    private let clock = TestDateProvider()
    private let schedule = SurpriseSchedule()
    private let defaults = UserDefaults(suiteName: "RemindLaterTests-\(UUID().uuidString)")!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    init() {
        container.mainContext.insert(schedule)
    }

    private var context: ModelContext { container.mainContext }

    private func date(_ string: String) -> Date {
        let parts = string.split(whereSeparator: { "- :".contains($0) }).map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4]))!
    }

    private func coordinator(_ permission: PermissionStatus = .granted) -> SurpriseCoordinator {
        let calendar = calendar
        return SurpriseCoordinator(
            context: context, notifications: notifications, permissions: PresetPermissionService(status: permission),
            clock: clock, calendar: { calendar }, generator: SeededRandomNumberGenerator(seed: 1), defaults: defaults
        )
    }

    /// A surprise that came at `time` and is open for 15 minutes; tomorrow's is planned too, so a refresh adds nothing today.
    @discardableResult
    private func surprise(at time: String, prefix: String = "") -> SurprisePrompt {
        let id = UUID()
        let planned = date(time)
        let prompt = SurprisePrompt(id: id, plannedAt: planned, expiresAt: planned.addingTimeInterval(15 * 60), notificationRequestID: prefix + id.uuidString)
        context.insert(prompt)
        try! context.save()
        return prompt
    }

    @Test func itComesBackHalfAnHourLaterWithAFreshWindowOnce() async {
        let prompt = surprise(at: "2026-11-11 10:00")
        clock.set(date("2026-11-11 10:02"))
        let coordinator = coordinator()
        #expect(await coordinator.remindLater(promptID: prompt.id) == .later(date("2026-11-11 10:32")))
        #expect(prompt.plannedAt == date("2026-11-11 10:32"))
        #expect(prompt.expiresAt == date("2026-11-11 10:47"))
        #expect(prompt.notificationRequestID == SurpriseCoordinator.retryPrefix + prompt.id.uuidString)
        #expect(prompt.outcome == .pending)
        let pending = await notifications.pending()
        #expect(pending.map(\.id) == [prompt.notificationRequestID])
        #expect(pending.first?.promptID == prompt.id.uuidString)
        // The retry has no second "Remind me later".
        #expect(pending.first?.categoryID == nil)
        // A second press, or the retry's own, does nothing more.
        clock.set(date("2026-11-11 10:33"))
        #expect(await coordinator.remindLater(promptID: prompt.id) == .ignored)
        #expect(prompt.plannedAt == date("2026-11-11 10:32"))
    }

    /// The first notification, tapped after "Remind me later", opens a plain camera: the surprise is the retry's now.
    @Test func theFirstNotificationGoesStale() async {
        let prompt = surprise(at: "2026-11-11 10:00")
        clock.set(date("2026-11-11 10:02"))
        let coordinator = coordinator()
        await coordinator.remindLater(promptID: prompt.id)
        clock.set(date("2026-11-11 10:05"))
        #expect(!coordinator.open(promptID: prompt.id))
        #expect(prompt.outcome == .pending)
        clock.set(date("2026-11-11 10:33"))
        #expect(coordinator.open(promptID: prompt.id))
    }

    /// Clamped earlier while at least 5 minutes away and the whole window fits in the hours (until 22:00).
    @Test func lateInTheDayItComesSoonerOrNotAtAll() async {
        let prompt = surprise(at: "2026-11-11 21:25")
        clock.set(date("2026-11-11 21:30"))
        #expect(await coordinator().remindLater(promptID: prompt.id) == .later(date("2026-11-11 21:45")))

        let late = surprise(at: "2026-11-11 21:35")
        clock.set(date("2026-11-11 21:42"))
        let coordinator = coordinator()
        #expect(await coordinator.remindLater(promptID: late.id) == .failed(.noTime))
        #expect(late.plannedAt == date("2026-11-11 21:35"))
        #expect(late.notificationRequestID == late.id.uuidString)
        #expect(await coordinator.todayStatus(latestCapture: nil).status == .ready(promptID: late.id))
    }

    /// Not into another planned surprise's window.
    @Test func itStaysClearOfTheNextSurprise() async {
        let prompt = surprise(at: "2026-11-11 10:00")
        surprise(at: "2026-11-11 10:40")
        clock.set(date("2026-11-11 10:02"))
        #expect(await coordinator().remindLater(promptID: prompt.id) == .later(date("2026-11-11 10:25")))
    }

    @Test func pausedSurprisesLeaveNoTime() async {
        let prompt = surprise(at: "2026-11-11 10:00")
        schedule.pausedUntil = date("2026-11-12 00:00")
        clock.set(date("2026-11-11 10:02"))
        #expect(await coordinator().remindLater(promptID: prompt.id) == .failed(.noTime))
    }

    /// Only an ordinary surprise that came and can still be answered; never "Send a surprise now" or onboarding's.
    @Test func onlyALiveOrdinarySurprise() async {
        let sentNow = surprise(at: "2026-11-11 10:00", prefix: SurpriseCoordinator.sendNowPrefix)
        let first = surprise(at: "2026-11-11 10:01", prefix: SurpriseCoordinator.firstPrefix)
        let expired = surprise(at: "2026-11-11 09:00")
        let later = surprise(at: "2026-11-11 12:00")
        let captured = surprise(at: "2026-11-11 09:55")
        captured.outcome = .captured
        clock.set(date("2026-11-11 10:02"))
        let coordinator = coordinator()
        for prompt in [sentNow, first, expired, later, captured] {
            #expect(await coordinator.remindLater(promptID: prompt.id) == .ignored)
        }
        #expect(await coordinator.remindLater(promptID: UUID()) == .ignored)
    }

    /// iOS turned it down: the surprise stays as it was, still open, and Today says so until the day changes.
    @Test func aFailedScheduleLeavesTheSurpriseAsItWas() async {
        let prompt = surprise(at: "2026-11-11 10:00")
        clock.set(date("2026-11-11 10:02"))
        await notifications.setScheduleError(.unavailable)
        let coordinator = coordinator()
        #expect(await coordinator.remindLater(promptID: prompt.id) == .failed(.failed))
        #expect(prompt.plannedAt == date("2026-11-11 10:00"))
        #expect(prompt.notificationRequestID == prompt.id.uuidString)
        // The live surprise comes first; once it's gone, the note.
        #expect(await coordinator.todayStatus(latestCapture: nil).status == .ready(promptID: prompt.id))
        clock.set(date("2026-11-11 10:20"))
        #expect(await coordinator.todayStatus(latestCapture: nil).status == .retryFailed(.failed))
        // A relaunch still knows; the next day doesn't.
        #expect(await self.coordinator().todayStatus(latestCapture: nil).status == .retryFailed(.failed))
        clock.set(date("2026-11-12 07:00"))
        #expect(await self.coordinator().todayStatus(latestCapture: nil).status != .retryFailed(.failed))
    }

    /// Today: "A little later" while it waits, then the surprise as usual.
    @Test func todaySaysALittleLater() async {
        let prompt = surprise(at: "2026-11-11 10:00")
        clock.set(date("2026-11-11 10:02"))
        let coordinator = coordinator()
        await coordinator.remindLater(promptID: prompt.id)
        #expect(await coordinator.todayStatus(latestCapture: nil).status == .later)
        clock.set(date("2026-11-11 10:33"))
        #expect(await coordinator.todayStatus(latestCapture: nil).status == .ready(promptID: prompt.id))
    }

    /// The retry survives a relaunch's refresh: it fits the hours, so nothing is drawn again.
    @Test func aRefreshKeepsTheRetry() async {
        let prompt = surprise(at: "2026-11-11 10:00")
        clock.set(date("2026-11-11 10:02"))
        await coordinator().remindLater(promptID: prompt.id)
        await coordinator().refresh()
        #expect(prompt.outcome == .pending)
        #expect(prompt.plannedAt == date("2026-11-11 10:32"))
        #expect(await notifications.pending().contains { $0.id == prompt.notificationRequestID })
    }

    /// Ordinary surprises carry the "Remind me later" action; the others don't.
    @Test func onlyOrdinarySurprisesOfferIt() async {
        clock.set(date("2026-11-11 06:00"))
        await coordinator().refresh()
        let pending = await notifications.pending()
        #expect(!pending.isEmpty)
        #expect(pending.allSatisfy { $0.categoryID == SurpriseCoordinator.remindLaterCategory })
    }

    /// A replan (new answer window, hours that still fit) keeps the surprise that is coming back, with the new window,
    /// and counts it for its day.
    @Test func aReplanKeepsAFittingRetry() async {
        let prompt = surprise(at: "2026-11-11 10:00")
        clock.set(date("2026-11-11 10:02"))
        let coordinator = coordinator()
        await coordinator.remindLater(promptID: prompt.id)
        schedule.expiryMinutes = 30
        await coordinator.settingsChanged()
        #expect(prompt.outcome == .pending)
        #expect(prompt.plannedAt == date("2026-11-11 10:32"))
        #expect(prompt.expiresAt == date("2026-11-11 11:02"))
        #expect(await notifications.pending().contains { $0.id == prompt.notificationRequestID })
    }

    /// Answered from Today while it was coming back: the retry's notification goes.
    @Test func aCaptureCancelsTheRetry() async throws {
        let prompt = surprise(at: "2026-11-11 10:00")
        clock.set(date("2026-11-11 10:01"))
        let coordinator = coordinator()
        #expect(coordinator.open(promptID: prompt.id))
        clock.set(date("2026-11-11 10:02"))
        await coordinator.remindLater(promptID: prompt.id)
        let moment = Moment(captured: CaptureTime(instant: date("2026-11-11 10:03"), timeZone: calendar.timeZone), origin: .randomPrompt, mediaType: .photo, createdAt: date("2026-11-11 10:03"))
        context.insert(moment)
        try context.save()
        coordinator.captured(promptID: prompt.id, momentID: moment.id)
        #expect(prompt.outcome == .captured)
        for _ in 0..<100 where await notifications.pending().contains(where: { $0.id == prompt.notificationRequestID }) {
            await Task.yield()
        }
        #expect(await !notifications.pending().contains { $0.id == prompt.notificationRequestID })
    }

    /// On the spring clock change the hours still close at 22:00 on the clock: the whole window fits before it.
    @Test func theHoursCloseOnTheClockOnAClockChangeDay() async {
        let prompt = surprise(at: "2027-03-28 21:20")
        clock.set(date("2027-03-28 21:25"))
        #expect(await coordinator().remindLater(promptID: prompt.id) == .later(date("2027-03-28 21:45")))
    }

    /// Paused after "Remind me later" failed: Today offers Resume rather than the failure.
    @Test func pauseComesBeforeAFailedRetry() async {
        let prompt = surprise(at: "2026-11-11 10:00")
        clock.set(date("2026-11-11 10:02"))
        await notifications.setScheduleError(.unavailable)
        let coordinator = coordinator()
        #expect(await coordinator.remindLater(promptID: prompt.id) == .failed(.failed))
        clock.set(date("2026-11-11 10:20"))
        #expect(await coordinator.todayStatus(latestCapture: nil).status == .retryFailed(.failed))
        await coordinator.pause(.indefinitely)
        #expect(await coordinator.todayStatus(latestCapture: nil).status == .paused(until: nil))
    }
}
