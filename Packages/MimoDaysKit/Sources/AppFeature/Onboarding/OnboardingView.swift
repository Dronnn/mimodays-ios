import SwiftUI

/// Flow 01 after launch: intro pages, reminder setup and its outcome, the first capture.
/// `onFinish` gets the tab to land on.
struct OnboardingView: View {
    @Bindable var flow: OnboardingFlow
    let onFinish: (MainTab) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch flow.step {
            case .intro:
                OnboardingIntroView(page: $flow.page, onFinish: flow.finishIntro)
            case .schedule:
                ReminderScheduleView(
                    schedule: $flow.schedule,
                    back: flow.backToIntro,
                    enable: { Task { await flow.enableReminders() } },
                    later: flow.remindLater
                )
            case let .reminders(outcome):
                RemindersResultView(outcome: outcome, schedule: flow.schedule, next: flow.finishReminders) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            case .firstCapture:
                FirstCaptureView(capture: flow.startFirstCapture) { onFinish(.today) }
            case .firstMomentSaved:
                if let moment = flow.firstMoment {
                    FirstMomentView(moment: moment) { onFinish(.memories) } done: { onFinish(.today) }
                }
            }
        }
        .animation(.default, value: flow.step)
        .fullScreenCover(isPresented: $flow.isCapturing) {
            CaptureFlowView(request: CaptureRequest())
        }
    }
}
