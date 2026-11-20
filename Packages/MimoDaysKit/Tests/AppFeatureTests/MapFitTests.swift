@testable import AppFeature
import SwiftUI
import Testing

/// Fitting every place keeps the markers clear of the places panel: the strip at the bottom on iPhone (P01), the
/// panel at the leading edge on iPad (X03).
struct MapFitTests {
    @Test func withoutAPanelEverySideKeepsRoomForAMarker() {
        let padding = MapCanvas.padding(EdgeInsets(), true)
        #expect(padding == UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 60))
    }

    @Test func onIPhoneTheStripIsKeptClear() {
        let padding = MapCanvas.padding(EdgeInsets(top: 0, leading: 0, bottom: 230, trailing: 0), true)
        #expect(padding == UIEdgeInsets(top: 60, left: 60, bottom: 290, right: 60))
    }

    @Test func onIPadThePanelIsKeptClearOnItsSide() {
        let cover = EdgeInsets(top: 0, leading: 376, bottom: 0, trailing: 0)
        #expect(MapCanvas.padding(cover, true) == UIEdgeInsets(top: 60, left: 436, bottom: 60, right: 60))
        // Right to left the panel is on the right.
        #expect(MapCanvas.padding(cover, false) == UIEdgeInsets(top: 60, left: 60, bottom: 60, right: 436))
    }
}
