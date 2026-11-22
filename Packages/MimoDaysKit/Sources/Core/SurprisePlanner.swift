import Foundation

/// What the planner needs from the person's surprise settings, independent of storage.
public struct SurpriseRules: Equatable, Sendable {
    public enum Cadence: Equatable, Sendable {
        /// `n` surprises on every enabled day.
        case daily(Int)
        /// `n` enabled days per calendar week, one surprise each.
        case weekly(Int)
    }

    public var cadence: Cadence
    /// Bit 0 = Sunday ... bit 6 = Saturday (Calendar weekday - 1).
    public var weekdayMask: Int
    /// Minutes after local midnight; both ends can be used.
    public var earliestMinute: Int
    public var latestMinute: Int

    public init(cadence: Cadence, weekdayMask: Int, earliestMinute: Int, latestMinute: Int) {
        self.cadence = cadence
        self.weekdayMask = weekdayMask
        self.earliestMinute = earliestMinute
        self.latestMinute = latestMinute
    }
}

/// Draws random surprise times (doc 01 §6). Pure: the calendar, the clock and the random source come in,
/// so a seed gives the same plan every time.
///
/// Decisions (Andrew, 2026-11-13): "3 a week" = 3 random enabled days per locale week; surprises on one day
/// are at least 2 hours apart (less only when the chosen window is too narrow); 14 days are planned ahead;
/// a period that is already under way uses what is left of it, starting 15 minutes from now.
public struct SurprisePlanner: Sendable {
    public var calendar: Calendar
    public var horizonDays = 14
    public var minimumSeparation = 120
    public var leadMinutes = 15

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    /// New surprise times for the days (or weeks) from today to the horizon that have none yet.
    /// `planned` holds every surprise already drawn and not cancelled, past ones included,
    /// so a period is drawn once and a relaunch never adds a second set.
    public func draw(
        _ rules: SurpriseRules, now: Date, planned: [Date], using generator: inout some RandomNumberGenerator
    ) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard rules.weekdayMask & 0b111_1111 != 0,
              let horizonEnd = calendar.date(byAdding: .day, value: horizonDays, to: today) else { return [] }
        let earliestStart = now.addingTimeInterval(TimeInterval(leadMinutes * 60))

