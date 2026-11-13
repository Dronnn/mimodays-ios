@testable import AppFeature
import SwiftUI
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct OnboardingSnapshotTests {
    @Test(arguments: OnboardingPage.allCases)
    func page(_ page: OnboardingPage) {
        assertScreenSnapshots(of: OnboardingIntroView(page: .constant(page), onFinish: {}), testName: "\(page)")
    }
}
