@preconcurrency import AVFoundation
import Core
import Foundation
import ImageIO
import os
import Persistence
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What review hands to the saver.
struct MomentDraft {
    var capture: CaptureResult
    /// One line; empty means no caption.
    var caption: String
    /// C08; empty means no note.
    var note = ""
    /// Where the selfie window sits in the shown media; nil without a selfie.
    var window: SelfieWindowFrame?
    /// The surprise this answers, if it was opened in time.
    var promptID: UUID?
    /// C10; kept as its own file, never mixed into the clip's sound.
    var voice: ReviewVoiceNote?
    /// C11; nil means no place.
    var place: ReviewPlace?
    /// E05 marks what came from Photos; nil means a surprise or a manual capture, by `promptID`.
    var origin: MomentOrigin?
    /// P8.8: the moment this captures again; linked on save if it's still there.
    var repeatOf: UUID?
    /// P8.4, P8.10.
    var tags: [String] = []
    var mood: Mood?
    /// The id to save under; a moment already saved with it is the same save again (rev-capture 19).
    var momentID: UUID?
}

enum SaveError: Error, Equatable {
    /// C13c: free up about `shortfall` bytes and try again. The capture is kept.
    case lowStorage(shortfall: Int64)
    case failed
}

/// Keeps a moment (doc 01: atomic save): the sources and derived files land in the media store, then the record
/// is saved in one transaction. If anything fails, every file written so far is removed and nothing is recorded;
/// the capture's temporary files stay, so review can try again. They are removed only after a successful save.
/// Saved: the main stream, the selfie stream (with its start offset), the composed photo (photos only; videos are
/// composed on playback from the streams and timing) and a composed thumbnail (Andrew, 2026-11-13).
@MainActor
struct MomentSaver {
    let context: ModelContext
    let store: MediaStore
    var clock: any DateProvider = SystemDateProvider()
    /// Free bytes on the volume; nil when unknown (then the save just tries).
    var freeBytes: @Sendable () -> Int64? = { CaptureStorage.freeBytes() }
    /// Left free after a save, for the system.
    static let reserve: Int64 = 50_000_000
    static let thumbnailSize = 600

