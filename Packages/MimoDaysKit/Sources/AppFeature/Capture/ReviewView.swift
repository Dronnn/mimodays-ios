import AVFoundation
import Core
import DesignSystem
import SwiftUI

/// C07 review, or C13d when a recording stopped early. The whole capture is shown (aspect-fit, never cropped);
/// the selfie window can still be moved. Save is the one primary action, everything else is optional.
struct ReviewView: View {
    @State var model: ReviewModel
    let onRetake: () -> Void
    let onSave: () -> Void
    @State private var adjustsSelfie = false
    @State private var topInset: CGFloat = 0
    @FocusState private var editsCaption: Bool

    var body: some View {
        MediaThenPanel(aspectRatio: model.aspectRatio, topInset: topInset) {
            media
            Group {
                if let interruption = model.interruption {
                    interruptedPanel(interruption)
                } else {
                    panel
                }
            }
            .padding(.horizontal, 16)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.top }) { topInset = $0 }
        .task { await model.load() }
        .onDisappear { model.stopPlayback() }
        .sheet(isPresented: $adjustsSelfie) {
            SelfieWindowSheet(placement: $model.window)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review")
    }

    // MARK: Media

    /// The whole frame (aspect-fit) on a full-width band: dark sides when it is too tall for the width.
    private var media: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height * model.aspectRatio)
            let size = CGSize(width: width, height: width / model.aspectRatio)
            ZStack(alignment: .topLeading) {
                ZStack {
                    if model.playback == .stopped {
                        still
                    } else {
                        ReviewPlayerView(player: model.player)
                    }
                    if model.video != nil, model.playback != .playing {
                        PlayButton()
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture { togglePlayback() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.video == nil ? Text("Photo", bundle: .module) : Text("Video", bundle: .module))
                .accessibilityAddTraits(model.video == nil ? .isImage : .isButton)
                .accessibilityAction { togglePlayback() }
                .accessibilityHint(model.video == nil ? Text(verbatim: "") : model.playback == .playing ? Text("Pauses the video", bundle: .module) : Text("Plays the video", bundle: .module))
                .accessibilityIdentifier("review.media")

                if model.hasSelfie, model.playback == .stopped {
                    let layout = SelfieWindowLayout(preview: size, topInset: topInset, bottomMargin: 20)
                    AdjustableSelfieWindow(placement: $model.window, showsSheet: $adjustsSelfie, layout: layout, id: "review.selfieWindow") {
                        if let selfie = model.selfie {
                            Image(uiImage: selfie).resizable().scaledToFill()
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .onChange(of: layout.windowFrame(model.window), initial: true) { model.windowFrame = $1 }
                }
            }
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(CameraPalette.background)
        .overlay(alignment: .topLeading) {
            RetakeButton(action: retake)
                .padding(.leading, 16)
                .padding(.top, topInset - 6)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var still: some View {
        if let main = model.main {
            Image(uiImage: main).resizable()
        } else {
            CameraPalette.previewPlaceholder
        }
    }

    private func togglePlayback() {
        guard model.video != nil else { return }
        Task { await model.togglePlayback() }
    }

    private func retake() {
        model.discard()
        onRetake()
    }

    // MARK: Panels

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            CaptionField(text: $model.caption, isFocused: $editsCaption)
                .padding(.top, 20)
            timeLabel
                .textStyle(.reviewMeta)
                .foregroundStyle(ColorToken.textBody.color)
                .padding(.leading, 2)
                .padding(.top, 18)
                .accessibilityIdentifier("review.time")
            Button { onSave() } label: { Text("Save", bundle: .module) }
                .buttonStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.top, 21)
                .padding(.bottom, 50)
                .accessibilityIdentifier("review.save")
        }
    }

    /// C13d: what stopped the recording, Save N seconds, Record again.
    private func interruptedPanel(_ interruption: CaptureInterruption) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Icon.glyphWarning.image
                    .frame(width: 24, height: 24)
                    .foregroundStyle(ColorToken.textLink.color)
                    .accessibilityHidden(true)
                interruptionText(interruption)
                    .textStyle(.reviewNote)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(minHeight: 88, alignment: .top)
            .background(FieldBlob().fill(ColorToken.accentPeach.color))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("review.interrupted")
            .padding(.top, 20)
            Button { onSave() } label: { Text("Save \(model.keptSeconds) seconds", bundle: .module) }
                .buttonStyle(.primary)
                .padding(.horizontal, 4)
                .padding(.top, 20)
                .accessibilityIdentifier("review.save")
            Button(action: retake) { Text("Record again", bundle: .module) }
                .buttonStyle(.text)
                .padding(.top, 14)
                .padding(.bottom, 40)
                .accessibilityIdentifier("review.recordAgain")
        }
    }

    /// Copy approved by Andrew, 2026-11-13; the call version is the design's.
    private func interruptionText(_ interruption: CaptureInterruption) -> Text {
        let at = Duration.seconds(model.keptSeconds).formatted(.time(pattern: .minuteSecond))
        return switch interruption {
        case .anotherApp: Text("A call stopped the recording at \(at). The part before the call is kept.", bundle: .module)
        case .background: Text("The recording stopped at \(at) when you left MimoDays. The part before is kept.", bundle: .module)
        case .tooWarm: Text("This iPhone got too warm, so the recording stopped at \(at). The part before is kept.", bundle: .module)
        case .lowStorage: Text("This iPhone ran out of space, so the recording stopped at \(at). The part before is kept.", bundle: .module)
        case .other: Text("The recording stopped at \(at). The part before is kept.", bundle: .module)
        }
    }

    /// "Today, 2:37 PM" in the time zone it was captured in.
    private var timeLabel: Text {
        let time = model.capture.capturedAt
        var format = Date.FormatStyle(date: .omitted, time: .shortened)
        format.timeZone = time.timeZone
        var calendar = Calendar.current
        calendar.timeZone = time.timeZone
        if calendar.isDate(time.instant, inSameDayAs: .now) {
            return Text("Today, \(Text(time.instant, format: format))", bundle: .module)
        }
        var full = Date.FormatStyle(date: .abbreviated, time: .shortened)
        full.timeZone = time.timeZone
        return Text(time.instant, format: full)
    }
}

