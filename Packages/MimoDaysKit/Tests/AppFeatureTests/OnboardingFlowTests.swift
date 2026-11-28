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

    /// Continue on "Notifications are off" while the status is still being read doesn't send the flow back.
    @Test func continueDuringTheRecheckIsKept() async {
        let permissions = HeldStatus()
        let flow = OnboardingFlow(permissions: permissions, store: InMemoryOnboardingStore())
        flow.step = .reminders(.denied)
        let recheck = Task { await flow.recheckReminders() }
        while await !permissions.isHolding { await Task.yield() }
        flow.finishReminders()
        let moved = flow.step
        await permissions.answer(.granted)
        await recheck.value
        #expect(flow.step == moved && moved != .reminders(.on))
    }

    /// A status read that waits until answered.
    private actor HeldStatus: PermissionService {
        private var held: CheckedContinuation<PermissionStatus, Never>?
        var isHolding: Bool { held != nil }
        func answer(_ status: PermissionStatus) { held?.resume(returning: status); held = nil }
        func status(of _: Permission) async -> PermissionStatus { await withCheckedContinuation { held = $0 } }
        func request(_ permission: Permission) async -> PermissionStatus { await status(of: permission) }
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
        flow.capture = nil
        #expect(flow.step == .firstCapture)
        #expect(flow.firstMoment == nil)
    }

    // MARK: The first surprise (P2)

    /// Records what the flow asks of the surprises; `answerable` is what `open` says.
    @MainActor
    final class Surprises {
        var chosen: [Bool] = []
        var opened: [UUID] = []
        var captured: [(UUID, UUID)] = []
        var answerable = true
        var notified = true
        var first: SurpriseCoordinator.FirstSurprise?

        var hooks: OnboardingSurprises {
            OnboardingSurprises(
                remindersChosen: { self.chosen.append($0); return self.notified },
                first: { self.first },
                open: { self.opened.append($0); return self.answerable },
                expiry: { _ in nil },
                captured: { self.captured.append(($0, $1)) }
            )
        }
    }

    private func flow(_ surprises: Surprises, answer: PermissionStatus = .granted, completed: Bool = false) -> OnboardingFlow {
        let store = InMemoryOnboardingStore()
        if completed { store.save(OnboardingRecord(isCompleted: true, step: 0, schedule: ReminderSchedule(), remindersEnabled: true)) }
        return OnboardingFlow(
            permissions: PresetPermissionService(status: answer, requestResult: answer), store: store, surprises: surprises.hooks
        )
    }

    /// P2.1: whatever the reminders answer, the first surprise is asked for once; a replay asks for none.
    @Test(arguments: [PermissionStatus.granted, .denied, .notDetermined])
    func theRemindersStepAsksForTheFirstSurprise(answer: PermissionStatus) async {
        let surprises = Surprises()
        let flow = flow(surprises, answer: answer)
        flow.finishIntro()
        await flow.enableReminders()
        #expect(surprises.chosen == [true])
    }

    @Test func maybeLaterAsksForTheFirstSurpriseToo() async {
        let surprises = Surprises()
        let flow = flow(surprises)
        flow.finishIntro()
        flow.remindLater()
        for _ in 0..<50 where surprises.chosen.isEmpty { await Task.yield() }
        #expect(surprises.chosen == [true])
    }

    @Test func aReplayBringsNoFirstSurprise() async {
        let surprises = Surprises()
        let flow = flow(surprises, completed: true)
        flow.restart()
        flow.finishIntro()
        await flow.enableReminders()
        #expect(surprises.chosen == [false])
        // "Maybe later" with the schedule as it was keeps the plan.
        flow.remindLater()
        for _ in 0..<50 { await Task.yield() }
        #expect(surprises.chosen == [false])
    }

    /// A replay that changed the schedule plans it on "Maybe later", still with no first surprise (rev-surprises 1).
    @Test func maybeLaterOnAReplayPlansOnlyAChangedSchedule() async {
        let surprises = Surprises()
        let flow = flow(surprises, completed: true)
        flow.restart()
        flow.finishIntro()
        flow.schedule.frequency = flow.schedule.frequency == .threeAWeek ? .threeADay : .threeAWeek
        flow.remindLater()
        for _ in 0..<50 where surprises.chosen.isEmpty { await Task.yield() }
        #expect(surprises.chosen == [false])
    }

    /// P2.0, P2.3: a tap opens the surprise camera over the page; closing it brings the page back.
    @Test func aSurpriseOpensItsCameraOverTheCurrentPage() {
        let surprises = Surprises()
        let flow = flow(surprises)
        flow.step = .reminders(.on)
        let id = UUID()
        flow.openSurprise(id)
        #expect(flow.capture?.promptID == id)
        flow.capture = nil
        #expect(flow.step == .reminders(.on))
    }

    @Test func aSurpriseTooLateOpensNothing() {
        let surprises = Surprises()
        surprises.answerable = false
        let flow = flow(surprises)
        flow.openSurprise(UUID())
        #expect(flow.capture == nil)
    }

    /// P2.0: a tap while the first-capture camera is up waits for it to close, then opens if still in time.
    @Test func aSurpriseDuringACaptureWaitsForIt() {
        let surprises = Surprises()
        let flow = flow(surprises)
        flow.step = .firstCapture
        flow.startFirstCapture()
        let id = UUID()
        flow.openSurprise(id)
        #expect(flow.capture?.promptID == nil)
        #expect(surprises.opened.isEmpty)
        flow.capture = nil
        // Not while the old cover is still on its way out.
        #expect(flow.capture == nil)
        flow.captureDismissed()
        #expect(flow.capture?.promptID == id)
    }

    @Test func aWaitingSurpriseThatExpiredOpensNothing() {
        let surprises = Surprises()
        let flow = flow(surprises)
        flow.startFirstCapture()
        flow.openSurprise(UUID())
        surprises.answerable = false
        flow.capture = nil
        flow.captureDismissed()
        #expect(flow.capture == nil)
    }

    /// The notification of the surprise whose camera is up, tapped: nothing waits to open it again after.
    @Test func theOpenSurpriseTappedAgainOpensNothingMore() {
        let surprises = Surprises()
        let flow = flow(surprises)
        let id = UUID()
        flow.openSurprise(id)
        flow.openSurprise(id)
        flow.capture = nil
        flow.captureDismissed()
        #expect(flow.capture == nil)
        #expect(surprises.opened == [id])
    }

    /// A surprise's shot saved too late to count is a plain moment: onboarding goes on where it was, not finished.
    @Test func aLateSurpriseShotDoesntFinishOnboarding() {
        let surprises = Surprises()
        let flow = flow(surprises)
        flow.step = .reminders(.on)
        flow.openSurprise(UUID())
        flow.saved(SavedCapture(momentID: UUID(), promptID: nil, capturedAt: Date()), moment: SavedMoment(photo: .placeholder, capturedAt: Date()))
        #expect(surprises.captured.isEmpty)
        #expect(flow.capture == nil)
        #expect(flow.step == .reminders(.on))
        #expect(!flow.isCompleted)
    }

    /// W03 looks again once the reminders step planned (the prompt may be new); a finished onboarding (a replay) shows none.
    @Test func theRibbonWatchRestartsAfterPlanningAndStopsOnceDone() async {
        let surprises = Surprises()
        surprises.first = SurpriseCoordinator.FirstSurprise(promptID: UUID(), plannedAt: Date(timeIntervalSince1970: 0), expiresAt: Date().addingTimeInterval(60))
        let flow = flow(surprises, answer: .denied)
        flow.finishIntro()
        #expect(flow.surprisesPlanned == 0)
        await flow.enableReminders()
        #expect(flow.surprisesPlanned == 1)
        flow.finish()
        await flow.watchFirstSurprise()
        #expect(flow.inAppSurprise == nil)
    }

    /// O3, W04: the surprise's moment answers it and onboarding goes on where it was; the first capture shows O10.
    @Test func aSavedSurpriseAnswersItAndOnboardingGoesOn() {
        let surprises = Surprises()
        let flow = flow(surprises)
        flow.step = .firstCapture
        let id = UUID()
        flow.openSurprise(id)
        let moment = UUID()
        flow.saved(SavedCapture(momentID: moment, promptID: id, capturedAt: Date()), moment: SavedMoment(photo: .placeholder, capturedAt: Date()))
        #expect(surprises.captured.map(\.0) == [id])
        #expect(surprises.captured.map(\.1) == [moment])
        #expect(flow.capture == nil)
        #expect(flow.step == .firstCapture)
        #expect(!flow.isCompleted)
    }

    /// P2.4: W03's ribbon while the first surprise can be answered and its notification didn't come.
    @Test(arguments: [(PermissionStatus.denied, true, true), (.granted, false, true), (.granted, true, false)])
    func theRibbonShowsWhenNoNotificationCame(status: PermissionStatus, notified: Bool, shows: Bool) async {
        let surprises = Surprises()
        surprises.notified = notified
        let id = UUID()
        surprises.first = SurpriseCoordinator.FirstSurprise(promptID: id, plannedAt: Date(timeIntervalSince1970: 0), expiresAt: Date().addingTimeInterval(60))
        let flow = flow(surprises, answer: status)
        flow.finishIntro()
        await flow.enableReminders()
        let watch = Task { await flow.watchFirstSurprise() }
        for _ in 0..<100 where flow.inAppSurprise == nil && shows { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        #expect((flow.inAppSurprise == id) == shows)
        flow.openSurprise(id)
        #expect(flow.inAppSurprise == nil)
        watch.cancel()
    }
}
