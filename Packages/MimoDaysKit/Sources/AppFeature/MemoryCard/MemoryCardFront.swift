import Core
import DesignSystem
import Persistence
import SwiftUI

/// U20-U24: the Memory Card's front. The photo, or both video streams from their own files, in the moment's shape,
/// with the selfie window (tilted -5.4°, hand-cut) in its corner. The window is dragged to a corner or
/// resized with touch and hold, and saved on the moment. Swapping grows the window's stream into the card while the
/// card's shrinks into the window: frame, size, tilt and edge move together and the players keep running.
/// A video's controls sit on a scrim at the bottom; tapping the card hides or shows them.
/// The viewer shows a saved moment on it; Review after capture shows the capture before Save (U42).
struct MemoryCardFront: View {
    /// The stills, under the players once a video plays.
    struct Pictures {
        let main: UIImage?
        let selfie: UIImage?
        let isVideo: Bool
        /// The video's length until the player knows it.
        var duration: Double = 0
        /// The card's own element: "viewer.media", "review.media".
        var id = "viewer.media"
    }

    /// The selfie window: the camera's layout for this shape, where the window is, how a move is kept, and the
    /// cameras swapped when it is tapped (Andrew, 2026-11-15: no Swap cameras button).
    struct Window {
        let layout: SelfieWindowLayout
        let placement: CameraSettings.SelfieWindow
        let rotation: Double
        /// "viewer.selfieWindow", "review.selfieWindow".
        let id: String
        let move: (CameraSettings.SelfieWindow) -> Void
        let swap: () -> Void
        /// H.8: the two streams each fill half the card instead, split across its long side; a tap swaps them.
        var halves = false
    }

    let pictures: Pictures
    let playback: ViewerVideoPlayer?
    let size: CGSize
    /// Nil without a selfie stream.
    let window: Window?
    let swapped: Bool
    /// The folded corner's side, bottom trailing; nil where the card can't turn yet (Review before Save).
    let cornerOnRight: Bool?
    @Binding var controlsShown: Bool
    /// The VoiceOver actions; nil in Review, which has no neighbours and no back yet.
    let actions: MemoryCardActions?
    /// A drag held part way, the corners showing: snapshots of U24.
    var heldDrag: CGSize?
    /// Part way from the recorded layout (0) to swapped (1): snapshots of U22. Otherwise the swap is 0 or 1 and
    /// SwiftUI animates between them.
    var swapProgress: Double?
    @State private var adjustsWindow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(resetTransaction: Transaction(animation: .snappy)) private var dragging: CGSize?

    /// How far the window is dragged now.
    private var drag: CGSize? { dragging ?? heldDrag }

    /// The card's face under the pictures, seen while they swap (U22).
    static let face = Color(hex: 0x2A1B21)

    /// U22: the picture going into the window leads, so the one growing out of it shows under it on the way, not
    /// only at the end. The grow is the swap's 0.5 s spring.
    static let shrinkDuration = 0.3
    static let growDuration = 0.5

    private enum Stream {
        case main
        case selfie
    }

    private var placement: CameraSettings.SelfieWindow? { window?.placement }
    private var isVideo: Bool { pictures.isVideo }

