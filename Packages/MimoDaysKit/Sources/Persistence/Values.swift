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
    /// Width as a fraction of the rear frame width.
    public var scale: Double
    public var shape: Shape
    /// Degrees; the design tilts the window -5.4.
    public var rotation: Double

    public init(centerX: Double, centerY: Double, scale: Double, shape: Shape = .roundedRectangle, rotation: Double = -5.4) {
        self.centerX = centerX
        self.centerY = centerY
        self.scale = scale
        self.shape = shape
        self.rotation = rotation
    }
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
