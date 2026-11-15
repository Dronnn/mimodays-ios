import Core
import DesignSystem
import Persistence
import SwiftUI

/// U20-U24: the Memory Card's front. The photo, or both video streams from their own files, in the moment's shape,
/// with the selfie window (tilted -5.4°, hand-cut) where it was recorded. The window is dragged to a corner or
/// resized with touch and hold, and saved on the moment. Swapping grows the window's stream into the card while the
/// card's shrinks into the window: frame, size, tilt and edge move together and the players keep running.
/// A video's controls sit on a scrim at the bottom; tapping the card hides or shows them.
struct MemoryCardFront: View {
    let model: MomentViewerModel
    let moment: ViewerMoment
    let playback: ViewerVideoPlayer?
    let size: CGSize
    /// The camera's window layout for this moment; nil without a selfie stream.
    let windowLayout: SelfieWindowLayout?
    let swapped: Bool
    /// The folded corner's side: bottom trailing.
    let cornerOnRight: Bool
    @Binding var controlsShown: Bool
    let actions: MemoryCardActions
    @State private var adjustsWindow = false
    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var drag: CGSize?

    /// The card's face under the pictures, seen while they swap (U22).
    static let face = Color(hex: 0x2A1B21)

    private enum Stream {
        case main
        case selfie
    }

    private var savedLayout: PiPLayout? { moment.video?.layout ?? moment.photo?.layout }

    /// The corner and size the saved window is shown at; a move saves it, which moves it here.
    private var placement: CameraSettings.SelfieWindow? {
        guard let windowLayout, let savedLayout else { return nil }
        return windowLayout.placement(nearest: savedLayout)
    }
    private var isVideo: Bool { moment.mediaType == .video }

    var body: some View {
        let bounds = CGRect(origin: .zero, size: size)
        let window = windowFrame
        ZStack(alignment: .topLeading) {
            Self.face
                .accessibilityElement()
                .accessibilityLabel(Text(isVideo ? "Video" : moment.selfiePath == nil ? "Photo" : "Photo with selfie", bundle: .module))
                .accessibilityAddTraits(.isImage)
                .memoryCardActions(actions)
            picture(.main, bounds: bounds, window: window)
            if let window {
                if let windowLayout, let placement, adjustsWindow || drag != nil {
                    targets(windowLayout, placement)
                }
                picture(.selfie, bounds: bounds, window: window)
            }
            if isVideo, controlsShown {
                MemoryCardVideoControls(playback: playback, fallbackDuration: moment.video?.timing.duration ?? 0)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .transition(.opacity)
            }
            MemoryCardFlipCorner()
                .scaleEffect(x: cornerOnRight ? 1 : -1)
                .position(x: cornerOnRight ? size.width - 29 : 29, y: size.height - 32)
                .accessibilityHidden(true)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(MemoryCardOutline())
        .overlay { MemoryCardOutline().strokeBorder(ColorToken.mediaFrame.color, lineWidth: 5).allowsHitTesting(false) }
        .contentShape(MemoryCardOutline())
        .onTapGesture {
            guard isVideo else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsShown.toggle() }
        }
        // Corners are physical, as the camera records them.
        .environment(\.layoutDirection, .leftToRight)
        .sheet(isPresented: $adjustsWindow) {
            if let placement {
                SelfieWindowSheet(placement: Binding(get: { placement }, set: { new in withAnimation(.snappy) { save(new) } }))
            }
        }
    }

    // MARK: Pictures

    /// The window's frame on the card, before any drag; nil without a selfie window.
    private var windowFrame: CGRect? {
        guard let windowLayout, let placement, moment.selfiePath != nil else { return nil }
        return MemoryCardGeometry.windowFrame(placement, layout: windowLayout, card: size)
    }

    /// A stream framed where it is now: filling the card, or in the window with its cream edge, shadow and tilt.
    private func picture(_ stream: Stream, bounds: CGRect, window: CGRect?) -> some View {
        let inWindow = window != nil && (stream == .selfie) != swapped
        let offset = inWindow ? drag ?? .zero : .zero
        let rect = inWindow ? window!.offsetBy(dx: offset.width, dy: offset.height) : bounds
        return content(stream)
            .frame(width: rect.width, height: rect.height)
            .clipShape(MemoryCardOutline())
            .overlay { MemoryCardOutline().strokeBorder(ColorToken.mediaFrame.color, lineWidth: inWindow ? 4 : 0) }
            .background {
                MemoryCardOutline()
                    .fill(ColorToken.mediaFrame.color)
                    .shadow(color: Color(hex: 0x2A1B21).opacity(inWindow ? 0.25 : 0), radius: 10, y: 8)
            }
            .rotationEffect(.degrees(inWindow ? savedLayout?.rotation ?? -5.4 : 0))
            .position(x: rect.midX, y: rect.midY)
            // The stream going into the window is on top, so it uncovers the one growing out of it.
            .zIndex(inWindow ? 1 : 0)
            .modifier(WindowAccess(isWindow: inWindow, placement: placement) { adjustsWindow = true })
            .gesture(windowGesture, isEnabled: inWindow)
    }

