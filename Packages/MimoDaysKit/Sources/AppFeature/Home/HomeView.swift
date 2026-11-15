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
    /// U11, while it shows.
    @State private var showsHint = false

    var body: some View {
        let side = turn.side
        ZStack {
            TodayView(model: today)
                .modifier(HomeFace(angle: turn.flip.angle, side: .today, reduceMotion: reduceMotion))
                .allowsHitTesting(side == .today)
                .accessibilityHidden(side != .today)
            MosaicView(model: mosaic, isFacing: side == .mosaic)
                .modifier(HomeFace(angle: turn.flip.angle, side: .mosaic, reduceMotion: reduceMotion))
                .allowsHitTesting(side == .mosaic)
                .accessibilityHidden(side != .mosaic)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .overlay(alignment: .bottomTrailing) {
            if showsHint {
                FlipHint { withAnimation(.snappy) { showsHint = false } }
                    .padding(.trailing, 60)
                    .padding(.bottom, 60)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
            }
        }
        .overlay(alignment: .bottomTrailing) { corner }
        // U11: once, after the 10th moment, on Today.
        .task(id: mosaic.allIDs.count) {
            guard turn.showsFlipHint(moments: mosaic.allIDs.count) else { return }
            turn.flipHintShown()
            withAnimation(.snappy.delay(0.6)) { showsHint = true }
        }
        .onChange(of: turn.target) { withAnimation(.snappy) { showsHint = false } }
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

/// `Home / Flip hint` (U11): a plum bubble pointing at the page corner. A tap puts it away.
struct FlipHint: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your moments have another side", bundle: .module)
                    .textStyle(.coachTitle)
                    .foregroundStyle(Color(hex: 0xFBF6EF))
                Text("Drag the corner or tap Mosaic", bundle: .module)
                    .textStyle(.coachBody)
                    .foregroundStyle(Color(hex: 0xFBF6EF).opacity(0.75))
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 270, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x4B2938)))
            HintTail()
                .fill(Color(hex: 0x4B2938))
                .frame(width: 24, height: 13)
                .offset(x: 2, y: -1)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { dismiss() }
        .accessibilityIdentifier("home.flipHint")
    }
}

private struct HintTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