    func save(_ draft: MomentDraft) async throws -> Moment {
        let capture = draft.capture
        // Saved already, and iOS ended the app before the draft went: nothing is copied twice.
        if let id = draft.momentID, let saved = try? context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })).first {
            capture.discardFiles()
            return saved
        }
        try checkSpace(for: [capture.mainURL, capture.selfieURL, capture.motionURL, draft.voice?.url].compactMap(\.self))
        var written: [String] = []
        var composedPhoto: URL?
        do {
            let isPhoto = if case .photo = capture.media { true } else { false }
            let window = capture.selfieURL == nil ? nil : draft.window
            let halves = capture.isHalves ? capture.format : nil
            if isPhoto, let selfieURL = capture.selfieURL {
                if let halves {
                    composedPhoto = try? await PhotoComposer.compose(mainURL: capture.mainURL, selfieURL: selfieURL, halves: halves)
                } else if let window {
                    composedPhoto = try? await PhotoComposer.compose(mainURL: capture.mainURL, selfieURL: selfieURL, window: window, format: capture.format)
                }
            }
            let mainRole = role(capture.mainPosition)
            var media = [try await stored(capture.mainURL, role: mainRole, isVideo: !isPhoto, written: &written)]
            if let selfieURL = capture.selfieURL {
                let selfie = try await stored(selfieURL, role: role(capture.mainPosition.other), isVideo: !isPhoto, written: &written)
                if case let .video(video) = capture.media { selfie.startOffset = video.selfieOffset }
                media.append(selfie)
            }
            // A Live Photo's motion must play, or the save fails: it is never dropped quietly.
            if let motionURL = capture.motionURL {
                media.append(try await stored(motionURL, role: .livePhotoMotion, isVideo: true, written: &written))
            }
            if let composedPhoto {
                media.append(try await stored(composedPhoto, role: .composedPreview, isVideo: false, area: .derived, written: &written))
            }
            if let thumbnail = try? await thumbnail(capture, composedPhoto: composedPhoto, window: window, halves: halves) {
                media.append(try await stored(thumbnail, role: .thumbnail, isVideo: false, area: .derived, written: &written))
                try? FileManager.default.removeItem(at: thumbnail)
            }

            let moment = Moment(
                id: draft.momentID ?? UUID(), captured: capture.capturedAt,
                origin: draft.origin ?? (draft.promptID == nil ? .manual : .randomPrompt),
                mediaType: isPhoto ? .photo : .video, promptID: draft.promptID, createdAt: clock.now()
            )
            let caption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            moment.title = caption.isEmpty ? nil : caption
            let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
            moment.note = note.isEmpty ? nil : note
            var layout = window.map { PiPLayout($0, source: role(capture.mainPosition.other)) }
            if halves != nil {
                // Halves still keeps a window, where the card's switch puts it back.
                layout = layout ?? PiPLayout(
                    centerX: 0.7, centerY: 0.2, scale: MomentComposition.defaultWindowScale, source: role(capture.mainPosition.other)
                )
                layout?.arrangement = .halves
            }
            moment.pipLayout = layout
            moment.captureFormat = capture.format
            moment.repeatOfMomentID = ThenNow.source(for: draft.repeatOf, in: context)
            moment.tags = draft.tags
            moment.mood = draft.mood
            let voiceNote = try draft.voice.map { voice in
                let file = try store.store(copyOf: voice.url, in: .originals)
                written.append(file.relativePath)
                let transcript = voice.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
                return MomentVoiceNote(
                    relativePath: file.relativePath, duration: voice.duration, recordedAt: voice.recordedAt,
                    transcript: transcript?.isEmpty == false ? transcript : nil
                )
            }
            context.insert(moment)
            moment.media = media
            moment.fitImportedFormat()
            if let voiceNote { moment.voiceNotes = [voiceNote] }
            if let place = draft.place {
                moment.location = MomentLocation(
                    latitude: place.latitude, longitude: place.longitude, precision: place.precision, source: place.source,
                    placeLabel: place.label
                )
            }
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
            capture.discardFiles()
            if let composedPhoto { try? FileManager.default.removeItem(at: composedPhoto) }
            return moment
        } catch {
            Logger(subsystem: "MimoDays", category: "Save").error("Saving a moment failed: \(String(describing: error), privacy: .public)")
            written.forEach { try? store.remove($0) }
            if let composedPhoto { try? FileManager.default.removeItem(at: composedPhoto) }
            throw error as? SaveError ?? .failed
        }
    }

    /// P8.6 "Keep motion": a Live Photo's motion joins the moment that already has its still. Nothing changes if it
    /// doesn't play or can't be kept; the picked file stays for the caller to remove.
    func attachMotion(_ url: URL, to moment: Moment) async throws {
        guard moment.livePhotoMotion == nil else { return }
        try checkSpace(for: [url])
        var written: [String] = []
        do {
            let media = try await stored(url, role: .livePhotoMotion, isVideo: true, written: &written)
            moment.media.append(media)
            moment.modifiedAt = clock.now()
            try context.save()
        } catch {
            context.rollback()
            written.forEach { try? store.remove($0) }
            throw error as? SaveError ?? .failed
        }
    }

    /// Copies, the composite and a thumbnail need about the sources' size twice, plus the reserve.
    private func checkSpace(for files: [URL]) throws {
        guard let free = freeBytes() else { return }
        let sources = files.reduce(Int64(0)) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        let needed = sources * 2 + Self.reserve
        if free < needed { throw SaveError.lowStorage(shortfall: needed - free) }
    }

    private func role(_ position: CameraPosition) -> MediaRole {
        position == .back ? .rearSource : .frontSource
    }

    private func stored(
        _ url: URL, role: MediaRole, isVideo: Bool, area: MediaStore.Area = .originals, written: inout [String]
    ) async throws -> MomentMedia {
        let file = try store.store(copyOf: url, in: area)
        written.append(file.relativePath)
        let info = isVideo ? try await Self.videoInfo(url) : try Self.imageInfo(url)
        return MomentMedia(
            role: role, relativePath: file.relativePath,
            uniformType: UTType(filenameExtension: url.pathExtension)?.identifier ?? "public.data",
            pixelWidth: info.width, pixelHeight: info.height, checksum: file.checksum, byteCount: file.byteCount,
            orientation: info.orientation, codec: info.codec, duration: info.duration, hasAudio: info.hasAudio
        )
    }

    /// The thumbnail grids and strips show: the composed photo, or the first frames composed like playback.
    private func thumbnail(
        _ capture: CaptureResult, composedPhoto: URL?, window: SelfieWindowFrame?, halves: CaptureFormat?
    ) async throws -> URL {
        let size = Self.thumbnailSize
        var image: CGImage?
        if case let .video(video) = capture.media {
            image = await Self.videoThumbnail(
                mainURL: video.mainURL, selfieURL: video.selfieURL, selfieOffset: video.selfieOffset, window: window, halves: halves
            )
        } else {
            image = await ReviewModel.still(composedPhoto ?? capture.mainURL, maxPixelSize: size, at: 0)?.cgImage
        }
        guard let image else { throw SaveError.failed }
        let url = try CaptureFiles.temporaryURL("jpg")
        try ThumbnailPipeline.jpegData(image).write(to: url)
        return url
    }

    /// A video's first frames composed with its selfie window, as grids show it; also when the player moves
    /// the window.
    static func videoThumbnail(
        mainURL: URL, selfieURL: URL?, selfieOffset: TimeInterval, window: SelfieWindowFrame?, halves: CaptureFormat? = nil
    ) async -> CGImage? {
        let size = thumbnailSize
        guard let main = await ReviewModel.still(mainURL, maxPixelSize: size, at: 0)?.cgImage else { return nil }
        guard let selfieURL, window != nil || halves != nil,
              let selfie = await ReviewModel.still(selfieURL, maxPixelSize: size, at: max(0, -selfieOffset))?.cgImage else { return main }
        if let halves { return PhotoComposer.compose(main: main, selfie: selfie, halves: halves) }
        return window.map { PhotoComposer.compose(main: main, selfie: selfie, window: $0) } ?? main
    }

    struct Info {
        var width: Int
        var height: Int
        var orientation = 1
        var codec: String?
        var duration: Double?
        var hasAudio = false
    }

    static func imageInfo(_ url: URL) throws -> Info {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw SaveError.failed }
        return Info(width: width, height: height, orientation: properties[kCGImagePropertyOrientation] as? Int ?? 1)
    }

    /// Upright size, codec FourCC, duration and audio presence.
    static func videoInfo(_ url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw SaveError.failed }
        let (natural, transform, formats) = try await track.load(.naturalSize, .preferredTransform, .formatDescriptions)
        let upright = CGRect(origin: .zero, size: natural).applying(transform).size
        let codec = formats.first.map { description -> String in
            let code = CMFormatDescriptionGetMediaSubType(description).bigEndian
            return withUnsafeBytes(of: code) { String(decoding: $0, as: UTF8.self) }
        }
        return Info(
            width: Int(abs(upright.width).rounded()), height: Int(abs(upright.height).rounded()), codec: codec,
            duration: try await asset.load(.duration).seconds,
            hasAudio: !(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        )
    }
}

