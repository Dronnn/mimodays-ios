import Foundation
import Persistence

/// `manifest.json`, the last entry of a `.mimodays` backup: every record with stable IDs, and every file's
/// SHA-256 and size. Media sits next to it under `media/`, at the paths the records use.
///
/// Restoring: read the archive once, hashing every file, and compare with the manifest (E07's check); then
/// read it again and keep the files the chosen records need, under new names, before the records point at
/// them. Moments already here (same ID) are left alone. Newer format versions are refused, never guessed at.
struct BackupDocument: Codable, Equatable {
    static let format = "MimoDays backup"
    /// Raise when a reader of this version couldn't restore the new layout.
    static let currentVersion = 2
    /// 1.0.5 reads version 1. A backup with nothing hidden, no mood and no Then & Now stays at 1 so it still restores
    /// there; with any of them it is 2, which 1.0.5 refuses rather than bring hidden moments back into memories.
    static let firstVersion = 1
    static let manifestPath = "manifest.json"
    static let mediaFolder = "media"

    var format = Self.format
    var formatVersion = Self.currentVersion
    var archiveID = UUID()
    var createdAt: Date
    var schemaVersion = SchemaV2.versionIdentifier.description
    /// Store-relative path -> checksum and size.
    var files: [String: FileEntry] = [:]
    var moments: [MomentRecord] = []
    var collections: [CollectionRecord] = []
    var movies: [MovieRecord] = []
    /// P8.3: days hidden from memories (`Moment.localDay` keys). Missing in version 1.
    var hiddenDays: [Int]?

    /// The lowest version that can restore everything in it.
    var neededVersion: Int {
        let usesNewFields = !(hiddenDays ?? []).isEmpty
            || moments.contains { $0.isHiddenFromMemories == true || $0.repeatOf != nil || $0.mood != nil }
        return usesNewFields ? Self.currentVersion : Self.firstVersion
    }

    struct FileEntry: Codable, Equatable {
        var sha256: String
        var bytes: Int64
    }

    struct MomentRecord: Codable, Equatable {
        var id: UUID
        var capturedAt: Date
        var timeZoneID: String
        var localDay: Int
        var origin: String
        var promptID: UUID?
        var mediaType: String
        var status: String
        var title: String?
        var note: String?
        var tags: [String]
        var isFavorite: Bool
        var pipLayout: PiPLayout?
        /// Missing in archives from before formats: portrait.
        var captureFormat: String?
        var createdAt: Date
        var modifiedAt: Date
        var media: [MediaRecord]
        var voiceNotes: [VoiceNoteRecord]
        var location: LocationRecord?
        /// Version 2 (P8.3, P8.8, P8.10); missing when unset.
        var isHiddenFromMemories: Bool?
        var repeatOf: UUID?
        var mood: String?

        /// Every file the moment needs.
        var paths: [String] { media.map(\.path) + voiceNotes.map(\.path) }
        /// Something to show: at least one camera file. A record without one (a damaged or hand-made manifest) is no
        /// moment to restore.
        var hasPicture: Bool {
            media.contains { $0.role == MediaRole.rearSource.rawValue || $0.role == MediaRole.frontSource.rawValue }
        }

        /// Without the files that are gone from this iPhone, so a restore brings back the rest of the moment
        /// instead of skipping it. One whose camera files are all gone stays as it is: there is nothing to restore.
        func leavingOut(_ isMissing: (String) -> Bool) -> Self {
            let sources = media.filter { $0.role == MediaRole.rearSource.rawValue || $0.role == MediaRole.frontSource.rawValue }
            guard sources.contains(where: { !isMissing($0.path) }) else { return self }
            var record = self
            record.media.removeAll { isMissing($0.path) }
            record.voiceNotes.removeAll { isMissing($0.path) }
            // The window's stream alone is left: it becomes the picture, with no window.
            if let window = record.pipLayout?.source.rawValue,
               !record.media.contains(where: { $0.role != window && ($0.role == MediaRole.rearSource.rawValue || $0.role == MediaRole.frontSource.rawValue) }) {
                record.pipLayout = nil
            }
            return record
        }
    }

    struct MediaRecord: Codable, Equatable {
        var id: UUID
        var role: String
        var path: String
        var uniformType: String
        var codec: String?
        var duration: Double?
        var pixelWidth: Int
        var pixelHeight: Int
        var orientation: Int
        var hasAudio: Bool
        var startOffset: Double?
        var checksum: String
        var byteCount: Int64
    }

