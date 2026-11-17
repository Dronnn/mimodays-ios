import Core
import DesignSystem
import Persistence
import SwiftUI

/// The camera (C01 photo, C01s surprise, C02 video idle, C03 recording, C04 selfie window, C05 single camera).
/// Dark in both appearances; sizes follow the 402 pt design.
struct CameraView: View {
    @State var model: CameraModel
    let onClose: () -> Void
    /// U01: the latest moment, bottom left; nil before the first one.
    let lastCapture: LastCapture?
    @State private var showsSettings = false
    /// C04: the selfie window sheet is open.
    @State private var adjustsSelfie: Bool
    /// The top safe-area inset, measured before the preview extends under the status bar.
    @State private var topInset: CGFloat = 0
    /// The surprise chip's height: a selfie window in its corner starts below it.
    @State private var chipHeight: CGFloat?
    /// C06c, before the microphone prompt.
    @State private var explainsMicrophone = false
    @Environment(\.permissions) private var permissions
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How the window is turned: upright while the capture flow keeps it so (iPhone); on iPad it turns with the device.
    @State private var windowHold: DeviceHold
    /// Snapshots set the window's turn; the app reads it from the scene.
    private let fixedWindowHold: DeviceHold?

    init(model: CameraModel, adjustsSelfie: Bool = false, windowHold: DeviceHold? = nil, lastCapture: LastCapture? = nil, onClose: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.lastCapture = lastCapture
        _adjustsSelfie = State(initialValue: adjustsSelfie)
        _windowHold = State(initialValue: windowHold ?? .upright)
        fixedWindowHold = windowHold
        self.onClose = onClose
    }

    /// The window has turned with the device (iPad): the camera draws its sideways layout as it is (Andrew, 2026-11-15).
    private var followsWindow: Bool { windowHold.isLandscape }

    /// The turn for an area of the camera: the camera's own with the window upright, none when the window has turned.
    private func turn(_ screen: CGSize) -> CameraTurn {
        followsWindow
            ? CameraTurn(hold: .landscapeLeft, screen: screen, turnsItself: false)
            : CameraTurn(hold: model.layoutHold, screen: screen)
    }

