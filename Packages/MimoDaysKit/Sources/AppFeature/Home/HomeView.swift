import DesignSystem
import SwiftUI

/// The first tab (U10-U15): Today and the Mosaic, switched in the header. Both stay alive, so each keeps its scroll
/// position and data; the one shown takes touches and VoiceOver.
struct HomeView: View {
    let today: TodayModel
    let mosaic: MemoriesModel
    @Environment(Home.self) private var home

    var body: some View {
        let side = home.side
        ZStack {
            TodayView(model: today)
                .opacity(side == .today ? 1 : 0)
                .allowsHitTesting(side == .today)
                .accessibilityHidden(side != .today)
            MosaicView(model: mosaic, isFacing: side == .mosaic)
                .opacity(side == .mosaic ? 1 : 0)
                .allowsHitTesting(side == .mosaic)
                .accessibilityHidden(side != .mosaic)
        }
    }
}
