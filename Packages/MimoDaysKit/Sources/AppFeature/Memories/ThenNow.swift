import Foundation
import Persistence
import SwiftData

/// P8.8: a moment captured again on purpose ("Capture this again"), linked to the one it repeats. Only moments in
/// the archive count: one in Recently Deleted is left out until it's recovered.
enum ThenNow {
    /// Then, and the repeats to choose from (newest first) with the one shown.
    struct Comparison: Equatable {
        /// Nil while the first is in Recently Deleted: "This moment is unavailable".
        var then: Moment?
        var thenID: UUID
        var repeats: [Moment]
        var selected: UUID
    }

    /// What a new moment repeating `id` links to: the moment's own first when it's a repeat itself and that is there,
    /// else the moment; nil when it's gone, so the moment saves unlinked.
    static func source(for id: UUID?, in context: ModelContext) -> UUID? {
        guard let id, let moment = active(id, in: context) else { return nil }
        if let first = moment.repeatOfMomentID, active(first, in: context) != nil { return first }
        return id
    }

    /// From a repeat: its first with every repeat of it, this one shown. From a first: the newest repeat. Nil when
    /// the moment has neither.
    static func comparison(for moment: Moment, in context: ModelContext) -> Comparison? {
        let thenID = moment.repeatOfMomentID ?? moment.id
        let repeats = (try? context.fetch(FetchDescriptor<Moment>(
            predicate: #Predicate { $0.repeatOfMomentID == thenID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []
        guard let newest = repeats.first else { return nil }
        let selected = moment.repeatOfMomentID == nil ? newest.id : moment.id
        return Comparison(then: active(thenID, in: context), thenID: thenID, repeats: repeats, selected: selected)
    }

    /// Before the first goes for good: its repeats stay, unlinked.
    static func unlinkRepeats(of ids: Set<UUID>, in context: ModelContext) throws {
        let list = Array(ids)
        for moment in try context.fetch(FetchDescriptor<Moment>(predicate: #Predicate { $0.repeatOfMomentID != nil })) {
            if let source = moment.repeatOfMomentID, list.contains(source) { moment.repeatOfMomentID = nil }
        }
    }

    private static func active(_ id: UUID, in context: ModelContext) -> Moment? {
        var descriptor = FetchDescriptor<Moment>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
