import Foundation
import Persistence
import SwiftData

/// P8.4: a moment's own words to find it by. Up to 10, each up to 30 characters, trimmed; told apart regardless of
/// case and accents (as Search reads them), kept as first typed and in the order added.
enum Tags {
    static let limit = 10
    static let maxLength = 30

    enum Problem: Equatable {
        case blank
        case duplicate
        /// "You can add up to 10 tags."
        case full
    }

    static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxLength))
    }

    /// What two spellings of one tag share.
    static func key(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Why Add is off, nil when it's on.
    static func problem(adding text: String, to tags: [String]) -> Problem? {
        guard let tag = cleaned(text) else { return .blank }
        if tags.contains(where: { key($0) == key(tag) }) { return .duplicate }
        return tags.count >= limit ? .full : nil
    }

    static func adding(_ text: String, to tags: [String]) -> [String] {
        guard problem(adding: text, to: tags) == nil, let tag = cleaned(text) else { return tags }
        return tags + [tag]
    }

    /// Tags from `recent` (most recent first) with `query` in them, not ones in `excluding`.
    static func suggestions(_ query: String, from recent: [String], excluding: [String]) -> [String] {
        let taken = Set(excluding.map(key))
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return recent.filter { !taken.contains(key($0)) && (query.isEmpty || $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil) }
    }

    /// Every tag in the archive once, as the most recent moment spells it, most recent first.
    static func recent(in context: ModelContext) -> [String] {
        let moments = (try? context.fetch(FetchDescriptor<Moment>(
            predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        ))) ?? []
        var seen: Set<String> = []
        return moments.flatMap(\.tags).filter { seen.insert(key($0)).inserted }
    }
}
