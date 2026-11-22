@testable import AppFeature
import Core
import Foundation
import Persistence
import SwiftData
import Testing
import TestSupport

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

    @Test func maybeLaterOnAReplayKeepsSurprisesOn() {
        let store = InMemoryOnboardingStore(OnboardingRecord(isCompleted: true, step: 7, remindersEnabled: true))
        let replay = flow(store)
        replay.restart()
        replay.finishIntro()
        replay.remindLater()
        #expect(store.record.remindersEnabled)
        #expect(replay.step == .reminders(.later))
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

    /// §V17: the pages added in 1.0.7 don't move the numbers 1.0.6 saved.
    @Test(arguments: [
        (0, OnboardingPage.welcome), (1, .surprise), (2, .dualCamera), (3, .voice), (4, .movie), (5, .privacy),
    ])
    func stepsSavedBefore107ResumeOnTheirPage(step: Int, page: OnboardingPage) {
        let resumed = flow(InMemoryOnboardingStore(OnboardingRecord(step: step)))
        #expect(resumed.step == .intro)
        #expect(resumed.page == page)
    }

    @Test func stepsSavedBefore107ResumeOnTheScheduleAndTheFirstCapture() {
        #expect(flow(InMemoryOnboardingStore(OnboardingRecord(step: 6))).step == .schedule)
        #expect(flow(InMemoryOnboardingStore(OnboardingRecord(step: 7))).step == .firstCapture)
    }

    @Test(arguments: OnboardingPage.allCases)
    func everyPageResumes(page: OnboardingPage) {
        let store = InMemoryOnboardingStore()
        flow(store).page = page
        let resumed = flow(store)
        #expect(resumed.step == .intro)
        #expect(resumed.page == page)
    }

    @Test func theNewPagesComeAfterTheVoice() {
        #expect(OnboardingPage.voice.next == .ways)
        #expect(OnboardingPage.ways.next == .widgets)
        #expect(OnboardingPage.widgets.next == .movie)
        #expect(OnboardingPage.allCases.count == 8)
    }

    @Test func unknownStepsFallBackSafely() {
        #expect(flow(InMemoryOnboardingStore(OnboardingRecord(step: -3))).page == .welcome)
        #expect(flow(InMemoryOnboardingStore(OnboardingRecord(step: 99))).step == .firstCapture)
    }

    @Test func swiftDataStoreRoundTrips() throws {
        let container = try TestStore.container()
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

    @Test func replayStartsOnTheFirstPageAndStaysFinished() {
        let store = InMemoryOnboardingStore()
        let first = flow(store)
        first.page = .movie
        first.finishIntro()
        first.finish()
        let replay = flow(store)
        replay.restart()
        #expect(replay.step == .intro)
        #expect(replay.page == .welcome)
        #expect(store.record.isCompleted)
        #expect(flow(store).isCompleted)
    }
}