    var body: some View {
        let bounds = CGRect(origin: .zero, size: size)
        let frame = windowFrame
        ZStack(alignment: .topLeading) {
            Self.face
            ZStack(alignment: .topLeading) {
                if let window, window.halves {
                    half(.main, bounds: bounds)
                    half(.selfie, bounds: bounds)
                } else {
                picture(.main, bounds: bounds, window: frame)
                if let frame {
                    if let window, adjustsWindow || drag != nil {
                        targets(window.layout, window.placement)
                    }
                    picture(.selfie, bounds: bounds, window: frame)
                }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // Reduce Motion: the swapped pictures cross-fade in place of moving (U35).
            .id(reduceMotion && swapped)
            .transition(.opacity)
            if isVideo, controlsShown {
                MemoryCardVideoControls(playback: playback, fallbackDuration: pictures.duration, foldOnRight: cornerOnRight)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
                    .transition(.opacity)
            }
            if let cornerOnRight {
                MemoryCardFlipCorner()
                    .scaleEffect(x: cornerOnRight ? 1 : -1)
                    .position(x: cornerOnRight ? size.width - 29 : 29, y: size.height - 32)
                // Drawing only, never a VoiceOver element: marking it hidden made an empty node the audit flags.
            }
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
            if let window {
                SelfieWindowSheet(placement: Binding(get: { window.placement }, set: { new in withAnimation(.snappy) { window.move(new) } }))
            }
        }
    }

    // MARK: Pictures

    /// The window's frame on the card, before any drag; nil without a selfie window.
    private var windowFrame: CGRect? {
        guard let window else { return nil }
        return MemoryCardGeometry.windowFrame(window.placement, layout: window.layout, card: size)
    }

    /// A stream framed where it is now: filling the card, or in the window with its cream edge, shadow and tilt,
    /// or part way between the two.
    private func picture(_ stream: Stream, bounds: CGRect, window: CGRect?) -> some View {
        // Where it ends up; part way through a swap, the swapped side.
        let inWindow = window != nil && (stream == .selfie) != (swapped || swapProgress != nil)
        // How far this stream is along, the one going into the window ahead, as its shorter spring has it.
        let progress = swapProgress.map { inWindow ? min($0 * Self.growDuration / Self.shrinkDuration, 1) : $0 } ?? (swapped ? 1 : 0)
        // 1 in the window, 0 filling the card.
        let share = window == nil ? 0 : stream == .selfie ? 1 - progress : progress
        let offset = inWindow ? drag ?? .zero : .zero
        let rect = Self.between(bounds, window?.offsetBy(dx: offset.width, dy: offset.height) ?? bounds, share)
        // The card's outline, or the window's own hand-cut frame with its 4 pt cream edge inside it.
        let shape = share > 0.5 ? AnyShape(CardSelfieBlob()) : AnyShape(MemoryCardOutline())
        return content(stream)
            .frame(width: rect.width, height: rect.height)
            .clipShape(shape)
            // A fill masked by the stroke: a stroke reaches 4 pt past the frame, and VoiceOver's (and the tests')
            // bounds of the window with it.
            .overlay { ColorToken.mediaFrame.color.mask { shape.stroke(lineWidth: 8 * share) }.clipShape(shape) }
            .background {
                shape
                    .fill(ColorToken.mediaFrame.color)
                    .shadow(color: Color(hex: 0x2A1B21).opacity(0.25 * share), radius: 10, y: 8)
            }
            .rotationEffect(.degrees((self.window?.rotation ?? 0) * share))
            .position(x: rect.midX, y: rect.midY)
            .animation(
                reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: inWindow ? Self.shrinkDuration : Self.growDuration),
                value: swapped
            )
            // The stream going into the window is on top, so it uncovers the one growing out of it.
            .zIndex(inWindow ? 1 : 0)
            .modifier(PictureAccess(
                isWindow: inWindow, placement: placement, windowID: self.window?.id ?? "", adjust: { adjustsWindow = true },
                swap: { self.window?.swap() }, isSwapped: swapped,
                label: Text(isVideo ? "Video" : window == nil ? "Photo" : "Photo with selfie", bundle: .module),
                id: pictures.id, actions: actions
            ))
            .gesture(windowGesture, isEnabled: inWindow)
    }

    /// H.8: a stream in its half of the card, main first (top, or left on a wide card); swapping slides them past
    /// each other. No window edge or tilt: the card's own outline frames both, as they're shared.
    private func half(_ stream: Stream, bounds: CGRect) -> some View {
        let (first, second) = HalvesArt.halves(bounds.size)
        let progress = swapProgress ?? (swapped ? 1 : 0)
        let rect = stream == .main ? Self.between(first, second, progress) : Self.between(second, first, progress)
        return content(stream)
            .frame(width: rect.width, height: rect.height)
            .clipped()
            .position(x: rect.midX, y: rect.midY)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: Self.growDuration), value: swapped)
            .modifier(PictureAccess(
                isWindow: stream == .selfie, placement: nil, windowID: window?.id ?? "", adjust: nil,
                swap: { window?.swap() }, isSwapped: swapped,
                label: Text(isVideo ? "Video" : "Photo with selfie", bundle: .module), id: pictures.id, actions: actions
            ))
            .onTapGesture { window?.swap() }
    }

    /// `from` moved `share` of the way to `to`.
    private static func between(_ from: CGRect, _ to: CGRect, _ share: Double) -> CGRect {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * share }
        return CGRect(x: mix(from.minX, to.minX), y: mix(from.minY, to.minY), width: mix(from.width, to.width), height: mix(from.height, to.height))
    }

    /// The picture at its frame's size: its VoiceOver element has the frame's bounds, which tests measure the
    /// window against.
    private func content(_ stream: Stream) -> some View {
        Color.clear
            .overlay {
                if let image = stream == .main ? pictures.main : pictures.selfie {
                    FilledStill(image: image)
                }
            }
            .overlay {
                if let playback {
                    if stream == .main {
                        PlayerLayerView(player: playback.main)
                    } else if playback.hasSelfie {
                        PlayerLayerView(player: playback.selfie)
                    }
                }
            }
    }

    // MARK: The window

    private var windowGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 6)
            .onEnded { _ in adjustsWindow = true }
            .exclusively(
                before: DragGesture(minimumDistance: 6)
                    .updating($dragging) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        guard let window, let frame = windowFrame else { return }
                        let windowLayout = window.layout, placement = window.placement
                        let scale = windowLayout.preview.width / max(size.width, 1)
                        // The layout's centres are the whole window's, the frame and the camera's handle below it.
                        let end = CGPoint(
                            x: (frame.midX + value.predictedEndTranslation.width) * scale,
                            y: (frame.midY + value.predictedEndTranslation.height) * scale + SelfieWindowLayout.handleSpace / 2
                        )
                        var moved = placement
                        moved.corner = windowLayout.nearest(to: end, placement.scale)
                        guard moved != placement else { return }
                        withAnimation(.snappy) { window.move(moved) }
                    }
            )
            // A tap, neither held nor moved, swaps the cameras.
            .exclusively(before: TapGesture().onEnded { window?.swap() })
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

}

