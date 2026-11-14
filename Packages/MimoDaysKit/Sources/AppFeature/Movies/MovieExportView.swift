import AVFoundation
import Core
import DesignSystem
import Persistence
import Photos
import SwiftData
import SwiftUI

struct MovieExportScreen: View {
    let projectID: UUID
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library, let project = MovieStore.project(projectID, in: library.context) {
            MovieExportHost(model: MovieExportModel(project: project, library: library), tiles: MemoriesModel(
                context: library.context, store: library.store, thumbnails: library.thumbnails
            ))
        }
    }
}

private struct MovieExportHost: View {
    @State var model: MovieExportModel
    @State var tiles: MemoriesModel
    var body: some View { MovieExportView(model: model, tiles: tiles) }
}

/// F11 options, then F12 rendering, F13 ready or F14 failed, all on one pushed screen.
struct MovieExportView: View {
    let model: MovieExportModel
    let tiles: MemoriesModel
    @Environment(AppRouter.self) private var router
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        Group {
            switch model.phase {
            case .options: MovieExportOptions(model: model, cover: cover)
            case let .rendering(progress, remaining): MovieRendering(progress: progress, remaining: remaining, cover: cover, cancel: model.cancel)
            case let .ready(render):
                MovieReady(title: model.project.title, render: render, url: library.flatMap { try? $0.store.url(for: render.relativePath) }, cover: cover) {
                    router.moviesPath = []
                }
            case let .failed(failure):
                MovieExportFailed(model: model, failure: failure) {
                    if !router.moviesPath.isEmpty { router.moviesPath.removeLast() }
                }
            }
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task { if let id = coverID { await tiles.load(id) } }
    }

    private var coverID: UUID? { model.plan.clips.first?.momentID }
    private var cover: UIImage? { coverID.flatMap { tiles.images[$0] } }
}

// MARK: - F11

struct MovieExportOptions: View {
    @Bindable var model: MovieExportModel
    let cover: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BackTitleBar(back: Text("Edit", bundle: .module), title: Text("Export movie", bundle: .module)) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 21) {
                        Poster(image: cover)
                            .frame(width: 60, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ColorToken.mediaFrame.color, lineWidth: 3))
                            .shadow(color: Color(hex: 0x4B2938).opacity(0.15), radius: 4, y: 2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.project.title)
                                .textStyle(TextStyle(.fraunces, size: 24, weight: 600, relativeTo: .title2, maximumScale: 1.35))
                                .foregroundStyle(ColorToken.textPrimary.color)
                            Text(MovieCard.length(model.plan.duration, model.project.aspectRatio, clips: model.plan.clips.count))
                                .textStyle(.noteMeta)
                                .foregroundStyle(ColorToken.textSecondary.color)
                        }
                    }
                    .padding(.leading, 15)
                    .padding(.top, 9)
                    caps(Text("Quality", bundle: .module)).padding(.top, 25)
                    SegmentedControl(selection: $model.resolution, options: MovieResolution.allCases, labelSize: 15) { $0.title }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .accessibilityIdentifier("export.quality")
                    note(sizeNote).padding(.top, 8)
                    caps(Text("Privacy", bundle: .module)).padding(.top, 19)
                    VStack(spacing: 0) {
                        toggle(Text("Date in the file", bundle: .module), isOn: $model.dateInFile, id: "export.date")
                        Color(hex: 0x4B2938).opacity(0.12).frame(height: 1).padding(.leading, 16)
                        toggle(Text("Exact place in the file", bundle: .module), isOn: $model.placeInFile, id: "export.place")
                    }
                    .background(ColorToken.surfaceCard.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    note(Text("Captions you added are part of the picture. File details are hidden unless you turn them on.", bundle: .module))
                        .padding(.top, 12)
                }
                .padding(.bottom, 24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            Button(action: model.start) { Text("Export movie", bundle: .module) }
                .buttonStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .accessibilityIdentifier("export.start")
        }
    }

    /// "About 95 MB. You have 12 GB free."
    private var sizeNote: Text {
        let size = model.estimatedBytes(model.resolution).formatted(.byteCount(style: .file))
        if let free = model.available {
            return Text("About \(size). You have \(free.formatted(.byteCount(style: .file))) free.", bundle: .module)
        }
        return Text("About \(size).", bundle: .module)
    }

    private func caps(_ text: Text) -> some View {
        text.textStyle(.labelCaps).foregroundStyle(ColorToken.textSecondary.color).padding(.horizontal, 22).accessibilityAddTraits(.isHeader)
    }

    private func note(_ text: Text) -> some View {
        text.textStyle(.meta).foregroundStyle(ColorToken.textSecondary.color).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 22)
    }

    private func toggle(_ title: Text, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) { title.textStyle(.rowTitle).foregroundStyle(ColorToken.textPrimary.color) }
            .tint(ColorToken.actionCoral.color)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .accessibilityIdentifier(id)
    }
}

