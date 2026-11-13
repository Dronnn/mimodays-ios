import Core
import DesignSystem
import SwiftUI

/// The camera (C01 photo, C01s surprise, C02 video idle, C03 recording, C04 selfie window, C05 single camera).
/// Dark in both appearances; sizes follow the 402 pt design.
struct CameraView: View {
    @State var model: CameraModel
    let onClose: () -> Void
    @State private var showsSettings = false
    /// C04: the selfie window sheet is open.
    @State private var adjustsSelfie: Bool
    /// The selfie window's drag offset; springs back as the window snaps to a corner.
    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var selfieDrag: CGSize?
    /// The top safe-area inset, measured before the preview extends under the status bar.
    @State private var topInset: CGFloat = 0
    @State private var chipBottom: CGFloat?
    /// C06c, before the microphone prompt.
    @State private var explainsMicrophone = false
    @Environment(\.permissions) private var permissions
    @Environment(\.layoutDirection) private var layoutDirection

    private typealias Corner = CameraSettings.SelfieWindow.Corner

    init(model: CameraModel, adjustsSelfie: Bool = false, onClose: @escaping () -> Void) {
        _model = State(initialValue: model)
        _adjustsSelfie = State(initialValue: adjustsSelfie)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                .ignoresSafeArea(edges: .top)
            bottomBar
                .frame(height: 140)
        }
        .background(CameraPalette.background.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { topInset = $0 }
        .environment(\.colorScheme, .dark)
        .task { await model.start() }
        .onDisappear { Task { await model.stop() } }
        .sheet(isPresented: $showsSettings) {
            CameraSettingsSheet(settings: $model.settings)
        }
        .sheet(isPresented: $adjustsSelfie) {
            SelfieWindowSheet(placement: $model.settings.selfieWindow)
        }
        // First time in Video with sound on and the microphone not asked yet (Andrew, 2026-11-13).
        .onChange(of: model.mode == .video && model.settings.recordsSound, initial: true) { _, wantsSound in
            guard wantsSound else { return }
            Task { if await permissions.status(of: .microphone) == .notDetermined { explainsMicrophone = true } }
        }
        .fullScreenCover(isPresented: $explainsMicrophone) {
            PermissionExplainerView(screen: .microphone) {
                Task {
                    _ = await permissions.request(.microphone)
                    explainsMicrophone = false
                    await model.refreshMicrophone()
                }
            } secondary: {
                // Record without sound: videos stay silent until sound is turned back on.
                model.settings.recordsSound = false
                explainsMicrophone = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera")
    }

    // MARK: Preview

    private var preview: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                CameraPalette.previewPlaceholder
                CameraPreview(engine: model.engine, position: model.mainPosition)
                    .accessibilityHidden(true)
                if let selfie = model.selfiePosition {
                    let chip = model.isSurprise ? chipBottom.map { (corner: layoutDirection == .rightToLeft ? Corner.topRight : .topLeft, bottom: $0) } : nil
                    let layout = SelfieWindowLayout(preview: proxy.size, topInset: topInset, chip: chip)
                    ZStack {
                        selfieWindow(selfie, layout: layout)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .onChange(of: layout.windowFrame(model.settings.selfieWindow), initial: true) { model.selfieWindowFrame = $1 }
                }
                VStack(spacing: 0) {
                    if model.isRecording {
                        RecordingPill(model: model)
                            .padding(.top, topInset - 6)
                    } else {
                        topBar
                            .padding(.top, topInset - 8)
                        if model.isSurprise {
                            SurpriseChip()
                                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.previewSpace)).maxY }) {
                                    chipBottom = $0
                                }
                                .padding(.top, 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 16)
                        }
                    }
                    Spacer(minLength: 0)
                    if !model.isRecording {
                        if let notice = model.notice {
                            CameraNote(notice)
                                .padding(.horizontal, 16)
                                .padding(.bottom, model.mode == .video ? 17 : 20)
                        }
                        if model.notice == nil, model.showsSingleCameraNote {
                            CameraNote(icon: .glyphInfo, text: Text("This iPhone can use one camera at a time. Tap ↻ to switch between you and the world.", bundle: .module), id: "camera.singleNote")
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)
                        } else if model.mode == .video {
                            DurationPicker(selection: $model.settings.videoLength)
                                .padding(.bottom, 16)
                        }
                    }
                }
            }
            .coordinateSpace(.named(Self.previewSpace))
        }
    }

    private nonisolated static let previewSpace = "preview"

    /// The selfie window at its corner; while it is dragged or the C04 sheet is open, the four corners show as
    /// targets with the one it will land on in coral.
    @ViewBuilder
    private func selfieWindow(_ position: CameraPosition, layout: SelfieWindowLayout) -> some View {
        let placement = model.settings.selfieWindow
        let home = layout.center(placement.corner, placement.scale)
        let offset = selfieDrag ?? .zero
        let center = CGPoint(x: home.x + offset.width, y: home.y + offset.height)
        if adjustsSelfie || selfieDrag != nil {
            let target = selfieDrag == nil ? placement.corner : layout.nearest(to: center, placement.scale)
            ForEach(Corner.allCases, id: \.self) { corner in
                SelfieTarget(scale: placement.scale, isSelected: corner == target)
                    .position(layout.frameCenter(corner, placement.scale))
            }
        }
        SelfiePreviewWindow(engine: model.engine, position: position, scale: placement.scale, showsHandle: !model.isRecording)
            .position(center)
            .gesture(adjustGesture(layout), isEnabled: !model.isRecording)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Selfie window", bundle: .module))
            .accessibilityValue(Text(placement.accessibilityValue))
            .accessibilityAction(named: Text("Adjust selfie window", bundle: .module)) {
                if !model.isRecording { adjustsSelfie = true }
            }
            .accessibilityIdentifier("camera.selfieWindow")
    }

    /// Touch and hold opens C04; dragging moves the window and it snaps to the nearest corner.
    private func adjustGesture(_ layout: SelfieWindowLayout) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 6)
            .onEnded { _ in adjustsSelfie = true }
            .exclusively(
                before: DragGesture(minimumDistance: 6)
                    .updating($selfieDrag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        let placement = model.settings.selfieWindow
                        let home = layout.center(placement.corner, placement.scale)
                        let end = CGPoint(x: home.x + value.predictedEndTranslation.width, y: home.y + value.predictedEndTranslation.height)
                        withAnimation(.snappy) { model.settings.selfieWindow.corner = layout.nearest(to: end, placement.scale) }
                    }
            )
    }

    private var topBar: some View {
        ZStack {
            HStack {
                RoundButton(icon: .glyphClose, label: Text("Close", bundle: .module), id: "capture.close", action: onClose)
                Spacer()
                RoundButton(icon: .glyphMore, label: Text("Camera settings", bundle: .module), id: "camera.more") {
                    showsSettings = true
                }
            }
            HStack(spacing: 86) {
                RoundButton(
                    icon: .glyphFlash, label: Text("Flash", bundle: .module), id: "camera.flash",
                    isOn: model.isFlashOn
                ) { model.isFlashOn.toggle() }
                if model.mode == .video {
                    RoundButton(
                        icon: model.microphoneOn ? .glyphSpeaker : .glyphMute,
                        label: Text("Sound", bundle: .module), id: "camera.sound", isOn: model.microphoneOn
                    ) { model.toggleSound() }
                } else {
                    RoundButton(
                        icon: .glyphPiP, label: Text("Selfie window", bundle: .module), id: "camera.selfie",
                        isOn: model.selfiePosition != nil
                    ) { model.toggleSelfie() }
                    .disabled(!model.canToggleSelfie)
                    .opacity(model.canToggleSelfie ? 1 : 0.4)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Bottom

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if model.isRecording {
                Text("Tap to stop", bundle: .module)
                    .textStyle(.hand)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(CameraPalette.cream)
                    .padding(.top, 16)
                    .frame(height: 44, alignment: .top)
                RecordButton(model: model)
            } else {
                ModeSwitch(mode: $model.mode)
                    .padding(.top, 14)
                    .frame(height: 48, alignment: .top)
                ZStack {
                    ShutterButton(mode: model.mode) { Task { await model.shutter() } }
                        .disabled(!model.canCapture)
                    HStack {
                        // Last capture thumbnail arrives with saved moments (Phase 7).
                        Color.clear.frame(width: 48, height: 48)
                        Spacer()
                        FlipButton { Task { await model.flip() } }
                    }
                    .padding(.horizontal, 36)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pieces

/// 40 pt round control over the preview.
private struct RoundButton: View {
    let icon: Icon
    let label: Text
    let id: String
    var isOn: Bool?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon.image
                .frame(width: 24, height: 24)
                .foregroundStyle(CameraPalette.cream)
                .frame(width: 40, height: 40)
                .background(CameraPalette.controlScrim, in: Circle())
                .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(-2)
        .accessibilityLabel(label)
        .accessibilityValue(isOn.map { $0 ? Text("On", bundle: .module) : Text("Off", bundle: .module) } ?? Text(verbatim: ""))
        .accessibilityIdentifier(id)
    }
}

private struct FlipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon.glyphFlip.image
                .frame(width: 24, height: 24)
                .foregroundStyle(CameraPalette.cream)
                .frame(width: 48, height: 48)
                .background(CameraPalette.cream.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Switch camera", bundle: .module))
        .accessibilityIdentifier("camera.flip")
    }
}

/// 84 pt ring with a cream (photo) or coral (video) disk.
private struct ShutterButton: View {
    let mode: CameraSettings.Mode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(CameraPalette.cream, lineWidth: 4)
                Circle()
                    .fill(mode == .photo ? CameraPalette.cream : CameraPalette.coral)
                    .frame(width: 66, height: 66)
            }
            .frame(width: 84, height: 84)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .photo ? Text("Take photo", bundle: .module) : Text("Record video", bundle: .module))
        .accessibilityIdentifier("camera.shutter")
    }
}

/// C03: 92 pt stop button with a ring that fills up to the limit.
private struct RecordButton: View {
    let model: CameraModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let progress = model.recordingProgress(at: context.date)
            Button { Task { await model.shutter() } } label: {
                ZStack {
                    Circle()
                        .stroke(CameraPalette.cream.opacity(0.35), lineWidth: 4)
                        .frame(width: 88, height: 88)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(CameraPalette.coral, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 88, height: 88)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(CameraPalette.coral)
                        .frame(width: 32, height: 32)
                }
                .frame(width: 92, height: 92)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop recording", bundle: .module))
            .accessibilityIdentifier("camera.stop")
        }
    }
}

