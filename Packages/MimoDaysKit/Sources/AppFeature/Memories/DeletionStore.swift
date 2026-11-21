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

    /// Not what is past its 30 days (Recently Deleted left open across the deadline): that goes at the next purge.
    /// The ones recovered.
    @discardableResult
    func recover(_ ids: Set<UUID>) throws -> Set<UUID> {
        let date = now()
        let cutoff = date.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        var recovered: Set<UUID> = []
        for moment in try moments(ids) where moment.deletedAt.map({ $0 >= cutoff }) == true {
            moment.deletedAt = nil
            moment.modifiedAt = date
            recovered.insert(moment.id)
        }
        try save()
        return recovered
    }

    /// When a moment deleted at `deletedAt` goes for good.
    static func expiry(deletedAt: Date) -> Date {
        deletedAt.addingTimeInterval(Double(keepDays) * 86_400)
    }

    /// The moments, their media and voice notes go; files are removed once the store has saved. Only moments in
    /// Recently Deleted: one recovered meanwhile (from another screen) stays.
    func deleteForever(_ ids: Set<UUID>) throws {
        var paths: [String] = []
        let gone = try moments(ids).filter { $0.deletedAt != nil }
        try ThenNow.unlinkRepeats(of: Set(gone.map(\.id)), in: context)
        for moment in gone {
            paths += moment.media.map(\.relativePath) + moment.voiceNotes.map(\.relativePath)
            context.delete(moment)
        }
        try save()
        for path in paths {
            do { try store.remove(path) } catch { Self.logger.error("Removing a file failed: \(error.localizedDescription, privacy: .public)") }
            try? store.remove(LoopPreviews.path(for: path))
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