extension MovieResolution {
    var title: Text {
        switch self {
        case .p720: Text(verbatim: "720p")
        case .p1080: Text(verbatim: "1080p")
        case .p2160: Text("4K", bundle: .module, comment: "Movie export quality, 2160p")
        }
    }
}

extension MovieCard {
    /// "1:04 · 9:16 · 24 clips".
    static func length(_ seconds: Double, _ shape: MovieAspectRatio, clips: Int) -> String {
        let length = Duration.seconds(seconds.rounded()).formatted(.time(pattern: .minuteSecond))
        return String(localized: "\(length) · \(shape.label) · \(clips) clips", bundle: .module, comment: "F11: the movie's length, shape and clip count")
    }
}

/// `Navigation / Back bar` with a back word and a centred title.
struct BackTitleBar: View {
    let back: Text
    var title: Text?
    let action: () -> Void

    var body: some View {
        ZStack {
            if let title {
                title
                    .textStyle(.editorTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .lineLimit(1)
                    .padding(.horizontal, 96)
                    .accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 0) {
                Button(action: action) {
                    HStack(spacing: 0) {
                        Icon.glyphBack.image
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .flipsForRightToLeftLayoutDirection(true)
                        back.textStyle(.editorCancel).foregroundStyle(ColorToken.textLink.color)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .frame(minHeight: Size.minimumTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("back")
                Spacer()
            }
        }
        .frame(height: 44)
    }
}

/// The movie's first picture, or its placeholder brown.
struct Poster: View {
    let image: UIImage?

    var body: some View {
        LinearGradient(colors: [Color(hex: 0xA58C7C), Color(hex: 0x7E6659)], startPoint: .top, endPoint: .bottom)
            .overlay { if let image { Image(uiImage: image).filling() } }
    }
}

/// `Movie / Poster` on F12/F13: 160×284, a 5 pt cream frame, tilted.
private struct TiltedPoster: View {
    let image: UIImage?
    let degrees: Double

    var body: some View {
        Poster(image: image)
            .frame(width: 160, height: 284)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ColorToken.mediaFrame.color, lineWidth: 5))
            .shadow(color: Color(hex: 0x4B2938).opacity(0.18), radius: 8, y: 4)
            .rotationEffect(.degrees(degrees))
            .accessibilityHidden(true)
    }
}

// MARK: - F12

struct MovieRendering: View {
    let progress: Double
    let remaining: Double?
    let cover: UIImage?
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    TiltedPoster(image: cover, degrees: -2).padding(.top, 93)
                    Text("Making your movie", bundle: .module)
                        .textStyle(TextStyle(.fraunces, size: 26, weight: 600, relativeTo: .title1, maximumScale: 1.35))
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .multilineTextAlignment(.center)
                        .padding(.top, 37)
                        .accessibilityAddTraits(.isHeader)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: 0xE0D2C6))
                            Capsule().fill(ColorToken.actionCoral.color).frame(width: proxy.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 8)
                    .padding(.horizontal, 40)
                    .padding(.top, 22)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Progress", bundle: .module))
                    .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
                    .accessibilityIdentifier("export.progress")
                    status
                        .textStyle(.noteMeta)
                        .foregroundStyle(ColorToken.textLink.color)
                        .padding(.top, 16)
                    Text("You can leave this screen or lock the phone. We'll let you know when it's ready.", bundle: .module)
                        .textStyle(.sheetBody)
                        .foregroundStyle(ColorToken.textBody.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 48)
                        .padding(.top, 24)
                }
                .frame(maxWidth: .infinity)
            }
            Button(action: cancel) { Text("Cancel", bundle: .module) }
                .buttonStyle(TextButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .accessibilityIdentifier("export.cancel")
        }
    }

    /// "42% · about 20 seconds left".
    private var status: Text {
        let percent = progress.formatted(.percent.precision(.fractionLength(0)))
        guard let remaining else { return Text(percent) }
        let left = Duration.seconds(max(remaining.rounded(), 1)).formatted(.units(allowed: [.minutes, .seconds], width: .wide, maximumUnitCount: 1))
        return Text("\(percent) · about \(left) left", bundle: .module, comment: "F12: progress and time left, as 42% · about 20 seconds left")
    }
}

