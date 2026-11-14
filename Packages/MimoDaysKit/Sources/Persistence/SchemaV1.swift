import Foundation
import SwiftData

// Enums are stored as raw strings (`…Raw`) so they work in #Predicate; typed accessors wrap them.
// Media lives in files; models keep paths relative to the media store root, never blobs.

public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Moment.self, MomentMedia.self, MomentVoiceNote.self, MomentLocation.self,
            SurpriseSchedule.self, SurprisePrompt.self,
            MomentCollection.self, CollectionMembership.self,
            MovieProject.self, MovieClip.self, MovieAudioTrack.self,
            ExportJob.self, BackupManifest.self, AppPreferences.self,
        ]
    }

    // MARK: Moments

    @Model
    public final class Moment {
        @Attribute(.unique) public var id: UUID
        /// Capture instant (UTC).
        public var capturedAt: Date
        /// Time zone where it was captured, e.g. "Europe/Berlin".
        public var timeZoneID: String
        /// Local calendar day at capture as yyyymmdd, for calendar grouping.
        public var localDay: Int
        public var originRaw: String
        public var promptID: UUID?
        public var mediaTypeRaw: String
        public var statusRaw: String
        public var title: String?
        public var note: String?
        public var tags: [String]
        public var isFavorite: Bool
        public var pipLayout: PiPLayout?
        public var createdAt: Date
        public var modifiedAt: Date
        /// Set while in Recently Deleted (kept 30 days).
        public var deletedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \MomentMedia.moment) public var media: [MomentMedia] = []
        @Relationship(deleteRule: .cascade, inverse: \MomentVoiceNote.moment) public var voiceNotes: [MomentVoiceNote] = []
        @Relationship(deleteRule: .cascade, inverse: \MomentLocation.moment) public var location: MomentLocation?
        @Relationship(deleteRule: .cascade, inverse: \CollectionMembership.moment) public var memberships: [CollectionMembership] = []
        @Relationship(deleteRule: .cascade, inverse: \MovieClip.moment) public var movieClips: [MovieClip] = []

        public init(
            id: UUID = UUID(), capturedAt: Date, timeZoneID: String, localDay: Int, origin: MomentOrigin,
            mediaType: MediaType, promptID: UUID? = nil, status: MomentStatus = .ready, createdAt: Date = Date()
        ) {
            self.id = id
            self.capturedAt = capturedAt
            self.timeZoneID = timeZoneID
            self.localDay = localDay
            originRaw = origin.rawValue
            self.promptID = promptID
            mediaTypeRaw = mediaType.rawValue
            statusRaw = status.rawValue
            tags = []
            isFavorite = false
            self.createdAt = createdAt
            modifiedAt = createdAt
        }

        public var origin: MomentOrigin {
            get { MomentOrigin(rawValue: originRaw) ?? .manual }
            set { originRaw = newValue.rawValue }
        }

        public var mediaType: MediaType {
            get { MediaType(rawValue: mediaTypeRaw) ?? .photo }
            set { mediaTypeRaw = newValue.rawValue }
        }

        public var status: MomentStatus {
            get { MomentStatus(rawValue: statusRaw) ?? .needsRepair }
            set { statusRaw = newValue.rawValue }
        }
    }

    @Model
    public final class MomentMedia {
        @Attribute(.unique) public var id: UUID
        public var roleRaw: String
        /// Path relative to the media store root.
        public var relativePath: String
        public var uniformType: String
        public var codec: String?
        public var duration: Double?
        public var pixelWidth: Int
        public var pixelHeight: Int
        /// EXIF orientation (1...8).
        public var orientation: Int
        public var hasAudio: Bool
        /// Video streams: seconds this stream starts after the main one (negative: earlier). Nil for the main stream.
        public var startOffset: Double?
        /// SHA-256, hex.
        public var checksum: String
        public var byteCount: Int64
        public var moment: Moment?

        public init(
            id: UUID = UUID(), role: MediaRole, relativePath: String, uniformType: String, pixelWidth: Int, pixelHeight: Int,
            checksum: String, byteCount: Int64, orientation: Int = 1, codec: String? = nil, duration: Double? = nil, hasAudio: Bool = false,
            startOffset: Double? = nil
        ) {
            self.id = id
            roleRaw = role.rawValue
            self.relativePath = relativePath
            self.uniformType = uniformType
            self.codec = codec
            self.duration = duration
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.orientation = orientation
            self.hasAudio = hasAudio
            self.startOffset = startOffset
            self.checksum = checksum
            self.byteCount = byteCount
        }

        public var role: MediaRole {
            get { MediaRole(rawValue: roleRaw) ?? .rearSource }
            set { roleRaw = newValue.rawValue }
        }
    }

    /// Voice commentary, kept separate from a clip's own audio.
    @Model
    public final class MomentVoiceNote {
        @Attribute(.unique) public var id: UUID
        public var relativePath: String
        public var duration: Double
        public var recordedAt: Date
        public var transcript: String?
        public var moment: Moment?

        public init(id: UUID = UUID(), relativePath: String, duration: Double, recordedAt: Date, transcript: String? = nil) {
            self.id = id
            self.relativePath = relativePath
            self.duration = duration
            self.recordedAt = recordedAt
            self.transcript = transcript
        }
    }

    /// Never inferred: only stored when permitted or added by hand.
    @Model
    public final class MomentLocation {
        public var latitude: Double?
        public var longitude: Double?
        public var horizontalAccuracy: Double?
        public var precisionRaw: String
        public var sourceRaw: String
        public var placeLabel: String?
        public var moment: Moment?

        public init(
            latitude: Double?, longitude: Double?, precision: LocationPrecision, source: LocationSource,
            horizontalAccuracy: Double? = nil, placeLabel: String? = nil
        ) {
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            precisionRaw = precision.rawValue
            sourceRaw = source.rawValue
            self.placeLabel = placeLabel
        }

        public var precision: LocationPrecision {
            get { LocationPrecision(rawValue: precisionRaw) ?? .city }
            set { precisionRaw = newValue.rawValue }
        }

        public var source: LocationSource {
            get { LocationSource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }
    }

    // MARK: Surprises

    /// One per app; holds the person's surprise settings.
    @Model
    public final class SurpriseSchedule {
        public var frequencyRaw: String
        /// Bit 0 = Sunday ... bit 6 = Saturday (Calendar weekday - 1).
        public var weekdayMask: Int
        /// Minutes after local midnight.
        public var earliestMinute: Int
        public var latestMinute: Int
        public var timeZonePolicyRaw: String
        public var fixedTimeZoneID: String?
        public var pausedUntil: Date?
        public var isPausedIndefinitely: Bool
        /// A prompt stays answerable this long after it fires.
        public var expiryMinutes: Int
        public var isEnabled: Bool

        public init(
            frequency: SurpriseFrequency = .onceADay, weekdayMask: Int = 0b111_1111, earliestMinute: Int = 8 * 60,
            latestMinute: Int = 22 * 60, timeZonePolicy: TimeZonePolicy = .followDevice, expiryMinutes: Int = 15
        ) {
            frequencyRaw = frequency.rawValue
            self.weekdayMask = weekdayMask
            self.earliestMinute = earliestMinute
            self.latestMinute = latestMinute
            timeZonePolicyRaw = timeZonePolicy.rawValue
            isPausedIndefinitely = false
            self.expiryMinutes = expiryMinutes
            isEnabled = true
        }

        public var frequency: SurpriseFrequency {
            get { SurpriseFrequency(rawValue: frequencyRaw) ?? .onceADay }
            set { frequencyRaw = newValue.rawValue }
        }

        public var timeZonePolicy: TimeZonePolicy {
            get { TimeZonePolicy(rawValue: timeZonePolicyRaw) ?? .followDevice }
            set { timeZonePolicyRaw = newValue.rawValue }
        }
    }

    @Model
    public final class SurprisePrompt {
        @Attribute(.unique) public var id: UUID
        public var plannedAt: Date
        public var expiresAt: Date
        public var notificationRequestID: String
        public var openedAt: Date?
        public var capturedMomentID: UUID?
        public var outcomeRaw: String

        public init(id: UUID = UUID(), plannedAt: Date, expiresAt: Date, notificationRequestID: String) {
            self.id = id
            self.plannedAt = plannedAt
            self.expiresAt = expiresAt
            self.notificationRequestID = notificationRequestID
            outcomeRaw = PromptOutcome.pending.rawValue
        }

        public var outcome: PromptOutcome {
            get { PromptOutcome(rawValue: outcomeRaw) ?? .pending }
            set { outcomeRaw = newValue.rawValue }
        }
    }

    // MARK: Collections

    @Model
    public final class MomentCollection {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var coverMomentID: UUID?
        public var sortOrder: Int
        public var createdAt: Date
        @Relationship(deleteRule: .cascade, inverse: \CollectionMembership.collection) public var memberships: [CollectionMembership] = []

        public init(id: UUID = UUID(), title: String, sortOrder: Int, createdAt: Date = Date()) {
            self.id = id
            self.title = title
            self.sortOrder = sortOrder
            self.createdAt = createdAt
        }

        /// Members in their saved order.
        public var orderedMoments: [Moment] {
            memberships.sorted { $0.position < $1.position }.compactMap(\.moment)
        }
    }

    /// Ordered link between a collection and a moment.
    @Model
    public final class CollectionMembership {
        public var position: Int
        public var addedAt: Date
        public var collection: MomentCollection?
        public var moment: Moment?

        public init(collection: MomentCollection, moment: Moment, position: Int, addedAt: Date = Date()) {
            self.collection = collection
            self.moment = moment
            self.position = position
            self.addedAt = addedAt
        }
    }

    // MARK: Movies

    @Model
    public final class MovieProject {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var sourceRule: MovieSourceRule
        public var aspectRatioRaw: String
        public var lengthRaw: String
        public var style: String?
        public var statusRaw: String
        /// Seconds, for `MovieLength.custom`.
        public var customLength: Double?
        public var fitRaw: String = MovieFit.fill.rawValue
        /// F08: the day, and the place, on each clip.
        public var showsDates: Bool = true
        public var showsPlaces: Bool = true
        /// F08: the movie's title over its first seconds.
        public var showsTitle: Bool = true
        /// F09: the clips' own sound, 0...1.
        public var clipSoundLevel: Double = 0.7
        /// F09: voice notes, 0...1.
        public var voiceNoteLevel: Double = 1
        /// Seed of the automatic pick, so the same source picks the same moments again.
        public var selectionSeed: Int = 0
        /// The latest rendered file; nil for a draft. Kept apart from the edit decisions above.
        public var render: MovieRender?
        public var createdAt: Date
        public var updatedAt: Date
        @Relationship(deleteRule: .cascade, inverse: \MovieClip.project) public var clips: [MovieClip] = []
        @Relationship(deleteRule: .cascade, inverse: \MovieAudioTrack.project) public var audioTracks: [MovieAudioTrack] = []

        public init(
            id: UUID = UUID(), title: String, sourceRule: MovieSourceRule, aspectRatio: MovieAspectRatio,
            length: MovieLength, createdAt: Date = Date()
        ) {
            self.id = id
            self.title = title
            self.sourceRule = sourceRule
            aspectRatioRaw = aspectRatio.rawValue
            lengthRaw = length.rawValue
            statusRaw = MovieStatus.draft.rawValue
            self.createdAt = createdAt
            updatedAt = createdAt
        }

        public var aspectRatio: MovieAspectRatio {
            get { MovieAspectRatio(rawValue: aspectRatioRaw) ?? .portrait9x16 }
            set { aspectRatioRaw = newValue.rawValue }
        }

        public var length: MovieLength {
            get { MovieLength(rawValue: lengthRaw) ?? .short }
            set { lengthRaw = newValue.rawValue }
        }

        public var status: MovieStatus {
            get { MovieStatus(rawValue: statusRaw) ?? .draft }
            set { statusRaw = newValue.rawValue }
        }

        public var fit: MovieFit {
            get { MovieFit(rawValue: fitRaw) ?? .fill }
            set { fitRaw = newValue.rawValue }
        }

        public var orderedClips: [MovieClip] { clips.sorted { $0.position < $1.position } }
    }

    @Model
    public final class MovieClip {
        public var position: Int
        public var trimStart: Double?
        public var trimEnd: Double?
        public var crop: NormalizedRect?
        /// nil keeps the selfie window where it was recorded.
        public var selfiePlacementRaw: String?
        public var transitionRaw: String = MovieTransition.cut.rawValue
        public var clipAudioRaw: String
        public var clipVolume: Double
        /// F09: the moment's voice note plays over its clip.
        public var includesVoiceNote: Bool = true
        public var project: MovieProject?
        public var moment: Moment?

        public init(project: MovieProject, moment: Moment, position: Int) {
            self.project = project
            self.moment = moment
            self.position = position
            clipAudioRaw = ClipAudio.original.rawValue
            clipVolume = 1
        }

        public var clipAudio: ClipAudio {
            get { ClipAudio(rawValue: clipAudioRaw) ?? .original }
            set { clipAudioRaw = newValue.rawValue }
        }

        public var selfiePlacement: MovieSelfiePlacement? {
            get { selfiePlacementRaw.flatMap(MovieSelfiePlacement.init(rawValue:)) }
            set { selfiePlacementRaw = newValue?.rawValue }
        }

        public var transition: MovieTransition {
            get { MovieTransition(rawValue: transitionRaw) ?? .cut }
            set { transitionRaw = newValue.rawValue }
        }
    }

    @Model
    public final class MovieAudioTrack {
        @Attribute(.unique) public var id: UUID
        public var kindRaw: String
        /// The person's own audio file (no bundled music in v1), relative to the media store root.
        public var relativePath: String
        public var startOffset: Double
        public var gain: Double
        public var gainEnvelope: [GainPoint]
        public var project: MovieProject?

        public init(id: UUID = UUID(), kind: AudioTrackKind, relativePath: String, startOffset: Double = 0, gain: Double = 1) {
            self.id = id
            kindRaw = kind.rawValue
            self.relativePath = relativePath
            self.startOffset = startOffset
            self.gain = gain
            gainEnvelope = []
        }

        public var kind: AudioTrackKind {
            get { AudioTrackKind(rawValue: kindRaw) ?? .soundtrack }
            set { kindRaw = newValue.rawValue }
        }
    }

    // MARK: Export, backup, preferences

    @Model
    public final class ExportJob {
        @Attribute(.unique) public var id: UUID
        public var kindRaw: String
        public var sourceIDs: [UUID]
        public var destinationRaw: String
        public var options: ExportOptions
        public var progress: Double
        public var stateRaw: String
        public var errorMessage: String?
        public var createdAt: Date
        public var finishedAt: Date?

        public init(
            id: UUID = UUID(), kind: ExportKind, sourceIDs: [UUID], destination: ExportDestination,
            options: ExportOptions = ExportOptions(), createdAt: Date = Date()
        ) {
            self.id = id
            kindRaw = kind.rawValue
            self.sourceIDs = sourceIDs
            destinationRaw = destination.rawValue
            self.options = options
            progress = 0
            stateRaw = ExportState.queued.rawValue
            self.createdAt = createdAt
        }

        public var kind: ExportKind {
            get { ExportKind(rawValue: kindRaw) ?? .moment }
            set { kindRaw = newValue.rawValue }
        }

        public var destination: ExportDestination {
            get { ExportDestination(rawValue: destinationRaw) ?? .files }
            set { destinationRaw = newValue.rawValue }
        }

        public var state: ExportState {
            get { ExportState(rawValue: stateRaw) ?? .failed }
            set { stateRaw = newValue.rawValue }
        }
    }

    /// Record of a backup archive written or restored.
    @Model
    public final class BackupManifest {
        @Attribute(.unique) public var archiveID: UUID
        public var formatVersion: Int
        public var createdAt: Date
        /// Relative path -> SHA-256 for every file in the archive.
        public var checksums: [String: String]
        /// Entity name -> count, checked after a restore.
        public var entityCounts: [String: Int]
        public var restoredAt: Date?

        public init(archiveID: UUID = UUID(), formatVersion: Int, createdAt: Date = Date(), checksums: [String: String] = [:], entityCounts: [String: Int] = [:]) {
            self.archiveID = archiveID
            self.formatVersion = formatVersion
            self.createdAt = createdAt
            self.checksums = checksums
            self.entityCounts = entityCounts
        }
    }

    /// One per app.
    @Model
    public final class AppPreferences {
        public var hasCompletedOnboarding: Bool
        /// Last onboarding page reached, for resuming.
        public var onboardingStep: Int
        /// Explainers already shown, e.g. "camera", "location".
        public var seenExplanations: [String]
        public var preferredTabRaw: String
        public var appearanceRaw: String
        public var defaultExportOptions: ExportOptions

        public init() {
            hasCompletedOnboarding = false
            onboardingStep = 0
            seenExplanations = []
            preferredTabRaw = AppTab.today.rawValue
            appearanceRaw = AppearancePreference.system.rawValue
            defaultExportOptions = ExportOptions()
        }

        public var preferredTab: AppTab {
            get { AppTab(rawValue: preferredTabRaw) ?? .today }
            set { preferredTabRaw = newValue.rawValue }
        }

        public var appearance: AppearancePreference {
            get { AppearancePreference(rawValue: appearanceRaw) ?? .system }
            set { appearanceRaw = newValue.rawValue }
        }
    }
}
