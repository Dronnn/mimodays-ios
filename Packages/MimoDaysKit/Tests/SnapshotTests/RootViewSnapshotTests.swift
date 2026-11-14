@testable import AppFeature
import SwiftUI
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct RootViewSnapshotTests {
    /// A tab root that its phase hasn't built yet. Today and Memories have their own suites.
    /// The system tab bar is Liquid Glass, which does not render offscreen (UI tests cover it).
    @Test func moviesPlaceholder() {
        assertScreenSnapshots(of: NavigationStack { TabRootView(tab: .movies) }.environment(AppRouter()), variants: [SnapshotVariant(.iPhone, .light)])
    }
}