/// C03 timer: elapsed / limit, no countdown pressure.
private struct RecordingPill: View {
    let model: CameraModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            HStack(spacing: 9) {
                Circle().fill(CameraPalette.cream).frame(width: 9, height: 9)
                Text(model.recordingLabel(at: context.date))
                    .textStyle(.cameraTimer)
                    .monospacedDigit()
                    .foregroundStyle(CameraPalette.cream)
            }
            .padding(.leading, 16)
            .padding(.trailing, 21)
            .frame(height: 36)
            .background(CameraPalette.recording, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Recording", bundle: .module))
            .accessibilityValue(Text(model.recordingLabel(at: context.date)))
            .accessibilityIdentifier("camera.timer")
        }
    }
}

/// PHOTO / VIDEO with a coral dot under the active one.
private struct ModeSwitch: View {
    @Binding var mode: CameraSettings.Mode

    /// As in the design: labels start 90 pt apart in a centred 160 pt row.
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            item(.photo, CameraSettings.Mode.photo.label, id: "camera.mode.photo")
                .frame(minWidth: 90, alignment: .leading)
            item(.video, CameraSettings.Mode.video.label, id: "camera.mode.video")
        }
        .frame(minWidth: 160, alignment: .leading)
    }

    private func item(_ value: CameraSettings.Mode, _ title: Text, id: String) -> some View {
        Button { mode = value } label: {
            VStack(spacing: 4) {
                title
                    .textStyle(.cameraMode)
                    .foregroundStyle(CameraPalette.cream.opacity(mode == value ? 1 : 0.5))
                Circle()
                    .fill(CameraPalette.coral)
                    .frame(width: 5, height: 5)
                    .opacity(mode == value ? 1 : 0)
            }
            .frame(minHeight: Size.minimumTapTarget, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == value ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// C02: 10 s / 30 s / 60 s.
private struct DurationPicker: View {
    @Binding var selection: CameraSettings.VideoLength

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CameraSettings.VideoLength.allCases, id: \.self) { length in
                Button { selection = length } label: {
                    Text(length.label)
                        .textStyle(.cameraChip)
                        .foregroundStyle(selection == length ? CameraPalette.chipText : CameraPalette.cream)
                        .frame(minWidth: 52, minHeight: 28)
                        .background(
                            selection == length ? AnyShapeStyle(CameraPalette.cream) : AnyShapeStyle(CameraPalette.background.opacity(0.5)),
                            in: Capsule()
                        )
                        .frame(minHeight: Size.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == length ? .isSelected : [])
                .accessibilityIdentifier("camera.length.\(length.rawValue)")
            }
        }
        .padding(.vertical, -8)
    }
}

/// C01s: mint hand-cut chip with a coral star.
private struct SurpriseChip: View {
    var body: some View {
        HStack(spacing: 8) {
            Icon.markStarSmall.image
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(CameraPalette.star)
            Text("A little surprise", bundle: .module)
                .textStyle(.hand)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(CameraPalette.chipText)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .frame(minHeight: 34)
        .background(ChipBlob().fill(CameraPalette.chip))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("camera.surprise")
    }
}

/// C05 and C13: a note card over the preview, above the controls.
private struct CameraNote: View {
    let icon: Icon
    let text: Text
    let id: String

    init(icon: Icon, text: Text, id: String) {
        self.icon = icon
        self.text = text
        self.id = id
    }

    init(_ notice: CameraNotice) {
        switch notice {
        case .microphoneOff:
            self.init(icon: .glyphMute, text: Text("Videos will be silent. Turn on the microphone in Settings to add sound.", bundle: .module), id: "camera.notice")
        case .lowStorage:
            self.init(icon: .glyphInfo, text: Text("Not enough space to record. Free up some space on this iPhone and try again.", bundle: .module), id: "camera.notice")
        case .interrupted(.anotherApp):
            self.init(icon: .glyphInfo, text: Text("The camera is busy with a call or another app. It comes back on its own.", bundle: .module), id: "camera.notice")
        case .interrupted(.tooWarm):
            self.init(icon: .glyphInfo, text: Text("This iPhone is too warm for the camera right now. It comes back once it cools down.", bundle: .module), id: "camera.notice")
        case .interrupted:
            self.init(icon: .glyphInfo, text: Text("The camera paused for a moment. It comes back on its own.", bundle: .module), id: "camera.notice")
        case .unavailable:
            self.init(icon: .glyphInfo, text: Text("The camera isn't available right now. Close and try again in a moment.", bundle: .module), id: "camera.notice")
        case .captureFailed:
            self.init(icon: .glyphInfo, text: Text("That one didn't come out. Try again.", bundle: .module), id: "camera.notice")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.image
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            text
                .textStyle(.cameraNote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(CameraPalette.cream)
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(CameraPalette.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// The front (or swapped) camera in a cream frame tilted -5.4°, with a drag handle (C01).
private struct SelfiePreviewWindow: View {
    let engine: any CaptureEngine
    let position: CameraPosition
    let scale: CameraSettings.SelfieWindow.Scale
    let showsHandle: Bool

    var body: some View {
        let frame = SelfieWindowLayout.frameSize(scale)
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(ColorToken.mediaFrame.color)
                .overlay {
                    ZStack {
                        CameraPalette.selfiePlaceholder
                        CameraPreview(engine: engine, position: position)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(4)
                }
                .frame(width: frame.width, height: frame.height)
                .shadow(color: .black.opacity(0.22), radius: 7, y: 4)
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

/// Hosts an engine's preview layer.
struct CameraPreview: UIViewRepresentable {
    let engine: any CaptureEngine
    let position: CameraPosition

    func makeUIView(context _: Context) -> PreviewView { PreviewView() }

    func updateUIView(_ view: PreviewView, context _: Context) {
        view.host(engine, position)
    }

    final class PreviewView: UIView {
        private var hosted: CALayer?
        private var hostedPosition: CameraPosition?

        func host(_ engine: any CaptureEngine, _ position: CameraPosition) {
            guard position != hostedPosition else { return }
            hostedPosition = position
            let layer = engine.previewLayer(for: position)
            // On a swap the other preview may already have taken this view's old layer.
            if let hosted, hosted.superlayer === self.layer { hosted.removeFromSuperlayer() }
            hosted = layer
            if let layer { self.layer.addSublayer(layer) }
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }
    }
}

// MARK: - Model helpers for the views

extension CameraModel {
    /// 0...1 of the video limit.
    func recordingProgress(at date: Date) -> CGFloat {
        guard case let .recording(startedAt) = phase else { return 0 }
        return CGFloat(min(1, max(0, date.timeIntervalSince(startedAt) / Double(settings.videoLength.rawValue))))
    }

    /// "00:07 / 00:10".
    func recordingLabel(at date: Date) -> String {
        guard case let .recording(startedAt) = phase else { return "" }
        let limit = settings.videoLength.rawValue
        let elapsed = min(limit, max(0, Int(date.timeIntervalSince(startedAt))))
        return "\(Self.clock(elapsed)) / \(Self.clock(limit))"
    }

    private static func clock(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }
}

extension CameraSettings.VideoLength {
    /// "10s": the system's narrow unit style, localized by Foundation.
    var label: String {
        duration.formatted(.units(allowed: [.seconds], width: .narrow))
    }
}
