@testable import AppFeature
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct PermissionExplainerSnapshotTests {
    @Test(arguments: PermissionScreen.allCases)
    func screen(_ screen: PermissionScreen) {
        assertScreenSnapshots(
            of: PermissionExplainerView(screen: screen, primary: {}, secondary: {}),
            testName: "\(screen)"
        )
    }
}
