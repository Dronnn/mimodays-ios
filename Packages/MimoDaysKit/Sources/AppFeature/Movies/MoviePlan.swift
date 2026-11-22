@preconcurrency import AVFoundation
import Core
import CoreGraphics
import Foundation
import Persistence
import SwiftData

/// A movie as the composer plays it: every clip still in the project and its text cards (U51) in play order, with
/// their files, timing and overlays (11.7). Read from the store on the main actor, then composed anywhere; the editor's
/// stage and the exporter compose the same plan, so the preview is the export.
struct MoviePlan: Sendable, Equatable {
    struct Clip: Sendable, Equatable {
        enum Media: Sendable, Equatable {
            case photo
            /// `start` seconds into the main stream; the selfie stream started `selfieOffset` later than it.
            case video(start: Double, selfieOffset: Double, hasAudio: Bool)
            /// U51: words on paper or plum, or over the first frame of the clip after it.
            case card(text: String, look: TextCardLook)
        }

        /// The moment's id; a text card's own id.
        var momentID: UUID
        var media: Media
        /// Nil for a text card.
        var mainURL: URL?
        var selfieURL: URL?
        /// The selfie window: where it was recorded, or where it was put in the editor (U52), relative to the main
        /// picture; nil without a selfie.
        var window: PiPLayout?
        /// F07's override; nil keeps the recorded spot.
        var placement: MovieSelfiePlacement?
        /// U52: which camera goes where; nil is the window as recorded.
        var layout: ClipCameraLayout?
        var duration: Double
        /// How this clip comes in after the one before.
        var transition: MovieTransition
        /// U53, with `.atmosphere`: how long the sound leads and which.
        var atmosphere: MovieAtmosphere?
        /// "Wed, Oct 7 · Oakland" (F08), nil when neither is shown.
        var caption: String?
        var voiceURL: URL?
        var soundOn: Bool
        /// U52: this clip's own sound, 0...1, on top of the movie's level.
        var volume: Double = 1
        /// The main picture's upright size in pixels: where the window goes on the stage (U52).
        var pictureSize: CGSize?

        var isCard: Bool {
            if case .card = media { true } else { false }
        }

        /// U53: seconds of sound before the picture, never more than half the item.
        var lead: Double? {
            guard transition == .atmosphere else { return nil }
            return min(atmosphere?.lead ?? MovieAtmosphere().lead, duration / 2)
        }
    }

    /// The movie's one track (F09), played at `gain`: the person's own audio file from the start, fading in and out,
    /// or their voice from where the movie was when it was recorded, which doesn't fade (its first and last words
    /// would).
    struct Music: Sendable, Equatable {
        var url: URL
        var gain: Double
        var fades = true
        /// Seconds into the movie where it starts.
        var start: Double = 0
    }

    var clips: [Clip]
    var aspectRatio: MovieAspectRatio
    var fit: MovieFit
    /// F08's title over the first clip; nil when it's off.
    var title: String?
    /// F09's levels, 0...1.
    var clipSoundLevel: Double
    var voiceNoteLevel: Double
    var music: Music?

    var duration: Double { clips.reduce(0) { $0 + $1.duration } }

    /// How long a photo can be made to show (F06's Trim).
    static let shortestPhoto = 1.0
    static let longestPhoto = 6.0

    @MainActor
    init(_ project: MovieProject, store: MediaStore) {
        aspectRatio = project.aspectRatio
        fit = project.fit
        title = project.showsTitle ? project.title : nil
        clipSoundLevel = project.clipSoundLevel
        voiceNoteLevel = project.voiceNoteLevel
        music = project.audioTracks.first.flatMap { track in
            (try? store.url(for: track.relativePath)).map {
                Music(url: $0, gain: track.gain, fades: track.kind == .soundtrack, start: max(track.startOffset, 0))
            }
        }
        let clips: [(Int, Clip)] = MovieStore.liveClips(of: project).compactMap { clip in
            guard let moment = clip.moment,
                  let planned = Self.clip(clip, moment, showsDates: project.showsDates, showsPlaces: project.showsPlaces, store: store)
            else { return nil }
            return (clip.position, planned)
        }
        let cards = project.textCards.map { ($0.position, Self.card($0, store: store)) }
        self.clips = (clips + cards).sorted { $0.0 < $1.0 }.map(\.1)
    }

    init(
        clips: [Clip], aspectRatio: MovieAspectRatio, fit: MovieFit, title: String? = nil, clipSoundLevel: Double = 0.7,
        voiceNoteLevel: Double = 1, music: Music? = nil
    ) {
        self.clips = clips
        self.aspectRatio = aspectRatio
        self.fit = fit
        self.title = title
        self.clipSoundLevel = clipSoundLevel
        self.voiceNoteLevel = voiceNoteLevel
        self.music = music
    }

