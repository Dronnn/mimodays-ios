import AVFoundation
import Core
import DesignSystem
import SwiftUI

/// A camera's picture that takes a tap (focus and exposure there), a long press (lock them) and a pinch (zoom)
/// (P1.3, P1.6). Outside `activeArea` (the format's mask) nothing happens. The selfie window's picture uses the
/// plain `CameraPreview`, so its own drag and press stay the window's.
struct InteractivePreview: View {
    let model: CameraModel
    let position: CameraPosition
    var activeArea: CGRect?
    @State private var size = CGSize.zero

    var body: some View {
        preview
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            // P4.3: what a tap, a long press and a pinch do, by name for Voice Control and VoiceOver.
            .accessibilityElement(children: .ignore)
            // In halves two pictures show at once: each says which camera it is.
            .accessibilityLabel(position == .back
                ? Text("Back camera", bundle: .module)
                : Text("Front camera", bundle: .module, comment: "Camera (P4.3): the selfie camera's live picture, for Voice Control and VoiceOver"))
            .accessibilityAction(named: Text("Focus in the middle", bundle: .module, comment: "Camera (P4.3): what a tap on the picture does, there in the middle")) {
                focusInTheMiddle(lock: false)
            }
            .accessibilityAction(named: Text("Lock focus and exposure", bundle: .module, comment: "Camera (P4.3): what a long press on the picture does, there in the middle")) {
                focusInTheMiddle(lock: true)
            }
            .accessibilityZoomAction { action in
                model.pinch(action.direction == .zoomIn ? 1.5 : 1 / 1.5, on: position, ended: true)
            }
            .accessibilityIdentifier("camera.picture")
    }

    private func focusInTheMiddle(lock: Bool) {
        let area = activeArea ?? CGRect(origin: .zero, size: size)
        Task { await model.focus(at: CGPoint(x: 0.5, y: 0.5), layerPoint: CGPoint(x: area.midX, y: area.midY), on: position, lock: lock) }
    }

    private var preview: some View {
        CameraPreview(engine: model.engine, position: position, gestures: CameraPreview.Gestures(
            activeArea: activeArea,
            tap: { point, layerPoint in Task { await model.focus(at: point, layerPoint: layerPoint, on: position, lock: false) } },
            press: { point, layerPoint in Task { await model.focus(at: point, layerPoint: layerPoint, on: position, lock: true) } },
            pinch: { scale, ended in model.pinch(scale, on: position, ended: ended) }
        ))
        .overlay {
            if let mark = model.focusMark, mark.position == position {
                FocusMarkView(mark: mark) { model.focusMarkFaded(mark) }
                    .position(mark.point)
                    .id(mark.id)
            }
        }
    }
}

/// The hand-cut square where the picture was tapped; it fades, unless it locked, which says so above it.
struct FocusMarkView: View {
    let mark: FocusMark
    let faded: () -> Void
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MemoryCardOutline()
            .stroke(CameraPalette.coral, lineWidth: 2)
            .frame(width: 72, height: 72)
            .scaleEffect(settled || reduceMotion ? 1 : 1.25)
            .overlay(alignment: .top) {
                if mark.result.locks {
                    lockLabel
                        .textStyle(.cameraChip)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .foregroundStyle(CameraPalette.chipText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(CameraPalette.chip, in: Capsule())
                        .fixedSize()
                        .offset(y: -34)
                        .accessibilityIdentifier("camera.focusLock")
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                withAnimation(.easeOut(duration: 0.2)) { settled = true }
                guard !mark.result.locks else { return }
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                faded()
            }
    }

    /// In plain words, not the Camera app's AE/AF (Andrew, 2026-11-23); only what the camera can keep.
    private var lockLabel: Text {
        switch (mark.result.focuses, mark.result.exposes) {
        case (true, true): Text("Focus & light locked", bundle: .module, comment: "Camera (P1.6): focus and exposure are kept after a long press")
        case (true, false): Text("Focus locked", bundle: .module, comment: "Camera (P1.6): only focus is kept after a long press")
        default: Text("Light locked", bundle: .module, comment: "Camera (P1.6): only exposure (brightness) is kept after a long press")
        }
    }
}

/// P1.4: the big camera's zoom (0.5×, 1×, 2.3×); a tap goes to the next lens.
struct ZoomLabel: View {
    let zoom: CameraZoom
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            Text(verbatim: Self.text(zoom.shown))
                .textStyle(.cameraChip)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .monospacedDigit()
                .foregroundStyle(zoom.currentStop == nil ? CameraPalette.coral : CameraPalette.cream)
                .padding(.horizontal, 12)
                .frame(minWidth: 48, minHeight: 32)
                .background(contrast == .increased ? CameraPalette.controlScrimIncreased : CameraPalette.controlScrim, in: Capsule())
                .frame(minHeight: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Zoom", bundle: .module, comment: "Camera (P1.4): VoiceOver label of the zoom button over the picture"))
        .accessibilityValue(Text(verbatim: Self.text(zoom.shown)))
        .accessibilityHint(Text("Goes to the next lens", bundle: .module, comment: "Camera (P1.4): VoiceOver hint of the zoom button"))
        .accessibilityIdentifier("camera.zoom")
    }

    /// "0.5×", "1×", "2.3×": one decimal at most, in the app's language.
    static func text(_ shown: Double) -> String {
        let rounded = (shown * 10).rounded() / 10
        return rounded.formatted(.number.precision(.fractionLength(0...1)).locale(AppLanguage.shared.locale)) + "×"
    }
}

extension CameraPreview {
    /// What a picture does with touches; nil for one that takes none (the selfie window).
    struct Gestures {
        var activeArea: CGRect?
        /// The camera's own point (0...1) and where in the view it was.
        var tap: (CGPoint, CGPoint) -> Void
        var press: (CGPoint, CGPoint) -> Void
        /// The pinch's scale since it began, and whether it has ended.
        var pinch: (Double, Bool) -> Void
    }
}

extension CameraPreview.PreviewView {
    /// The camera's own point for a point in this view: the preview layer converts it, taking its fill and mirroring
    /// into account; a layer that isn't a camera's (the simulator) just scales it.
    func devicePoint(_ point: CGPoint) -> CGPoint {
        if let preview = previewLayer as? AVCaptureVideoPreviewLayer {
            return preview.captureDevicePointConverted(fromLayerPoint: layer.convert(point, to: preview))
        }
        return CGPoint(x: point.x / max(bounds.width, 1), y: point.y / max(bounds.height, 1))
    }
}
