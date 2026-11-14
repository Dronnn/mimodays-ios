import Core
import Foundation
import os
import Persistence
import SwiftData

/// M15/M16: deleting moves moments to Recently deleted for 30 days; after that, or on "Delete now", they and their
/// files are gone for good. Collections and movie drafts lose them with them (their links cascade).
@MainActor
struct DeletionStore {
    let context: ModelContext
    let store: MediaStore
    var now: () -> Date = Date.init

    static let keepDays = 30
    private static let logger = Logger(subsystem: "MimoDays", category: "Deletion")

    func moveToRecentlyDeleted(_ ids: Set<UUID>) throws {
        let date = now()
        for moment in try moments(ids) where moment.deletedAt == nil {
            moment.deletedAt = date
            moment.modifiedAt = date
        }
        try save()
    }

    func recover(_ ids: Set<UUID>) throws {
        let date = now()
        for moment in try moments(ids) where moment.deletedAt != nil {
            moment.deletedAt = nil
            moment.modifiedAt = date
        }
        try save()
    }

    /// The moments, their media and voice notes go; files are removed once the store has saved.
    func deleteForever(_ ids: Set<UUID>) throws {
        var paths: [String] = []
        for moment in try moments(ids) {
            paths += moment.media.map(\.relativePath) + moment.voiceNotes.map(\.relativePath)
            context.delete(moment)
        }
        try save()
        for path in paths {
            do { try store.remove(path) } catch { Self.logger.error("Removing a file failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    /// Everything in Recently deleted for longer than 30 days.
    func purgeExpired() throws {
        let cutoff = now().addingTimeInterval(-Double(Self.keepDays) * 86_400)
        let expired = try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.deletedAt != nil }))
            .filter { ($0.deletedAt ?? .distantFuture) < cutoff }
        guard !expired.isEmpty else { return }
        try deleteForever(Set(expired.map(\.id)))
    }

    /// Movie drafts that use any of these moments (M15's note).
    func movieDrafts(using ids: Set<UUID>) throws -> Int {
        Set(try moments(ids).flatMap(\.movieClips).compactMap { $0.project?.id }).count
    }

    /// Whole days left before a moment deleted at `deletedAt` goes for good; at least 1 while it's still here.
    static func daysLeft(deletedAt: Date, now: Date) -> Int {
        let left = Double(keepDays) - now.timeIntervalSince(deletedAt) / 86_400
        return max(1, Int(left.rounded(.up)))
    }

    /// Whole days since it was deleted.
    static func daysAgo(deletedAt: Date, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(deletedAt) / 86_400))
    }

    private func moments(_ ids: Set<UUID>) throws -> [Moment] {
        let list = Array(ids)
        return try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { list.contains($0.id) }))
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
