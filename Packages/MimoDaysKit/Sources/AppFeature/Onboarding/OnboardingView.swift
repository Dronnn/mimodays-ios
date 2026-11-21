import Core
import SwiftUI

/// Flow 01 after launch: intro pages, reminder setup and its outcome, the first capture.
/// `onFinish` gets the tab to land on.
struct OnboardingView: View {
    @Bindable var flow: OnboardingFlow
    let onFinish: (MainTab) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.permissions) private var permissions
    @State private var asker = PermissionAsker()

    var body: some View {
        Group {
            switch flow.step {
            case .intro:
                OnboardingIntroView(page: $flow.page, onFinish: flow.finishIntro)
            case .schedule:
                ReminderScheduleView(
                    schedule: $flow.schedule,
                    back: flow.backToIntro,
                    enable: { Task { await flow.enableReminders { await asker.request($0, using: permissions) } } },
                    later: flow.remindLater
                )
            case let .reminders(outcome):
                RemindersResultView(outcome: outcome, schedule: flow.schedule, next: flow.finishReminders) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            case .firstCapture:
                FirstCaptureView(capture: flow.startFirstCapture) { finish(on: .today) }
            case .firstMomentSaved:
                if let moment = flow.firstMoment {
                    FirstMomentView(moment: moment, surprisesOn: flow.remindersEnabled && flow.remindersAllowed) { finish(on: .memories) } done: { finish(on: .today) }
                }
            }
        }
        .animation(.default, value: flow.step)
        // W03: the first surprise in the app when its notification can't come (P2.4).
        .overlay(alignment: .top) {
            if let promptID = flow.inAppSurprise, !flow.isCapturing {
                SurpriseRibbon(status: .ready(promptID: promptID), now: Date()) { flow.openSurprise(promptID) }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("onboarding.surprise")
            }
        }
        .animation(.snappy, value: flow.inAppSurprise)
        .task(id: [flow.isCapturing ? 1 : 0, flow.surprisesPlanned]) {
            guard !flow.isCapturing else { return }
            await flow.watchFirstSurprise()
        }
        .permissionExplainers(asker)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await flow.recheckReminders() } }
        }
        .fullScreenCover(item: $flow.capture, onDismiss: flow.captureDismissed) { request in
            CaptureFlowView(request: request, promptExpiry: request.promptID.flatMap(flow.expiry)) { saved in
                flow.saved(saved, moment: SavedMoment(
                    photo: saved.main.map { .image(Image(uiImage: $0)) } ?? .placeholder,
                    selfie: saved.selfie.map { .image(Image(uiImage: $0)) },
                    capturedAt: saved.capturedAt
                ))
            }
        }
    }

    private func finish(on tab: MainTab) {
        flow.finish()
        onFinish(tab)
    }
}
