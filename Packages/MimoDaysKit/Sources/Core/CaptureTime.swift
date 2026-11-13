import Foundation

/// A calendar day in the place a moment happened, independent of where the person is now.
public struct LocalDay: Hashable, Comparable, Codable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `timeZone`.
    public init(_ date: Date, in timeZone: TimeZone) {
        let components = Self.calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }

    /// Stored form: yyyymmdd, sortable and usable in predicates.
    public init?(key: Int) {
        let day = LocalDay(year: key / 10_000, month: key / 100 % 100, day: key % 100)
        guard (1...12).contains(day.month), (1...31).contains(day.day) else { return nil }
        self = day
    }

    public var key: Int { year * 10_000 + month * 100 + day }

    /// Midnight starting this day in `timeZone` (first valid instant if midnight is skipped by DST).
    public func start(in timeZone: TimeZone) -> Date? {
        Self.calendar(timeZone).date(from: DateComponents(year: year, month: month, day: day))
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool { lhs.key < rhs.key }

    private static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// When a moment was captured: the instant (UTC) plus the time zone it was captured in.
/// The time zone is kept so a moment always shows its original local time and day, even after travel.
public struct CaptureTime: Hashable, Codable, Sendable {
    public var instant: Date
    public var timeZoneID: String

    public init(instant: Date, timeZone: TimeZone) {
        self.instant = instant
        timeZoneID = timeZone.identifier
    }

    public init(instant: Date, timeZoneID: String) {
        self.instant = instant
        self.timeZoneID = timeZoneID
    }

    /// Capture now, wherever the device is.
    public static func now(_ clock: some DateProvider = SystemDateProvider(), timeZone: TimeZone = .current) -> CaptureTime {
        CaptureTime(instant: clock.now(), timeZone: timeZone)
    }

    /// Falls back to GMT if the stored identifier is unknown on this OS version.
    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }

    public var localDay: LocalDay { LocalDay(instant, in: timeZone) }

    /// Offset from GMT at capture, in seconds (includes DST).
    public var utcOffset: Int { timeZone.secondsFromGMT(for: instant) }

    /// Formats the original local time, e.g. "6:42 PM" where it was taken.
    public func formatted(_ style: Date.FormatStyle = .dateTime.hour().minute()) -> String {
        var style = style
        style.timeZone = timeZone
        return instant.formatted(style)
    }
}
