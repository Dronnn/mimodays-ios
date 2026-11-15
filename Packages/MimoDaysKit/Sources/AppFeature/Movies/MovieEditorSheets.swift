@preconcurrency import AVFoundation
import Core
import DesignSystem
import Persistence
import SwiftUI

/// `Navigation / Editor bar` on the editor's sheets: Cancel, the title, Done.
struct SheetBar: View {
    let title: Text
    var done: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            title
                .textStyle(.editorTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel", bundle: .module)
                        .textStyle(.editorCancel)
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .padding(.horizontal, 16)
                        .frame(minHeight: Size.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sheet.cancel")
                Spacer()
                if let done {
                    Button {
                        done()
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                            .textStyle(.editorDone)
                            .foregroundStyle(ColorToken.textLink.color)
                            .padding(.horizontal, 16)
                            .frame(minHeight: Size.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sheet.done")
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Trim

/// Trim: a video's part between two handles over its frames; a photo's time on screen.
struct TrimSheet: View {
    let model: MovieEditorModel
    @State private var start = 0.0
    @State private var end = MovieSelection.photoSeconds
    @State private var length: Double?
    @State private var frames: [UIImage] = []

    /// A clip can't be trimmed shorter than this.
    static let shortest = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetBar(title: Text("Trim", bundle: .module), done: { model.trim(start: start, end: end) })
            switch model.selectedPlan?.media {
            case .photo: photo
            case .video: video
            case .card, nil: EmptyView()
            }
            Spacer(minLength: 0)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .presentationDetents([.height(260)])
        .task { await load() }
    }

    private var photo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shows for \(end - start, format: .number.precision(.fractionLength(1))) s", bundle: .module)
                .textStyle(.rowTitle)
                .foregroundStyle(ColorToken.textPrimary.color)
            LevelSlider(
                value: Binding(
                    get: { (end - MoviePlan.shortestPhoto) / (MoviePlan.longestPhoto - MoviePlan.shortestPhoto) },
                    set: { end = ((MoviePlan.shortestPhoto + $0 * (MoviePlan.longestPhoto - MoviePlan.shortestPhoto)) * 2).rounded() / 2 }
                ),
                changing: { _ in }
            )
            .accessibilityLabel(Text("Seconds on screen", bundle: .module))
            .accessibilityIdentifier("trim.photo")
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
    }

    @ViewBuilder
    private var video: some View {
        if let length {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(MovieEditorView.clock(start)) – \(MovieEditorView.clock(end)) · \(end - start, format: .number.precision(.fractionLength(1))) s", bundle: .module)
                    .textStyle(.rowTitle)
                    .monospacedDigit()
                    .foregroundStyle(ColorToken.textPrimary.color)
                TrimRange(start: $start, end: $end, length: length, shortest: Self.shortest, frames: frames)
                    .frame(height: 64)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
        }
    }

    private func load() async {
        guard let plan = model.selectedPlan else { return }
        switch plan.media {
        case .photo:
            end = plan.duration
        case .card:
            return
        case let .video(clipStart, _, _):
            guard let url = plan.mainURL else { return }
            start = clipStart
            end = clipStart + plan.duration
            let asset = AVURLAsset(url: url)
            let total = (try? await asset.load(.duration).seconds) ?? end
            length = max(total, end)
            frames = await Self.frames(of: asset, length: length ?? end)
        }
    }

    /// Eight frames across the video for the strip under the handles.
    private static func frames(of asset: AVURLAsset, length: Double) async -> [UIImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        var images: [UIImage] = []
        for index in 0..<8 {
            let time = CMTime(seconds: length * (Double(index) + 0.5) / 8, preferredTimescale: 600)
            if let image = try? await generator.image(at: time).image { images.append(UIImage(cgImage: image)) }
        }
        return images
    }
}

/// The video's frames with an apricot handle at each end of the part that plays; the rest dimmed.
private struct TrimRange: View {
    @Binding var start: Double
    @Binding var end: Double
    let length: Double
    let shortest: Double
    let frames: [UIImage]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x0 = width * start / length
            let x1 = width * end / length
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(frames.enumerated()), id: \.offset) { _, frame in
                        Image(uiImage: frame).filling().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    }
                }
                .background(Color(hex: 0xC9B8AA))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                ColorToken.mediaScrim.color.frame(width: x0)
                ColorToken.mediaScrim.color.frame(width: max(width - x1, 0)).offset(x: x1)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(ColorToken.actionCoral.color, lineWidth: 3)
                    .frame(width: max(x1 - x0, 0))
                    .offset(x: x0)
                handle.offset(x: x0 - 10)
                    .gesture(DragGesture().onChanged { start = min(max($0.location.x / width * length, 0), end - shortest) })
                    .accessibilityElement()
                    .accessibilityLabel(Text("Start", bundle: .module))
                    .accessibilityValue(Text(MovieEditorView.clock(start)))
                    .accessibilityAdjustableAction { start = min(max(start + ($0 == .increment ? 0.5 : -0.5), 0), end - shortest) }
                    .accessibilityIdentifier("trim.start")
                handle.offset(x: x1)
                    .gesture(DragGesture().onChanged { end = max(min($0.location.x / width * length, length), start + shortest) })
                    .accessibilityElement()
                    .accessibilityLabel(Text("End", bundle: .module))
                    .accessibilityValue(Text(MovieEditorView.clock(end)))
                    .accessibilityAdjustableAction { end = max(min(end + ($0 == .increment ? 0.5 : -0.5), length), start + shortest) }
                    .accessibilityIdentifier("trim.end")
            }
        }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(hex: 0xF2A93B))
            .frame(width: 10)
            .overlay { Capsule().fill(ColorToken.surfaceCard.color).frame(width: 2, height: 22) }
            .frame(width: 10)
            .contentShape(Rectangle().inset(by: -12))
    }
}

