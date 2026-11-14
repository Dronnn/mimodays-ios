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
        if moment.mediaType == .video, let main = moment.media.first(where: { $0.relativePath == summary.mainPath }) {
            let selfie = moment.media.first { $0.relativePath == summary.selfiePath }
            video = VideoSource(
                mainPath: main.relativePath, selfiePath: selfie?.relativePath,
                timing: VideoTiming(
                    duration: main.duration ?? 0, selfieOffset: selfie?.startOffset ?? 0, hasAudio: main.hasAudio,
                    mainPosition: main.role == .frontSource ? .front : .back,
                    window: selfie == nil ? nil : moment.pipLayout?.windowFrame(in: CGSize(width: main.pixelWidth, height: main.pixelHeight))
                )
            )
        }
    }
}

/// M05/M06: one moment at a time, swiping to the others it was opened among. Reads the store again when it saves.
@MainActor
@Observable
final class MomentViewerModel {
    let ids: [UUID]
    /// The moment on screen.
    var current: UUID?
    private(set) var moments: [UUID: ViewerMoment] = [:]
    private(set) var images: [String: UIImage] = [:]
    private(set) var voiceLevels: [UUID: [Float]] = [:]
    /// The moment whose voice note is playing.
    private(set) var playingVoice: UUID?
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
        playingVoice = id
        voicePlayer.play()
    }

    func stopVoice() {
        voicePlayer.pause()
        voicePlayer.replaceCurrentItem(with: nil)
        if let voiceEnd { NotificationCenter.default.removeObserver(voiceEnd) }
        voiceEnd = nil
        playingVoice = nil
    }

    /// Main and selfie streams as one, the window where it was (M06).
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
