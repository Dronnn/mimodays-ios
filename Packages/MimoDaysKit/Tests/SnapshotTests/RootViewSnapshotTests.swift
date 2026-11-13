@testable import AppFeature
import SwiftUI
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct RootViewSnapshotTests {
    /// The tab root only: the system tab bar is Liquid Glass, which does not render offscreen
    /// (UI tests cover it).
    @Test func today() {
        assertScreenSnapshots(of: NavigationStack { TabRootView(tab: .today) }.environment(AppRouter()))
    }
}