        switch rules.cadence {
        case let .daily(count):
            var result: [Date] = []
            var day = today
            while day < horizonEnd {
                // A day keeps what it has (a surprise that already came) and gets the rest of its count after it.
                let taken = planned.filter { calendar.isDate($0, inSameDayAs: day) }
                // The whole window's real length: on a DST change it isn't the clock-time difference.
                let dayGap = gap(count, minutes: window(on: day, rules, notBefore: day)?.minutes ?? 0)
                let notBefore = taken.max().map { max(earliestStart, $0.addingTimeInterval(TimeInterval(dayGap * 60))) }
                if isEnabled(day, rules), taken.count < count,
                   let window = window(on: day, rules, notBefore: notBefore ?? earliestStart) {
                    // A day that is already under way gets only as many surprises as fit with the day's gap.
                    let fitting = window.isPartial ? 1 + window.minutes / max(dayGap, 1) : count
                    result += slots(min(count - taken.count, fitting), in: window, gap: dayGap, using: &generator)
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return result

        case let .weekly(count):
            var result: [Date] = []
            var weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
            while weekStart < horizonEnd {
                guard let week = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { break }
                // A week keeps what it has (a surprise that already came, or the ones a replan left) and gets the rest
                // of its count on other days: one surprise left over mustn't stand for the whole week.
                let taken = planned.filter { week.contains($0) && $0 != week.end }
                if taken.count < count {
                    result += drawWeek(week, count: count, taken: taken, rules, notBefore: earliestStart, using: &generator)
                }
                weekStart = week.end
            }
            return result
        }
    }

    // MARK: Weeks

    private func drawWeek(
        _ week: DateInterval, count: Int, taken: [Date], _ rules: SurpriseRules, notBefore: Date,
        using generator: inout some RandomNumberGenerator
    ) -> [Date] {
        var enabledDays = 0
        // Enabled days from today on, with or without a surprise already; those with one.
        var daysAhead = 0
        var takenAhead = 0
        var candidates: [Window] = []
        let today = calendar.startOfDay(for: notBefore)
        var day = week.start
        while day < week.end {
            if isEnabled(day, rules) {
                enabledDays += 1
                if taken.contains(where: { calendar.isDate($0, inSameDayAs: day) }) {
                    if day >= today {
                        daysAhead += 1
                        takenAhead += 1
                    }
                } else if let window = window(on: day, rules, notBefore: notBefore) {
                    candidates.append(window)
                    daysAhead += 1
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        guard enabledDays > 0, !candidates.isEmpty else { return [] }
        // A week under way gets its share of the surprises for the enabled days still ahead, counting the ones it has
        // there: drawing again (a relaunch) adds none.
        let share = daysAhead == enabledDays
            ? count
            : Int((Double(count * daysAhead) / Double(enabledDays)).rounded())
        let wanted = min(share - takenAhead, count - taken.count, candidates.count)
        guard wanted > 0 else { return [] }
        let picked = candidates.shuffled(using: &generator).prefix(wanted)
        return picked.flatMap { slots(1, in: $0, gap: 0, using: &generator) }.sorted()
    }

    // MARK: Days

    private struct Window {
        var start: Date
        /// Length in whole minutes; both ends can be used.
        var minutes: Int
        /// Today, with part of the window already gone.
        var isPartial: Bool
    }

    private func isEnabled(_ day: Date, _ rules: SurpriseRules) -> Bool {
        rules.weekdayMask & (1 << (calendar.component(.weekday, from: day) - 1)) != 0
    }

    /// The day's window, cut to start no earlier than `notBefore` (rounded up to a whole minute).
    private func window(on day: Date, _ rules: SurpriseRules, notBefore: Date) -> Window? {
        guard let start = time(rules.earliestMinute, on: day), var end = time(rules.latestMinute, on: day) else { return nil }
        // A latest time the clocks skip (spring forward) comes out as the first time after the gap: the window
        // ends at the last minute before it instead.
        if calendar.component(.hour, from: end) * 60 + calendar.component(.minute, from: end) != rules.latestMinute {
            end.addTimeInterval(-60)
        }
        guard end >= start else { return nil }
        let from = max(start, roundedUpToMinute(notBefore))
        guard from <= end else { return nil }
        return Window(start: from, minutes: Int(end.timeIntervalSince(from) / 60), isPartial: from > start)
    }

    /// Clock time on a day. On a DST change the calendar moves a missing time forward.
    private func time(_ minute: Int, on day: Date) -> Date? {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
    }

    private func roundedUpToMinute(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.up) * 60)
    }

    /// The gap between a day's surprises, from its whole window: the full `minimumSeparation` when they fit,
    /// else an even share that leaves room for chance.
    private func gap(_ count: Int, minutes: Int) -> Int {
        guard count > 1 else { return minimumSeparation }
        return minutes >= minimumSeparation * (count - 1) ? minimumSeparation : minutes / count
    }

    /// `count` random minutes in the window, `preferred` minutes apart, or less when that doesn't fit what is left of it.
    private func slots(
        _ count: Int, in window: Window, gap preferred: Int, using generator: inout some RandomNumberGenerator
    ) -> [Date] {
        guard count > 0 else { return [] }
        let gap = count > 1 ? min(preferred, window.minutes / (count - 1)) : 0
        let free = window.minutes - (count - 1) * gap
        let offsets = (0..<count).map { _ in Int.random(in: 0...free, using: &generator) }.sorted()
        return offsets.enumerated().map { index, offset in
            window.start.addingTimeInterval(TimeInterval((offset + index * gap) * 60))
        }
    }
}
