import AVFoundation
import Core
import DesignSystem
import OSLog
import Persistence
import SwiftData
import SwiftUI

/// P8.8 GG04: the moment taken then and one taken again, read from the archive.
@MainActor
@Observable
final class ThenNowModel {
    private(set) var then: MomentSummary?
    private(set) var thenID: UUID?
    /// Newest first.
    private(set) var repeats: [MomentSummary] = []
    var selected: UUID?
    private(set) var isLoaded = false
    private(set) var images: [String: UIImage] = [:]
    /// Pictures that wouldn't read: "Preview unavailable".
    private(set) var failed: Set<String> = []

    private let library: MediaLibrary
    private let momentID: UUID
    private let logger = Logger(subsystem: "MimoDays", category: "ThenNow")

    init(library: MediaLibrary, momentID: UUID) {
        self.library = library
        self.momentID = momentID
    }

    var now: MomentSummary? { repeats.first { $0.id == selected } ?? repeats.first }

    func refresh() async {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == momentID })
        descriptor.fetchLimit = 1
        guard let moment = try? library.context.fetch(descriptor).first,
              let comparison = ThenNow.comparison(for: moment, in: library.context) else {
            then = nil
            repeats = []
            isLoaded = true
            return
        }
        then = comparison.then.map(MomentSummary.init)
        thenID = comparison.thenID
        repeats = comparison.repeats.map(MomentSummary.init)
        if selected == nil || !repeats.contains(where: { $0.id == selected }) { selected = comparison.selected }
        isLoaded = true
        for summary in [then].compactMap(\.self) + repeats {
            await load(summary.picturePath, DayModel.photoPixels)
            await load(summary.windowPath, DayModel.selfiePixels)
        }
    }

    func videoURL(_ summary: MomentSummary) -> URL? {
        guard summary.mediaType == .video, let path = summary.mainPath else { return nil }
        return try? library.store.url(for: path)
    }

    private func load(_ path: String?, _ size: Int) async {
        guard let path, images[path] == nil, !failed.contains(path) else { return }
        do {
            let url = try library.store.url(for: path)
            images[path] = UIImage(cgImage: try await library.thumbnails.thumbnail(for: url, maxPixelSize: size))
        } catch {
            failed.insert(path)
            logger.error("Reading a Then & Now picture failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct ThenNowScreen: View {
    let momentID: UUID
    @Environment(\.mediaLibrary) private var library

    var body: some View {
        if let library {
            ModelHost({ ThenNowModel(library: library, momentID: momentID) }) { ThenNowView(model: $0) }
        }
    }
}

/// GG04: "Then & Now", the repeat shown with "Choose a repeat" when there are several, and the two cards: stacked on
/// a phone and at large type, side by side when there's room.
struct ThenNowView: View {
    @Bindable var model: ThenNowModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Then & Now", bundle: .module)
                    .textStyle(.screenTitle)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                if model.repeats.count > 1 { chooser.padding(.top, 8) }
                let layout = sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 20)) : AnyLayout(VStackLayout(spacing: 26))
                layout {
                    ThenNowCard(model: model, label: Text("Then & Now card Then", bundle: .module), summary: model.then)
                    ThenNowCard(model: model, label: Text("Then & Now card Now", bundle: .module), summary: model.now)
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .frame(maxWidth: sizeClass == .regular ? 900 : 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(ColorToken.canvas.color.ignoresSafeArea())
        .navigationTitle(Text("Then & Now", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(removing: .title)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in Task { await model.refresh() } }
    }

    /// The repeat's date, a menu of every repeat's date.
    private var chooser: some View {
        HStack(spacing: 10) {
            Menu {
                Picker(selection: $model.selected) {
                    ForEach(model.repeats) { summary in
                        ThenNow.dateText(summary.captured).tag(Optional(summary.id))
                    }
                } label: { EmptyView() }
            } label: {
                HStack(spacing: 6) {
                    Icon.glyphClock.image.resizable().frame(width: 16, height: 16).accessibilityHidden(true)
                    if let now = model.now { ThenNow.dateText(now.captured) }
                    Icon.glyphChevron.image.resizable().frame(width: 8, height: 8).rotationEffect(.degrees(90))
                        .accessibilityHidden(true)
                }
                .textStyle(.noteMeta)
                .foregroundStyle(ColorToken.textPrimary.color)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(ReviewChipBlob().fill(ColorToken.surfaceChip.color))
            }
            .accessibilityLabel(Text("Choose a repeat", bundle: .module))
            .accessibilityIdentifier("thenNow.choose")
            Text("Choose a repeat", bundle: .module)
                .textStyle(.noteMeta)
                .foregroundStyle(ColorToken.textSecondary.color)
                .accessibilityHidden(true)
        }
    }
}

/// One side: the picture with its place and time, "Then"/"Now" and its date, "Open moment"; play/stop on a video.
private struct ThenNowCard: View {
    let model: ThenNowModel
    let label: Text
    let summary: MomentSummary?
    @State private var player: AVPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            picture
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(MemoryCardOutline())
                .overlay { MemoryCardOutline().strokeBorder(ColorToken.mediaFrame.color, lineWidth: 6).allowsHitTesting(false) }
                .environment(\.layoutDirection, .leftToRight)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                label
                    .textStyle(.dayCaption)
                    .foregroundStyle(ColorToken.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                if let summary {
                    ThenNow.dateText(summary.captured)
                        .textStyle(.noteMeta)
                        .foregroundStyle(ColorToken.textSecondary.color)
                }
                Spacer(minLength: 8)
                if let summary {
                    NavigationLink(value: MemoriesRoute.moment(MomentPager(ids: [summary.id], start: summary.id))) {
                        Text("Open moment", bundle: .module)
                            .textStyle(.noteMeta)
                            .foregroundStyle(ColorToken.textPrimary.color)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(ReviewChipBlob().fill(ColorToken.surfaceChip.color))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("thenNow.open")
                }
            }
            .padding(.horizontal, 4)
        }
        .onChange(of: summary?.id) { stop() }
        .onDisappear { stop() }
    }

    @ViewBuilder
    private var picture: some View {
        ColorToken.surfaceChip.color
            .overlay {
                if let summary {
                    if summary.mediaType == .text {
                        PaperTileFace(excerpt: summary.excerpt, glyphSize: 20, isLarge: true)
                    } else if let image = summary.picturePath.flatMap({ model.images[$0] }) {
                        Image(uiImage: image).filling()
                    } else if let path = summary.picturePath, model.failed.contains(path) {
                        notice(Text("Preview unavailable", bundle: .module))
                    }
                    if let player { PlayerLayerView(player: player) }
                } else if model.isLoaded {
                    notice(Text("This moment is unavailable", bundle: .module))
                }
            }
            .overlay(alignment: .topTrailing) {
                if let path = summary?.windowPath {
                    SelfieWindow(media: model.images[path].map { .image(Image(uiImage: $0)) } ?? .placeholder)
                        .frame(width: 64, height: SelfieWindowStyle.height(forWidth: 64))
                        .padding(14)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let summary, summary.mediaType != .text {
                    VStack(alignment: .leading, spacing: 2) {
                        if let place = summary.place {
                            HStack(spacing: 4) {
                                Icon.glyphPinSolid.image.resizable().frame(width: 11, height: 14)
                                Text(place).textStyle(.hand)
                            }
                        }
                        Text(summary.captured.instant, format: Self.format(summary.captured))
                            .textStyle(.heroTime)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .padding(18)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let summary, let url = model.videoURL(summary) {
                    Button { player == nil ? play(url) : stop() } label: {
                        (player == nil ? Icon.glyphPlay : .glyphPause).image
                            .resizable()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(ColorToken.actionCoral.color))
                    }
                    .accessibilityLabel(player == nil ? Text("Play", bundle: .module) : Text("Stop", bundle: .module))
                    .accessibilityIdentifier("thenNow.play")
                    .padding(14)
                }
            }
            .accessibilityElement(children: .contain)
    }

    private func notice(_ text: Text) -> some View {
        text
            .textStyle(.noteMeta)
            .foregroundStyle(ColorToken.textSecondary.color)
            .multilineTextAlignment(.center)
            .padding(20)
    }

    private func play(_ url: URL) {
        let player = AVPlayer(url: url)
        self.player = player
        player.play()
    }

    private func stop() {
        player?.pause()
        player = nil
    }

    private static func format(_ time: CaptureTime) -> Date.FormatStyle {
        var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        format.timeZone = time.timeZone
        return format
    }
}
