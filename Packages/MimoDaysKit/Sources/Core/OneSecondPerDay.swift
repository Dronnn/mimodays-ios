import Foundation

/// P8.9: a movie of one second for each day of a month or a year that has a moment (Andrew, 2026-11-21: the day's
/// first surprise, else its earliest moment; any day's moment can be changed by hand).
public enum OneSecondPerDay {
    public struct Candidate: Equatable, Sendable {
        public var id: UUID
        public var capturedAt: Date
        /// Local calendar day (yyyymmdd).
        public var day: Int
        public var isSurprise: Bool
        /// Its media is there and plays; a broken one gives way to the day's next.
        public var isPlayable: Bool

        public init(id: UUID, capturedAt: Date, day: Int, isSurprise: Bool, isPlayable: Bool = true) {
            self.id = id
            self.capturedAt = capturedAt
            self.day = day
            self.isSurprise = isSurprise
            self.isPlayable = isPlayable
        }
    }

    /// One day of the movie: the moment it shows and every one it could ("Change moment"), in pick order.
    public struct Day: Equatable, Sendable {
        public var day: Int
        public var choices: [UUID]
        public var picked: UUID
    }

    /// How a clip fills its second: played from its start, then its last frame held for the rest.
    public struct Beat: Equatable, Sendable {
        public var play: Double
        public var hold: Double
    }

    public static let seconds = 1.0

    /// Days oldest first, each with a playable moment: surprises first, then the rest, each earliest first, the id
    /// deciding a tie.
    public static func days(_ candidates: [Candidate]) -> [Day] {
        Dictionary(grouping: candidates.filter(\.isPlayable), by: \.day)
            .sorted { $0.key < $1.key }
            .map { day, moments in
                let ordered = moments.sorted {
                    ($0.isSurprise ? 0 : 1, $0.capturedAt, $0.id.uuidString) < ($1.isSurprise ? 0 : 1, $1.capturedAt, $1.id.uuidString)
                }.map(\.id)
                return Day(day: day, choices: ordered, picked: ordered[0])
            }
    }

    /// A photo (nil) holds the whole second; a video plays its first second, or all of a shorter one and then holds.
    public static func beat(videoDuration: Double?) -> Beat {
        guard let videoDuration else { return Beat(play: 0, hold: seconds) }
        let play = min(max(videoDuration, 0), seconds)
        return Beat(play: play, hold: seconds - play)
    }

    /// The month's days as day keys (yyyymmdd); `month` is yyyymm.
    public static func days(ofMonth month: Int) -> ClosedRange<Int> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = calendar.date(from: DateComponents(year: month / 100, month: month % 100, day: 1)) ?? .distantPast
        let count = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        return (month * 100 + 1)...(month * 100 + count)
    }

    public static func days(ofYear year: Int) -> ClosedRange<Int> {
        (year * 10_000 + 101)...(year * 10_000 + 1231)
    }
}