// MARK: - Replace

/// Replace: the source's other moments; the one tapped takes the chosen clip's place.
struct ReplaceSheet: View {
    let model: MovieEditorModel
    @State private var items: [MemoryItem] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(title: Text("Replace with", bundle: .module))
            ScrollView {
                if items.isEmpty {
                    Text("Every moment is already in the movie.", bundle: .module)
                        .textStyle(.emptyBody)
                        .foregroundStyle(ColorToken.textBody.color)
                        .multilineTextAlignment(.center)
                        .padding(.top, 60)
                        .padding(.horizontal, 32)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                        ForEach(items) { item in
                            Button {
                                model.replace(with: item.id)
                                dismiss()
                            } label: {
                                MemoryTile(item: item, detail: model.tiles.details[item.id], image: model.tiles.images[item.id], videoBadgeAtTop: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("replace.moment")
                            .task { await model.tiles.load(item.id) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .task { items = model.replacements() }
    }
}

// MARK: - Title

/// Title at the start (F08): the movie's name, and whether it shows over the first seconds.
struct TitleSheet: View {
    let model: MovieEditorModel
    @State private var text: String
    @State private var shows: Bool
    @FocusState private var focused: Bool

    init(model: MovieEditorModel) {
        self.model = model
        _text = State(initialValue: model.project.title)
        _shows = State(initialValue: model.project.showsTitle)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(title: Text("Title", bundle: .module), done: { model.setTitle(text, shows: shows) })
            VStack(spacing: 0) {
                TextField(text: $text) { Text("Movie title", bundle: .module) }
                    .textStyle(.rowTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .tint(ColorToken.actionCoral.color)
                    .focused($focused)
                    .submitLabel(.done)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .accessibilityIdentifier("title.text")
                Color(hex: 0x4B2938).opacity(0.12).frame(height: 1).padding(.leading, 16)
                Toggle(isOn: $shows) {
                    Text("Show it at the start", bundle: .module).textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color)
                }
                .tint(ColorToken.actionCoral.color)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .accessibilityIdentifier("title.shows")
            }
            .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 20)
            Spacer(minLength: 0)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}