/// The card's VoiceOver actions, where it has them.
private struct CardActions: ViewModifier {
    let actions: MemoryCardActions?

    func body(content: Content) -> some View {
        if let actions { content.memoryCardActions(actions) } else { content }
    }
}

/// The pictures' VoiceOver elements: the window says where it is and has the touch-and-hold sheet as an action;
/// the picture filling the card is the card's picture, with the card's actions. Each picture is inside its element:
/// a picture outside one reached VoiceOver's audit as an empty image, however it was marked hidden.
private struct PictureAccess: ViewModifier {
    let isWindow: Bool
    let placement: CameraSettings.SelfieWindow?
    let windowID: String
    /// Nil for a half (H.8), which has no size or corner to change.
    let adjust: (() -> Void)?
    let swap: () -> Void
    /// The window shows the main stream: VoiceOver hears it as selected, as the Swap cameras button was.
    let isSwapped: Bool
    let label: Text
    let id: String
    let actions: MemoryCardActions?

    func body(content: Content) -> some View {
        if isWindow, let adjust {
            selfie(content, label: Text("Selfie window", bundle: .module))
                .accessibilityValue(Text(placement?.accessibilityValue ?? ""))
                .accessibilityAction(named: Text("Adjust selfie window", bundle: .module), adjust)
        } else if isWindow {
            selfie(content, label: Text("Selfie half", bundle: .module, comment: "Memory Card (H.8): VoiceOver label of the selfie camera's half of the card"))
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier(id)
                .modifier(CardActions(actions: actions))
        }
    }
}

extension PictureAccess {
    /// The selfie's element, in its window or its half: a tap or VoiceOver's activate swaps the cameras.
    func selfie(_ content: Content, label: Text) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isSwapped ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { swap() }
            .accessibilityAction(named: Text("Swap cameras", bundle: .module), swap)
            .accessibilityIdentifier(windowID)
    }
}

/// U20: the video's controls on a soft scrim inside the card: the scrubber, the time on each side, pause in the
/// middle and the sound beside the total. The times keep clear of the folded corner, on whichever side it is.
struct MemoryCardVideoControls: View {
    let playback: ViewerVideoPlayer?
    let fallbackDuration: Double
    /// The card's folded corner: right, left, or none (review).
    var foldOnRight: Bool?
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
                // U20: the total ends 32 pt from the card's edge, over the fold's crease.
                .padding(.leading, foldOnRight == false ? 10 : 0)
                .padding(.trailing, foldOnRight == true ? 10 : 0)
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
        .padding(.bottom, 20)
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

/// A still filling its frame, cropped inside one drawing. A scaled-to-fill `Image` reaches past its frame, and the
/// picture's VoiceOver element grew to it.
private struct FilledStill: View {
    let image: UIImage

    var body: some View {
        Canvas { context, size in
            let scale = max(size.width / max(image.size.width, 1), size.height / max(image.size.height, 1))
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height)
            context.draw(Image(uiImage: image), in: rect)
        }
        .allowsHitTesting(false)
    }
}