    struct VoiceNoteRecord: Codable, Equatable {
        var id: UUID
        var path: String
        var duration: Double
        var recordedAt: Date
        var transcript: String?
    }

    struct LocationRecord: Codable, Equatable {
        var latitude: Double?
        var longitude: Double?
        var horizontalAccuracy: Double?
        var precision: String
        var source: String
        var placeLabel: String?
    }

    struct CollectionRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var coverMomentID: UUID?
        var sortOrder: Int
        var createdAt: Date
        var members: [MemberRecord]
    }

    struct MemberRecord: Codable, Equatable {
        var momentID: UUID
        var position: Int
        var addedAt: Date
    }

    struct MovieRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var sourceRule: MovieSourceRule
        var aspectRatio: String
        var length: String
        var style: String?
        var status: String
        var customLength: Double?
        var fit: String
        var showsDates: Bool
        var showsPlaces: Bool
        var showsTitle: Bool
        var clipSoundLevel: Double
        var voiceNoteLevel: Double
        var selectionSeed: Int
        /// Only when rendered movies were included.
        var render: MovieRender?
        var createdAt: Date
        var updatedAt: Date
        var clips: [ClipRecord]
        var audioTracks: [AudioTrackRecord]
        /// Missing in archives from before text cards.
        var textCards: [TextCardRecord]?
    }

    struct ClipRecord: Codable, Equatable {
        var momentID: UUID
        var position: Int
        var trimStart: Double?
        var trimEnd: Double?
        var crop: NormalizedRect?
        var selfiePlacement: String?
        var transition: String
        var clipAudio: String
        var clipVolume: Double
        var includesVoiceNote: Bool
        var cameraLayout: String?
        var pipFrame: PiPLayout?
        var atmosphere: MovieAtmosphere?
    }

    struct TextCardRecord: Codable, Equatable {
        var id: UUID
        var position: Int
        var text: String
        var look: String
        var duration: Double
        var transition: String
        var atmosphere: MovieAtmosphere?
        var voiceNoteID: UUID?
    }

    struct AudioTrackRecord: Codable, Equatable {
        var id: UUID
        var kind: String
        var path: String
        var name: String?
        var startOffset: Double
        var gain: Double
        var gainEnvelope: [GainPoint]
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Seconds since 1970 as doubles, so dates come back to the same instant.
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

// MARK: Records from the models

extension BackupDocument.MomentRecord {
    init(_ moment: Moment) {
        id = moment.id
        capturedAt = moment.capturedAt
        timeZoneID = moment.timeZoneID
        localDay = moment.localDay
        origin = moment.originRaw
        promptID = moment.promptID
        mediaType = moment.mediaTypeRaw
        status = moment.statusRaw
        title = moment.title
        note = moment.note
        tags = moment.tags
        isFavorite = moment.isFavorite
        pipLayout = moment.pipLayout
        captureFormat = moment.captureFormatRaw
        isHiddenFromMemories = moment.isHiddenFromMemories ? true : nil
        repeatOf = moment.repeatOfMomentID
        mood = moment.moodRaw
        createdAt = moment.createdAt
        modifiedAt = moment.modifiedAt
        media = moment.media.sorted { $0.roleRaw < $1.roleRaw }.map {
            .init(
                id: $0.id, role: $0.roleRaw, path: $0.relativePath, uniformType: $0.uniformType, codec: $0.codec, duration: $0.duration,
                pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, orientation: $0.orientation, hasAudio: $0.hasAudio,
                startOffset: $0.startOffset, checksum: $0.checksum, byteCount: $0.byteCount
            )
        }
        voiceNotes = moment.voiceNotes.sorted { $0.recordedAt < $1.recordedAt }.map {
            .init(id: $0.id, path: $0.relativePath, duration: $0.duration, recordedAt: $0.recordedAt, transcript: $0.transcript)
        }
        location = moment.location.map {
            .init(
                latitude: $0.latitude, longitude: $0.longitude, horizontalAccuracy: $0.horizontalAccuracy, precision: $0.precisionRaw,
                source: $0.sourceRaw, placeLabel: $0.placeLabel
            )
        }
    }

    /// A new moment from the record, its files at `paths` (backup path -> path in this store).
    func moment(paths: [String: String]) -> Moment {
        let moment = Moment(
            id: id, capturedAt: capturedAt, timeZoneID: timeZoneID, localDay: localDay,
            origin: MomentOrigin(rawValue: origin) ?? .manual, mediaType: MediaType(rawValue: mediaType) ?? .photo,
            promptID: promptID, status: MomentStatus(rawValue: status) ?? .ready, createdAt: createdAt
        )
        moment.title = title
        moment.note = note
        moment.tags = tags
        moment.isFavorite = isFavorite
        moment.pipLayout = pipLayout
        moment.captureFormatRaw = captureFormat ?? CaptureFormat.portrait.rawValue
        moment.isHiddenFromMemories = isHiddenFromMemories ?? false
        moment.repeatOfMomentID = repeatOf
        moment.moodRaw = mood
        moment.modifiedAt = modifiedAt
        moment.media = media.map {
            MomentMedia(
                id: $0.id, role: MediaRole(rawValue: $0.role) ?? .rearSource, relativePath: paths[$0.path] ?? $0.path,
                uniformType: $0.uniformType, pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, checksum: $0.checksum,
                byteCount: $0.byteCount, orientation: $0.orientation, codec: $0.codec, duration: $0.duration, hasAudio: $0.hasAudio,
                startOffset: $0.startOffset
            )
        }
        // A backup from before imports kept their shape.
        moment.fitImportedFormat()
        moment.voiceNotes = voiceNotes.map {
            MomentVoiceNote(id: $0.id, relativePath: paths[$0.path] ?? $0.path, duration: $0.duration, recordedAt: $0.recordedAt, transcript: $0.transcript)
        }
        moment.location = location.map {
            MomentLocation(
                latitude: $0.latitude, longitude: $0.longitude, precision: LocationPrecision(rawValue: $0.precision) ?? .exact,
                source: LocationSource(rawValue: $0.source) ?? .manual, horizontalAccuracy: $0.horizontalAccuracy, placeLabel: $0.placeLabel
            )
        }
        return moment
    }
}

extension BackupDocument.CollectionRecord {
    init(_ collection: MomentCollection) {
        id = collection.id
        title = collection.title
        coverMomentID = collection.coverMomentID
        sortOrder = collection.sortOrder
        createdAt = collection.createdAt
        members = collection.memberships.compactMap { membership in
            guard let moment = membership.moment, moment.deletedAt == nil else { return nil }
            return .init(momentID: moment.id, position: membership.position, addedAt: membership.addedAt)
        }
        .sorted { $0.position < $1.position }
    }
}

extension BackupDocument.MovieRecord {
    init(_ project: MovieProject, includesRender: Bool) {
        id = project.id
        title = project.title
        sourceRule = project.sourceRule
        aspectRatio = project.aspectRatioRaw
        length = project.lengthRaw
        style = project.style
        status = includesRender ? project.statusRaw : (project.render == nil ? project.statusRaw : MovieStatus.draft.rawValue)
        customLength = project.customLength
        fit = project.fitRaw
        showsDates = project.showsDates
        showsPlaces = project.showsPlaces
        showsTitle = project.showsTitle
        clipSoundLevel = project.clipSoundLevel
        voiceNoteLevel = project.voiceNoteLevel
        selectionSeed = project.selectionSeed
        render = includesRender ? project.render : nil
        createdAt = project.createdAt
        updatedAt = project.updatedAt
        clips = project.orderedClips.compactMap { clip in
            guard let moment = clip.moment, moment.deletedAt == nil else { return nil }
            return .init(
                momentID: moment.id, position: clip.position, trimStart: clip.trimStart, trimEnd: clip.trimEnd, crop: clip.crop,
                selfiePlacement: clip.selfiePlacementRaw, transition: clip.transitionRaw, clipAudio: clip.clipAudioRaw,
                clipVolume: clip.clipVolume, includesVoiceNote: clip.includesVoiceNote, cameraLayout: clip.cameraLayoutRaw,
                pipFrame: clip.pipFrame, atmosphere: clip.atmosphere
            )
        }
        textCards = project.textCards.sorted { $0.position < $1.position }.map {
            .init(
                id: $0.id, position: $0.position, text: $0.text, look: $0.lookRaw, duration: $0.duration, transition: $0.transitionRaw,
                atmosphere: $0.atmosphere, voiceNoteID: $0.voiceNoteID
            )
        }
        audioTracks = project.audioTracks.map {
            .init(id: $0.id, kind: $0.kindRaw, path: $0.relativePath, name: $0.name, startOffset: $0.startOffset, gain: $0.gain, gainEnvelope: $0.gainEnvelope)
        }
    }

    /// Every file the project needs; the render's only when it was included.
    var paths: [String] { audioTracks.map(\.path) + (render.map { [$0.relativePath] } ?? []) }
}