// MARK: - F13

struct MovieReady: View {
    let title: String
    let render: MovieRender
    let url: URL?
    let cover: UIImage?
    let done: () -> Void
    @State private var watching = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Button { watching = true } label: {
                        TiltedPoster(image: cover, degrees: 2)
                            .overlay { PlayDisc() }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Play the movie", bundle: .module))
                    .accessibilityIdentifier("ready.play")
                    .overlay(alignment: .topTrailing) {
                        Icon.markStarSmall.image.resizable().frame(width: 17.2, height: 17.5)
                            .foregroundStyle(ColorToken.accentCoralMark.color).offset(x: 41, y: -5).accessibilityHidden(true)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Icon.markStarSolo.image.resizable().frame(width: 39.2, height: 40.4)
                            .foregroundStyle(ColorToken.accentApricot.color).offset(x: -32, y: -10).accessibilityHidden(true)
                    }
                    .padding(.top, 43)
                    Text("Your movie is ready", bundle: .module)
                        .textStyle(TextStyle(.fraunces, size: 28, weight: 600, relativeTo: .title1, maximumScale: 1.35))
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .multilineTextAlignment(.center)
                        .padding(.top, 36)
                        .accessibilityAddTraits(.isHeader)
                    Text(meta)
                        .textStyle(.noteMeta)
                        .foregroundStyle(ColorToken.textSecondary.color)
                        .padding(.top, 8)
                        .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            MovieFileButtons(url: url, primary: .photos)
                .padding(.horizontal, 20)
            Button(action: done) { Text("Done", bundle: .module) }
                .buttonStyle(TextButtonStyle())
                .padding(.top, 18)
                .padding(.bottom, 36)
                .accessibilityIdentifier("ready.done")
        }
        .background(alignment: .top) {
            // `Hero / Bg`: the sage card runs off the top of the screen, 460×580 from 60 pt above it.
            DayCardBlob()
                .fill(Color(hex: 0xD8DBC1))
                .frame(width: 460, height: 580)
                .offset(y: -60)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .fullScreenCover(isPresented: $watching) {
            if let url { RenderedMoviePlayer(url: url) }
        }
    }

    /// "October 2026 · 1:04 · 95 MB".
    private var meta: String {
        let length = Duration.seconds(render.duration.rounded()).formatted(.time(pattern: .minuteSecond))
        return "\(title) · \(length) · \(render.byteCount.formatted(.byteCount(style: .file)))"
    }
}

/// `Media / Play button`: a 64 pt cream disc with the plum play glyph.
struct PlayDisc: View {
    var body: some View {
        Icon.glyphPlay.image
            .resizable()
            .frame(width: 30, height: 30)
            .foregroundStyle(ColorToken.textPrimary.color)
            .offset(x: 2)
            .frame(width: 64, height: 64)
            .background(Circle().fill(ColorToken.mediaFrame.color.opacity(0.9)))
            .shadow(color: Color(hex: 0x4B2938).opacity(0.15), radius: 6, y: 3)
            .accessibilityHidden(true)
    }
}