    @MainActor
    private static func clip(_ clip: MovieClip, _ moment: Moment, showsDates: Bool, showsPlaces: Bool, store: MediaStore) -> Clip? {
        let summary = MomentSummary(moment)
        let caption = captionLine(summary, showsDates: showsDates, showsPlaces: showsPlaces)
        // P8.11: a written moment is a paper card with the start of its words, timed like a photo.
        if moment.mediaType == .text {
            return Clip(
                momentID: moment.id, media: .card(text: TextMoment.excerpt(moment.note ?? ""), look: .paper), mainURL: nil, selfieURL: nil,
                window: nil, placement: nil, layout: nil,
                duration: min(max(clip.trimEnd ?? MovieSelection.photoSeconds, MoviePlan.shortestPhoto), MoviePlan.longestPhoto),
                transition: clip.transition, atmosphere: clip.atmosphere, caption: caption,
                voiceURL: clip.includesVoiceNote ? moment.voiceNotes.first.flatMap { try? store.url(for: $0.relativePath) } : nil, soundOn: false
            )
        }
        guard var mainPath = summary.mainPath, var mainURL = try? store.url(for: mainPath) else { return nil }
        var selfieURL = summary.selfiePath.flatMap { try? store.url(for: $0) }
        // P8.6: a Live Photo plays its motion, on its own; the still when the motion is gone.
        let motion = moment.mediaType == .photo ? moment.livePhotoMotion.flatMap { media in
            (try? store.url(for: media.relativePath)).flatMap { FileManager.default.fileExists(atPath: $0.path) ? (media, $0) : nil }
        } : nil
        if let motion {
            mainPath = motion.0.relativePath
            mainURL = motion.1
            selfieURL = nil
        }
        let media: Clip.Media
        let duration: Double
        if moment.mediaType == .video || motion != nil {
            let main = moment.media.first { $0.relativePath == mainPath }
            let selfie = motion == nil ? moment.media.first { $0.relativePath == summary.selfiePath } : nil
            let length = main?.duration ?? MovieSelection.longestVideoSeconds
            let start = min(max(clip.trimStart ?? 0, 0), max(length - 0.1, 0))
            let end = min(clip.trimEnd ?? start + MovieSelection.longestVideoSeconds, length)
            media = .video(start: start, selfieOffset: selfie?.startOffset ?? 0, hasAudio: main?.hasAudio ?? false)
            duration = max(end - start, 0.1)
        } else {
            media = .photo
            // A photo's trim is how long it shows (F06's Trim).
            duration = min(max(clip.trimEnd ?? MovieSelection.photoSeconds, MoviePlan.shortestPhoto), MoviePlan.longestPhoto)
        }
        let voice = clip.includesVoiceNote ? moment.voiceNotes.first.flatMap { try? store.url(for: $0.relativePath) } : nil
        return Clip(
            momentID: moment.id, media: media, mainURL: mainURL, selfieURL: selfieURL,
            window: selfieURL == nil ? nil : clip.pipFrame ?? moment.pipLayout, placement: clip.selfiePlacement,
            // H.8: a moment kept in halves stays in halves until the clip picks otherwise.
            layout: selfieURL == nil ? nil : clip.cameraLayout ?? (summary.isHalves ? .sideBySide : nil), duration: duration, transition: clip.transition,
            atmosphere: clip.atmosphere, caption: caption,
            voiceURL: voice, soundOn: clip.clipAudio != .muted, volume: clip.clipVolume,
            pictureSize: moment.media.first { $0.relativePath == mainPath }.map { media in
                // Photos keep their EXIF turn: 5-8 lie on their side.
                (5...8).contains(media.orientation) && moment.mediaType == .photo && motion == nil
                    ? CGSize(width: media.pixelHeight, height: media.pixelWidth) : CGSize(width: media.pixelWidth, height: media.pixelHeight)
            }
        )
    }

    /// The date and place line under a clip, as the movie's options say.
    @MainActor
    private static func captionLine(_ summary: MomentSummary, showsDates: Bool, showsPlaces: Bool) -> String? {
        var parts: [String] = []
        if showsDates, let zone = TimeZone(identifier: summary.captured.timeZoneID) {
            parts.append(summary.captured.instant.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).month(.abbreviated).day().locale(AppLanguage.shared.locale)))
        }
        if showsPlaces, let place = summary.place { parts.append(place) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// U51: the card for as long as it's set to show, with the voice comment picked for it.
    @MainActor
    private static func card(_ card: MovieTextCard, store: MediaStore) -> Clip {
        // rev-library: only a voice the editor offers, a note of a clip still in the movie whose moment isn't deleted,
        // so a card never plays one the card sheet can't show.
        let offered = card.project.map { MovieStore.liveClips(of: $0).compactMap { $0.moment?.voiceNotes.first } } ?? []
        let voice = card.voiceNoteID.flatMap { id in offered.first { $0.id == id } }.flatMap { try? store.url(for: $0.relativePath) }
        return Clip(
            momentID: card.id, media: .card(text: card.text, look: card.look), mainURL: nil, selfieURL: nil, window: nil,
            placement: nil, layout: nil, duration: card.duration, transition: card.transition, atmosphere: card.atmosphere,
            caption: nil, voiceURL: voice, soundOn: false
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

extension MoviePlan {
    /// Doc 01 §16: a moment whose picture can't be read any more (a damaged file) is left out of the export, as a
    /// deleted one is, rather than stopping it or showing an empty frame (Andrew, 2026-11-16).
    func leavingOutUnreadable() async -> MoviePlan {
        var plan = self
        plan.clips = []
        for clip in clips where await clip.isReadable { plan.clips.append(clip) }
        return plan
    }
}

private extension MoviePlan.Clip {
    var isReadable: Bool {
        get async {
            guard let mainURL else { return isCard }
            switch media {
            case .card: return true
            case .photo: return ImageDecoding.thumbnailNow(mainURL, maxPixelSize: 64) != nil
            case .video: return (try? await AVURLAsset(url: mainURL).loadTracks(withMediaType: .video).first) != nil
            }
        }
    }
}
