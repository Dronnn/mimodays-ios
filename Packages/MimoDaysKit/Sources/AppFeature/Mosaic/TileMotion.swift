@preconcurrency import AVFoundation
import Combine
import DesignSystem
import Observation
import Persistence
import SwiftData
import SwiftUI

/// The screens whose tiles move (H.9, Andrew 2026-11-16), each switched in Settings › Appearance.
enum MotionScreen: CaseIterable, Sendable {
    case today
    case mosaic
    case memories
    case map
    case search

    var title: Text {
        switch self {
        case .today: Text("Today", bundle: .module)
        case .mosaic: Text("Mosaic", bundle: .module)
        case .memories: Text("Memories", bundle: .module)
        case .map: Text("Map", bundle: .module)
        case .search: Text("Search", bundle: .module)
        }
    }
}

/// How many tiles of a screen play at once (Andrew, 2026-11-18); Automatic goes by the iPhone.
enum TilesAtOnce: String, Codable, CaseIterable, Sendable {
    case automatic
    case four
    case eight
    case twelve
    case all

    /// Automatic's count: twelve with 8 GB of memory or more (iPhone 15 Pro and later), eight with 6 GB, four below.
    static let deviceDefault: Int = {
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / Double(1 << 30)
        return gigabytes >= 7.5 ? 12 : gigabytes >= 5.5 ? 8 : 4
    }()

    /// Tiles playing at once; fewer while the iPhone is hot.
    func count(thermal: ProcessInfo.ThermalState) -> Int {
        let count = switch self {
        case .automatic: Self.deviceDefault
        case .four: 4
        case .eight: 8
        case .twelve: 12
        case .all: Int.max
        }
        switch thermal {
        case .serious: return min(count, 4)
        case .critical: return min(count, 1)
        default: return count
        }
    }

    var title: Text {
        switch self {
        case .automatic:
            Text("Automatic (\(Self.deviceDefault))", bundle: .module, comment: "Settings › Appearance › Motion: how many videos play at once, chosen by the iPhone; the argument is that number")
        case .four: Text(4, format: .number)
        case .eight: Text(8, format: .number)
        case .twelve: Text(12, format: .number)
        case .all: Text("All on screen", bundle: .module, comment: "Settings › Appearance › Motion: every video on screen plays at once")
        }
    }
}

/// Which screens' video tiles play on their own; all on until switched off.
struct MotionSettings: Codable, Equatable, Sendable {
    var today = true
    var mosaic = true
    var memories = true
    var map = true
    var search = true
    var atOnce = TilesAtOnce.automatic

    init() {}

    /// Settings saved by an earlier version lack the newer keys; those keep their defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        today = try container.decodeIfPresent(Bool.self, forKey: .today) ?? today
        mosaic = try container.decodeIfPresent(Bool.self, forKey: .mosaic) ?? mosaic
        memories = try container.decodeIfPresent(Bool.self, forKey: .memories) ?? memories
        map = try container.decodeIfPresent(Bool.self, forKey: .map) ?? map
        search = try container.decodeIfPresent(Bool.self, forKey: .search) ?? search
        // A count this version doesn't know keeps the default, not the rest of the settings.
        atOnce = (try? container.decodeIfPresent(TilesAtOnce.self, forKey: .atOnce)).flatMap { $0 } ?? atOnce
    }

    subscript(screen: MotionScreen) -> Bool {
        get {
            switch screen {
            case .today: today
            case .mosaic: mosaic
            case .memories: memories
            case .map: map
            case .search: search
            }
        }
        set {
            switch screen {
            case .today: today = newValue
            case .mosaic: mosaic = newValue
            case .memories: memories = newValue
            case .map: map = newValue
            case .search: search = newValue
            }
        }
    }
}

/// One screen's moving tiles: whether they play on their own, and which do - the first videos on screen, as many as
/// Settings › Appearance › Motion says.
@MainActor
@Observable
final class TileMotion {
    /// How many play at once.
    var limit = 4
    /// The screen's setting, and neither Reduce Motion nor Low Power Mode, and the screen in front.
    var isOn = false
    private var onScreen: [UUID] = []

