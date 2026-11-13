import Foundation
import Persistence

/// What OB-07 collects. Always valid: at least one day is on, and the window is at least an hour.
struct ReminderSchedule: Equatable {
    var frequency: SurpriseFrequency = .onceADay
    /// Bit 0 = Sunday ... bit 6 = Saturday, like `SurpriseSchedule.weekdayMask`.
    private(set) var weekdayMask = 0b111_1111
    /// Minutes after local midnight; spec default 08:00-22:00.
    private(set) var earliestMinute = 8 * 60
    private(set) var latestMinute = 22 * 60

    static let minimumWindow = 60
    static let lastMinute = 24 * 60 - 1

    /// `weekday` is a `Calendar` weekday, 1 = Sunday.
    func isOn(_ weekday: Int) -> Bool {
        weekdayMask & (1 << (weekday - 1)) != 0
    }

    /// Turning off the last remaining day does nothing.
    mutating func toggle(_ weekday: Int) {
        let mask = weekdayMask ^ (1 << (weekday - 1))
        if mask != 0 { weekdayMask = mask }
    }

    var earliestRange: ClosedRange<Int> { 0...(latestMinute - Self.minimumWindow) }
    var latestRange: ClosedRange<Int> { (earliestMinute + Self.minimumWindow)...Self.lastMinute }

    mutating func setEarliest(_ minute: Int) {
        earliestMinute = min(max(minute, earliestRange.lowerBound), earliestRange.upperBound)
    }

    mutating func setLatest(_ minute: Int) {
        latestMinute = min(max(minute, latestRange.lowerBound), latestRange.upperBound)
    }

    /// O08b body: cadence and hours, e.g. "Once a day, between 8:00 AM and 10:00 PM. ..."
    func summary(calendar: Calendar, locale: Locale) -> LocalizedStringResource {
        let start = Self.time(earliestMinute, calendar: calendar, locale: locale)
        let end = Self.time(latestMinute, calendar: calendar, locale: locale)
        var resource = switch frequency {
        case .threeAWeek:
            LocalizedStringResource(
                "Three times a week, between \(start) and \(end). You can change this any time in Settings.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .onceADay:
            LocalizedStringResource(
                "Once a day, between \(start) and \(end). You can change this any time in Settings.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .twiceADay:
            LocalizedStringResource(
                "Twice a day, between \(start) and \(end). You can change this any time in Settings.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        case .threeADay:
            LocalizedStringResource(
                "Three times a day, between \(start) and \(end). You can change this any time in Settings.",
                bundle: .atURL(Bundle.module.bundleURL)
            )
        }
        resource.locale = locale
        return resource
    }

    // MARK: Minutes <-> clock time

    /// A clock time on a fixed day without DST changes, for pickers and formatting.
    static func date(_ minute: Int, calendar: Calendar) -> Date {
        let day = calendar.date(from: DateComponents(year: 2001, month: 1, day: 1)) ?? Date(timeIntervalSinceReferenceDate: 0)
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day) ?? day
    }

    static func minute(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func time(_ minute: Int, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        return date(minute, calendar: calendar).formatted(style)
    }
}

extension SurpriseFrequency {
    /// Segment labels in O07.
    var label: LocalizedStringResource {
        switch self {
        case .threeAWeek: LocalizedStringResource("3 a week", bundle: .atURL(Bundle.module.bundleURL))
        case .onceADay: LocalizedStringResource("Once a day", bundle: .atURL(Bundle.module.bundleURL))
        case .twiceADay: LocalizedStringResource("Twice", bundle: .atURL(Bundle.module.bundleURL))
        case .threeADay: LocalizedStringResource("3 a day", bundle: .atURL(Bundle.module.bundleURL))
        }
    }
}

extension Calendar {
    /// Weekdays (1 = Sunday) starting on this calendar's first day of the week.
    var orderedWeekdays: [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }
}
