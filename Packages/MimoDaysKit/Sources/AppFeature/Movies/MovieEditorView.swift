import AVFoundation
import Core
import DesignSystem
import Persistence
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Opens a project in the editor by its id; nothing when it has gone.
struct MovieEditorScreen: View {
    let projectID: UUID
    @Environment(\.mediaLibrary) private var library
    @Environment(\.camera) private var camera
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let library, let project = MovieStore.project(projectID, in: library.context) {
            // Made once: each one composes the whole movie.
            ModelHost({ MovieEditorModel(project: project, library: library, voice: (camera ?? .simulated).voice) }) { model in
                MovieEditorHost(model: model, export: { router.moviesPath.append(.export(projectID)) })
            }
        }
    }
}

private struct MovieEditorHost: View {
    @State var model: MovieEditorModel
    let export: () -> Void
    var body: some View { MovieEditorView(model: model, export: export) }
}

/// F06-F09: the stage, play and Undo, the clips strip, and the tool picked below: Clips, Shape, Captions, Audio.
struct MovieEditorView: View {
    let model: MovieEditorModel
    let export: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sheet: Sheet?
    @State private var choosingMusic = false
    @State private var musicOptions = false
    /// The voice over the movie while it records (F09).
    @State private var voiceover: VoiceRecording?
    @State private var microphoneOff = false
    @State private var asker = PermissionAsker()
    /// Off screen (left while the microphone was asked for): nothing starts recording.
    @State private var isShown = false
    @Environment(\.permissions) private var permissions
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var previewing = false
    /// U52: the window while a finger moves it on the stage, in movie pixels.
    @State private var movingWindow: CGRect?
    @State private var isLandscape = false

    enum Sheet: Identifiable, Hashable {
        case trim
        case replace
        case title
        case clip
        case card
        /// U53: into the item at this index.
        case transition(Int)

        var id: Self { self }
    }

    /// The panel under the strip, as tall as drawn; it scrolls when larger text needs more.
    @ScaledMetric(relativeTo: .body) private var panelHeight: CGFloat = 182

