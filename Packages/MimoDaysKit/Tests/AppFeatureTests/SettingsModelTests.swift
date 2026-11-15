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
    private let container = try! MimoDaysStore.makeContainer(inMemory: true)
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
