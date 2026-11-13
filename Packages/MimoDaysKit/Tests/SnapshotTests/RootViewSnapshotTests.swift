@testable import AppFeature
import SwiftUI
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct RootViewSnapshotTests {
    /// A tab root that its phase hasn't built yet. Today has its own suite.
    /// The system tab bar is Liquid Glass, which does not render offscreen (UI tests cover it).
    @Test func memoriesPlaceholder() {
        assertScreenSnapshots(of: NavigationStack { TabRootView(tab: .memories) }.environment(AppRouter()), variants: [SnapshotVariant(.iPhone, .light)])
    }
}
