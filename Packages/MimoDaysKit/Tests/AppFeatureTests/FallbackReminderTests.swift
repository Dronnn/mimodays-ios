@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// P8.14: an optional reminder at a chosen time on enabled days with no surprise planned.
@MainActor
struct FallbackReminderTests {
    private let container = try! TestStore.container()
    private let notifications = FakeNotificationScheduler()
    private let clock = TestDateProvider()
    private let schedule = SurpriseSchedule()
    private let defaults = UserDefaults(suiteName: "FallbackReminderTests-\(UUID().uuidString)")!
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    init() {
        container.mainContext.insert(schedule)
        clock.set(date("2026-11-11 06:00")) // Wednesday
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

    private func fallbacks() async -> [SurpriseNotification] {
        await notifications.pending().filter { $0.id.hasPrefix(SurpriseCoordinator.fallbackPrefix) }
    }

    @Test func offByDefault() async {
        schedule.frequency = .threeAWeek
        let coordinator = coordinator()
        #expect(coordinator.fallback == FallbackReminder())
        await coordinator.refresh()
        #expect(await fallbacks().isEmpty)
    }

    /// Delete All starts over: the reminder is off again, as on a new install (rev-surprises 4).
    @Test func deleteAllTurnsItOff() async {
        let coordinator = coordinator()
        await coordinator.setFallback(FallbackReminder(isOn: true, minute: 20 * 60))
        coordinator.resetSettings()
        #expect(coordinator.fallback == FallbackReminder())
        #expect(self.coordinator().fallback == FallbackReminder())
    }

    /// 8:00 PM when the hours allow it, else the latest time inside them.
    @Test func itStartsAtEightOrTheLatestTimeThatFits() {
        #expect(FallbackReminder.defaultMinute(earliest: 8 * 60, latest: 22 * 60) == 20 * 60)
        #expect(FallbackReminder.defaultMinute(earliest: 8 * 60, latest: 18 * 60) == 18 * 60)
        #expect(FallbackReminder.defaultMinute(earliest: 21 * 60, latest: 23 * 60) == 21 * 60)
    }

    /// Once a day: every day has its surprise, so there's no reminder.
    @Test func aDailyPlanLeavesNoBlankDay() async {
        let coordinator = coordinator()
        await coordinator.setFallback(FallbackReminder(isOn: true, minute: 20 * 60))
        #expect(await fallbacks().isEmpty)
    }

    /// Three a week: the blank days get one reminder at the chosen time, with its own words and no actions.
    @Test func blankDaysGetOneReminderAtTheTime() async throws {
        schedule.frequency = .threeAWeek
        let coordinator = coordinator()
        await coordinator.setFallback(FallbackReminder(isOn: true, minute: 20 * 60))
        let prompts = try context.fetch(FetchDescriptor<SurprisePrompt>()).filter { $0.outcome == .pending }
        // Weeks are drawn whole, so some surprises fall past the two weeks the reminders cover.
        let horizon = date("2026-11-25 00:00")
        let surpriseDays = Set(prompts.map { calendar.startOfDay(for: $0.plannedAt) }.filter { $0 < horizon })
        let reminders = await fallbacks()
        #expect(!reminders.isEmpty)
        for reminder in reminders {
            let day = calendar.startOfDay(for: reminder.fireDate)
            #expect(!surpriseDays.contains(day))
            #expect(calendar.dateComponents([.hour, .minute], from: reminder.fireDate) == DateComponents(hour: 20, minute: 0))
            #expect(reminder.title == "A moment for today" && reminder.body == "If you'd like, take a moment to remember today.")
            #expect(reminder.categoryID == nil)
        }
        // Every day in the two weeks has a surprise or a reminder, once.
        let reminderDays = reminders.map { calendar.startOfDay(for: $0.fireDate) }
        #expect(Set(reminderDays).count == reminderDays.count)
        #expect(surpriseDays.union(reminderDays).count == 14)
        // Again, or after a relaunch: the same, nothing doubled.
        await self.coordinator().refresh()
        #expect(await fallbacks().map(\.id) == reminders.map(\.id))
    }

    /// Only on enabled days; never while paused, off or outside the hours.
    @Test func onlyOnEnabledUnpausedDaysInsideTheHours() async {
        schedule.frequency = .threeAWeek
        schedule.weekdayMask = 0b011_1110 // Monday to Friday
        let coordinator = coordinator()
        await coordinator.setFallback(FallbackReminder(isOn: true, minute: 20 * 60))
        for reminder in await fallbacks() {
            let weekday = calendar.component(.weekday, from: reminder.fireDate)
            #expect((2...6).contains(weekday))
        }
        await coordinator.setFallback(FallbackReminder(isOn: true, minute: 23 * 60))
        #expect(await fallbacks().isEmpty)
        await coordinator.setFallback(FallbackReminder(isOn: true, minute: 20 * 60))
        await coordinator.pause(.week)
        #expect(await fallbacks().allSatisfy { $0.fireDate >= date("2026-11-18 00:00") })
        schedule.isEnabled = false
        await coordinator.settingsChanged()
        #expect(await fallbacks().isEmpty)
    }

    /// A new time replaces the reminders; turning it off removes them.
    @Test func aNewTimeReplacesThemAndOffRemovesThem() async {
        schedule.frequency = .threeAWeek
        let coordinator = coordinator()
        await coordinator.setFallback(FallbackReminder(isOn: true, minute: 20 * 60))
        let ids = await fallbacks().map(\.id)
        await coordinator.setFallback(FallbackReminder(isOn: true, minute: 19 * 60 + 30))
        let moved = await fallbacks()
        #expect(moved.map(\.id) == ids)
        #expect(moved.allSatisfy { calendar.dateComponents([.hour, .minute], from: $0.fireDate) == DateComponents(hour: 19, minute: 30) })
        await coordinator.setFallback(FallbackReminder(isOn: false, minute: 19 * 60 + 30))
        #expect(await fallbacks().isEmpty)
        #expect(self.coordinator().fallback == FallbackReminder(isOn: false, minute: 19 * 60 + 30))
    }

    /// Not today once its time has passed: no catch-up.
    @Test func noCatchUp() async {
        schedule.frequency = .threeAWeek
        clock.set(date("2026-11-11 20:30"))
        await coordinator().setFallback(FallbackReminder(isOn: true, minute: 20 * 60))
        #expect(await fallbacks().allSatisfy { $0.fireDate > clock.now() })
    }

    /// iOS turned it down: Settings says so.
    @Test func aFailedScheduleIsReported() async {
        schedule.frequency = .threeAWeek
        await notifications.setScheduleError(.unavailable)
        let coordinator = coordinator()
        await coordinator.setFallback(FallbackReminder(isOn: true, minute: 20 * 60))
        #expect(coordinator.fallbackFailed)
        await notifications.setScheduleError(nil)
        await coordinator.refresh()
        #expect(!coordinator.fallbackFailed)
    }

    /// A tap on it opens the plain camera, through App Lock like a shortcut.
    @Test func aTapOpensThePlainCamera() {
        _ = CameraShortcut.take()
        SurpriseNotificationHandler.opened(requestID: SurpriseCoordinator.fallbackPrefix + "20261111")
        #expect(CameraShortcut.take())
        SurpriseNotificationHandler.opened(requestID: UUID().uuidString)
        #expect(!CameraShortcut.take())
    }
}
