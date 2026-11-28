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

/// What onboarding needs from the surprises (P2): the plan and the first surprise after the reminders step, and
/// that surprise's camera. `SurpriseCoordinator` gives them in the app; tests give their own.
@MainActor
struct OnboardingSurprises {
    /// The reminders step chose; true when iOS has the first surprise's notification.
    var remindersChosen: (_ firstSurprise: Bool) async -> Bool = { _ in false }
    var first: () -> SurpriseCoordinator.FirstSurprise? = { nil }
    /// A surprise opened in time; false when it can't be answered any more.
    var open: (UUID) -> Bool = { _ in false }
    var expiry: (UUID) -> Date? = { _ in nil }
    var captured: (_ promptID: UUID, _ momentID: UUID) -> Void = { _, _ in }
}

extension OnboardingSurprises {
    init(_ coordinator: SurpriseCoordinator) {
        self.init(
            remindersChosen: { await coordinator.remindersChosen(firstSurprise: $0) },
            first: { coordinator.firstSurprise() },
            open: { coordinator.open(promptID: $0) },
            expiry: { coordinator.expiry(of: $0) },
            captured: { coordinator.captured(promptID: $0, momentID: $1) }
        )
    }
}

/// Onboarding's state machine. Every change is saved, so a later launch resumes on the same screen.
@MainActor
@Observable
final class OnboardingFlow {
    var step: OnboardingStep = .intro { didSet { save() } }
    var page: OnboardingPage = .welcome { didSet { save() } }
    var schedule = ReminderSchedule() { didSet { save() } }
    /// The schedule as a replay found it.
    private var scheduleAtReplay: ReminderSchedule?
    /// The camera: the first capture, or a surprise over whatever page is showing (P2.0).
    var capture: CaptureRequest?

    /// The camera's cover is gone: a surprise tapped while it was up opens now, if still in time. Not before: a
    /// cover still on its way out would take the new one with it.
    func captureDismissed() {
        guard capture == nil, let held = heldSurprise else { return }
        heldSurprise = nil
        openSurprise(held)
    }

    /// Planning the first surprise finished: W03's watcher looks again (the prompt may be new).
    private(set) var surprisesPlanned = 0

    var isCapturing: Bool { capture != nil }
    private var heldSurprise: UUID?
    /// W03: the first surprise shown in the app, when its notification can't come (P2.4).
    var inAppSurprise: UUID?
    /// iOS took the first surprise's notification in this run.
    private var surpriseNotified = false
    private(set) var firstMoment: SavedMoment?
    /// Surprises are on: the reminders choice, or on a replay the person's existing setting.
    private(set) var remindersEnabled = false
    /// Whether iOS lets the reminders through: O10 promises a surprise only then.
    private(set) var remindersAllowed = false
    private(set) var isCompleted = false

    private let permissions: any PermissionService
    private let store: any OnboardingStore
    private let surprises: OnboardingSurprises

