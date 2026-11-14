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
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let library, let project = MovieStore.project(projectID, in: library.context) {
            MovieEditorHost(model: MovieEditorModel(project: project, library: library), export: { router.moviesPath.append(.export(projectID)) })
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
    @State private var sheet: Sheet?
    @State private var choosingMusic = false
    @State private var musicOptions = false
    @State private var previewing = false

    enum Sheet: String, Identifiable {
        case trim
        case replace
        case title
        var id: String { rawValue }
    }

    /// The panel under the strip, as tall as drawn; it scrolls when larger text needs more.
    @ScaledMetric(relativeTo: .body) private var panelHeight: CGFloat = 182

    var body: some View {
        VStack(spacing: 0) {
            topBar
            stage
                .padding(.top, 8)
            transport
                .padding(.top, 8)
            MovieTimeline(model: model, trim: { sheet = .trim })
            ScrollView {
                panel.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: panelHeight)
            .padding(.top, 8)
            toolBar
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .trim: TrimSheet(model: model)
            case .replace: ReplaceSheet(model: model)
            case .title: TitleSheet(model: model)
            }
        }
        .fileImporter(isPresented: $choosingMusic, allowedContentTypes: [.audio]) { result in
            if case let .success(url) = result { model.setMusic(from: url) }
        }
        .confirmationDialog(Text("Music", bundle: .module), isPresented: $musicOptions, titleVisibility: .hidden) {
            Button { choosingMusic = true } label: { Text("Choose another file", bundle: .module) }
            Button(role: .destructive) { model.removeMusic() } label: { Text("Remove music", bundle: .module) }
        }
        .fullScreenCover(isPresented: $previewing) {
            MoviePreviewView(model: model, export: {
                previewing = false
                export()
            })
        }
        .onDisappear { if !previewing { model.close() } }
    }

    // MARK: Top

    /// `Navigation / Back bar`: ‹ Movies, the movie's name, Export.
    private var topBar: some View {
        ZStack {
            Text(model.project.title)
                .textStyle(.editorTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .lineLimit(1)
                .padding(.horizontal, 96)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
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
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .frame(minHeight: Size.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("editor.back")
                Spacer()
                Button(action: export) {
                    Text("Export", bundle: .module)
                        .textStyle(TextStyle(.nunito, size: 17, weight: 700, relativeTo: .body, maximumScale: 1.35))
                        .foregroundStyle(ColorToken.textLink.color)
                        .padding(.horizontal, 20)
                        .frame(minHeight: Size.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.clips.isEmpty)
                .accessibilityIdentifier("editor.export")
            }
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
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .frame(minHeight: 140, maxHeight: 330)
        .background(Color(hex: 0x2A1B21))
        .accessibilityElement()
        .accessibilityLabel(Text("Movie preview", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { previewing = true }
        .accessibilityIdentifier("editor.stage")
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
                .textStyle(TextStyle(.nunito, size: 14, weight: 700, relativeTo: .footnote))
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
        Duration.seconds(max(seconds, 0).rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }

    // MARK: Panels

    @ViewBuilder
    private var panel: some View {
        switch model.tool {
        case .clips: ClipsPanel(model: model, trim: { sheet = .trim }, replace: { sheet = .replace })
        case .shape: ShapePanel(model: model)
        case .captions: CaptionsPanel(model: model, title: { sheet = .title })
        case .audio: AudioPanel(model: model, music: {
                if model.music == nil { choosingMusic = true } else { musicOptions = true }
            })
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
                            .textStyle(TextStyle(.nunito, size: 12, weight: 700, relativeTo: .caption2, maximumScale: 1.35))
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
        .overlay(alignment: .top) { Color(hex: 0x4B2938).opacity(0.14).frame(height: 1) }
        .background(ColorToken.canvas.color.ignoresSafeArea(edges: .bottom))
    }
}

extension MovieEditorModel.Tool {
    var icon: Icon {
        switch self {
        case .clips: .glyphScissors
        case .shape: .glyphCrop
        case .captions: .glyphText
        case .audio: .glyphMusic
        }
    }

    var title: Text {
        switch self {
        case .clips: Text("Clips", bundle: .module)
        case .shape: Text("Shape", bundle: .module)
        case .captions: Text("Captions", bundle: .module)
        case .audio: Text("Audio", bundle: .module)
        }
    }
}

// MARK: - Clips (F06)

struct ClipsPanel: View {
    let model: MovieEditorModel
    let trim: () -> Void
    let replace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let meta = model.selectedMeta {
                Text(meta)
                    .textStyle(.noteMeta)
                    .foregroundStyle(ColorToken.textSecondary.color)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .accessibilityIdentifier("editor.clipMeta")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(spacing: 8) { actions }
            }
            .padding(.horizontal, 16)
            .padding(.top, 11)
            HStack(spacing: 12) {
                Text("Transition", bundle: .module)
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                Spacer(minLength: 0)
                SegmentedControl(
                    selection: Binding(get: { model.selectedClip?.transition ?? .cut }, set: model.setTransition),
                    options: MovieTransition.allCases, labelSize: 15
                ) { transition in
                    switch transition {
                    case .cut: Text("Cut", bundle: .module)
                    case .fade: Text("Fade", bundle: .module)
                    }
                }
                .frame(width: 200)
                .accessibilityIdentifier("editor.transition")
            }
            .padding(.leading, 18)
            .padding(.trailing, 16)
            .padding(.top, 14)
            Text("Long-press and drag a clip to move it.", bundle: .module)
                .textStyle(TextStyle(.nunito, size: 13, weight: 500, relativeTo: .footnote))
                .foregroundStyle(ColorToken.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.top, 16)
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: trim) { Label { Text("Trim", bundle: .module) } icon: { glyph(.glyphScissors) } }
            .buttonStyle(ThirdButtonStyle())
            .accessibilityIdentifier("editor.trim")
        Button(action: replace) { Label { Text("Replace", bundle: .module) } icon: { glyph(.glyphRefresh) } }
            .buttonStyle(ThirdButtonStyle())
            .accessibilityIdentifier("editor.replace")
        Button(action: model.remove) { Label { Text("Remove", bundle: .module) } icon: { glyph(.glyphTrash) } }
            .buttonStyle(ThirdButtonStyle())
            .disabled(!model.canRemove)
            .accessibilityIdentifier("editor.remove")
    }

    private func glyph(_ icon: Icon) -> some View {
        icon.image.resizable().frame(width: 20, height: 20)
    }
}

/// `Button / Third`: a 20 pt glyph and a word on the hand-cut chip shape, 44 pt tall.
struct ThirdButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ThirdLabelStyle())
            .textStyle(TextStyle(.nunito, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35))
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
    /// "Clip 3 of 24 · Wed, Oct 7 · 2.5 s".
    var selectedMeta: String? {
        guard let clip = selectedClip, let plan = selectedPlan, let moment = clip.moment else { return nil }
        let zone = TimeZone(identifier: moment.timeZoneID) ?? .current
        let day = moment.capturedAt.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).month(.abbreviated).day())
        let length = plan.duration.formatted(.number.precision(.fractionLength(0...1)))
        return String(
            localized: "Clip \(selected + 1) of \(clips.count) · \(day) · \(length) s", bundle: .module,
            comment: "Editor: which clip is chosen, its day, and how many seconds it plays"
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
                .textStyle(TextStyle(.nunito, size: 15, weight: 700, relativeTo: .subheadline))
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

    var body: some View {
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
        .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                detail: Text("\(model.voiceNoteCount) of \(model.clips.count) clips", bundle: .module, comment: "F09: how many clips have a voice note")
            )
            .padding(.top, 10)
            LevelSlider(value: Binding(get: { model.project.voiceNoteLevel }, set: model.setVoiceNoteLevel), changing: changing)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .accessibilityLabel(Text("Voice notes", bundle: .module))
                .accessibilityIdentifier("editor.voiceLevel")
            Button(action: music) {
                HStack(spacing: 4) {
                    Text("Music", bundle: .module)
                        .textStyle(.rowTitle)
                        .foregroundStyle(ColorToken.textPrimary.color)
                    Spacer(minLength: 8)
                    Group {
                        if let track = model.music {
                            Text(track.name ?? String(localized: "On", bundle: .module))
                        } else {
                            Text("None", bundle: .module, comment: "F09: no music chosen")
                        }
                    }
                    .textStyle(TextStyle(.nunito, size: 14, weight: 600, relativeTo: .footnote))
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
            Text("Your own audio file from Files. Fades in and out.", bundle: .module)
                .textStyle(TextStyle(.nunito, size: 13, weight: 500, relativeTo: .footnote))
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
                .textStyle(TextStyle(.nunito, size: 14, weight: 600, relativeTo: .footnote))
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
                    .onEnded { _ in
                        dragging = false
                        changing(false)
                    }
            )
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
