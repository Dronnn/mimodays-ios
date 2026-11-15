import DesignSystem
import SwiftUI

/// The selfie window at its corner, moved by dragging (snaps to the nearest corner) or by touch and hold (C04 sheet).
/// While it is dragged or the sheet is open, the four corners show as targets with the one it will land on in coral.
/// Shared by the camera and review (C07). Corners are physical, so the layer is always laid out left to right.
struct AdjustableSelfieWindow<Content: View>: View {
    @Binding var placement: CameraSettings.SelfieWindow
    @Binding var showsSheet: Bool
    let layout: SelfieWindowLayout
    var isEnabled = true
    /// How far the camera turns this layer for a sideways hold; the picture inside turns back so it stays as the camera sees it.
    var turn: Angle = .zero
    let id: String
    @ViewBuilder let content: () -> Content
    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var drag: CGSize?

    private typealias Corner = CameraSettings.SelfieWindow.Corner

    var body: some View {
        ZStack {
            let home = layout.center(placement.corner, placement.scale)
            let offset = drag ?? .zero
            let center = CGPoint(x: home.x + offset.width, y: home.y + offset.height)
            if showsSheet || drag != nil {
                let target = drag == nil ? placement.corner : layout.nearest(to: center, placement.scale)
                ForEach(Corner.allCases, id: \.self) { corner in
                    SelfieTarget(size: layout.frameSize(placement.scale), isSelected: corner == target)
                        .position(layout.frameCenter(corner, placement.scale))
                }
            }
            SelfieWindowView(scale: placement.scale, showsHandle: isEnabled, sideways: layout.sideways, turn: turn, content: content)
                .position(center)
                .gesture(gesture, isEnabled: isEnabled)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Selfie window", bundle: .module))
                .accessibilityValue(Text(placement.accessibilityValue))
                .accessibilityAction(named: Text("Adjust selfie window", bundle: .module)) {
                    if isEnabled { showsSheet = true }
                }
                .accessibilityIdentifier(id)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var gesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 6)
            .onEnded { _ in showsSheet = true }
            .exclusively(
                before: DragGesture(minimumDistance: 6)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        let home = layout.center(placement.corner, placement.scale)
                        let end = CGPoint(x: home.x + value.predictedEndTranslation.width, y: home.y + value.predictedEndTranslation.height)
                        withAnimation(.snappy) { placement.corner = layout.nearest(to: end, placement.scale) }
                    }
            )
    }
}

/// The signature window: `content` in a cream frame tilted -5.4°, with a drag handle below (C01, C07).
/// `sideways` lays it on its side (16:9): in review a quarter turn; in the camera, whose layer is turned with the
/// phone by `turn`, U04's hand-cut landscape frame. Either way the picture shows as the camera recorded it.
struct SelfieWindowView<Content: View>: View {
    let scale: CameraSettings.SelfieWindow.Scale
    let showsHandle: Bool
    var sideways = false
    var turn: Angle = .zero
    @ViewBuilder let content: () -> Content

    var body: some View {
        let frame = SelfieWindowLayout.frameSize(scale)
        if sideways, turn != .zero {
            // U04: the camera's layer is already on its side, so the window is drawn landscape in it, in its hand-cut
            // frame and without the handle; the picture turns back to how the camera sees it.
            CameraPalette.selfiePlaceholder
                .overlay { TurnedPicture(angle: -turn, content: content) }
                .clipShape(LandscapeSelfieBlob())
                .overlay { LandscapeSelfieBlob().stroke(CameraPalette.cream, lineWidth: 3.5) }
                .shadow(color: .black.opacity(SelfieWindowStyle.shadowOpacity), radius: SelfieWindowStyle.shadowBlur / 2, y: SelfieWindowStyle.shadowY)
                .frame(width: frame.height, height: frame.width)
                .rotationEffect(Size.selfieWindowTilt)
        } else {
            upright(frame)
        }
    }

    private func upright(_ frame: CGSize) -> some View {
        let frameTurn: Angle = sideways ? .degrees(90) : .zero
        return VStack(spacing: 6) {
            SelfieFrame(placeholder: CameraPalette.selfiePlaceholder, tilted: false) {
                TurnedPicture(angle: -(frameTurn + turn), content: content)
            }
            .frame(width: frame.width, height: frame.height)
            .rotationEffect(frameTurn)
            .frame(width: sideways ? frame.height : frame.width, height: sideways ? frame.width : frame.height)
            Capsule()
                .fill(CameraPalette.cream.opacity(0.9))
                .frame(width: 24, height: 4)
                .opacity(showsHandle ? 1 : 0)
        }
        .rotationEffect(Size.selfieWindowTilt)
    }
}

/// `content` laid out for its space turned by `angle` (a quarter turn swaps the sides), then turned into it.
private struct TurnedPicture<Content: View>: View {
    let angle: Angle
    @ViewBuilder let content: () -> Content

    var body: some View {
        if angle == .zero {
            content()
        } else {
            GeometryReader { proxy in
                let quarter = abs(angle.degrees.truncatingRemainder(dividingBy: 180)) == 90
                content()
                    .frame(width: quarter ? proxy.size.height : proxy.size.width, height: quarter ? proxy.size.width : proxy.size.height)
                    .rotationEffect(angle)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
    }
}

/// C04 corner target: dashed, or a coral ring around the window where it lands.
struct SelfieTarget: View {
    let size: CGSize
    let isSelected: Bool

    var body: some View {
        let frame = size
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(CameraPalette.coral, lineWidth: 2.5)
                    .frame(width: frame.width + 8, height: frame.height + 8)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CameraPalette.cream.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [10, 10]))
                    .frame(width: frame.width, height: frame.height)
            }
        }
        .rotationEffect(Size.selfieWindowTilt)
        .accessibilityHidden(true)
    }
}
