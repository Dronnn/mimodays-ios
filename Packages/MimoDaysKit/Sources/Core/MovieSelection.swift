import Foundation

/// The automatic pick for a movie (doc 01 §11): spread over the whole period rather than the latest days,
/// moments far apart in time before ones taken seconds apart, never a moment twice. The same seed picks the same.
public enum MovieSelection {
    public struct Candidate: Equatable, Sendable {
        public var id: UUID
        public var capturedAt: Date
        /// Local calendar day (yyyymmdd).
        public var day: Int
        /// Seconds of video; nil for a photo.
        public var videoDuration: Double?

        public init(id: UUID, capturedAt: Date, day: Int, videoDuration: Double? = nil) {
            self.id = id
            self.capturedAt = capturedAt
            self.day = day
            self.videoDuration = videoDuration
        }
    }

    /// A photo holds the screen this long (F06: "2.5 s").
    public static let photoSeconds = 2.5
    /// A video plays at most this long before the next clip.
    public static let longestVideoSeconds = 5.0
    /// Fewer moments than this don't make a movie (F16): we never repeat or pad clips.
    public static let minimumMoments = 5

    public static func seconds(of candidate: Candidate) -> Double {
        candidate.videoDuration.map { min($0, longestVideoSeconds) } ?? photoSeconds
    }

    /// How long these clips play together.
    public static func seconds(of candidates: [Candidate]) -> Double {
        candidates.reduce(0) { $0 + seconds(of: $1) }
    }

    /// The picked moments in the order they happened. `target` nil takes every moment (Full); otherwise clips are
    /// added until the next one would run past it. Each round takes one more moment from every day, the days in an
    /// order that keeps whatever is taken spread over the period.
    public static func pick(_ candidates: [Candidate], target: Double?, seed: UInt64) -> [UUID] {
        let sorted = candidates.sorted { ($0.capturedAt, $0.id.uuidString) < ($1.capturedAt, $1.id.uuidString) }
        guard let target else { return sorted.map(\.id) }
        var generator = SeededRandomNumberGenerator(seed: seed)
        // Shuffled day by day in calendar order: a dictionary's own order changes from run to run.
        var remaining: [Int: [Candidate]] = [:]
        for (day, moments) in Dictionary(grouping: sorted, by: \.day).sorted(by: { $0.key < $1.key }) {
            remaining[day] = moments.shuffled(using: &generator)
        }
        var picked: [Int: [Candidate]] = [:]
        var total = 0.0
        var full = false
        while !full, !remaining.isEmpty {
            let days = remaining.keys.sorted()
            for index in spreadOrder(days.count) {
                let day = days[index]
                guard let choice = farthest(remaining[day] ?? [], from: picked[day] ?? []) else { continue }
                let length = seconds(of: choice)
                if total + length > target {
                    full = true
                    break
                }
                total += length
                picked[day, default: []].append(choice)
                remaining[day]?.removeAll { $0.id == choice.id }
                if remaining[day]?.isEmpty == true { remaining[day] = nil }
            }
        }
        return picked.values.joined().sorted { ($0.capturedAt, $0.id.uuidString) < ($1.capturedAt, $1.id.uuidString) }.map(\.id)
    }

    /// The moment farthest in time from those already taken that day; the first of the (shuffled) list on a tie.
    private static func farthest(_ options: [Candidate], from taken: [Candidate]) -> Candidate? {
        var best: (candidate: Candidate, gap: TimeInterval)?
        for option in options {
            let gap = taken.map { abs($0.capturedAt.timeIntervalSince(option.capturedAt)) }.min() ?? .infinity
            if best == nil || gap > best!.gap { best = (option, gap) }
            if gap == .infinity { break }
        }
        return best?.candidate
    }

    /// 0..<count, each next index the farthest from those before it (first, last, middle, quarters, ...):
    /// stopping anywhere leaves an even spread.
    static func spreadOrder(_ count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var order = [0]
        var distance = (0..<count).map { $0 }
        while order.count < count {
            var next = 0
            for index in 0..<count where distance[index] > distance[next] { next = index }
            order.append(next)
            for index in 0..<count { distance[index] = min(distance[index], abs(index - next)) }
        }
        return order
    }
}
