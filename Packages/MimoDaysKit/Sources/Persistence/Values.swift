import Foundation

// Value types stored inside models. Raw values are persisted: never rename a case, add new ones instead.

public enum MomentOrigin: String, Codable, CaseIterable, Sendable {
    case randomPrompt
    case manual
    case imported
}

public enum MediaType: String, Codable, CaseIterable, Sendable {
    case photo
    case video
    /// P8.11: words only, the body in `note` and the caption in `title`; no media. Needs backup version 2.
    case text
}

public enum MomentStatus: String, Codable, CaseIterable, Sendable {
    /// Saved and complete.
    case ready
    /// Media still being written or composed.
    case processing
    /// A media file is missing or fails its checksum.
    case needsRepair
}

public enum MediaRole: String, Codable, CaseIterable, Sendable {
    case rearSource
    case frontSource
    case composedPreview
    case thumbnail
    case audioSource
    /// P8.6: an imported Live Photo's paired motion, next to its still (the main source). Needs backup version 2.
    case livePhotoMotion
}

public enum LocationPrecision: String, Codable, CaseIterable, Sendable {
    case exact
    case approximate
    case city
}

public enum LocationSource: String, Codable, CaseIterable, Sendable {
    case gps
    case manual
    case imported
}

/// Selfie window placement, normalised to the rear frame (0...1).
public struct PiPLayout: Codable, Equatable, Hashable, Sendable {
    public enum Shape: String, Codable, CaseIterable, Sendable {
        case roundedRectangle
        case circle
    }

    public var centerX: Double
    public var centerY: Double
    /// The window's short side as a fraction of the frame's short side: its width on portrait and square, its height on landscape.
    public var scale: Double
    public var shape: Shape
    /// Degrees; the design tilts the window -5.4.
    public var rotation: Double
    /// The stream in the window: the front camera, or the rear one after ↻ made the front camera the big one.
    /// In halves, the stream in the second half (bottom on 9:16, right on 16:9).
    public var source: MediaRole
    /// How the two cameras share the frame; nil is the window (every moment from before halves existed).
    public var arrangement: Arrangement?

    /// H.8 (Andrew, 2026-11-16): the selfie in its window, or both cameras each filling half the frame, split
    /// across its long side. 1:1 has the window only.
    public enum Arrangement: String, Codable, CaseIterable, Sendable {
        case window
        case halves
    }

    public init(
        centerX: Double, centerY: Double, scale: Double, shape: Shape = .roundedRectangle, rotation: Double = -5.4,
        source: MediaRole = .frontSource, arrangement: Arrangement? = nil
    ) {
        self.centerX = centerX
        self.centerY = centerY
        self.scale = scale
        self.shape = shape
        self.rotation = rotation
        self.source = source
        self.arrangement = arrangement
    }

    /// Both cameras each fill half the frame.
    public var isHalves: Bool { arrangement == .halves }
}

/// The shape a moment was recorded in (U01-U07). The full sensor frame is kept; the format crops it on screen and in exports.
public enum CaptureFormat: String, Codable, CaseIterable, Sendable {
    /// 9:16 with the phone upright. Every moment from before formats existed.
    case portrait
    /// 16:9 with the phone sideways.
    case landscape
    /// 1:1 with the phone upright, cropped from the portrait frame.
    case square
}

public enum SurpriseFrequency: String, Codable, CaseIterable, Sendable {
    case threeAWeek
    case onceADay
    case twiceADay
    case threeADay
}

public enum TimeZonePolicy: String, Codable, CaseIterable, Sendable {
    /// Hours follow wherever the device is.
    case followDevice
    /// Hours stay in `fixedTimeZoneID`.
    case fixed
}

public enum PromptOutcome: String, Codable, CaseIterable, Sendable {
    case pending
    case captured
    case expired
    case dismissed
    case cancelled
}

public enum MovieSourceKind: String, Codable, CaseIterable, Sendable {
    case dateRange
    case collection
    case selection
    case onThisDay
    /// The moments at one place on the map (`momentIDs`).
    case place
    /// P8.9: one second per day of `start`...`end` (a month or a year), the moments in `momentIDs` as chosen.
    /// Needs backup version 2.
    case oneSecondPerDay
}

/// Which moments a movie is built from.
public struct MovieSourceRule: Codable, Equatable, Hashable, Sendable {
    public var kind: MovieSourceKind
    public var start: Date?
    public var end: Date?
    public var collectionID: UUID?
    public var momentIDs: [UUID]

    public init(kind: MovieSourceKind, start: Date? = nil, end: Date? = nil, collectionID: UUID? = nil, momentIDs: [UUID] = []) {
        self.kind = kind
        self.start = start
        self.end = end
        self.collectionID = collectionID
        self.momentIDs = momentIDs
    }
}

public enum MovieAspectRatio: String, Codable, CaseIterable, Sendable {
    case portrait9x16
    case landscape16x9
    case square1x1
}

public enum MovieLength: String, Codable, CaseIterable, Sendable {
    case quick
    case short
    case full
    case custom
}

public enum MovieStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case rendering
    case rendered
    case failed
}

