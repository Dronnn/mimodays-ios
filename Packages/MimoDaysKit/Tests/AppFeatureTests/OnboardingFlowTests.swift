@testable import AppFeature
import Core
import Foundation
import Testing

@MainActor
struct OnboardingFlowTests {
    @Test func startsOnTheFirstIntroPage() {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined), store: InMemoryOnboardingStore())
        #expect(flow.step == .intro)
        #expect(flow.page == .welcome)
    }

    @Test func introLeadsToScheduleAndBackKeepsThePage() {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined), store: InMemoryOnboardingStore())
        flow.page = .privacy
        flow.finishIntro()
        #expect(flow.step == .schedule)
        flow.backToIntro()
        #expect(flow.step == .intro)
        #expect(flow.page == .privacy)
    }

    @Test(arguments: [
        (PermissionStatus.granted, RemindersOutcome.on),
        (.limited, .on),
        (.denied, .denied),
        (.restricted, .denied),
        (.notDetermined, .later),
    ])
    func enableRemindersFollowsTheSystemAnswer(answer: PermissionStatus, outcome: RemindersOutcome) async {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined, requestResult: answer), store: InMemoryOnboardingStore())
        flow.finishIntro()
        await flow.enableReminders()
        #expect(flow.step == .reminders(outcome))
    }

    @Test func maybeLaterSkipsThePrompt() {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined), store: InMemoryOnboardingStore())
        flow.finishIntro()
        flow.remindLater()
        #expect(flow.step == .reminders(.later))
    }

    @Test(arguments: RemindersOutcome.allCases)
    func everyOutcomeContinuesToTheFirstCapture(outcome: RemindersOutcome) {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined), store: InMemoryOnboardingStore())
        flow.step = .reminders(outcome)
        flow.finishReminders()
        #expect(flow.step == .firstCapture)
    }

    @Test func firstCaptureOpensTheCameraAndASaveShowsTheMoment() {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined), store: InMemoryOnboardingStore())
        flow.step = .firstCapture
        flow.startFirstCapture()
        #expect(flow.isCapturing)
        let savedAt = Date(timeIntervalSince1970: 1_000)
        flow.firstMomentSaved(SavedMoment(photo: .placeholder, selfie: nil, capturedAt: savedAt))
        #expect(!flow.isCapturing)
        #expect(flow.step == .firstMomentSaved)
        #expect(flow.firstMoment?.capturedAt == savedAt)
    }

    @Test func closingTheCameraWithoutSavingStaysOnTheInvitation() {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined), store: InMemoryOnboardingStore())
        flow.step = .firstCapture
        flow.startFirstCapture()
        flow.isCapturing = false
        #expect(flow.step == .firstCapture)
        #expect(flow.firstMoment == nil)
    }
}
