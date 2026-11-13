import DesignSystem
import Testing
import TestSupport

@MainActor
@Suite(.tags(.snapshot))
struct DesignSystemGallerySnapshotTests {
    @Test func gallery() {
        assertScreenSnapshots(of: DesignSystemGallery())
    }
}