/// Save to Photos, Share, Save to Files for a rendered file (F13; F15 shows the first two side by side).
struct MovieFileButtons: View {
    enum Primary { case photos }
    let url: URL?
    let primary: Primary
    @State private var saved = false
    @State private var problem: Text?
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 12) {
            Button { Task { await saveToPhotos() } } label: {
                HStack(spacing: 8) {
                    (saved ? Icon.glyphCheck : Icon.glyphDownload).image.resizable().frame(width: 20, height: 20)
                    saved ? Text("Saved to Photos", bundle: .module) : Text("Save to Photos", bundle: .module)
                }
            }
            .buttonStyle(.primary)
            .disabled(url == nil || saved)
            .accessibilityIdentifier("ready.photos")
            if let url {
                ShareLink(item: url) {
                    Label { Text("Share", bundle: .module) } icon: { Icon.glyphShare.image.resizable().frame(width: 20, height: 20) }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("ready.share")
            }
            Button { exporting = true } label: {
                Label { Text("Save to Files", bundle: .module) } icon: { Icon.glyphFolder.image.resizable().frame(width: 20, height: 20) }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(url == nil)
            .accessibilityIdentifier("ready.files")
        }
        .sheet(isPresented: $exporting) {
            if let url { FileExportSheet(url: url).ignoresSafeArea() }
        }
        .alert(Text("Couldn't save to Photos", bundle: .module), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button { problem = nil } label: { Text("OK", bundle: .module) }
        } message: {
            problem
        }
    }

    private func saveToPhotos() async {
        guard let url else { return }
        do {
            try await MovieFiles.saveToPhotos(url)
            saved = true
        } catch MovieFiles.Failure.notAllowed {
            problem = Text("Allow MimoDays to add to your photos in Settings.", bundle: .module)
        } catch {
            problem = Text("Something went wrong. Try again.", bundle: .module)
        }
    }
}

enum MovieFiles {
    enum Failure: Error { case notAllowed }

    static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.notAllowed }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }
}

/// `Button / Secondary`: a 20 pt glyph and Nunito words on the hand-cut chip shape, 48 pt tall.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(SecondaryLabelStyle())
            .textStyle(TextStyle(.nunito, size: 15, weight: 700, relativeTo: .subheadline, maximumScale: 1.35))
            .foregroundStyle(ColorToken.textPrimary.color)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background { ColorToken.surfaceChip.color.mask { Icon.shapeButton.image.resizable() } }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

private struct SecondaryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}

/// Files' own picker, saving a copy of the movie where the person chooses.
struct FileExportSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}
}

/// A rendered movie, played on F10's frame with only ×.
struct RenderedMoviePlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let player {
                MovieWatchView(player: player, close: { dismiss() }) { EmptyView() }
            } else {
                Color(hex: 0x2A1B21).ignoresSafeArea()
            }
        }
        .onAppear {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}

// MARK: - F14

struct MovieExportFailed: View {
    let model: MovieExportModel
    let failure: MovieExportModel.Failure
    let backToEditor: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ExplainerArt(glyph: .explainerWarning, ink: .textLink).padding(.top, 116)
                    Text("The movie couldn't be finished", bundle: .module)
                        .textStyle(TextStyle(.fraunces, size: 26, weight: 600, relativeTo: .title1, maximumScale: 1.35))
                        .foregroundStyle(ColorToken.textPrimary.color)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 260)
                        .padding(.top, 16)
                        .accessibilityAddTraits(.isHeader)
                    body(for: failure)
                        .textStyle(.sheetBody)
                        .foregroundStyle(ColorToken.textBody.color)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 40)
                        .padding(.top, 14)
                }
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 12) {
                switch failure {
                case .space:
                    if model.resolution != .p720 {
                        Button(action: model.retryAt720) {
                            Text("Make it in 720p (about \(model.estimatedBytes(.p720).formatted(.byteCount(style: .file))))", bundle: .module)
                        }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("failed.smaller")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: { Text("Free up space", bundle: .module) }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("failed.space")
                case .other:
                    Button(action: model.start) { Text("Try again", bundle: .module) }
                        .buttonStyle(.primary)
                        .accessibilityIdentifier("failed.retry")
                }
            }
            .padding(.horizontal, 20)
            Button(action: backToEditor) { Text("Back to the editor", bundle: .module) }
                .buttonStyle(TextButtonStyle())
                .padding(.top, 14)
                .padding(.bottom, 32)
                .accessibilityIdentifier("failed.back")
        }
    }

    private func body(for failure: MovieExportModel.Failure) -> Text {
        switch failure {
        case let .space(needed):
            Text("There isn't enough free space on this iPhone.\nIt needs about \(needed.formatted(.byteCount(style: .file))) more.\nYour draft is safe.", bundle: .module)
        case .other:
            Text("Something went wrong while making it.\nYour draft is safe.", bundle: .module)
        }
    }
}
