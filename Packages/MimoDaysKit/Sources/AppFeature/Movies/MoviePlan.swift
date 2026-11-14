import Core
import CoreGraphics
import Foundation
import Persistence

/// A movie as the composer plays it: every clip still in the project, with its files, timing and overlays (11.7).
/// Read from the store on the main actor, then composed anywhere.
struct MoviePlan: Sendable, Equatable {
    struct Clip: Sendable, Equatable {
        enum Media: Sendable, Equatable {
            case photo
            /// `start` seconds into the main stream; the selfie stream started `selfieOffset` later than it.
            case video(start: Double, selfieOffset: Double, hasAudio: Bool)
        }

        var momentID: UUID
        var media: Media
        var mainURL: URL
        var selfieURL: URL?
        /// The selfie window where it was recorded, relative to the main picture; nil without a selfie.
        var window: PiPLayout?
        /// F07's override; nil keeps the recorded spot.
        var placement: MovieSelfiePlacement?
        var duration: Double
        /// How this clip comes in after the one before.
        var transition: MovieTransition
        /// "Oct 3, 2026 · Yerevan" (F08), nil when neither is shown.
        var caption: String?
        var voiceURL: URL?
        var soundOn: Bool
    }

    var clips: [Clip]
    var aspectRatio: MovieAspectRatio
    var fit: MovieFit
    /// F09's clip sound level, 0...1.
    var clipSoundLevel: Double

    var duration: Double { clips.reduce(0) { $0 + $1.duration } }

    @MainActor
    init(_ project: MovieProject, store: MediaStore) {
        aspectRatio = project.aspectRatio
        fit = project.fit
        clipSoundLevel = project.clipSoundLevel
        clips = MovieStore.liveClips(of: project).compactMap { clip in
            guard let moment = clip.moment else { return nil }
            return Self.clip(clip, moment, showsDates: project.showsDates, showsPlaces: project.showsPlaces, store: store)
        }
    }

    init(clips: [Clip], aspectRatio: MovieAspectRatio, fit: MovieFit, clipSoundLevel: Double) {
        self.clips = clips
        self.aspectRatio = aspectRatio
        self.fit = fit
        self.clipSoundLevel = clipSoundLevel
    }

    @MainActor
    private static func clip(_ clip: MovieClip, _ moment: Moment, showsDates: Bool, showsPlaces: Bool, store: MediaStore) -> Clip? {
        let summary = MomentSummary(moment)
        guard let mainPath = summary.mainPath, let mainURL = try? store.url(for: mainPath) else { return nil }
        let selfieURL = summary.selfiePath.flatMap { try? store.url(for: $0) }
        let media: Clip.Media
        let duration: Double
        if moment.mediaType == .video {
            let main = moment.media.first { $0.relativePath == mainPath }
            let selfie = moment.media.first { $0.relativePath == summary.selfiePath }
            let length = main?.duration ?? MovieSelection.longestVideoSeconds
            let start = min(max(clip.trimStart ?? 0, 0), max(length - 0.1, 0))
            let end = min(clip.trimEnd ?? start + MovieSelection.longestVideoSeconds, length)
            media = .video(start: start, selfieOffset: selfie?.startOffset ?? 0, hasAudio: main?.hasAudio ?? false)
            duration = max(end - start, 0.1)
        } else {
            media = .photo
            duration = MovieSelection.photoSeconds
        }
        var parts: [String] = []
        if showsDates, let zone = TimeZone(identifier: summary.captured.timeZoneID) {
            parts.append(summary.captured.instant.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zone)))
        }
        if showsPlaces, let place = summary.place { parts.append(place) }
        let voice = clip.includesVoiceNote ? moment.voiceNotes.first.flatMap { try? store.url(for: $0.relativePath) } : nil
        return Clip(
            momentID: moment.id, media: media, mainURL: mainURL, selfieURL: selfieURL,
            window: selfieURL == nil ? nil : moment.pipLayout, placement: clip.selfiePlacement, duration: duration,
            transition: clip.transition, caption: parts.isEmpty ? nil : parts.joined(separator: " · "),
            voiceURL: voice, soundOn: clip.clipAudio != .muted
        )
    }
}

extension MovieAspectRatio {
    /// The frame in pixels: the short side is the resolution's number (1080p 9:16 is 1080x1920).
    func renderSize(_ resolution: MovieResolution) -> CGSize {
        let short: CGFloat = switch resolution {
        case .p720: 720
        case .p1080: 1080
        case .p2160: 2160
        }
        return switch self {
        case .portrait9x16: CGSize(width: short, height: short * 16 / 9)
        case .landscape16x9: CGSize(width: short * 16 / 9, height: short)
        case .square1x1: CGSize(width: short, height: short)
        }
    }
}
