import Core
import DesignSystem
import Foundation
import Observation

/// Where onboarding is (flow 01): intro pages, reminder setup, its outcome, then the first capture.
enum OnboardingStep: Equatable {
    case intro
    case schedule
    case reminders(RemindersOutcome)
    /// O09
    case firstCapture
    /// O10
    case firstMomentSaved
}

/// The moment saved from the first capture, shown on O10.
struct SavedMoment {
    var photo: HeroMedia
    var selfie: HeroMedia?
    var capturedAt: Date
}

/// O08b / O08c.
enum RemindersOutcome: Equatable, CaseIterable {
    case on
    /// "Don't Allow" now or earlier: only iOS Settings can turn them on.
    case denied
    /// "Maybe later": the system prompt hasn't been shown.
    case later
}

/// Onboarding's state machine. Every change is saved, so a later launch resumes on the same screen.
@MainActor
@Observable
final class OnboardingFlow {
    var step: OnboardingStep = .intro { didSet { save() } }
    var page: OnboardingPage = .welcome { didSet { save() } }
    var schedule = ReminderSchedule() { didSet { save() } }
    /// The camera is open for the first capture.
    var isCapturing = false
    private(set) var firstMoment: SavedMoment?
    /// Surprises are on: the reminders choice, or on a replay the person's existing setting.
    private(set) var remindersEnabled = false
    /// Whether iOS lets the reminders through: O10 promises a surprise only then.
    private(set) var remindersAllowed = false
    private(set) var isCompleted = false

    private let permissions: any PermissionService
    private let store: any OnboardingStore
    /// Runs once the reminders choice is saved, so surprises are planned (or dropped) right away.
    private let remindersChanged: @MainActor () async -> Void

    init(permissions: any PermissionService, store: any OnboardingStore, remindersChanged: @escaping @MainActor () async -> Void = {}) {
        self.permissions = permissions
        self.store = store
        self.remindersChanged = remindersChanged
        let record = store.load()
        schedule = record.schedule
        remindersEnabled = record.remindersEnabled
        isCompleted = record.isCompleted
        switch record.step {
        case Self.scheduleStep: step = .schedule
        case Self.firstCaptureStep...: step = .firstCapture
        default: page = OnboardingPage(rawValue: max(record.step, 0)) ?? .welcome
        }
    }

    /// Continue on the last page, or Skip on any page.
    func finishIntro() {
        step = .schedule
    }

    func backToIntro() {
        guard !isEnablingReminders else { return }
        step = .intro
    }

    /// From "Enable reminders" until iOS has answered: Back and Maybe later wait, so a late answer can't undo them.
    private(set) var isEnablingReminders = false

    /// "Enable reminders": our explainer and the system prompt (through `request`), or the earlier answer.
    func enableReminders(request: ((Permission) async -> PermissionStatus)? = nil) async {
        guard !isEnablingReminders else { return }
        isEnablingReminders = true
        defer { isEnablingReminders = false }
        let wasEnabled = remindersEnabled
        remindersEnabled = true
        let status = if let request { await request(.notifications) } else { await permissions.request(.notifications) }
        // Our explainer closed without Continue: nothing was asked, so the schedule stays as it was, to try again.
        if request != nil, status == .notDetermined {
            remindersEnabled = wasEnabled
            return
        }
        remindersAllowed = status.isUsable
        step = .reminders(status.isUsable ? .on : status.needsSettings ? .denied : .later)
        await remindersChanged()
    }

    /// Back from iOS Settings on "Notifications are off": allowed there, the outcome says they are on.
    func recheckReminders() async {
        guard step == .reminders(.denied), await permissions.status(of: .notifications).isUsable else { return }
        remindersAllowed = true
        step = .reminders(.on)
        await remindersChanged()
    }

    /// "Maybe later". On a replay (Help › "Show the introduction again") the person's existing reminders setting
    /// stays as it is.
    func remindLater() {
        guard !isEnablingReminders else { return }
        if !isCompleted { remindersEnabled = false }
        step = .reminders(.later)
    }

    func finishReminders() {
        step = .firstCapture
    }

    /// "Capture my first moment": the camera, with its own explainer if access isn't granted yet.
    func startFirstCapture() {
        isCapturing = true
    }

    /// The first moment exists, so onboarding is done even if the app closes on O10.
    func firstMomentSaved(_ moment: SavedMoment) {
        firstMoment = moment
        isCapturing = false
        isCompleted = true
        step = .firstMomentSaved
        // Relaunched after the reminders step, or allowed in Settings since.
        Task { remindersAllowed = await permissions.status(of: .notifications).isUsable }
    }

    /// Help › "Show the introduction again": from the first page. A finished onboarding stays finished, so closing
    /// the app on the way doesn't bring it back on the next launch.
    func restart() {
        firstMoment = nil
        isCapturing = false
        page = .welcome
        step = .intro
    }

    func finish() {
        isCompleted = true
        save()
    }

    // MARK: Saving

    private static let scheduleStep = OnboardingPage.allCases.count
    private static let firstCaptureStep = scheduleStep + 1

    private var savedStep: Int {
        switch step {
        case .intro: page.rawValue
        case .schedule: Self.scheduleStep
        case .reminders, .firstCapture, .firstMomentSaved: Self.firstCaptureStep
        }
    }

    private func save() {
        store.save(OnboardingRecord(isCompleted: isCompleted, step: savedStep, schedule: schedule, remindersEnabled: remindersEnabled))
    }
}
