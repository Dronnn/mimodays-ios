import AVFoundation
import Core
import DesignSystem
import Persistence
import SwiftUI

/// C07 review, or C13d when a recording stopped early. The whole capture is shown (aspect-fit, never cropped);
/// the selfie window can still be moved. Save is the one primary action, everything else is optional.
struct ReviewView: View {
    @State var model: ReviewModel
    let onRetake: () -> Void
    let onSave: () async throws -> Void
    @State private var adjustsSelfie = false
    @State private var isSaving = false
    @State private var editsNote = false
    @State private var confirmsRetake = false
    /// C09 while it is open.
    @State private var recording: VoiceRecording?
    @State private var microphoneOff = false
    @State private var choosesPlace = false
    @State private var locationAllowed = false
    @Environment(\.permissions) private var permissions
    /// C13c, or the generic save failure.
    @State private var saveError: SaveError?
    @Environment(\.openURL) private var openURL
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
        .task {
            // Location is never asked for here: only after a tap on Place.
            guard await permissions.status(of: .location).isUsable else { return }
            locationAllowed = true
            await model.locate()
        }
        .onDisappear { model.stopPlayback() }
        .sheet(isPresented: $adjustsSelfie) {
            SelfieWindowSheet(placement: $model.window)
        }
        .fullScreenCover(isPresented: $editsNote) {
            NoteEditorView(model: model)
        }
        .sheet(item: $recording) { recording in
            VoiceRecordingSheet(recording: recording) { model.addVoice(at: $0.url, recordedAt: $0.startedAt) }
        }
        .sheet(isPresented: $choosesPlace) {
            PlaceSheet(model: model, showsCurrent: locationAllowed)
        }
        .sheet(isPresented: $microphoneOff) {
            PermissionExplainerView(screen: .microphoneOff) {
                openSettings()
            } secondary: {
                microphoneOff = false
            }
        }
        .confirmationDialog(retakeTitle, isPresented: $confirmsRetake, titleVisibility: .visible) {
            Button(role: .destructive) { discardAndRetake() } label: { Text("Retake", bundle: .module) }
            Button(role: .cancel) {} label: { Text("Keep editing", bundle: .module) }
        }
        .alert(saveErrorTitle, isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            if case .lowStorage = saveError {
                Button { openSettings() } label: { Text("Manage storage", bundle: .module) }
            } else {
                Button(role: .cancel) {} label: { Text("Not now", bundle: .module) }
            }
            Button { save() } label: { Text("Try again", bundle: .module) }
                .keyboardShortcut(.defaultAction)
        } message: {
            saveErrorMessage
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

                if model.hasSelfie, model.playback == .stopped, proxy.size.width > 0 {
                    // Laid out as the camera did, on the media at full width, then drawn at the size it is shown:
                    // what is saved is what was recorded, whatever the keyboard or the panel leaves of the media.
                    let layout = SelfieWindowLayout.media(width: proxy.size.width, aspectRatio: model.aspectRatio, topInset: topInset)
                    let reference = layout.preview
                    AdjustableSelfieWindow(placement: $model.window, showsSheet: $adjustsSelfie, layout: layout, id: "review.selfieWindow") {
                        if let selfie = model.selfie {
                            Image(uiImage: selfie).filling()
                        }
                    }
                    .frame(width: reference.width, height: reference.height)
                    .scaleEffect(size.width / reference.width, anchor: .topLeading)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
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
        guard !isSaving else { return }
        if model.hasAnnotations {
            confirmsRetake = true
        } else {
            discardAndRetake()
        }
    }

    /// Copy approved by Andrew, 2026-11-13.
    private var retakeTitle: Text {
        switch (model.note.isEmpty, model.voice == nil) {
        case (false, false): Text("Retake and drop the notes?", bundle: .module)
        case (true, false): Text("Retake and drop the voice note?", bundle: .module)
        default: Text("Retake and drop the note?", bundle: .module)
        }
    }

    /// The system prompt the first time (the tap says why), then one fix for the city (Andrew, 2026-11-13).
    private func choosePlace() {
        guard !isSaving else { return }
        Task {
            var status = await permissions.status(of: .location)
            if status == .notDetermined { status = await permissions.request(.location) }
            locationAllowed = status.isUsable
            choosesPlace = true
            if status.isUsable { await model.locate() }
        }
    }

    /// The system prompt the first time (the tap says why); once it is off, the way to Settings.
    private func recordVoice() {
        guard !isSaving else { return }
        Task {
            var status = await permissions.status(of: .microphone)
            if status == .notDetermined { status = await permissions.request(.microphone) }
            guard status.isUsable else {
                microphoneOff = true
                return
            }
            model.stopPlayback()
            model.stopVoice()
            guard let recording = try? model.makeVoiceRecording(), recording.start() else { return }
            self.recording = recording
        }
    }

    private func discardAndRetake() {
        model.discard()
        onRetake()
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await onSave()
            } catch {
                saveError = error as? SaveError ?? .failed
            }
            isSaving = false
        }
    }

    /// Place, Voice note (until there is one: then its card shows above), Note.
    @ViewBuilder
    private var chips: some View {
        ReviewChip(icon: .glyphPin, title: placeTitle, action: choosePlace)
            .accessibilityLabel(Text("Place", bundle: .module))
            .accessibilityValue(model.place.map { $0.label.map { Text($0) } ?? Text("Current location", bundle: .module) } ?? Text("None", bundle: .module))
            .accessibilityIdentifier("review.place")
        if model.voice == nil {
            ReviewChip(icon: .glyphMic, title: Text("Voice note", bundle: .module), action: recordVoice)
                .accessibilityIdentifier("review.voiceNote")
        }
        ReviewChip(icon: .glyphNote, title: model.note.isEmpty ? Text("Note", bundle: .module) : Text(model.note), isFilled: !model.note.isEmpty) {
            editsNote = true
        }
        .accessibilityLabel(Text("Note", bundle: .module))
        .accessibilityValue(Text(model.note))
        .accessibilityIdentifier("review.note")
    }

    /// The place's name; "Place" until there is one.
    private var placeTitle: Text {
        guard let place = model.place else { return Text("Place", bundle: .module) }
        return place.label.map { Text($0) } ?? Text("Current location", bundle: .module)
    }

    // MARK: Save errors

    private var saveErrorTitle: Text {
        if case .lowStorage = saveError {
            Text("Not enough space to save", bundle: .module)
        } else {
            Text("This moment didn't save", bundle: .module)
        }
    }

    private var saveErrorMessage: Text {
        if case let .lowStorage(shortfall) = saveError {
            // Rounded up to 10 MB: "about 40 MB".
            let rounded = (shortfall + 9_999_999) / 10_000_000 * 10_000_000
            return Text("This moment is kept until you free up about \(rounded.formatted(.byteCount(style: .file))). Nothing is lost.", bundle: .module)
        }
        return Text("Nothing is lost. Try again in a moment.", bundle: .module)
    }

    /// There is no public link to iPhone Storage; Settings is one tap away from it (Andrew, 2026-11-13).
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    // MARK: Panels

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            CaptionField(text: $model.caption, isFocused: $editsCaption)
                .padding(.top, 20)
            if let voice = model.voice {
                VoiceNoteCard(model: model, voice: voice)
                    .padding(.top, 14)
            }
            // One row; under each other once large text no longer fits them side by side.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 0) { chips }
            }
            .padding(.top, 14)
            OriginLabel(origin: model.promptID == nil ? .manual : .randomPrompt, time: CaptureTimeLabel.text(model.capture.capturedAt))
                .textStyle(.reviewMeta)
                .foregroundStyle(ColorToken.textBody.color)
                .padding(.leading, 2)
                .padding(.top, 18)
                .accessibilityIdentifier("review.time")
            Button { save() } label: { Text("Save", bundle: .module) }
                .buttonStyle(.primary)
                .disabled(isSaving)
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
            Button { save() } label: { Text("Save \(model.keptSeconds) seconds", bundle: .module) }
                .buttonStyle(.primary)
                .disabled(isSaving)
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

/// `Chip / Review`: glyph and label on a hand-cut chip; peach once something was added (it then shows its
/// first words).
private struct ReviewChip: View {
    let icon: Icon
    let title: Text
    var isFilled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                icon.image
                    .frame(width: 18, height: 18)
                title
                    .textStyle(.reviewChip)
                    .lineLimit(1)
            }
            .foregroundStyle(ColorToken.textPrimary.color)
            .padding(.leading, 11)
            .padding(.trailing, 13)
            .frame(minHeight: 34)
            .frame(maxWidth: 200, alignment: .leading)
            .fixedSize(horizontal: !isFilled, vertical: false)
            .background(ReviewChipBlob().fill(isFilled ? ColorToken.accentPeach.color : ColorToken.surfaceChip.color))
            .frame(minHeight: Size.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
