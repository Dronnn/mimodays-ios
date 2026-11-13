import Foundation
import SwiftData

// Current model names. When SchemaV2 lands, point these at it and add a stage to the migration plan.
public typealias Moment = SchemaV1.Moment
public typealias MomentMedia = SchemaV1.MomentMedia
public typealias MomentVoiceNote = SchemaV1.MomentVoiceNote
public typealias MomentLocation = SchemaV1.MomentLocation
public typealias SurpriseSchedule = SchemaV1.SurpriseSchedule
public typealias SurprisePrompt = SchemaV1.SurprisePrompt
public typealias MomentCollection = SchemaV1.MomentCollection
public typealias CollectionMembership = SchemaV1.CollectionMembership
public typealias MovieProject = SchemaV1.MovieProject
public typealias MovieClip = SchemaV1.MovieClip
public typealias MovieAudioTrack = SchemaV1.MovieAudioTrack
public typealias ExportJob = SchemaV1.ExportJob
public typealias BackupManifest = SchemaV1.BackupManifest
public typealias AppPreferences = SchemaV1.AppPreferences

/// Every schema version in order. Each new version adds a migration stage; versions are never edited once shipped.
public enum MimoDaysMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

public enum MimoDaysStore {
    public static var schema: Schema { Schema(versionedSchema: SchemaV1.self) }

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