    func plays(_ id: UUID) -> Bool {
        isOn && onScreen.prefix(limit).contains(id)
    }

    func setOnScreen(_ id: UUID, _ isOnScreen: Bool) {
        if isOnScreen {
            if !onScreen.contains(id) { onScreen.append(id) }
        } else {
            onScreen.removeAll { $0 == id }
        }
    }
}

extension EnvironmentValues {
    /// Nil where tiles never move (Movies, Settings).
    @Entry var tileMotion: TileMotion?
    /// Where the tile opens: its touch-and-hold menu's Open.
    @Entry var tileOpen: TileOpen?
}

/// How a tile opens its moment: a link's route, or the button's action.
enum TileOpen {
    case route(MemoriesRoute)
    case action(@MainActor () -> Void)
}

/// A tile's link to its moment: a tap opens it, and so does the touch-and-hold menu's Open.
struct MomentTileLink<Label: View>: View {
    let route: MemoriesRoute
    @ViewBuilder let label: () -> Label

    init(_ route: MemoriesRoute, @ViewBuilder label: @escaping () -> Label) {
        self.route = route
        self.label = label
    }

    var body: some View {
        NavigationLink(value: route) { label().environment(\.tileOpen, .route(route)) }
    }
}

extension View {
    /// The screen's tiles move as its Motion setting says; `isActive` false while another side is in front.
    func tileMotionScreen(_ screen: MotionScreen, isActive: Bool = true) -> some View {
        modifier(TileMotionScreen(screen: screen, isActive: isActive))
    }

    /// A tile that plays its video's main stream on its own where the screen's motion is on, and lifted while held.
    /// `still` is the composed picture under it, whose selfie stays as it is.
    /// `plays` false: only the hold, for a tile that plays its video inside itself (Today's hero, under its frame
    /// and caption); `holds` false: only the playing.
    func tileMotion(_ id: UUID, isVideo: Bool, still: UIImage?, plays: Bool = true, holds: Bool = true) -> some View {
        modifier(TileMotionTile(id: id, isVideo: isVideo, still: still, plays: plays, holds: holds))
    }
}

private struct TileMotionScreen: ViewModifier {
    let screen: MotionScreen
    let isActive: Bool
    @State private var motion = TileMotion()
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermal = ProcessInfo.processInfo.thermalState
    @Environment(AppearancePreferences.self) private var preferences: AppearancePreferences?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOn: Bool {
        isActive && (preferences?.value.motion[screen] ?? true) && !reduceMotion && !lowPower
    }

    private var limit: Int {
        (preferences?.value.motion.atOnce ?? .automatic).count(thermal: thermal)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.tileMotion, motion)
            .onChange(of: isOn, initial: true) { motion.isOn = $1 }
            .onChange(of: limit, initial: true) { motion.limit = $1 }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: RunLoop.main)) { _ in
                thermal = ProcessInfo.processInfo.thermalState
            }
    }
}

private struct TileMotionTile: ViewModifier {
    let id: UUID
    let isVideo: Bool
    let still: UIImage?
    let plays: Bool
    let holds: Bool
    @Environment(\.tileMotion) private var motion
    @Environment(\.mediaLibrary) private var library
    @Environment(\.tileOpen) private var open
    @Environment(MoviePreferences.self) private var moviePreferences: MoviePreferences?
    @State private var isOnScreen = false
    @State private var exporting: MomentExportModel?

    func body(content: Content) -> some View {
        if let motion, isVideo, let library {
            let tile = content
                .overlay {
                    if plays, isOnScreen, motion.plays(id) { TileLoop(id: id, still: still, library: library) }
                }
                .onScrollVisibilityChange(threshold: 0.3) { visible in
                    isOnScreen = visible
                    // A tile that only holds (Today's hero, which plays itself) takes no place among the playing
                    // ones, and leaving doesn't stop the same moment's tile elsewhere on the screen.
                    if plays { motion.setOnScreen(id, visible) }
                }
                .onDisappear {
                    isOnScreen = false
                    if plays { motion.setOnScreen(id, false) }
                }
            if !holds || open == nil {
                tile
            } else {
                // Touch and hold lifts the tile and plays it without sound, as iOS previews do, with Open, Share and
                // Favorite under it, whether the screen's motion is on or off (Andrew, 2026-11-16); letting go doesn't
                // open it, a tap still does. Only on tiles that open (not while selecting).
                tile.contextMenu {
                    menu(open, library)
                } preview: {
                    TilePreview(id: id, still: still, library: library)
                }
                .sheet(item: $exporting) { MomentExportSheet(model: $0) }
            }
        } else {
            content
        }
    }
}

