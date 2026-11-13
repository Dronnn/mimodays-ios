@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing

/// Resuming after the app closes mid-onboarding (Andrew, 2026-11-13: same screen, results kept).
@MainActor
struct OnboardingResumeTests {
    private func flow(_ store: any OnboardingStore, answer: PermissionStatus = .granted) -> OnboardingFlow {
        OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined, requestResult: answer), store: store)
    }

    @Test func resumesOnTheSameIntroPage() {
        let store = InMemoryOnboardingStore()
        flow(store).page = .voice
        let resumed = flow(store)
        #expect(resumed.step == .intro)
        #expect(resumed.page == .voice)
    }

    @Test func resumesOnTheScheduleWithEditsKept() {
        let store = InMemoryOnboardingStore()
        let first = flow(store)
        first.finishIntro()
        first.schedule.frequency = .threeADay
        first.schedule.toggle(1)
        first.schedule.setEarliest(10 * 60)
        let resumed = flow(store)
        #expect(resumed.step == .schedule)
        #expect(resumed.schedule == first.schedule)
        #expect(!store.record.remindersEnabled)
    }

    @Test(arguments: [(PermissionStatus.granted, true), (.denied, true)])
    func enableKeepsRemindersOnEvenIfDenied(answer: PermissionStatus, enabled: Bool) async {
        let store = InMemoryOnboardingStore()
        let first = flow(store, answer: answer)
        first.finishIntro()
        await first.enableReminders()
        #expect(store.record.remindersEnabled == enabled)
        #expect(flow(store).step == .firstCapture)
    }

    @Test func maybeLaterSavesRemindersOffAndMovesOn() {
        let store = InMemoryOnboardingStore()
        let first = flow(store)
        first.finishIntro()
        first.remindLater()
        #expect(!store.record.remindersEnabled)
        #expect(flow(store).step == .firstCapture)
    }

    @Test func aSavedFirstMomentCompletesOnboarding() {
        let store = InMemoryOnboardingStore(OnboardingRecord(step: 7))
        let first = flow(store)
        #expect(first.step == .firstCapture)
        first.firstMomentSaved(SavedMoment(photo: .placeholder, selfie: nil, capturedAt: .now))
        #expect(store.record.isCompleted)
        #expect(flow(store).isCompleted)
    }

    @Test func finishingCompletesOnboarding() {
        let store = InMemoryOnboardingStore(OnboardingRecord(step: 7))
        flow(store).finish()
        #expect(store.record.isCompleted)
    }

    @Test func unknownStepsFallBackSafely() {
        #expect(flow(InMemoryOnboardingStore(OnboardingRecord(step: -3))).page == .welcome)
        #expect(flow(InMemoryOnboardingStore(OnboardingRecord(step: 99))).step == .firstCapture)
    }

    @Test func swiftDataStoreRoundTrips() throws {
        let container = try MimoDaysStore.makeContainer(inMemory: true)
        let store = SwiftDataOnboardingStore(context: container.mainContext)
        #expect(store.load() == OnboardingRecord())

        var schedule = ReminderSchedule()
        schedule.frequency = .threeAWeek
        schedule.toggle(4)
        schedule.setLatest(20 * 60)
        let record = OnboardingRecord(isCompleted: false, step: 6, schedule: schedule, remindersEnabled: true)
        store.save(record)
        store.save(record)
        #expect(SwiftDataOnboardingStore(context: container.mainContext).load() == record)

        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<AppPreferences>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SurpriseSchedule>()) == 1)
        let stored = try #require(try context.fetch(FetchDescriptor<SurpriseSchedule>()).first)
        #expect(stored.weekdayMask == 0b111_0111)
        #expect(stored.latestMinute == 20 * 60)
        #expect(stored.isEnabled)
    }
}