    var body: some View {
        Group {
            // X04 is drawn landscape; an upright iPad keeps the stacked layout, the stage taking the extra height.
            if sizeClass == .regular, isLandscape { wideLayout } else { narrowLayout }
        }
        .onGeometryChange(for: Bool.self, of: { $0.size.width > $0.size.height }) { isLandscape = $0 }
        // The whole screen, so the canvas reaches every edge whatever the content's height.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .trim: TrimSheet(model: model)
            case .replace: ReplaceSheet(model: model)
            case .title: TitleSheet(model: model)
            case .clip: ClipSheet(model: model)
            case .card: CardSheet(model: model)
            case let .transition(index): TransitionSheet(model: model, index: index)
            }
        }
        // Playback moves the selection on: a sheet edits the item it opened for, so playing stops.
        .onChange(of: sheet) { _, sheet in
            if sheet != nil { model.pause() }
        }
        .fileImporter(isPresented: $choosingMusic, allowedContentTypes: [.audio]) { result in
            if case let .success(url) = result { model.setMusic(from: url) }
        }
        .confirmationDialog(Text("Music", bundle: .module), isPresented: $musicOptions, titleVisibility: .hidden) {
            switch model.track?.kind {
            case nil:
                Button { choosingMusic = true } label: {
                    Text("Choose music", bundle: .module, comment: "Movie editor (F09): menu action that picks a music file for the movie")
                }
                Button(action: recordVoice) {
                    Text("Record voice", bundle: .module, comment: "Movie editor (F09): menu action that records the person's voice over the whole movie")
                }
            case .soundtrack:
                Button { choosingMusic = true } label: { Text("Choose another file", bundle: .module) }
                Button(action: recordVoice) { Text("Record voice", bundle: .module) }
                Button(role: .destructive, action: model.removeTrack) { Text("Remove music", bundle: .module) }
            case .voiceover:
                Button(action: recordVoice) {
                    Text("Movie voice: record again", bundle: .module, comment: "Movie editor (F09): menu action that records the voice over the movie again, replacing the old one. English: Record again")
                }
                Button { choosingMusic = true } label: { Text("Choose music", bundle: .module) }
                Button(role: .destructive, action: model.removeTrack) {
                    Text("Remove your voice", bundle: .module, comment: "Movie editor (F09): menu action that takes the recorded voice out of the movie")
                }
            }
        }
        .sheet(item: $voiceover) { recording in
            // Up at once, so nothing behind it changes while the movie gets ready; it starts the take from there.
            VoiceRecordingSheet(recording: recording, title: Text("Your voice", bundle: .module), start: { await model.startVoiceover(recording) }) {
                model.finishVoiceover($0)
            }
        }
        .permissionExplainers(asker)
        .alert(
            Text("Not enough space to record. Free up some space on this iPhone and try again.", bundle: .module),
            isPresented: Binding { model.noRoomForVoice } set: { model.noRoomForVoice = $0 }
        ) {
            Button(role: .cancel) {} label: { Text("OK", bundle: .module) }
        }
        .sheet(isPresented: $microphoneOff) {
            PermissionExplainerView(screen: .movieVoiceOff) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } secondary: {
                microphoneOff = false
            }
        }
        // Leaving MimoDays stops the recording; what was recorded is kept, whether or not its sheet came up.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, let take = model.voiceover else { return }
            model.finishVoiceover(take)
            voiceover = nil
        }
        .fullScreenCover(isPresented: $previewing) {
            MoviePreviewView(model: model, export: {
                previewing = false
                export()
            })
        }
        .onAppear {
            isShown = true
            model.observeTime()
        }
        .onDisappear {
            isShown = false
            // The microphone's explainer covers the editor without leaving it.
            if !previewing, asker.screen == nil { model.close() }
        }
    }

    /// F09's voice over the movie: our explainer and the system prompt the first time; once it is off, the way to
    /// Settings.
    private func recordVoice() {
        guard !asker.isAsking, model.voiceover == nil else { return }
        Task {
            let status = await asker.request(.microphone, screen: .movieVoice, using: permissions)
            // The microphone only records with its sheet up: not once the editor is gone or something else opened.
            guard isShown, sheet == nil, !previewing, model.voiceover == nil else { return }
            guard status.isUsable else {
                if status.needsSettings { microphoneOff = true }
                return
            }
            voiceover = model.newVoiceover()
        }
    }

    // MARK: Layouts

    private var narrowLayout: some View {
        VStack(spacing: 0) {
            topBar
                .clearOfBareTopEdge()
            stage
                .padding(.top, 8)
            transport
                .padding(.top, 8)
            timeline
                .padding(.top, 8)
            ScrollView {
                panel.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            // As tall as drawn where the screen has room (the stage gives way first); a short screen (iPhone Duo's
            // outer display) shortens it, and it scrolls.
            .frame(minHeight: 96, idealHeight: panelHeight, maxHeight: panelHeight)
            .layoutPriority(1)
            .padding(.top, 8)
            toolBar
                .overlay(alignment: .top) { Color(hex: 0x4B2938).opacity(0.14).frame(height: 1) }
                .background(ColorToken.canvas.color.ignoresSafeArea(edges: .bottom))
        }
    }

    /// X04: the stage and transport with the tools beside them, the tool's panel under the tools; the timeline runs
    /// the full width below.
    private var wideLayout: some View {
        VStack(spacing: 0) {
            topBar
                .clearOfBareTopEdge()
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    stage
                        .padding(.top, 8)
                    transport
                        .padding(.top, 8)
                }
                VStack(spacing: 0) {
                    toolBar
                        .padding(.horizontal, 8)
                    ScrollView {
                        panel.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: .infinity)
                    .background(ColorToken.canvasSidebar.color)
                }
                .frame(width: 400)
                .padding(.top, 8)
            }
            timeline
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
    }

    private var timeline: some View {
        MovieTimeline(model: model, transition: { index in
            model.select(index)
            sheet = .transition(index)
        })
    }

    // MARK: Top

    /// `Navigation / Back bar`: ‹ Movies, the movie's name, Export.
    private var topBar: some View {
        TitleBar {
            Button { dismiss() } label: {
                HStack(spacing: 0) {
                    Icon.glyphBack.image
                        .resizable()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .flipsForRightToLeftLayoutDirection(true)
                    Text("Movies", bundle: .module)
                        .textStyle(.editorCancel)
                        .foregroundStyle(ColorToken.textLink.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                // At most 96 pt, so the movie's name keeps the room, however long the translation.
                .frame(maxWidth: 96, minHeight: Size.minimumTapTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor.back")
        } title: {
            Text(model.project.title)
                .textStyle(.editorTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
        } trailing: {
            Button(action: export) {
                Text("Export", bundle: .module)
                    .textStyle(TextStyle(.body, size: 17, weight: 700, relativeTo: .body, maximumScale: 1.35))
                    .foregroundStyle(ColorToken.textLink.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: 96, minHeight: Size.minimumTapTarget, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.items.isEmpty)
            .accessibilityIdentifier("editor.export")
        }
        .frame(height: 44)
    }

    // MARK: Stage

    /// `Editor / Stage`: the movie in its shape on the dark stage; tap to watch it big (F10).
    private var stage: some View {
        GeometryReader { proxy in
            let size = MovieEditorView.frame(for: model.project.aspectRatio, in: CGSize(width: proxy.size.width - 32, height: proxy.size.height - 18))
            ZStack {
                MoviePlayerSurface(player: model.player)
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipShape(HandCutCard(cornerRadius: 12))
                    // The movie is one element and the selfie window over it another, each with its own actions.
                    .accessibilityElement()
                    .accessibilityLabel(Text("Movie preview", bundle: .module))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { previewing = true }
                    .accessibilityIdentifier("editor.stage")
                    .overlay { if sheet == .clip { windowHandle(size) } }
                    .overlay(alignment: .bottom) { if let lead = model.leadProgress { leadBadge(lead) } }
                if model.failed {
                    Text("This movie can't play right now.", bundle: .module)
                        .textStyle(.pageIntro)
                        .foregroundStyle(ColorToken.mediaFrame.color)
                        .multilineTextAlignment(.center)
                        .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { previewing = true }
        }
        // iPad's taller screen goes to the stage; on iPhone it is as tall as drawn at most.
        .frame(minHeight: 140, maxHeight: sizeClass == .regular ? .infinity : 330)
        .background(Color(hex: 0x2A1B21))
    }

    /// U54: while an Atmosphere's sound leads, the sound drawn in the dark and a coral pill naming it.
    private func leadBadge(_ lead: (elapsed: Double, lead: Double)) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(ColorToken.mediaFrame.color.opacity(0.9))
            Spacer()
            Text("Atmosphere · sound first", bundle: .module)
                .textStyle(TextStyle(.body, size: 13, weight: 800, relativeTo: .footnote, maximumScale: 1.2))
                .foregroundStyle(ColorToken.mediaFrame.color)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(Capsule().fill(ColorToken.actionCoral.color))
                .padding(.bottom, 14)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// U52: the clip's window as the movie draws it, dashed in coral; drag to move it, pinch to resize.
    @ViewBuilder
    private func windowHandle(_ stage: CGSize) -> some View {
        if let plan = model.selectedPlan, plan.selfieURL != nil, [nil, .window, .swapped].contains(plan.layout) {
            let canvas = model.project.aspectRatio.renderSize(MovieEditorModel.previewResolution)
            let scale = stage.width / canvas.width
            let picture = MovieComposer.pictureRect(source: plan.pictureSize ?? canvas, canvas: canvas, fit: model.project.fit)
            if let rect = movingWindow ?? MovieComposer.windowRect(window: plan.window, placement: plan.placement, picture: picture, canvas: canvas) {
                SelfieWindowShape()
                    .stroke(ColorToken.actionCoral.color, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .rotationEffect(.degrees(-5.4))
                    .contentShape(Rectangle())
                    .position(x: rect.midX * scale, y: rect.midY * scale)
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                let base = MovieComposer.windowRect(window: plan.window, placement: plan.placement, picture: picture, canvas: canvas) ?? rect
                                movingWindow = base.offsetBy(dx: drag.translation.width / scale, dy: drag.translation.height / scale)
                            }
                            .onEnded { _ in placeWindow(picture: picture, canvas: canvas) }
                            .simultaneously(with: MagnifyGesture()
                                .onChanged { pinch in
                                    movingWindow = Self.resized(movingWindow ?? rect, by: pinch.magnification, canvas: canvas)
                                }
                                .onEnded { _ in placeWindow(picture: picture, canvas: canvas) })
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("Selfie window", bundle: .module))
                    // VoiceOver: a corner from the actions, the size by swiping up or down.
                    .accessibilityActions {
                        ForEach(CameraSettings.SelfieWindow.Corner.allCases, id: \.self) { corner in
                            Button { moveWindow(rect, to: corner, picture: picture, canvas: canvas) } label: { Text(corner.title) }
                        }
                    }
                    .accessibilityAdjustableAction { direction in
                        movingWindow = Self.resized(rect, by: direction == .increment ? 1.2 : 1 / 1.2, canvas: canvas)
                        placeWindow(picture: picture, canvas: canvas)
                    }
                    .accessibilityIdentifier("editor.window")
            }
        }
    }

    /// The moved window kept as a share of the picture, the way the movie reads it.
    /// The window scaled about its centre: at least 15 % of the movie's width, at most half its width and half its
    /// height, so a tall window in a wide movie still fits.
    static func resized(_ rect: CGRect, by factor: CGFloat, canvas: CGSize) -> CGRect {
        let largest = min(canvas.width * 0.5, canvas.height * 0.5 * rect.width / rect.height)
        let width = min(max(rect.width * factor, canvas.width * 0.15), largest)
        let height = width * rect.height / rect.width
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    /// VoiceOver's corner actions: the window into that corner of the picture, a little in from its edges.
    private func moveWindow(_ rect: CGRect, to corner: CameraSettings.SelfieWindow.Corner, picture: CGRect, canvas: CGSize) {
        let inset = min(picture.width, picture.height) * 0.04
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        movingWindow = CGRect(
            x: left ? picture.minX + inset : picture.maxX - inset - rect.width,
            y: top ? picture.minY + inset : picture.maxY - inset - rect.height,
            width: rect.width, height: rect.height
        )
        placeWindow(picture: picture, canvas: canvas)
    }

    private func placeWindow(picture: CGRect, canvas: CGSize) {
        guard let rect = movingWindow, let window = model.selectedPlan?.window, picture.width > 0, picture.height > 0 else { return }
        var frame = window
        frame.centerX = Double((rect.midX - picture.minX) / picture.width)
        frame.centerY = Double((rect.midY - picture.minY) / picture.height)
        frame.scale = Double(rect.width / min(canvas.width, canvas.height))
        model.setWindow(frame)
        movingWindow = nil
    }

    /// The movie's frame inside the stage, as large as fits.
    static func frame(for ratio: MovieAspectRatio, in space: CGSize) -> CGSize {
        let shape = ratio.renderSize(.p720)
        let scale = min(space.width / shape.width, space.height / shape.height)
        return CGSize(width: (shape.width * scale).rounded(), height: (shape.height * scale).rounded())
    }

    // MARK: Transport

    /// `Editor / Transport`: play or pause, where we are of how long, Undo.
    private var transport: some View {
        HStack(spacing: 0) {
            Button(action: model.togglePlay) {
                (model.isPlaying ? Icon.glyphPause : Icon.glyphPlay).image
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module))
            .accessibilityIdentifier("editor.play")
            .padding(.leading, -8)
            Text(verbatim: "\(Self.clock(model.time)) / \(Self.clock(model.duration))")
                .textStyle(TextStyle(.body, size: 14, weight: 700, relativeTo: .footnote))
                .monospacedDigit()
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.leading, 2)
                .accessibilityIdentifier("editor.time")
            Spacer()
            Button(action: model.undo) {
                Icon.glyphUndo.image
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .frame(width: Size.minimumTapTarget, height: Size.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo)
            .opacity(model.canUndo ? 1 : 0.35)
            .accessibilityLabel(Text("Undo", bundle: .module))
            .accessibilityIdentifier("editor.undo")
            .padding(.trailing, -8)
        }
        .padding(.horizontal, 18)
        .frame(height: 28)
    }

    /// "0:12".
    static func clock(_ seconds: Double) -> String {
        Duration.seconds(max(seconds, 0).rounded(.down)).formatted(.time(pattern: .minuteSecond).locale(AppLanguage.shared.locale))
    }

    // MARK: Panels

    @ViewBuilder
    private var panel: some View {
        switch model.tool {
        case .clips: ClipsPanel(model: model, open: { sheet = $0 })
        case .shape: ShapePanel(model: model)
        case .text: CaptionsPanel(model: model, title: { sheet = .title }, addCard: {
                model.addCard()
                sheet = .card
            })
        case .audio: AudioPanel(model: model, music: { musicOptions = true })
        }
    }

    // MARK: Tools

    /// `Editor / Clips` (the tool bar): four tools, the current one on a peach pill.
    private var toolBar: some View {
        HStack(spacing: 0) {
            ForEach(MovieEditorModel.Tool.allCases, id: \.self) { tool in
                let isOn = model.tool == tool
                Button { model.tool = tool } label: {
                    VStack(spacing: 8) {
                        tool.icon.image
                            .resizable()
                            .frame(width: 24, height: 24)
                            .frame(width: 60, height: 32)
                            .background { if isOn { Capsule().fill(ColorToken.accentPeach.color) } }
                        tool.title
                            .textStyle(TextStyle(.body, size: 12, weight: 700, relativeTo: .caption2, maximumScale: 1.35))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle((isOn ? ColorToken.textLink : .textPrimary).color)
                    .frame(maxWidth: .infinity, minHeight: Size.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("editor.tool.\(tool)")
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

extension MovieEditorModel.Tool {
    var icon: Icon {
        switch self {
        case .clips: .glyphScissors
        case .shape: .glyphCrop
        case .text: .glyphText
        case .audio: .glyphMusic
        }
    }

    var title: Text {
        switch self {
        case .clips: Text("Clips", bundle: .module)
        case .shape: Text("Shape", bundle: .module)
        case .text: Text("Text", bundle: .module, comment: "Editor tool: captions and text cards")
        case .audio: Text("Audio", bundle: .module)
        }
    }
}

// MARK: - Clips (F06)

struct ClipsPanel: View {
    let model: MovieEditorModel
    let open: (MovieEditorView.Sheet) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let meta = model.selectedMeta(locale: locale) {
                Text(meta)
                    .textStyle(.noteMeta)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .accessibilityIdentifier("editor.clipMeta")
            }
            HStack(spacing: 8) { actions }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            HStack(spacing: 20) {
                if model.selectedClip != nil {
                    quiet(Text("Replace", bundle: .module), id: "editor.replace") { open(.replace) }
                }
                quiet(Text("Remove", bundle: .module), id: "editor.remove", action: model.remove)
                    .disabled(!model.canRemove)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            Text("Long-press and drag to move. Tap a dot between two to change how one leads into the next.", bundle: .module)
                .textStyle(TextStyle(.body, size: 13, weight: 500, relativeTo: .footnote))
                .foregroundStyle(ColorToken.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.selectedCard != nil {
            Button { open(.card) } label: { Text("Edit card", bundle: .module) }
                .buttonStyle(PeachButtonStyle())
                .accessibilityIdentifier("editor.editCard")
        } else {
            Button { open(.clip) } label: { Text("Cameras", bundle: .module) }
                .buttonStyle(PeachButtonStyle())
                .accessibilityIdentifier("editor.cameras")
            Button { open(.clip) } label: { Text("Sound", bundle: .module) }
                .buttonStyle(PeachButtonStyle())
                .accessibilityIdentifier("editor.sound")
            Button { open(.trim) } label: { Text("Trim", bundle: .module) }
                .buttonStyle(PeachButtonStyle())
                .accessibilityIdentifier("editor.trim")
        }
    }

    private func quiet(_ title: Text, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .textStyle(TextStyle(.body, size: 14, weight: 700, relativeTo: .subheadline))
                .foregroundStyle(ColorToken.textLink.color)
                .frame(minHeight: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// U50's Cameras / Sound / Trim: a word in plum on a peach pill.
struct PeachButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(TextStyle(.body, size: 15, weight: 800, relativeTo: .subheadline, maximumScale: 1.35))
            .foregroundStyle(ColorToken.textPrimary.color)
            // Long translations wrap rather than lose letters.
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(ColorToken.accentPeach.color))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

/// `Button / Third`: a 20 pt glyph and a word on the hand-cut chip shape, 44 pt tall.
struct ThirdButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ThirdLabelStyle())
            .textStyle(TextStyle(.body, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35))
            .foregroundStyle(ColorToken.textPrimary.color)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background { ColorToken.surfaceChip.color.mask { Icon.shapeButton.image.resizable() } }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

private struct ThirdLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title.lineLimit(1).minimumScaleFactor(0.85)
        }
    }
}

extension MovieEditorModel {
    /// "Clip 2 · Nov 11, 6:42 PM · 0:06", "Text card · 3 s"; during an Atmosphere lead "Atmosphere · 1.4 s of 2.0 s lead" (U54).
    func selectedMeta(locale: Locale) -> String? {
        if let lead = leadProgress {
            return String(
                appLocalized: "Atmosphere · \(TransitionSheet.seconds(lead.elapsed)) of \(TransitionSheet.seconds(lead.lead)) lead", bundle: .module,
                comment: "U54: how far the sound has led, e.g. Atmosphere · 1.4 s of 2.0 s lead"
            )
        }
        if let card = selectedCard {
            return String(appLocalized: "Text card · \(Int(card.duration)) s", bundle: .module, comment: "U50: a chosen text card and its seconds")
        }
        guard let clip = selectedClip, let plan = selectedPlan, let moment = clip.moment else { return nil }
        let zone = TimeZone(identifier: moment.timeZoneID) ?? .current
        let when = moment.capturedAt.formatted(Date.FormatStyle(locale: locale, timeZone: zone).month(.abbreviated).day().hour().minute())
        return String(
            appLocalized: "Clip \(selectedClipNumber) · \(when) · \(MovieEditorView.clock(plan.duration))", bundle: .module,
            comment: "U50: the chosen clip, when it was taken, and how long it plays, e.g. Clip 2 · Nov 11, 6:42 PM · 0:06"
        )
    }
}

// MARK: - Shape (F07)

struct ShapePanel: View {
    let model: MovieEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SegmentedControl(selection: Binding(get: { model.project.aspectRatio }, set: model.setAspectRatio), options: MovieAspectRatio.allCases, labelSize: 15) {
                Text(verbatim: $0.label)
            }
            .padding(.horizontal, 20)
            .accessibilityIdentifier("editor.aspect")
            SegmentedControl(selection: Binding(get: { model.project.fit }, set: model.setFit), options: MovieFit.allCases, labelSize: 15) { fit in
                switch fit {
                case .fill: Text("Fill", bundle: .module)
                case .showAll: Text("Show all", bundle: .module)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .accessibilityIdentifier("editor.fit")
            Text("Selfie window for this clip", bundle: .module)
                .textStyle(TextStyle(.body, size: 15, weight: 700, relativeTo: .subheadline))
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.horizontal, 20)
                .padding(.top, 14)
            if model.selectedPlan?.window == nil {
                Text("This clip has no selfie.", bundle: .module)
                    .textStyle(.pageIntro)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            } else {
                FlowChips(selection: model.selectedClip?.selfiePlacement, choose: model.setPlacement)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
        }
    }
}

/// `Chip / Selfie`: where this clip's selfie window goes; none lit while it stays where it was recorded.
private struct FlowChips: View {
    let selection: MovieSelfiePlacement?
    let choose: (MovieSelfiePlacement) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) { chip(.topRight); chip(.topLeft) }
                HStack(spacing: 8) { chip(.bottom); chip(.hidden) }
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(MovieSelfiePlacement.allCases, id: \.self) { chip($0) }
    }

    private func chip(_ placement: MovieSelfiePlacement) -> some View {
        let isOn = selection == placement
        return Button { choose(placement) } label: {
            placement.title
                .textStyle(isOn ? .reviewChipOn : .reviewChip)
                .foregroundStyle((isOn ? ColorToken.textLink : .textPrimary).color)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(ReviewChipBlob().fill((isOn ? ColorToken.accentPeach : .surfaceChip).color))
                .frame(minHeight: Size.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("editor.selfie.\(placement.rawValue)")
    }
}

extension MovieSelfiePlacement {
    var title: Text {
        switch self {
        case .topRight: Text("Top right", bundle: .module)
        case .topLeft: Text("Top left", bundle: .module)
        case .bottom: Text("Bottom", bundle: .module, comment: "Selfie window placement: bottom right of the movie frame")
        case .hidden: Text("Hidden", bundle: .module)
        }
    }
}

// MARK: - Captions (F08)

struct CaptionsPanel: View {
    let model: MovieEditorModel
    let title: () -> Void
    /// U51: a new text card before the first clip.
    let addCard: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: addCard) { Label { Text("Add a text card", bundle: .module) } icon: { Icon.glyphPlus.image.resizable().frame(width: 20, height: 20) } }
                .buttonStyle(ThirdButtonStyle())
                .padding(.horizontal, 16)
                .accessibilityIdentifier("editor.addCard")
            captions
        }
    }

    private var captions: some View {
        VStack(spacing: 0) {
            toggle(Text("Date on each clip", bundle: .module), isOn: model.project.showsDates, set: model.setShowsDates, id: "editor.dates")
            separator
            toggle(Text("Place on each clip", bundle: .module), isOn: model.project.showsPlaces, set: model.setShowsPlaces, id: "editor.places")
            separator
            Button(action: title) {
                HStack(spacing: 8) {
                    Text("Title at the start", bundle: .module)
                        .textStyle(.rowTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                    Spacer(minLength: 8)
                    Group {
                        if model.project.showsTitle {
                            Text(model.project.title)
                        } else {
                            Text("Off", bundle: .module)
                        }
                    }
                    .textStyle(.rowValue)
                    .foregroundStyle(ColorToken.textTertiary.color)
                    .lineLimit(1)
                    Icon.glyphChevron.image
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .flipsForRightToLeftLayoutDirection(true)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("editor.title")
        }
        .background(ColorToken.surfaceCard.color, in: HandCutCard())
        .padding(.horizontal, 16)
    }

    private var separator: some View {
        Color(hex: 0x4B2938).opacity(0.12).frame(height: 1).padding(.leading, 16)
    }

    private func toggle(_ title: Text, isOn: Bool, set: @escaping @Sendable @MainActor (Bool) -> Void, id: String) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            title.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
        }
        .tint(ColorToken.actionCoral.color)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Audio (F09)

struct AudioPanel: View {
    let model: MovieEditorModel
    let music: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(Text("Sound from clips", bundle: .module), detail: Text(model.project.clipSoundLevel, format: .percent.precision(.fractionLength(0))))
            LevelSlider(value: Binding(get: { model.project.clipSoundLevel }, set: model.setClipSoundLevel), changing: changing)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .accessibilityLabel(Text("Sound from clips", bundle: .module))
                .accessibilityIdentifier("editor.clipSound")
            row(
                Text("Voice notes", bundle: .module),
                detail: Text("\(model.voiceNoteCount) of \(model.clipCount) clips", bundle: .module, comment: "F09: how many clips have a voice note")
            )
            .padding(.top, 10)
            LevelSlider(value: Binding(get: { model.project.voiceNoteLevel }, set: model.setVoiceNoteLevel), changing: changing)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .accessibilityLabel(Text("Voice notes", bundle: .module))
                .accessibilityIdentifier("editor.voiceLevel")
            Button(action: music) {
                HStack(spacing: 4) {
                    Text("Music or voice", bundle: .module, comment: "Movie editor (F09): the row of the movie's one track, a music file or the person's voice")
                        .textStyle(.rowTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                    Spacer(minLength: 8)
                    Group {
                        if let track = model.track {
                            Text(track.kind == .voiceover ? track.title : track.name ?? String(appLocalized: "On", bundle: .module))
                        } else {
                            Text("None", bundle: .module, comment: "F09: no music chosen")
                        }
                    }
                    .textStyle(TextStyle(.body, size: 14, weight: 600, relativeTo: .footnote))
                    .foregroundStyle(ColorToken.textLink.color)
                    .lineLimit(1)
                    Icon.glyphChevron.image
                        .resizable()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .flipsForRightToLeftLayoutDirection(true)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Size.minimumTapTarget)
                .contentShape(Rectangle())
                // A 44 pt target in the 20 pt row drawn.
                .padding(.vertical, -12)
            }
            .buttonStyle(.plain)
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.top, 10)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("editor.music")
            if let track = model.track {
                LevelSlider(value: Binding(get: { track.gain }, set: model.setTrackLevel), changing: changing)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .accessibilityLabel(Text(track.title))
                    .accessibilityIdentifier("editor.trackLevel")
            }
            Text("A song from Files, or your voice over the movie.", bundle: .module, comment: "Movie editor (F09): note under the music or voice row")
                .textStyle(TextStyle(.body, size: 13, weight: 500, relativeTo: .footnote))
                .foregroundStyle(ColorToken.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.top, 8)
        }
    }

    private func changing(_ isChanging: Bool) {
        if isChanging { model.beginLevelChange() } else { model.endLevelChange() }
    }

    private func row(_ title: Text, detail: Text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            title.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
            Spacer(minLength: 8)
            detail
                .textStyle(TextStyle(.body, size: 14, weight: 600, relativeTo: .footnote))
                .foregroundStyle(ColorToken.textSecondary.color)
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
    }
}

/// `Control / Slider`: a 5 pt track, coral up to a cream knob ringed in coral.
struct LevelSlider: View {
    @Binding var value: Double
    /// True when a drag starts, false when it ends.
    let changing: (Bool) -> Void
    @State private var dragging = false
    @GestureState private var pressed = false

    var body: some View {
        GeometryReader { proxy in
            let knob: CGFloat = 24
            let span = max(proxy.size.width - knob, 1)
            let x = CGFloat(value) * span
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: 0xE0D2C6)).frame(height: 5)
                Capsule().fill(ColorToken.actionCoral.color).frame(width: x + knob / 2, height: 5)
                Circle()
                    .fill(ColorToken.surfaceCard.color)
                    .overlay(Circle().strokeBorder(ColorToken.actionCoral.color, lineWidth: 2))
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            // Left to right in every language, as the preview's scrubber: the fill, the knob and a touch agree.
            .environment(\.layoutDirection, .leftToRight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !dragging {
                            dragging = true
                            changing(true)
                        }
                        value = Double(min(max((drag.location.x - knob / 2) / span, 0), 1))
                    }
                    .updating($pressed) { _, pressed, _ in pressed = true }
                    .onEnded { _ in
                        dragging = false
                        changing(false)
                    }
            )
            // A drag cancelled (a call coming in) or cut short (another tool picked) never ends: the change is kept
            // all the same.
            .onDisappear {
                if dragging {
                    dragging = false
                    changing(false)
                }
            }
            .onChange(of: pressed) { _, pressed in
                if !pressed, dragging {
                    dragging = false
                    changing(false)
                }
            }
        }
        .frame(height: 24)
        // 24 pt as drawn; the touch area reaches 10 pt further each way.
        .contentShape(Rectangle().inset(by: -10))
        .accessibilityElement()
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            changing(true)
            switch direction {
            case .increment: value = min(value + 0.1, 1)
            case .decrement: value = max(value - 0.1, 0)
            @unknown default: break
            }
            changing(false)
        }
    }
}

/// An `AVPlayerLayer` for a player owned elsewhere: the picture fitted inside, nothing cropped.
struct MoviePlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context _: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerView, context _: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

extension MovieAudioTrack {
    /// F09's name for the movie's track: "Your voice", or the song's file name.
    var title: String {
        switch kind {
        case .voiceover:
            String(
                appLocalized: "Your voice", bundle: .module,
                comment: "Movie editor (F09): the person's voice recorded over the movie, where a song's name would show; the recording sheet's title"
            )
        case .soundtrack: name ?? String(appLocalized: "Music", bundle: .module)
        }
    }
}
