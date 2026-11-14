@preconcurrency import AVFoundation
import Core
import Foundation
import Observation
import os
import Persistence
import SwiftData
import SwiftUI

/// What screens need to read moments and their media; set once at the root.
struct MediaLibrary {
    let context: ModelContext
    let store: MediaStore
    let thumbnails: ThumbnailPipeline
}

extension EnvironmentValues {
    /// Nil only in previews that never open a moment.
    @Entry var mediaLibrary: MediaLibrary?
}

/// The viewer is opened on one moment among others it can swipe to, in the order they were shown.
struct MomentPager: Hashable {
    var ids: [UUID]
    var start: UUID
}

/// One moment as the viewer shows it (M05, M06).
struct ViewerMoment: Equatable, Identifiable {
    struct Voice: Equatable {
        var path: String
        var duration: Double
        var transcript: String?
    }

    struct VideoSource: Equatable {
        var mainPath: String
        var selfiePath: String?
        var timing: VideoTiming
        /// The main stream's upright size in pixels.
        var pixelSize: CGSize
        /// Where the selfie window is, as saved on the moment; nil without a selfie stream.
        var layout: PiPLayout?

        var aspectRatio: CGFloat { pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 9.0 / 16.0 }
    }

    /// A photo's upright size and its selfie window as saved (9.28).
    struct PhotoSource: Equatable {
        var pixelSize: CGSize
        /// Nil without a selfie.
        var layout: PiPLayout?

        var aspectRatio: CGFloat { pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 3.0 / 4.0 }
    }

    var id: UUID
    var captured: CaptureTime
    var origin: MomentOrigin
    var mediaType: MediaType
    var place: String?
    var title: String?
    var note: String?
    var isFavorite: Bool
    var mainPath: String?
    var selfiePath: String?
    /// The single picture made for sharing (photos).
    var composedPath: String?
    var voice: Voice?
    var video: VideoSource?
    var photo: PhotoSource?
    /// The collections it's in, by name (M05 chips).
    var collections: [CollectionLink]

    struct CollectionLink: Equatable, Identifiable {
        var id: UUID
        var title: String
    }

    init(_ moment: Moment) {
        let summary = MomentSummary(moment)
        id = moment.id
        captured = summary.captured
        origin = moment.origin
        mediaType = moment.mediaType
        place = summary.place
        title = moment.title
        note = moment.note.flatMap { $0.isEmpty ? nil : $0 }
        isFavorite = moment.isFavorite
        mainPath = summary.mainPath
        selfiePath = summary.selfiePath
        composedPath = moment.media.first { $0.role == .composedPreview }?.relativePath
        collections = moment.memberships.compactMap { $0.collection.map { CollectionLink(id: $0.id, title: $0.title) } }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        voice = moment.voiceNotes.first.map { Voice(path: $0.relativePath, duration: $0.duration, transcript: $0.transcript) }
        if moment.mediaType == .photo, let main = moment.media.first(where: { $0.relativePath == summary.mainPath }) {
            // Stored as encoded; EXIF orientations 5-8 turn it a quarter.
            let encoded = CGSize(width: main.pixelWidth, height: main.pixelHeight)
            photo = PhotoSource(
                pixelSize: main.orientation >= 5 ? CGSize(width: encoded.height, height: encoded.width) : encoded,
                layout: summary.selfiePath == nil ? nil : moment.pipLayout
            )
        }
        if moment.mediaType == .video, let main = moment.media.first(where: { $0.relativePath == summary.mainPath }) {
            let selfie = moment.media.first { $0.relativePath == summary.selfiePath }
            let pixelSize = CGSize(width: main.pixelWidth, height: main.pixelHeight)
            let layout = selfie == nil ? nil : moment.pipLayout
            video = VideoSource(
                mainPath: main.relativePath, selfiePath: selfie?.relativePath,
                timing: VideoTiming(
                    duration: main.duration ?? 0, selfieOffset: selfie?.startOffset ?? 0, hasAudio: main.hasAudio,
                    mainPosition: main.role == .frontSource ? .front : .back,
                    window: layout?.windowFrame(in: pixelSize)
                ),
                pixelSize: pixelSize, layout: layout
            )
        }
    }
}

/// M05/M06: one moment at a time, swiping to the others it was opened among. Reads the store again when it saves.
@MainActor
@Observable
final class MomentViewerModel {
    /// Shrinks as moments are deleted from here.
    private(set) var ids: [UUID]
    /// The moment on screen.
    var current: UUID?
    private(set) var moments: [UUID: ViewerMoment] = [:]
    private(set) var images: [String: UIImage] = [:]
    private(set) var voiceLevels: [UUID: [Float]] = [:]
    /// The moment whose voice note is playing.
    private(set) var playingVoice: UUID?
    /// How far the playing voice note is, in seconds.
    private(set) var voiceTime: Double = 0
    private var voiceClock: Any?
    let voicePlayer = AVPlayer()

