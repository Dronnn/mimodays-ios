import Core
import Foundation
import SwiftData

// Current model names: the newest schema. A shipped version is never edited; a new one copies it and adds a stage.
public typealias Moment = SchemaV2.Moment
public typealias MomentMedia = SchemaV2.MomentMedia
public typealias MomentVoiceNote = SchemaV2.MomentVoiceNote
public typealias MomentLocation = SchemaV2.MomentLocation
public typealias SurpriseSchedule = SchemaV2.SurpriseSchedule
public typealias SurprisePrompt = SchemaV2.SurprisePrompt
public typealias MomentCollection = SchemaV2.MomentCollection
public typealias CollectionMembership = SchemaV2.CollectionMembership
public typealias MovieProject = SchemaV2.MovieProject
public typealias MovieClip = SchemaV2.MovieClip
public typealias MovieTextCard = SchemaV2.MovieTextCard
public typealias MovieAudioTrack = SchemaV2.MovieAudioTrack
public typealias ExportJob = SchemaV2.ExportJob
public typealias BackupManifest = SchemaV2.BackupManifest
public typealias AppPreferences = SchemaV2.AppPreferences
public typealias HiddenDay = SchemaV2.HiddenDay

/// Every schema version in order. Each new version adds a migration stage; versions are never edited once shipped.
public enum MimoDaysMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    /// 1.0.5 → 1.0.7: new optional fields and `HiddenDay`; nothing to convert.
    public static var stages: [MigrationStage] { [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)] }
}

public enum MimoDaysStore {
    public static var schema: Schema { Schema(versionedSchema: SchemaV2.self) }

    /// The app's container. `url` nil uses the default store location; tests pass `inMemory: true`.
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, migrationPlan: MimoDaysMigrationPlan.self, configurations: configuration)
    }
}


public extension Moment {
    /// Creates a moment whose day and time zone come from one capture time, so they can't disagree.
    convenience init(
        id: UUID = UUID(), captured: CaptureTime, origin: MomentOrigin, mediaType: MediaType, promptID: UUID? = nil, createdAt: Date
    ) {
        self.init(
            id: id, capturedAt: captured.instant, timeZoneID: captured.timeZoneID, localDay: captured.localDay.key,
            origin: origin, mediaType: mediaType, promptID: promptID, createdAt: createdAt
        )
    }

    var captureTime: CaptureTime { CaptureTime(instant: capturedAt, timeZoneID: timeZoneID) }
}
