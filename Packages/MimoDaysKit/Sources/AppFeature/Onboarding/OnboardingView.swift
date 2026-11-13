import SwiftUI

/// Flow 01 after launch: intro pages, reminder setup and its outcome. The first capture follows (OB-08).
struct OnboardingView: View {
    @Bindable var flow: OnboardingFlow
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
                EmptyView()
            }
        }
        .animation(.default, value: flow.step)
    }
}
