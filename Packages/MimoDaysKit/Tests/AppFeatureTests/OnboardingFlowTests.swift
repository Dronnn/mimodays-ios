@testable import AppFeature
import Core
import Testing

@MainActor
struct OnboardingFlowTests {
    @Test func startsOnTheFirstIntroPage() {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined))
        #expect(flow.step == .intro)
        #expect(flow.page == .welcome)
    }

    @Test func introLeadsToScheduleAndBackKeepsThePage() {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined))
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
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined, requestResult: answer))
        flow.finishIntro()
        await flow.enableReminders()
        #expect(flow.step == .reminders(outcome))
    }

    @Test func maybeLaterSkipsThePrompt() {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined))
        flow.finishIntro()
        flow.remindLater()
        #expect(flow.step == .reminders(.later))
    }

    @Test(arguments: RemindersOutcome.allCases)
    func everyOutcomeContinuesToTheFirstCapture(outcome: RemindersOutcome) {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .notDetermined))
        flow.step = .reminders(outcome)
        flow.finishReminders()
        #expect(flow.step == .firstCapture)
    }
}