    init(permissions: any PermissionService, store: any OnboardingStore, surprises: OnboardingSurprises = OnboardingSurprises()) {
        self.permissions = permissions
        self.store = store
        self.surprises = surprises
        let record = store.load()
        schedule = record.schedule
        remindersEnabled = record.remindersEnabled
        isCompleted = record.isCompleted
        if let saved = OnboardingPage(savedNumber: record.step) {
            page = saved
        } else if record.step == Self.scheduleStep {
            step = .schedule
        } else if record.step > Self.scheduleStep {
            step = .firstCapture
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
        let status = if let request { await request(.notifications) } else { await permissions.request(.notifications) }
        // Our explainer closed without Continue: nothing was asked, so the schedule stays as it was, to try again.
        // Set only after the answer: a schedule edit saved while it waited mustn't store reminders as on.
        if request != nil, status == .notDetermined { return }
        remindersEnabled = true
        remindersAllowed = status.isUsable
        step = .reminders(status.isUsable ? .on : status.needsSettings ? .denied : .later)
        await remindersChosen()
    }

    /// Surprises planned (or dropped) right away; the first time through, the first surprise comes in a few seconds,
    /// whatever was chosen (P2.1, P2.4). A replay keeps the person's surprises as they are.
    private func remindersChosen() async {
        let notified = await surprises.remindersChosen(!isCompleted)
        surpriseNotified = surpriseNotified || notified
        surprisesPlanned += 1
    }

    /// Back from iOS Settings on "Notifications are off": allowed there, the outcome says they are on.
    func recheckReminders() async {
        guard step == .reminders(.denied), await permissions.status(of: .notifications).isUsable,
              // Continue tapped while the status was read: the flow has moved on.
              step == .reminders(.denied) else { return }
        remindersAllowed = true
        step = .reminders(.on)
        _ = await surprises.remindersChosen(false)
    }

    /// "Maybe later". On a replay (Help › "Show the introduction again") the person's existing reminders setting
    /// stays as it is.
    func remindLater() {
        guard !isEnablingReminders else { return }
        if !isCompleted { remindersEnabled = false }
        step = .reminders(.later)
        // On a replay the schedule page saved each change as it was made: a changed schedule is planned again
        // (rev-surprises 1); an unchanged one keeps its plan, and a surprise due soon with it.
        if !isCompleted || schedule != scheduleAtReplay { Task { await remindersChosen() } }
    }

    func finishReminders() {
        step = .firstCapture
    }

    /// "Capture my first moment": the camera, with its own explainer if access isn't granted yet.
    func startFirstCapture() {
        capture = CaptureRequest()
    }

    /// A draft iOS closed the app on: back in its camera, a surprise's as a surprise.
    func resumeCapture(promptID: UUID?) {
        guard promptID != nil || step == .firstCapture else { return }
        capture = CaptureRequest(promptID: promptID)
    }

    // MARK: The first surprise (P2)

    /// A surprise's notification tapped, or W03's Open: its camera over this page at once; while a camera is up it
    /// waits for it to close (P2.0). Too late, nothing opens: the person goes on with onboarding.
    func openSurprise(_ promptID: UUID) {
        // Its own camera is up already (opened from W03, then the notification tapped): nothing more to open.
        guard capture?.promptID != promptID else { return }
        guard capture == nil else {
            heldSurprise = promptID
            return
        }
        guard surprises.open(promptID) else { return }
        inAppSurprise = nil
        capture = CaptureRequest(promptID: promptID)
    }

    func expiry(of promptID: UUID) -> Date? { surprises.expiry(promptID) }

    /// A save from the camera: a surprise answers its prompt and onboarding goes on where it was (W04); the first
    /// capture shows its moment (O10).
    /// A surprise's camera stays a surprise's when the shot came too late to count: onboarding goes on where it was.
    func saved(_ saved: SavedCapture, moment: SavedMoment) {
        if capture?.promptID != nil {
            if let promptID = saved.promptID { surprises.captured(promptID, saved.momentID) }
            capture = nil
        } else {
            firstMomentSaved(moment)
        }
    }

    /// Keeps W03's ribbon in step with the first surprise until it's caught or gone: shown while it can be answered,
    /// unless iOS brought its notification.
    /// Not once onboarding is done: Today shows it then, and a replay from Help brings no first surprise.
    func watchFirstSurprise(now: () -> Date = Date.init) async {
        while !Task.isCancelled, !isCompleted, let first = surprises.first() {
            let wait = first.plannedAt.timeIntervalSince(now())
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                continue
            }
            let allowed = await permissions.status(of: .notifications).isUsable
            inAppSurprise = allowed && surpriseNotified ? nil : first.promptID
            try? await Task.sleep(for: .seconds(max(first.expiresAt.timeIntervalSince(now()), 1)))
        }
        inAppSurprise = nil
    }

    /// The first moment exists, so onboarding is done even if the app closes on O10.
    func firstMomentSaved(_ moment: SavedMoment) {
        firstMoment = moment
        capture = nil
        isCompleted = true
        step = .firstMomentSaved
        // Relaunched after the reminders step, or allowed in Settings since.
        Task { remindersAllowed = await permissions.status(of: .notifications).isUsable }
    }

    /// Help › "Show the introduction again": from the first page. A finished onboarding stays finished, so closing
    /// the app on the way doesn't bring it back on the next launch.
    func restart() {
        scheduleAtReplay = schedule
        firstMoment = nil
        capture = nil
        page = .welcome
        step = .intro
    }

    func finish() {
        isCompleted = true
        save()
    }

    // MARK: Saving

    /// After the six pages of 1.0.6, as saved then.
    static let scheduleStep = 6
    static let firstCaptureStep = 7

    private var savedStep: Int {
        switch step {
        case .intro: page.savedNumber
        case .schedule: Self.scheduleStep
        case .reminders, .firstCapture, .firstMomentSaved: Self.firstCaptureStep
        }
    }

    private func save() {
        store.save(OnboardingRecord(isCompleted: isCompleted, step: savedStep, schedule: schedule, remindersEnabled: remindersEnabled))
    }
}