/// How a photo or video that doesn't match the movie's shape sits in its frame (F04, F07).
public enum MovieFit: String, Codable, CaseIterable, Sendable {
    case fill
    case showAll
}

/// How a clip begins after the one before it (F06).
public enum MovieTransition: String, Codable, CaseIterable, Sendable {
    case cut
    case fade
    /// U53: the item's sound starts first, then its picture fades in (`MovieAtmosphere`).
    case atmosphere
}

/// Where a clip's selfie window goes in the movie (F07). A clip without one keeps it where it was recorded.
public enum MovieSelfiePlacement: String, Codable, CaseIterable, Sendable {
    case topRight
    case topLeft
    case bottom
    case hidden
}

/// Rendered movie height (F11).
public enum MovieResolution: String, Codable, CaseIterable, Sendable {
    case p720
    case p1080
    case p2160
}

/// A rendered file: an export made from a project. Losing it never loses the project, which can render it again.
public struct MovieRender: Codable, Equatable, Hashable, Sendable {
    /// Relative to the media store root.
    public var relativePath: String
    public var renderedAt: Date
    /// Seconds.
    public var duration: Double
    public var resolution: MovieResolution
    public var byteCount: Int64

    public init(relativePath: String, renderedAt: Date, duration: Double, resolution: MovieResolution, byteCount: Int64) {
        self.relativePath = relativePath
        self.renderedAt = renderedAt
        self.duration = duration
        self.resolution = resolution
        self.byteCount = byteCount
    }
}

/// How a clip shows its two cameras in a movie (U52). A clip without one uses the layout saved with the moment.
/// "Main" is the stream recorded full-frame, "selfie" the one recorded in the window.
public enum ClipCameraLayout: String, Codable, CaseIterable, Sendable {
    /// The selfie in the window over the main stream, as recorded.
    case window
    /// The main stream in the window over the selfie.
    case swapped
    case mainOnly
    case selfieOnly
    case sideBySide
}

/// U53 Atmosphere: the sound starts first, then the picture fades in.
public struct MovieAtmosphere: Codable, Equatable, Hashable, Sendable {
    public enum Lead: String, Codable, CaseIterable, Sendable {
        case clipSound
        case voiceComment
    }

    /// Seconds the sound may lead the picture.
    public static let leadRange: ClosedRange<Double> = 0.5...5

    /// Seconds the sound starts before the picture, within `leadRange`.
    public var lead: Double
    public var leadsWith: Lead

    public init(lead: Double = 2, leadsWith: Lead = .clipSound) {
        self.lead = min(max(lead, Self.leadRange.lowerBound), Self.leadRange.upperBound)
        self.leadsWith = leadsWith
    }
}

/// U51: how a text card looks.
public enum TextCardLook: String, Codable, CaseIterable, Sendable {
    case paper
    case plum
    /// Over the first frame of the clip after it.
    case overClip
}

public enum ClipAudio: String, Codable, CaseIterable, Sendable {
    case original
    case muted
    case ducked
}

/// Crop rectangle normalised to the clip frame (0...1).
public struct NormalizedRect: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum AudioTrackKind: String, Codable, CaseIterable, Sendable {
    case soundtrack
    case voiceover
}

/// Volume at a point in the movie timeline.
public struct GainPoint: Codable, Equatable, Hashable, Sendable {
    public var time: Double
    public var gain: Double

    public init(time: Double, gain: Double) {
        self.time = time
        self.gain = gain
    }
}

public enum ExportKind: String, Codable, CaseIterable, Sendable {
    case moment
    case selection
    case movie
    case archive
}

public enum ExportDestination: String, Codable, CaseIterable, Sendable {
    case photos
    case files
    case share
}

public enum ExportState: String, Codable, CaseIterable, Sendable {
    case queued
    case running
    case finished
    case failed
    case cancelled
}

/// Privacy defaults: exact place and voice are left out unless chosen (doc 01 §13).
public struct ExportOptions: Codable, Equatable, Hashable, Sendable {
    public var includesLocation: Bool
    public var includesVoiceNotes: Bool
    public var includesNotes: Bool

    public init(includesLocation: Bool = false, includesVoiceNotes: Bool = false, includesNotes: Bool = true) {
        self.includesLocation = includesLocation
        self.includesVoiceNotes = includesVoiceNotes
        self.includesNotes = includesNotes
    }
}

public enum AppTab: String, Codable, CaseIterable, Sendable {
    case today
    case memories
    case map
    case movies
}

public enum AppearancePreference: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

/// P8.10: a private mark on a moment, set only by the person. Stored by its stable code, never by its name.
public enum Mood: String, CaseIterable, Codable, Sendable {
    case joyful
    case calm
    case okay
    case low
    case heavy

    public var emoji: String {
        switch self {
        case .joyful: "😄"
        case .calm: "😌"
        case .okay: "🙂"
        case .low: "😕"
        case .heavy: "😞"
        }
    }
}

public extension Moment {
    /// An unknown code (from a newer version's backup) reads as no mood.
    var mood: Mood? {
        get { moodRaw.flatMap(Mood.init(rawValue:)) }
        set { moodRaw = newValue?.rawValue }
    }
}