    static let photoPixels = 1600
    static let selfiePixels = 400
    static let voiceBars = 22

    let library: MediaLibrary
    private var voiceEnd: (any NSObjectProtocol)?
    private let logger = Logger(subsystem: "MimoDays", category: "Viewer")

    init(pager: MomentPager, library: MediaLibrary) {
        ids = pager.ids
        current = pager.start
        self.library = library
    }

    var currentMoment: ViewerMoment? { current.flatMap { moments[$0] } }

    func url(_ path: String?) -> URL? {
        path.flatMap { try? library.store.url(for: $0) }
    }

    func image(_ path: String?) -> UIImage? {
        path.flatMap { images[$0] }
    }

    /// The moment, its pictures and its voice note's waveform. Gone moments stay out.
    func load(_ id: UUID) async {
        guard let moment = fetch(id), moment.deletedAt == nil else {
            moments[id] = nil
            return
        }
        let viewed = ViewerMoment(moment)
        moments[id] = viewed
        for (path, size) in [(viewed.mainPath, Self.photoPixels), (viewed.selfiePath, Self.selfiePixels)] {
            guard let path, images[path] == nil, let url = url(path),
                  let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: size) else { continue }
            images[path] = UIImage(cgImage: image)
        }
        if let voice = viewed.voice, voiceLevels[id] == nil, let url = url(voice.path) {
            voiceLevels[id] = VoiceWaveform.read(url, bars: Self.voiceBars)?.levels ?? []
        }
    }

    func reload() async {
        for id in moments.keys { await load(id) }
    }

    func toggleFavorite(_ id: UUID) {
        guard let moment = fetch(id) else { return }
        moment.isFavorite.toggle()
        moment.modifiedAt = Date()
        do {
            try library.context.save()
            moments[id]?.isFavorite = moment.isFavorite
        } catch {
            logger.error("Saving the favourite failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Movie drafts that use the moment (M15's note).
    func movieDrafts(_ id: UUID) -> Int {
        (try? deletionStore.movieDrafts(using: [id])) ?? 0
    }

    /// Moves the moment to Recently deleted and shows the next one, or the one before when it was last.
    func delete(_ id: UUID) {
        stopVoice()
        do {
            try deletionStore.moveToRecentlyDeleted([id])
        } catch {
            logger.error("Deleting the moment failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        removeFromPager(id)
    }

    /// After Edit moment deleted it.
    func removeFromPager(_ id: UUID) {
        guard let index = ids.firstIndex(of: id) else { return }
        ids.remove(at: index)
        moments[id] = nil
        if current == id { current = ids.isEmpty ? nil : ids[min(index, ids.count - 1)] }
    }

    private var deletionStore: DeletionStore { DeletionStore(context: library.context, store: library.store) }

    /// Plays the voice note, or stops it when it's the one playing.
    func toggleVoice(_ id: UUID) {
        if playingVoice == id {
            stopVoice()
            return
        }
        stopVoice()
        guard let url = url(moments[id]?.voice?.path) else { return }
        let item = AVPlayerItem(url: url)
        voicePlayer.replaceCurrentItem(with: item)
        voiceEnd = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopVoice() }
        }
        voiceClock = voicePlayer.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.voiceTime = time.seconds }
        }
        // Heard with the ring/silent switch on silent too: it's something the person asked to play.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        playingVoice = id
        voicePlayer.play()
    }

    func stopVoice() {
        voicePlayer.pause()
        voicePlayer.replaceCurrentItem(with: nil)
        if let voiceClock { voicePlayer.removeTimeObserver(voiceClock) }
        voiceClock = nil
        voiceTime = 0
        if let voiceEnd { NotificationCenter.default.removeObserver(voiceEnd) }
        voiceEnd = nil
        playingVoice = nil
    }

    /// Puts the moment in exactly these collections (the ••• menu's Add to collection).
    func setCollections(_ collections: Set<UUID>, for id: UUID) {
        do {
            try CollectionStore(context: library.context).place(id, in: collections)
            try library.context.save()
        } catch {
            library.context.rollback()
            logger.error("Saving collections failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The video as seen (both streams in one file) in a temporary file, for the share sheet.
    func exportVideo(_ id: UUID) async -> URL? {
        guard let composed = await composedVideo(id),
              let session = AVAssetExportSession(asset: composed.asset, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        session.videoComposition = composed.videoComposition
        let url = FileManager.default.temporaryDirectory.appending(path: "MimoDays-\(id.uuidString.prefix(8)).mp4")
        try? FileManager.default.removeItem(at: url)
        do {
            try await session.export(to: url, as: .mp4)
            return url
        } catch {
            logger.error("Exporting the video failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The player's two streams, kept apart: the main one with its sound, and the selfie one on the main
    /// one's timeline (its start offset applied, silent) for the live window over it.
    func playerItems(_ id: UUID) async -> (main: AVPlayerItem, selfie: AVPlayerItem?)? {
        guard let source = moments[id]?.video, let mainURL = url(source.mainPath) else { return nil }
        let mainAsset = AVURLAsset(url: mainURL)
        var selfie: AVPlayerItem?
        if source.layout != nil, let selfieURL = url(source.selfiePath) {
            do {
                let duration = try await mainAsset.load(.duration)
                let stream = try await VideoComposer.selfieStream(selfieURL, offset: source.timing.selfieOffset, mainDuration: duration)
                selfie = AVPlayerItem(asset: stream)
            } catch {
                logger.error("Reading the selfie stream failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return (AVPlayerItem(asset: mainAsset), selfie)
    }

    /// The player's window moved or changed size: kept on the moment, and used from now on for sharing.
    func setWindow(_ layout: PiPLayout, for id: UUID) {
        guard let moment = fetch(id), let viewed = moments[id],
              let current = viewed.video?.layout ?? viewed.photo?.layout, current != layout else { return }
        var saved = layout
        saved.source = moment.pipLayout?.source ?? layout.source
        moment.pipLayout = saved
        moment.modifiedAt = Date()
        do {
            try library.context.save()
        } catch {
            library.context.rollback()
            logger.error("Saving the selfie window failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if var video = viewed.video {
            video.layout = saved
            video.timing.window = saved.windowFrame(in: video.pixelSize)
            moments[id]?.video = video
        } else {
            moments[id]?.photo?.layout = saved
        }
        guard let changed = moments[id] else { return }
        let previous = thumbnailRefresh
        thumbnailRefresh = Task {
            await previous?.value
            await recompose(changed)
        }
    }

    /// The last rebuild of what grids and sharing show; each waits for the one before, so files are replaced
    /// in order.
    private(set) var thumbnailRefresh: Task<Void, Never>?

    /// Grids and sharing show the window where the viewer put it: a video's thumbnail is composed again; a
    /// photo's shared picture too, and its thumbnail from that. New files replace the old ones.
    private func recompose(_ viewed: ViewerMoment) async {
        do {
            if let video = viewed.video {
                guard let main = url(video.mainPath),
                      let image = await MomentSaver.videoThumbnail(
                          mainURL: main, selfieURL: url(video.selfiePath), selfieOffset: video.timing.selfieOffset, window: video.timing.window
                      ) else { return }
                try replace(.thumbnail, of: viewed.id, with: image)
            } else if let photo = viewed.photo, let layout = photo.layout,
                      let main = url(viewed.mainPath), let selfie = url(viewed.selfiePath) {
                let composed = try await PhotoComposer.compose(mainURL: main, selfieURL: selfie, window: layout.windowFrame(in: photo.pixelSize))
                defer { try? FileManager.default.removeItem(at: composed) }
                moments[viewed.id]?.composedPath = try replace(.composedPreview, of: viewed.id, with: composed)
                guard let image = await ReviewModel.still(composed, maxPixelSize: MomentSaver.thumbnailSize, at: 0)?.cgImage else { return }
                try replace(.thumbnail, of: viewed.id, with: image)
            }
        } catch {
            logger.error("Recomposing after the window moved failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func replace(_ role: MediaRole, of id: UUID, with image: CGImage) throws {
        let temporary = try CaptureFiles.temporaryURL("jpg")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try ThumbnailPipeline.jpegData(image).write(to: temporary)
        try replace(role, of: id, with: temporary)
    }

    /// Stores a copy of `file` as the moment's media of that role, then removes the old file. The new path.
    @discardableResult
    private func replace(_ role: MediaRole, of id: UUID, with file: URL) throws -> String? {
        guard let media = fetch(id)?.media.first(where: { $0.role == role }) else { return nil }
        let stored = try library.store.store(copyOf: file, in: .derived)
        let old = media.relativePath
        media.relativePath = stored.relativePath
        media.checksum = stored.checksum
        media.byteCount = stored.byteCount
        do {
            try library.context.save()
        } catch {
            library.context.rollback()
            try? library.store.remove(stored.relativePath)
            throw error
        }
        try? library.store.remove(old)
        return stored.relativePath
    }

    /// Main and selfie streams as one, the window where the player has it: what sharing exports.
    func composedVideo(_ id: UUID) async -> VideoComposer.Composed? {
        guard let source = moments[id]?.video, let main = url(source.mainPath) else { return nil }
        do {
            return try await VideoComposer.compose(mainURL: main, selfieURL: url(source.selfiePath), timing: source.timing)
        } catch {
            logger.error("Composing the video failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func fetch(_ id: UUID) -> Moment? {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? library.context.fetch(descriptor).first
    }
}