extension CaptureResult {
    var mainPosition: CameraPosition {
        switch media {
        case let .photo(photo): photo.mainPosition
        case let .video(video): video.mainPosition
        }
    }
}

extension PiPLayout {
    /// The window normalised to the shape it was put on: its centre by the shape's sides, its size as short side
    /// over short side, as `MomentComposition` reads it.
    init(_ window: SelfieWindowFrame, source: MediaRole) {
        self.init(
            centerX: window.frame.midX / window.preview.width, centerY: window.frame.midY / window.preview.height,
            scale: min(window.frame.width, window.frame.height) / min(window.preview.width, window.preview.height), source: source
        )
    }

    /// Back to a frame in a view of `size`, for composing on playback. On a wide shape the window lies on its side (U04).
    func windowFrame(in size: CGSize) -> SelfieWindowFrame {
        let short = scale * min(size.width, size.height)
        let long = short * SelfieWindowLayout.frame.height / SelfieWindowLayout.frame.width
        let (width, height) = size.width > size.height ? (long, short) : (short, long)
        let frame = CGRect(x: centerX * size.width - width / 2, y: centerY * size.height - height / 2, width: width, height: height)
        return SelfieWindowFrame(frame: frame, preview: size)
    }
}

extension EnvironmentValues {
    /// Nil in previews and snapshots; Save then fails with the generic error.
    @Entry var momentSaver: MomentSaver?
}
