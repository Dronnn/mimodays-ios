import Foundation

/// P8.2: what each widget shows for a payload, decided apart from drawing so it can be tested.
public enum WidgetContent {
    public enum OnThisDay: Equatable, Sendable {
        /// The gallery, loading, nothing written yet or a day the app hasn't worked out: no memory.
        case placeholder
        case locked
        /// Nothing on this day yet.
        case empty
        case memory(WidgetPayload.Day)
    }

    public enum Random: Equatable, Sendable {
        case placeholder
        case locked
        /// No memories yet.
        case empty
        /// `canSwap`: Another shows only with more than one to choose from.
        case memory(WidgetPayload.Memory, canSwap: Bool)
    }

    public static func onThisDay(_ payload: WidgetPayload?, today: Int) -> OnThisDay {
        guard let payload else { return .placeholder }
        if payload.isLocked { return .locked }
        guard (payload.firstDay...payload.lastDay).contains(today) else { return .placeholder }
        return payload.onThisDay.first { $0.today == today }.map(OnThisDay.memory) ?? .empty
    }

    public static func random(_ payload: WidgetPayload?, pick: UUID?) -> Random {
        guard let payload else { return .placeholder }
        if payload.isLocked { return .locked }
        guard let first = payload.random.first else { return .empty }
        let memory = payload.random.first { $0.id == pick } ?? first
        return .memory(memory, canSwap: payload.random.count > 1)
    }

    /// Another: any other memory of the pool, never the one on show.
    public static func another(after current: UUID?, in pool: [WidgetPayload.Memory], using generator: inout some RandomNumberGenerator) -> UUID? {
        let others = pool.filter { $0.id != current }
        return (others.randomElement(using: &generator) ?? pool.first)?.id
    }

    /// yyyymmdd for a date in `calendar`'s zone.
    public static func dayKey(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// Noon of a yyyymmdd day, for formatting it.
    public static func date(ofDay key: Int, calendar: Calendar) -> Date {
        let parts = DateComponents(year: key / 10_000, month: key / 100 % 100, day: key % 100, hour: 12)
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }
}
