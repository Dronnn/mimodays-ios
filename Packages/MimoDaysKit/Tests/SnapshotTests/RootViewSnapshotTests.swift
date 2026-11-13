import AppFeature
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct RootViewSnapshotTests {
    @Test func shell() {
        assertScreenSnapshots(of: RootView())
    }
}
