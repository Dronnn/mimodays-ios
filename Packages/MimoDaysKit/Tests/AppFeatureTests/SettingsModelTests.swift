@testable import AppFeature
@testable import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

/// 13.2 and 13.10: surprise settings are saved at once, survive a relaunch, and replan the coming notifications.
@MainActor
@Suite(.serialized)
struct SettingsModelTests {
    private let container = try! TestStore.container()
    private let store: MediaStore
    private let notifications = FakeNotificationScheduler()
    private let clock = TestDateProvider()

    init() throws {
        store = try MediaStore(root: FileManager.default.temporaryDirectory.appending(path: "Settings-\(UUID().uuidString)"))
    }

    private var library: MediaLibrary { MediaLibrary(context: container.mainContext, store: store, thumbnails: ThumbnailPipeline()) }

    private func model(_ permissions: any PermissionService = PresetPermissionService(status: .granted)) -> SettingsModel {
        let surprises = SurpriseCoordinator(context: container.mainContext, notifications: notifications, permissions: permissions, clock: clock)
        return SettingsModel(library: library, surprises: surprises, permissions: permissions)
    }

    private func fallbackModel(suite: String = "SettingsFallback-\(UUID().uuidString)") -> (SettingsModel, SurpriseCoordinator) {
        let permissions = PresetPermissionService(status: .granted)
        let surprises = SurpriseCoordinator(
            context: container.mainContext, notifications: notifications, permissions: permissions, clock: clock,
            defaults: UserDefaults(suiteName: suite)
        )
        return (SettingsModel(library: library, surprises: surprises, permissions: permissions), surprises)
    }

    /// KK01/KK02: off by default; on, it starts at 8:00 PM when that fits the hours, else at their latest time.
    @Test func theFallbackReminderStartsAtEightOrTheLatestTime() async {
        let suite = "SettingsFallback-\(UUID().uuidString)"
        let (model, surprises) = fallbackModel(suite: suite)
        await model.load()
        await model.setSurprises(true)
        #expect(!model.fallback.isOn)
        model.reminders.setLatest(18 * 60)
        await model.replanning?.value
        await model.setFallback(isOn: true)
        #expect(model.fallback == FallbackReminder(isOn: true, minute: 18 * 60))
        #expect(surprises.fallback == model.fallback)
        await model.setFallbackMinute(17 * 60 + 30)
        await model.setFallback(isOn: false)
        // Off keeps the time for the next time it's on.
        #expect(surprises.fallback == FallbackReminder(isOn: false, minute: 17 * 60 + 30))
        let (relaunched, _) = fallbackModel(suite: suite)
        await relaunched.load()
        #expect(relaunched.fallback == FallbackReminder(isOn: false, minute: 17 * 60 + 30))
    }

    /// KK03: a time outside the surprise hours is kept, said, and not scheduled.
    @Test func aTimeOutsideTheHoursIsSaid() async {
        let (model, _) = fallbackModel()
        await model.load()
        await model.setSurprises(true)
        await model.setFallback(isOn: true)
        #expect(!model.fallbackOutsideHours)
        await model.setFallbackMinute(23 * 60)
        #expect(model.fallbackOutsideHours)
        model.reminders.setLatest(23 * 60 + 30)
        #expect(!model.fallbackOutsideHours)
        // The replan reads the store: it ends before the test's store goes.
        await model.replanning?.value
    }

    /// KK05: iOS turned it down: the row says so, and Try again schedules it once it can.
    @Test func aFailedFallbackIsSaidAndTriedAgain() async {
        let (model, _) = fallbackModel()
        await model.load()
        await model.setSurprises(true)
        model.reminders.frequency = .threeAWeek
        await model.replanning?.value
        await notifications.setScheduleError(.unavailable)
        await model.setFallback(isOn: true)
        #expect(model.fallbackFailed)
        await notifications.setScheduleError(nil)
        await model.retryFallback()
        #expect(!model.fallbackFailed)
    }

    private func schedule() throws -> SurpriseSchedule? {
        try container.mainContext.fetch(FetchDescriptor<SurpriseSchedule>()).first
    }

    @Test func changesAreSavedAndComeBackAfterARelaunch() async throws {
        let model = model()
        await model.load()
        await model.setSurprises(true)
        model.reminders.frequency = .twiceADay
        model.reminders.setEarliest(10 * 60)
        model.expiryMinutes = 30
        await model.replanning?.value

        let stored = try #require(try schedule())
        #expect(stored.isEnabled)
        #expect(stored.frequency == .twiceADay)
        #expect(stored.earliestMinute == 10 * 60)
        #expect(stored.expiryMinutes == 30)

        let relaunched = self.model()
        await relaunched.load()
        #expect(relaunched.surprisesOn)
        #expect(relaunched.reminders.frequency == .twiceADay)
        #expect(relaunched.reminders.earliestMinute == 10 * 60)
        #expect(relaunched.expiryMinutes == 30)
    }

    /// Back from iOS Settings, a change made while the notification status is still being read is kept.
    @Test func aChangeWhileLoadingIsSaved() async throws {
        let first = model()
        await first.load()
        await first.setSurprises(true)
        await first.replanning?.value
        let model = model()
        let loading = Task { await model.load() }
        while model.surprisesOn == false { await Task.yield() }
        model.reminders.frequency = .twiceADay
        await loading.value
        await model.replanning?.value
        #expect(try #require(try schedule()).frequency == .twiceADay)
    }

    @Test func aChangeDrawsTheComingSurprisesAgain() async throws {
        let model = model()
        await model.load()
        await model.setSurprises(true)
        await model.replanning?.value
        #expect(await notifications.pending().allSatisfy { $0.fireDate.timeIntervalSince(clock.now()) >= 0 })
        model.expiryMinutes = 60
        await model.replanning?.value
        let prompts = try container.mainContext.fetch(FetchDescriptor<SurprisePrompt>()).filter { $0.outcome == .pending }
        #expect(!prompts.isEmpty)
        #expect(prompts.allSatisfy { $0.expiresAt == $0.plannedAt.addingTimeInterval(60 * 60) })
    }

    @Test func turningSurprisesOffClearsWhatIsPending() async throws {
        let model = model()
        await model.load()
        await model.setSurprises(true)
        await model.replanning?.value
        #expect(await !notifications.pending().isEmpty)
        await model.setSurprises(false)
        await model.replanning?.value
        #expect(await notifications.pending().isEmpty)
        #expect(try schedule()?.isEnabled == false)
    }

    @Test func turningSurprisesOnAsksForNotificationsOnce() async throws {
        let permissions = FakePermissionService(requestResults: [.notifications: .denied])
        let model = model(permissions)
        await model.load()
        await model.setSurprises(true)
        #expect(model.notifications == .denied)
        await model.setSurprises(false)
        await model.setSurprises(true)
        // Turning it off replans in the background; the store must outlive it.
        await model.replanning?.value
        #expect(await permissions.requested == [.notifications])
    }

    @Test func aPauseShowsAndEnds() async throws {
        let model = model()
        await model.load()
        await model.setSurprises(true)
        await model.pause(.week)
        guard case .until = model.pause else { Issue.record("not paused: \(model.pause)"); return }
        await model.pause(.indefinitely)
        #expect(model.pause == .indefinitely)
        await model.resume()
        #expect(model.pause == .off)
    }
}
