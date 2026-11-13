import Core
import Observation

/// Where onboarding is (flow 01): intro pages, reminder setup, its outcome, then the first capture.
enum OnboardingStep: Equatable {
    case intro
    case schedule
    case reminders(RemindersOutcome)
    case firstCapture
}

/// O08b / O08c.
enum RemindersOutcome: Equatable, CaseIterable {
    case on
    /// "Don't Allow" now or earlier: only iOS Settings can turn them on.
    case denied
    /// "Maybe later": the system prompt hasn't been shown.
    case later
}

@MainActor
@Observable
final class OnboardingFlow {
    var step: OnboardingStep = .intro
    var page: OnboardingPage = .welcome
    var schedule = ReminderSchedule()

    private let permissions: any PermissionService

    init(permissions: any PermissionService) {
        self.permissions = permissions
    }

    /// Continue on the last page, or Skip on any page.
    func finishIntro() {
        step = .schedule
    }

    func backToIntro() {
        step = .intro
    }

    /// "Enable reminders": the system prompt, or its earlier answer.
    func enableReminders() async {
        let status = await permissions.request(.notifications)
        step = .reminders(status.isUsable ? .on : status.needsSettings ? .denied : .later)
    }

    func remindLater() {
        step = .reminders(.later)
    }

    func finishReminders() {
        step = .firstCapture
    }
}
