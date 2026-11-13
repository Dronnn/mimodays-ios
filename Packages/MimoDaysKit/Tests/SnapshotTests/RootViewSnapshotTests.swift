import AppFeature
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct RootViewSnapshotTests {
    @Test func placeholder() {
        assertScreenSnapshots(of: RootView())
    }
}