// MARK: - Pieces

/// Media from the top edge, the panel right under it. The panel gets its height first; the media takes the rest,
/// up to its own aspect height. Space left over (tall screens, the keyboard gone) stays below the panel.
private struct MediaThenPanel: Layout {
    let aspectRatio: CGFloat
    /// Under the status bar, which the media goes beneath.
    let topInset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        guard subviews.count == 2 else { return }
        let panel = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        let media = max(topInset, min(bounds.width / aspectRatio, bounds.height - panel))
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: media))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + media), proposal: ProposedViewSize(width: bounds.width, height: panel))
    }
}

/// "Add a few words (optional)": one line on a hand-cut cream field.
private struct CaptionField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        TextField(text: $text) {
            Text("Add a few words (optional)", bundle: .module)
                .foregroundStyle(ColorToken.textTertiary.color)
        }
        .textStyle(.reviewField)
        .foregroundStyle(ColorToken.textPrimary.color)
        .tint(ColorToken.actionCoral.color)
        .focused(isFocused)
        .submitLabel(.done)
        .onSubmit { isFocused.wrappedValue = false }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .background(
            FieldBlob()
                .fill(ColorToken.surfaceCard.color)
                .shadow(color: CameraPalette.chipText.opacity(0.08), radius: 2, y: 1)
        )
        .accessibilityLabel(Text("Caption", bundle: .module))
        .accessibilityIdentifier("review.caption")
    }
}

/// 92×36 dark capsule over the photo.
private struct RetakeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Retake", bundle: .module)
                .textStyle(.reviewRetake)
                .foregroundStyle(CameraPalette.cream)
                .padding(.horizontal, 21)
                .frame(minHeight: 36)
                .background(CameraPalette.controlScrim, in: Capsule())
                .frame(minHeight: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review.retake")
    }
}

/// 64 pt cream disc with a plum triangle.
private struct PlayButton: View {
    var body: some View {
        Icon.glyphPlay.image
            .frame(width: 30, height: 30)
            .foregroundStyle(CameraPalette.chipText)
            .frame(width: 64, height: 64)
            .background(CameraPalette.cream.opacity(0.9), in: Circle())
            .shadow(color: .black.opacity(0.2), radius: 7, y: 4)
            .accessibilityHidden(true)
    }
}

/// The composed clip, whole frame (aspect-fit, like the still).
private struct ReviewPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context _: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_: PlayerView, context _: Context) {}

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
