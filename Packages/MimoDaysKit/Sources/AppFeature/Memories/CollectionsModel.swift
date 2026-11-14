import Core
import Foundation
import Observation
import os
import Persistence
import SwiftData
import UIKit

/// Writes collections. A collection only groups moments: removing a moment from one, or deleting it, never
/// touches the moment (only its `CollectionMembership` goes).
@MainActor
struct CollectionStore {
    let context: ModelContext

    /// The new collection goes first. Nil for a name that is only spaces.
    @discardableResult
    func create(_ title: String, with momentIDs: [UUID] = []) throws -> UUID? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let first = try context.fetch(FetchDescriptor<MomentCollection>(sortBy: [SortDescriptor(\.sortOrder)])).first?.sortOrder ?? 1
        let collection = MomentCollection(title: title, sortOrder: first - 1)
        context.insert(collection)
        try add(momentIDs, to: collection)
        try save()
        return collection.id
    }

    func rename(_ id: UUID, to title: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let collection = try collection(id) else { return }
        collection.title = title
        try save()
    }

    /// The collection and its memberships go; every moment stays.
    func delete(_ id: UUID) throws {
        guard let collection = try collection(id) else { return }
        context.delete(collection)
        try save()
    }

    /// Moments not in it yet go to the end, in the order given.
    func add(_ momentIDs: [UUID], to id: UUID) throws {
        guard let collection = try collection(id) else { return }
        try add(momentIDs, to: collection)
        try save()
    }

    func remove(_ momentIDs: Set<UUID>, from id: UUID) throws {
        guard let collection = try collection(id) else { return }
        for membership in collection.memberships where membership.moment.map({ momentIDs.contains($0.id) }) ?? true {
            context.delete(membership)
        }
        if let cover = collection.coverMomentID, momentIDs.contains(cover) { collection.coverMomentID = nil }
        try save()
    }

    /// The collections a moment is in.
    func collectionIDs(of momentID: UUID) throws -> Set<UUID> {
        guard let moment = try moment(momentID) else { return [] }
        return Set(moment.memberships.compactMap(\.collection?.id))
    }

    /// Puts the moment in exactly these collections, without saving (Edit moment saves it all at once).
    func place(_ momentID: UUID, in ids: Set<UUID>) throws {
        guard let moment = try moment(momentID) else { return }
        for membership in moment.memberships where !ids.contains(membership.collection?.id ?? UUID()) {
            context.delete(membership)
        }
        let current = Set(moment.memberships.compactMap(\.collection?.id))
        for id in ids.subtracting(current) {
            guard let collection = try collection(id) else { continue }
            try add([momentID], to: collection)
        }
    }

    private func add(_ momentIDs: [UUID], to collection: MomentCollection) throws {
        let present = Set(collection.memberships.compactMap(\.moment?.id))
        var position = (collection.memberships.map(\.position).max() ?? -1) + 1
        for id in momentIDs where !present.contains(id) {
            guard let moment = try moment(id) else { continue }
            context.insert(CollectionMembership(collection: collection, moment: moment, position: position))
            position += 1
        }
    }

    func collection(_ id: UUID) throws -> MomentCollection? {
        var descriptor = FetchDescriptor<MomentCollection>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func moment(_ id: UUID) throws -> Moment? {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

/// One collection as M11 shows it. Moments in Recently deleted don't count.
struct CollectionSummary: Equatable, Identifiable {
    var id: UUID
    var title: String
    var count: Int
    /// The cover's thumbnail: the chosen cover, else the newest moment.
    var coverPath: String?
}

/// M11: every collection, newest first, with its cover and count.
@MainActor
@Observable
final class CollectionsModel {
    private(set) var collections: [CollectionSummary] = []
    private(set) var isLoaded = false
    /// Moments in Recently deleted (M16's row at the bottom of M11).
    private(set) var deletedCount = 0
    private(set) var covers: [UUID: UIImage] = [:]

    let library: MediaLibrary
    private let logger = Logger(subsystem: "MimoDays", category: "Collections")

    init(library: MediaLibrary) {
        self.library = library
    }

    var store: CollectionStore { CollectionStore(context: library.context) }

    func refresh() {
        do {
            collections = try library.context.fetch(FetchDescriptor<MomentCollection>(sortBy: [SortDescriptor(\.sortOrder)])).map(Self.summary)
            deletedCount = try library.context.fetchCount(FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt != nil }))
        } catch {
            logger.error("Reading collections failed: \(error.localizedDescription, privacy: .public)")
        }
        isLoaded = true
    }

    static func summary(_ collection: MomentCollection) -> CollectionSummary {
        let alive = collection.memberships.compactMap(\.moment).filter { $0.deletedAt == nil }
        let cover = alive.first { $0.id == collection.coverMomentID } ?? alive.max { $0.capturedAt < $1.capturedAt }
        return CollectionSummary(
            id: collection.id, title: collection.title, count: alive.count,
            coverPath: cover?.media.first { $0.role == .thumbnail }?.relativePath
        )
    }

    func loadCover(_ summary: CollectionSummary) async {
        guard covers[summary.id] == nil, let path = summary.coverPath, let url = try? library.store.url(for: path),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: 480) else { return }
        covers[summary.id] = UIImage(cgImage: image)
    }

    @discardableResult
    func create(_ title: String) -> UUID? {
        do {
            return try store.create(title)
        } catch {
            logger.error("Creating a collection failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// M12: one collection's moments, oldest first, like a story.
@MainActor
@Observable
final class CollectionModel {
    let id: UUID
    private(set) var title = ""
    private(set) var items: [MemoryItem] = []
    private(set) var details: [UUID: TileDetail] = [:]
    private(set) var images: [UUID: UIImage] = [:]
    private(set) var cover: UIImage?
    /// False once the collection is gone (deleted here or elsewhere).
    private(set) var exists = true

    let library: MediaLibrary
    private var coverPath: String?
    private let logger = Logger(subsystem: "MimoDays", category: "Collections")

    init(id: UUID, library: MediaLibrary) {
        self.id = id
        self.library = library
    }

    var store: CollectionStore { CollectionStore(context: library.context) }

    /// The first and last local days, yyyymmdd.
    var span: (first: Int, last: Int)? {
        guard let first = items.first?.localDay, let last = items.last?.localDay else { return nil }
        return (first, last)
    }

    func refresh() {
        guard let collection = try? store.collection(id) else {
            exists = false
            return
        }
        title = collection.title
        let moments = collection.memberships.compactMap(\.moment).filter { $0.deletedAt == nil }.sorted { $0.capturedAt < $1.capturedAt }
        items = moments.map {
            MemoryItem(
                id: $0.id, localDay: $0.localDay, capturedAt: $0.capturedAt, timeZoneID: $0.timeZoneID,
                mediaType: $0.mediaType, origin: $0.origin, isFavorite: $0.isFavorite
            )
        }
        details = Dictionary(uniqueKeysWithValues: moments.map {
            ($0.id, TileDetail(
                thumbnailPath: $0.media.first { $0.role == .thumbnail }?.relativePath,
                duration: $0.mediaType == .video ? $0.media.compactMap(\.duration).max() : nil,
                hasVoiceNote: !$0.voiceNotes.isEmpty
            ))
        })
        let path = CollectionsModel.summary(collection).coverPath
        if path != coverPath { cover = nil }
        coverPath = path
    }

    func load(_ id: UUID) async {
        guard images[id] == nil, let path = details[id]?.thumbnailPath, let url = try? library.store.url(for: path),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: MemoriesModel.tilePixels) else { return }
        images[id] = UIImage(cgImage: image)
    }

    func loadCover() async {
        guard cover == nil, let coverPath, let url = try? library.store.url(for: coverPath),
              let image = try? await library.thumbnails.thumbnail(for: url, maxPixelSize: 1000) else { return }
        cover = UIImage(cgImage: image)
    }

    func rename(_ title: String) {
        perform { try store.rename(id, to: title) }
    }

    func delete() {
        perform { try store.delete(id) }
        exists = false
    }

    func remove(_ momentID: UUID) {
        perform { try store.remove([momentID], from: id) }
    }

    func add(_ momentIDs: [UUID]) {
        perform { try store.add(momentIDs, to: id) }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            logger.error("Changing the collection failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
