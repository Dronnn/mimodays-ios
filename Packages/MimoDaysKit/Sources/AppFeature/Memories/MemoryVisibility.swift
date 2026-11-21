import Foundation
import os
import Persistence
import SwiftData

/// P8.3: which moments stay out of On this day, the widgets and automatic movies. Hidden moments stay everywhere
/// else (Today's latest and month strip, Timeline, Calendar, Search, Favorites, Collections, Map, Mosaic) and can
/// still be picked by hand for a movie.
struct MemoryVisibility {
    /// Days hidden as a whole (`Moment.localDay` keys); a moment added to one later is hidden too.
    let hiddenDays: Set<Int>

    init(hiddenDays: Set<Int> = []) {
        self.hiddenDays = hiddenDays
    }

    init(context: ModelContext) {
        let days = (try? context.fetch(FetchDescriptor<HiddenDay>())) ?? []
        hiddenDays = Set(days.map(\.localDay))
    }

    func isHidden(_ moment: Moment) -> Bool {
        moment.isHiddenFromMemories || hiddenDays.contains(moment.localDay)
    }

    /// Hidden by its day rather than on its own: the card says so, and showing it again is the day's choice.
    func isHiddenWithItsDay(_ moment: Moment) -> Bool {
        hiddenDays.contains(moment.localDay)
    }

    func isDayHidden(_ day: Int) -> Bool {
        hiddenDays.contains(day)
    }

    /// The moments that may come back on their own, in the same order.
    func visible(_ moments: [Moment]) -> [Moment] {
        moments.filter { !isHidden($0) }
    }

    // MARK: Changes

    /// Hides or shows one moment; saved at once. Showing it leaves a hidden day as it is.
    static func setHidden(_ hidden: Bool, _ moment: Moment, in context: ModelContext) throws {
        moment.isHiddenFromMemories = hidden
        try context.save()
    }

    /// Hides or shows a whole day; showing it leaves moments hidden on their own as they are.
    static func setDayHidden(_ hidden: Bool, _ day: Int, in context: ModelContext, now: Date = Date()) throws {
        let existing = try context.fetch(FetchDescriptor<HiddenDay>(predicate: #Predicate { $0.localDay == day }))
        if hidden, existing.isEmpty {
            context.insert(HiddenDay(localDay: day, createdAt: now))
        } else if !hidden {
            existing.forEach(context.delete)
        }
        try context.save()
    }

    /// Days were relabelled (Settings › Memories › Days): each hidden day moves with its moments, to every day they
    /// now fall on. Called with each moment's day before the change, in the same save as the new days.
    static func remapHiddenDays(_ context: ModelContext, oldDays: [UUID: Int]) throws {
        let rules = try context.fetch(FetchDescriptor<HiddenDay>())
        guard !rules.isEmpty else { return }
        let hidden = Set(rules.map(\.localDay))
        let moves = try context.fetch(FetchDescriptor<Moment>()).map { (from: oldDays[$0.id] ?? $0.localDay, to: $0.localDay) }
        let wanted = remapped(hidden, moves)
        for rule in rules where !wanted.contains(rule.localDay) { context.delete(rule) }
        for day in wanted.subtracting(hidden) { context.insert(HiddenDay(localDay: day)) }
    }

    /// The hidden days after every moment goes from its old day to its new one: a hidden day goes to every day its
    /// moments now fall on, and keeps its rule while one of its own moments is still on it, or when none left it.
    static func remapped(_ hidden: Set<Int>, _ moves: [(from: Int, to: Int)]) -> Set<Int> {
        guard !hidden.isEmpty else { return [] }
        var stayed: Set<Int> = []
        var leftDays: Set<Int> = []
        var movedTo: Set<Int> = []
        for move in moves {
            guard move.from != move.to else {
                stayed.insert(move.to)
                continue
            }
            guard hidden.contains(move.from) else { continue }
            leftDays.insert(move.from)
            movedTo.insert(move.to)
        }
        return movedTo.union(hidden.filter { stayed.contains($0) || !leftDays.contains($0) })
    }
}
