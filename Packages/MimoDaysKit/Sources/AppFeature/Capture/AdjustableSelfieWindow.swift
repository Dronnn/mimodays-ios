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
                    SelfieTarget(scale: placement.scale, isSelected: corner == target)
                        .position(layout.frameCenter(corner, placement.scale))
                }
            }
            SelfieWindowView(scale: placement.scale, showsHandle: isEnabled, content: content)
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
struct SelfieWindowView<Content: View>: View {
    let scale: CameraSettings.SelfieWindow.Scale
    let showsHandle: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        let frame = SelfieWindowLayout.frameSize(scale)
        VStack(spacing: 6) {
            SelfieFrame(placeholder: CameraPalette.selfiePlaceholder, tilted: false, content: content)
                .frame(width: frame.width, height: frame.height)
            Capsule()
                .fill(CameraPalette.cream.opacity(0.9))
                .frame(width: 24, height: 4)
                .opacity(showsHandle ? 1 : 0)
        }
        .rotationEffect(Size.selfieWindowTilt)
    }
}

/// C04 corner target: dashed, or a coral ring around the window where it lands.
private struct SelfieTarget: View {
    let scale: CameraSettings.SelfieWindow.Scale
    let isSelected: Bool

    var body: some View {
        let frame = SelfieWindowLayout.frameSize(scale)
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
