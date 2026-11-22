@testable import AppFeature
import SwiftUI
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct OnboardingSnapshotTests {
    @Test(arguments: OnboardingPage.allCases)
    func page(_ page: OnboardingPage) {
        assertScreenSnapshots(
            of: OnboardingIntroView(page: .constant(page), onFinish: {}),
            variants: SnapshotVariant.standard + SnapshotVariant.languages, testName: "\(page)"
        )
    }

    /// §V17 LL03.
    @Test func whatsNew() {
        assertScreenSnapshots(of: WhatsNewView(onContinue: {}), variants: SnapshotVariant.standard + SnapshotVariant.languages)
    }
}