    @ViewBuilder
    private func content(_ stream: Stream) -> some View {
        let path = stream == .main ? moment.mainPath : moment.selfiePath
        ZStack {
            if let image = model.image(path) {
                Image(uiImage: image).filling()
            }
            if let playback {
                if stream == .main {
                    PlayerLayerView(player: playback.main)
                } else if playback.hasSelfie {
                    PlayerLayerView(player: playback.selfie)
                }
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: The window

    private var windowGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 6)
            .onEnded { _ in adjustsWindow = true }
            .exclusively(
                before: DragGesture(minimumDistance: 6)
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        guard let windowLayout, let placement, let frame = windowFrame else { return }
                        let scale = windowLayout.preview.width / max(size.width, 1)
                        // The layout's centres are the whole window's, the frame and the camera's handle below it.
                        let end = CGPoint(
                            x: (frame.midX + value.predictedEndTranslation.width) * scale,
                            y: (frame.midY + value.predictedEndTranslation.height) * scale + SelfieWindowLayout.handleSpace / 2
                        )
                        var moved = placement
                        moved.corner = windowLayout.nearest(to: end, placement.scale)
                        guard moved != placement else { return }
                        withAnimation(.snappy) { save(moved) }
                    }
            )
    }

    /// The four corners while the window is moved or resized, the one it will land on in coral.
    private func targets(_ layout: SelfieWindowLayout, _ placement: CameraSettings.SelfieWindow) -> some View {
        let scale = size.width / max(layout.preview.width, 1)
        let frame = layout.frameSize(placement.scale)
        let shown = CGSize(width: frame.width * scale, height: frame.height * scale)
        let target: CameraSettings.SelfieWindow.Corner = {
            guard let drag, let window = windowFrame else { return placement.corner }
            let center = CGPoint(x: (window.midX + drag.width) / scale, y: (window.midY + drag.height) / scale + SelfieWindowLayout.handleSpace / 2)
            return layout.nearest(to: center, placement.scale)
        }()
        return ForEach(CameraSettings.SelfieWindow.Corner.allCases, id: \.self) { corner in
            let center = layout.frameCenter(corner, placement.scale)
            SelfieTarget(size: shown, isSelected: corner == target)
                .position(x: center.x * scale, y: center.y * scale)
        }
        .allowsHitTesting(false)
    }

    private func save(_ placement: CameraSettings.SelfieWindow) {
        guard let windowLayout, let saved = savedLayout else { return }
        model.setWindow(PiPLayout(windowLayout.windowFrame(placement), source: saved.source), for: moment.id)
    }
}

/// The window's VoiceOver element: where it is, and the touch-and-hold sheet as an action.
private struct WindowAccess: ViewModifier {
    let isWindow: Bool
    let placement: CameraSettings.SelfieWindow?
    let adjust: () -> Void

    func body(content: Content) -> some View {
        if isWindow {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Selfie window", bundle: .module))
                .accessibilityValue(Text(placement?.accessibilityValue ?? ""))
                .accessibilityAction(named: Text("Adjust selfie window", bundle: .module), adjust)
                .accessibilityIdentifier("viewer.selfieWindow")
        } else {
            content
        }
    }
}

/// U20: the video's controls on a soft scrim inside the card: the scrubber, the time on each side, pause in the
/// middle and the sound beside the total.
struct MemoryCardVideoControls: View {
    let playback: ViewerVideoPlayer?
    let fallbackDuration: Double
    /// Playing before a scrub started.
    @State private var resumesAfterScrub: Bool?

    var body: some View {
        let duration = max(playback?.duration ?? fallbackDuration, 0.1)
        let time = min(playback?.time ?? 0, duration)
        VStack(spacing: 0) {
            scrubber(time: time, duration: duration)
            ZStack {
                HStack(spacing: 0) {
                    Text(Duration.seconds(time.rounded()), format: .time(pattern: .minuteSecond))
                    Spacer(minLength: 8)
                    Button { playback?.isMuted.toggle() } label: {
                        (playback?.isMuted == true ? Icon.glyphMute : .glyphSpeaker).image
                            .resizable()
                            .frame(width: 24, height: 24)
                            .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(playback?.isMuted == true ? "Sound off" : "Sound on", bundle: .module))
                    Text(Duration.seconds(duration.rounded()), format: .time(pattern: .minuteSecond))
                        .accessibilityHidden(true)
                }
                .textStyle(.scrubTime)
                Button { playback?.toggle() } label: {
                    (playback?.isPlaying == true ? Icon.glyphPause : .glyphPlay).image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(playback?.isPlaying == true ? "Pause" : "Play", bundle: .module))
                .accessibilityIdentifier("viewer.play")
            }
        }
        .foregroundStyle(ColorToken.mediaFrame.color)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .padding(.top, 40)
        .background {
            LinearGradient(
                colors: [Color(hex: 0x2A1B21).opacity(0), Color(hex: 0x2A1B21).opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }

    /// A 4 pt track, coral up to where it is, a 14 pt cream knob; drag anywhere on it to seek.
    private func scrubber(time: Double, duration: Double) -> some View {
        GeometryReader { proxy in
            let progress = CGFloat(time / duration)
            ZStack(alignment: .leading) {
                Capsule().fill(ColorToken.mediaFrame.color.opacity(0.35)).frame(height: 4)
                Capsule().fill(ColorToken.actionCoral.color).frame(width: max(4, proxy.size.width * progress), height: 4)
                Circle().fill(ColorToken.mediaFrame.color).frame(width: 14, height: 14)
                    .offset(x: proxy.size.width * progress - 7)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resumesAfterScrub == nil {
                            resumesAfterScrub = playback?.isPlaying ?? false
                            playback?.pause()
                        }
                        let fraction = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        playback?.seek(to: duration * fraction)
                    }
                    .onEnded { _ in
                        if resumesAfterScrub == true { playback?.play() }
                        resumesAfterScrub = nil
                    }
            )
        }
        .frame(height: Size.minimumTapTarget / 2)
        .accessibilityElement()
        .accessibilityLabel(Text("Playback position", bundle: .module))
        .accessibilityValue(Text(Duration.seconds(time.rounded()), format: .time(pattern: .minuteSecond)))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 5.0 : -5.0
            playback?.seek(to: min(max(time + step, 0), duration))
        }
    }
}