    var body: some View {
        let layout = followsWindow ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            preview
                .clipShape(UnevenRoundedRectangle(
                    bottomLeadingRadius: followsWindow ? 0 : 28, bottomTrailingRadius: 28,
                    topTrailingRadius: followsWindow ? 28 : 0, style: .continuous
                ))
                .ignoresSafeArea(edges: followsWindow ? [.top, .bottom, .leading] : .top)
            bottomBar
                .frame(width: followsWindow ? CameraChrome.Bar.height : nil, height: followsWindow ? nil : CameraChrome.Bar.height)
        }
        .background(CameraPalette.background.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { topInset = CameraChrome.topInset($0) }
        // The window's turn changes its size.
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { _ in
            windowHold = fixedWindowHold ?? OrientationLock.windowHold
        }
        .onChange(of: windowHold, initial: true) { _, hold in model.engine.setPreviewHold(hold) }
        .environment(\.colorScheme, .dark)
        // U07: one spring as the phone turns; Reduce Motion cross-fades instead.
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35), value: model.layoutHold)
        // Sideways the status bar would run down the buttons' column; the Camera app hides it too.
        .statusBarHidden(model.layoutHold.isLandscape || followsWindow)
        .task { await model.start() }
        .onDisappear { Task { await model.stop() } }
        .sheet(isPresented: $showsSettings) {
            CameraSettingsSheet(settings: $model.settings, lenses: model.lenses)
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
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera")
    }

    /// With Reduce Motion the controls are replaced (and cross-fade) when the phone turns, instead of moving.
    private var turnIdentity: DeviceHold {
        reduceMotion ? model.layoutHold : .upright
    }

    /// Mid-recording the layout keeps the recording's hold; only the chips turn to stay readable (U07).
    private func spin(_ turn: CameraTurn) -> Angle {
        turn.turnsItself ? CameraTurn(hold: model.hold, screen: turn.screen).angle - turn.angle : .zero
    }

    // MARK: Preview

    private var preview: some View {
        GeometryReader { proxy in
            let turn = turn(proxy.size)
            let chrome = CameraChrome(turn: turn, topInset: topInset, isRightToLeft: layoutDirection == .rightToLeft)
            let whole = CGRect(origin: .zero, size: turn.size)
            // The format's own way up fills the preview where the preview has about its shape (the iPhone: 9:16
            // upright, as before formats; 16:9 sideways); otherwise its shape is a frame inside it (U02, U03, U06),
            // as on the iPad's squarer screen.
            let ownWay = model.format == (turn.hold.isLandscape ? .landscape : .portrait)
            let fills = ownWay && abs(turn.size.width / max(turn.size.height, 1) / model.format.aspectRatio - 1) < 0.05
            let shape = fills ? whole : FormatMask.frame(model.format, in: turn.size)
            // While the phone is held the wrong way the window stays where the hold's own format has it (U03).
            let windowArea = fills || model.needsRotation ? whole : shape
            ZStack {
                CameraPalette.previewPlaceholder
                if let selfie = model.selfiePosition, model.showsHalves, !model.needsRotation {
                    halves(turn, shape: shape, selfie: selfie)
                } else {
                    CameraPreview(engine: model.engine, position: model.mainPosition)
                        .accessibilityHidden(true)
                }
                if !fills {
                    FormatMask(frame: turn.rect(shape))
                }
                overPreview(turn, chrome, shape: shape, windowArea: windowArea, insideShape: !fills && windowArea == shape)
                    .id(turnIdentity)
                    .transition(.opacity)
            }
            // Boxes are placed on the screen left to right; each lays itself out in the language's direction.
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// H.8: each camera fills its half of the format's frame, the big one first (top, or left held sideways);
    /// ↻ swaps them. The previews stay upright as the camera sees them, like the full one.
    private func halves(_ turn: CameraTurn, shape: CGRect, selfie: CameraPosition) -> some View {
        let (first, second) = HalvesArt.halves(shape.size)
        return ZStack(alignment: .topLeading) {
            ForEach([(model.mainPosition, first), (selfie, second)], id: \.0) { position, half in
                let rect = turn.rect(half.offsetBy(dx: shape.minX, dy: shape.minY))
                CameraPreview(engine: model.engine, position: position)
                    .frame(width: rect.width, height: rect.height)
                    .clipped()
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .accessibilityHidden(true)
    }

    private func overPreview(_ turn: CameraTurn, _ chrome: CameraChrome, shape: CGRect, windowArea: CGRect, insideShape: Bool) -> some View {
        let direction = layoutDirection
        return ZStack {
            // U03/U06: while the phone is held the wrong way the hint has the preview to itself.
            if let selfie = model.selfiePosition, !model.needsRotation, !model.showsHalves {
                let chipBottom = model.isSurprise ? chipHeight.map { chrome.surpriseChip.minY + $0 } : nil
                AdjustableSelfieWindow(
                    placement: $model.settings.selfieWindow, showsSheet: $adjustsSelfie,
                    layout: chrome.selfieWindow(in: windowArea, insideShape: insideShape, chipBottom: chipBottom),
                    isEnabled: !model.isRecording, turn: turn.angle, id: "camera.selfieWindow"
                ) {
                    CameraPreview(engine: model.engine, position: selfie)
                }
                .turned(windowArea, turn, direction: .leftToRight)
            }
            if model.needsRotation {
                RotateHint(format: model.format)
                    .turned(CGRect(x: shape.midX - 150, y: shape.midY - 150, width: 300, height: 300), turn, direction: direction)
                    .transition(.opacity)
            }
            if model.isRecording {
                RecordingPill(model: model)
                    .rotationEffect(spin(turn))
                    .turned(chrome.timer, turn, direction: direction)
                FormatLockedChip(format: model.format)
                    .rotationEffect(spin(turn))
                    .turned(chrome.lockChip, turn, direction: direction)
            } else {
                buttons(turn, chrome, direction)
                if model.isSurprise {
                    SurpriseChip()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { chipHeight = $0 }
                        .turned(chrome.surpriseChip, turn, alignment: chrome.leading(.top), direction: direction)
                }
                pickersAndNotes(turn, chrome, direction)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.needsRotation)
    }

    @ViewBuilder
    private func buttons(_ turn: CameraTurn, _ chrome: CameraChrome, _ direction: LayoutDirection) -> some View {
        RoundButton(icon: .glyphClose, label: Text("Close", bundle: .module), id: "capture.close", action: onClose)
            .turned(chrome.button(.close), turn, direction: direction)
        RoundButton(
            icon: model.settings.flash.icon, label: Text("Flash", bundle: .module), id: "camera.flash",
            value: model.settings.flash.label
        ) { model.nextFlash() }
            .turned(chrome.button(.flash), turn, direction: direction)
        Group {
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
        .turned(chrome.button(.middle), turn, direction: direction)
        RoundButton(icon: .glyphMore, label: Text("Camera settings", bundle: .module), id: "camera.more") {
            showsSettings = true
        }
        .turned(chrome.button(.more), turn, direction: direction)
    }

    /// The notes stand on the format picker; the 10/30/60 s picker shows in Video when there's no note.
    @ViewBuilder
    private func pickersAndNotes(_ turn: CameraTurn, _ chrome: CameraChrome, _ direction: LayoutDirection) -> some View {
        let sideways = turn.hold.isLandscape
        let withDuration = model.notice == nil && !model.showsSingleCameraNote && model.mode == .video
        let picker = chrome.formatPicker(withDuration: withDuration)
        if let notice = model.notice {
            CameraNote(notice)
                .turned(chrome.note(above: picker, gap: model.mode == .video ? 17 : 20), turn, alignment: .bottom, direction: direction)
        } else if model.showsSingleCameraNote {
            CameraNote(icon: .glyphInfo, text: Text("This iPhone can use one camera at a time. Tap ↻ to switch between you and the world.", bundle: .module), id: "camera.singleNote")
                .turned(chrome.note(above: picker, gap: 20), turn, alignment: .bottom, direction: direction)
        }
        FormatPicker(selection: model.format) { format in
            withAnimation(.easeInOut(duration: 0.3)) { model.setFormat(format) }
        }
        .turned(picker, turn, alignment: Alignment(horizontal: sideways && withDuration ? chrome.physical(right: true) : .center, vertical: .center), direction: direction)
        if withDuration {
            DurationPicker(selection: $model.settings.videoLength)
                .turned(chrome.durationPicker, turn, alignment: Alignment(horizontal: sideways ? chrome.physical(right: false) : .center, vertical: .center), direction: direction)
        }
    }

    // MARK: Bottom

    private var bottomBar: some View {
        GeometryReader { proxy in
            let turn = turn(proxy.size)
            let bar = CameraChrome.Bar(turn: turn, isRightToLeft: layoutDirection == .rightToLeft)
            let sideways = turn.hold.isLandscape
            let direction = layoutDirection
            ZStack {
                if model.isRecording {
                    if !sideways {
                        Text("Tap to stop", bundle: .module)
                            .textStyle(.hand)
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .foregroundStyle(CameraPalette.cream)
                            .turned(bar.tapToStop, turn, alignment: .top, direction: direction)
                    }
                    RecordButton(model: model)
                        .turned(bar.shutter(92), turn, direction: direction)
                } else {
                    ModeSwitch(mode: $model.mode, isVertical: sideways)
                        .turned(bar.modeSwitch, turn, alignment: sideways ? .center : .top, direction: direction)
                    ShutterButton(mode: model.mode) { Task { await model.shutter() } }
                        .disabled(!model.canCapture)
                        .opacity(model.needsRotation ? 0.35 : 1)
                        .accessibilityHint(model.needsRotation ? rotateHint : Text(verbatim: ""))
                        .turned(bar.shutter(84), turn, direction: direction)
                    if let lastCapture {
                        LastCaptureButton(capture: lastCapture)
                            .turned(bar.lastCapture, turn, direction: direction)
                    }
                    FlipButton { Task { await model.flip() } }
                        .turned(bar.flip, turn, direction: direction)
                    if model.needsRotation {
                        RotateReason(format: model.format, mode: model.mode, lines: sideways ? 3 : 1)
                            .turned(bar.rotateReason, turn, alignment: sideways ? .top : .bottom, direction: direction)
                    }
                }
            }
            .id(turnIdentity)
            .transition(.opacity)
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// VoiceOver on the dimmed shutter (U07).
    private var rotateHint: Text {
        model.format == .landscape
            ? Text("Turn your phone sideways to record 16:9.", bundle: .module, comment: "Camera (U07): VoiceOver hint on the dimmed shutter while the phone is upright and 16:9 is picked")
            : Text("Turn your phone upright to record \(model.format.label).", bundle: .module, comment: "Camera (U07): VoiceOver hint on the dimmed shutter while the phone is sideways, e.g. 'Turn your phone upright to record 9:16.'")
    }
}

// MARK: - Pieces

/// 40 pt round control over the preview.
private struct RoundButton: View {
    let icon: Icon
    let label: Text
    let id: String
    var isOn: Bool?
    /// Says more than on or off (the flash's Auto).
    var value: Text?
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
        .accessibilityValue(value ?? isOn.map { $0 ? Text("On", bundle: .module) : Text("Off", bundle: .module) } ?? Text(verbatim: ""))
        .accessibilityIdentifier(id)
    }
}

/// The latest moment and how to open it (DG.1).
struct LastCapture {
    var image: UIImage?
    var open: () -> Void
}

/// U01: the last moment in an uneven cream frame; a tap closes the camera and opens it.
private struct LastCaptureButton: View {
    let capture: LastCapture

    var body: some View {
        Button(action: capture.open) {
            ZStack {
                CameraPalette.cream.opacity(0.16)
                if let image = capture.image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: 50, height: 50)
            .clipShape(ThumbnailBlob())
            .overlay { ThumbnailBlob().stroke(CameraPalette.cream, lineWidth: 2) }
            .frame(width: Size.minimumTapTarget + 8, height: Size.minimumTapTarget + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Last moment", bundle: .module, comment: "Camera (U01): VoiceOver label of the last capture's thumbnail, which opens it"))
        .accessibilityIdentifier("camera.lastCapture")
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
    /// Sideways (U04): one over the other in the shutter's column, without the dot.
    var isVertical = false

    /// As in the design: labels start 90 pt apart in a centred 160 pt row.
    var body: some View {
        if isVertical {
            VStack(spacing: 0) {
                item(.photo, CameraSettings.Mode.photo.label, id: "camera.mode.photo")
                item(.video, CameraSettings.Mode.video.label, id: "camera.mode.video")
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                item(.photo, CameraSettings.Mode.photo.label, id: "camera.mode.photo")
                    // A long word still keeps its distance from the next; inside the 90 pt in English.
                    .padding(.trailing, 16)
                    .frame(minWidth: 90, alignment: .leading)
                item(.video, CameraSettings.Mode.video.label, id: "camera.mode.video")
            }
            .frame(minWidth: 160, alignment: .leading)
        }
    }

    private func item(_ value: CameraSettings.Mode, _ title: Text, id: String) -> some View {
        Button { mode = value } label: {
            VStack(spacing: 4) {
                title
                    .textStyle(.cameraMode)
                    .foregroundStyle(CameraPalette.cream.opacity(mode == value ? 1 : 0.5))
                    // Long translations keep the whole word: the bar has the room.
                    .fixedSize()
                if !isVertical {
                    Circle()
                        .fill(CameraPalette.coral)
                        .frame(width: 5, height: 5)
                        .opacity(mode == value ? 1 : 0)
                }
            }
            // Sideways each row spans the column, so the target stays wide where it is short.
            .frame(minWidth: isVertical ? 124 : nil, minHeight: isVertical ? 24 : Size.minimumTapTarget, alignment: isVertical ? .center : .top)
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
            self.init(icon: .glyphMute, text: Text("Videos will be silent. Turn on the microphone in iOS Settings to add sound.", bundle: .module), id: "camera.notice")
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
