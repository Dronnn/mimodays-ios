import DesignSystem
import SwiftUI

/// The first tab (U10-U16): Today and the Mosaic as the two sides of one page. Both stay alive, so each keeps its
/// scroll position and data; the one facing the person takes touches and VoiceOver. The page corner turns it.
struct HomeView: View {
    let today: TodayModel
    let mosaic: MemoriesModel
    @Environment(HomeTurn.self) private var turn
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction
    @State private var width: CGFloat = 0

    var body: some View {
        let side = turn.side
        ZStack {
            TodayView(model: today)
                .modifier(HomeFace(angle: turn.flip.angle, side: .today, reduceMotion: reduceMotion))
                .allowsHitTesting(side == .today)
                .accessibilityHidden(side != .today)
            MosaicView(model: mosaic)
                .modifier(HomeFace(angle: turn.flip.angle, side: .mosaic, reduceMotion: reduceMotion))
                .allowsHitTesting(side == .mosaic)
                .accessibilityHidden(side != .mosaic)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .overlay(alignment: .bottomTrailing) { corner }
        .sensoryFeedback(.impact(weight: .light), trigger: side)
    }

    /// `Home / Page corner`, bottom trailing: drag it across to turn the page, or tap it.
    private var corner: some View {
        HomePageCorner()
            .scaleEffect(x: direction == .leftToRight ? 1 : -1)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        turn.drag(value.translation.width, width: width, cornerOnRight: direction == .leftToRight, reduceMotion: reduceMotion)
                    }
                    .onEnded { value in
                        turn.endDrag(
                            value.translation.width, predicted: value.predictedEndTranslation.width,
                            width: width, cornerOnRight: direction == .leftToRight, reduceMotion: reduceMotion
                        )
                    }
            )
            .onTapGesture { turn.toggle(reduceMotion: reduceMotion) }
            .accessibilityElement()
            .accessibilityLabel(turn.target == .today ? Text("Show Mosaic", bundle: .module) : Text("Show Today", bundle: .module))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { turn.toggle(reduceMotion: reduceMotion) }
            .accessibilityIdentifier("home.corner")
    }
}