extension TileMotionTile {
    /// Open, Share and Favorite under the held tile (Andrew, 2026-11-16), as the Memory Card has them.
    @ViewBuilder
    private func menu(_ open: TileOpen?, _ library: MediaLibrary) -> some View {
        let label = Label { Text("Open", bundle: .module) } icon: { Icon.glyphChevron.image }
        switch open {
        case let .route(route): NavigationLink(value: route) { label }
        case let .action(action): Button(action: action) { label }
        case nil: EmptyView()
        }
        Button {
            exporting = MomentExportModel(ids: [id], library: library, exactPlace: moviePreferences?.value.exactPlaceInFiles ?? false)
        } label: {
            Label { Text("Share", bundle: .module) } icon: { Icon.glyphShare.image }
        }
        let isFavorite = library.moment(id)?.isFavorite == true
        Button { library.toggleFavorite(id) } label: {
            Label { Text("Favorite", bundle: .module) } icon: { (isFavorite ? Icon.glyphHeartFilled : .glyphHeart).image }
        }
    }
}

extension MediaLibrary {
    @MainActor
    func moment(_ id: UUID) -> Moment? {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// As the Memory Card's heart does it.
    @MainActor
    func toggleFavorite(_ id: UUID) {
        guard let moment = moment(id) else { return }
        moment.isFavorite.toggle()
        moment.modifiedAt = Date()
        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }
}

/// The held tile, larger, its video playing: the composed picture until the stream is ready.
private struct TilePreview: View {
    let id: UUID
    let still: UIImage?
    let library: MediaLibrary

    var body: some View {
        let size = still.map { CGSize(width: 300, height: 300 * $0.size.height / max($0.size.width, 1)) } ?? CGSize(width: 300, height: 400)
        ZStack {
            Color(hex: 0xC9B8AA)
            if let still { Image(uiImage: still).filling() }
            TileLoop(id: id, still: still, library: library)
        }
        .frame(width: size.width, height: min(size.height, 520))
        .accessibilityElement()
        .accessibilityIdentifier("tile.preview")
    }
}

/// A video tile going round without sound: the main stream where the tile shows it, the selfie left as the composed
/// picture has it - a still in its window, or its half. Until the stream is ready the picture under it shows.
struct TileLoop: View {
    let id: UUID
    /// The composed picture under the loop: its window is laid over the stream. Nil when the tile draws its selfie
    /// itself (the Mosaic).
    let still: UIImage?
    let library: MediaLibrary
    @State private var video: ViewerMoment.VideoSource?
    @State private var player: ViewerVideoPlayer?

