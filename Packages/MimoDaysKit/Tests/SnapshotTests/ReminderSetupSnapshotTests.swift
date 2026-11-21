@testable import AppFeature
import Core
import SwiftUI
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct ReminderSetupSnapshotTests {
    @Test func schedule() {
        assertScreenSnapshots(of: ReminderScheduleView(schedule: .constant(ReminderSchedule()), back: {}, enable: {}, later: {}))
    }

    /// Some days off and a narrower window, as after editing.
    @Test func scheduleEdited() {
        var schedule = ReminderSchedule()
        schedule.frequency = .twiceADay
        schedule.toggle(1)
        schedule.toggle(7)
        schedule.setEarliest(9 * 60)
        schedule.setLatest(21 * 60 + 30)
        assertScreenSnapshots(of: ReminderScheduleView(schedule: .constant(schedule), back: {}, enable: {}, later: {}))
    }

    @Test(arguments: RemindersOutcome.allCases)
    func outcome(_ outcome: RemindersOutcome) {
        assertScreenSnapshots(
            of: RemindersResultView(outcome: outcome, schedule: ReminderSchedule(), next: {}, openSettings: {}),
            testName: "\(outcome)"
        )
    }

    /// W03 (P2.4): no reminders, and the first surprise shows in the app at the top.
    @Test func firstSurpriseInTheApp() {
        let flow = OnboardingFlow(permissions: PresetPermissionService(status: .denied), store: InMemoryOnboardingStore())
        flow.step = .reminders(.denied)
        flow.inAppSurprise = UUID()
        assertScreenSnapshots(
            of: OnboardingView(flow: flow) { _ in },
            variants: [SnapshotVariant(.iPhone, .light), SnapshotVariant(.iPhone, .dark), SnapshotVariant(.iPhone, .light, .accessibilityExtraLarge), SnapshotVariant(.iPhone, .light, rightToLeft: true)]
        )
    }
}