    var body: some View {
        GeometryReader { proxy in
            if let video, let player, player.isReady {
                let bounds = CGRect(origin: .zero, size: proxy.size)
                if let format = video.timing.halves {
                    // The tile fills with the format's frame; the main stream has the first half.
                    let canvas = MomentComposition.fitted(aspect: format.aspectRatio, in: bounds, fit: .fill)
                    let half = HalvesArt.halves(canvas.size).first.offsetBy(dx: canvas.minX, dy: canvas.minY)
                    PlayerLayerView(player: player.main)
                        .frame(width: half.width, height: half.height)
                        .clipped()
                        .position(x: half.midX, y: half.midY)
                } else {
                    let canvas = MomentComposition.fitted(aspect: video.aspectRatio, in: bounds, fit: .fill)
                    ZStack {
                        PlayerLayerView(player: player.main)
                            .frame(width: canvas.width, height: canvas.height)
                            .position(x: canvas.midX, y: canvas.midY)
                        if let still, let window = video.timing.window, video.selfiePath != nil {
                            let rect = PhotoComposer.placement(of: window, in: canvas.size).rect.offsetBy(dx: canvas.minX, dy: canvas.minY)
                            Image(uiImage: still)
                                .filling()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .mask { WindowShape(rect: rect) }
                                .shadow(color: .black.opacity(SelfieWindowStyle.shadowOpacity), radius: 3, y: 1)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard let loaded = await library.loop(id, small: true), !Task.isCancelled else { return }
            let player = ViewerVideoPlayer(duration: loaded.video.timing.duration, silent: true)
            await player.load(main: loaded.main, selfie: nil)
            guard !Task.isCancelled else { return player.stop() }
            video = loaded.video
            self.player = player
            player.play()
        }
        .onDisappear {
            player?.stop()
            player = nil
        }
    }
}

/// Today's hero playing its latest video (Andrew, 2026-11-16): unlike the other tiles, the selfie plays too - in the
/// hero's window, or in its half.
struct HeroVideo: View {
    let player: ViewerVideoPlayer
    let halves: CaptureFormat?

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            if let halves {
                let canvas = MomentComposition.fitted(aspect: halves.aspectRatio, in: bounds, fit: .fill)
                let (first, second) = HalvesArt.halves(canvas.size)
                ZStack(alignment: .topLeading) {
                    half(player.main, first.offsetBy(dx: canvas.minX, dy: canvas.minY))
                    if player.hasSelfie { half(player.selfie, second.offsetBy(dx: canvas.minX, dy: canvas.minY)) }
                }
            } else {
                PlayerLayerView(player: player.main)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func half(_ player: AVPlayer, _ rect: CGRect) -> some View {
        PlayerLayerView(player: player)
            .frame(width: rect.width, height: rect.height)
            .clipped()
            .position(x: rect.midX, y: rect.midY)
    }
}

/// The selfie window's outline where the composed picture has it: rounded and tilted.
private struct WindowShape: View {
    let rect: CGRect

    var body: some View {
        let style = SelfieWindowStyle.self
        RoundedRectangle(cornerRadius: style.cornerRadius * min(rect.width, rect.height) / style.size.width, style: .continuous)
            .frame(width: rect.width, height: rect.height)
            .rotationEffect(style.tilt)
            .position(x: rect.midX, y: rect.midY)
    }
}

extension MediaLibrary {
    /// A video moment's main stream as a silent loop item, and what places it; its selfie stream too where asked
    /// (Today's hero). A tile (`small`) plays the stream's small copy.
    @MainActor
    func loop(_ id: UUID, withSelfie: Bool = false, small: Bool = false) async -> (video: ViewerMoment.VideoSource, main: AVPlayerItem, selfie: AVPlayerItem?)? {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let moment = try? context.fetch(descriptor).first, moment.mediaType == .video,
              let video = ViewerMoment(moment).video, let mainURL = try? store.url(for: video.mainPath) else { return nil }
        if small, let preview = await LoopPreviews.shared.preview(of: video.mainPath, store: store) {
            if let main = try? await Self.picture(of: preview) { return (video, AVPlayerItem(asset: main.stream), nil) }
            // A damaged copy: the original plays, and the next ask makes a new one.
            await LoopPreviews.shared.discard(video.mainPath, store: store)
        }
        do {
            let (main, duration) = try await Self.picture(of: mainURL)
            var selfie: AVPlayerItem?
            if withSelfie, let path = video.selfiePath, let selfieURL = try? store.url(for: path) {
                selfie = AVPlayerItem(asset: try await VideoComposer.selfieStream(selfieURL, offset: video.timing.selfieOffset, mainDuration: duration))
            }
            return (video, AVPlayerItem(asset: main), selfie)
        } catch {
            return nil
        }
    }

    /// A video's picture alone, and its length: the same as a selfie stream with no offset.
    private static func picture(of url: URL) async throws -> (stream: AVComposition, duration: CMTime) {
        let duration = try await AVURLAsset(url: url).load(.duration)
        return (try await VideoComposer.selfieStream(url, offset: 0, mainDuration: duration), duration)
    }
}
