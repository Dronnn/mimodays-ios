@testable import Core
import Foundation
import Testing

/// 11.5 Automatic balanced selection: spread over the period, far-apart moments first, deterministic with a seed.
struct MovieSelectionTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// `perDay` photos on each of `days` days, two hours apart.
    private func candidates(days: Int, perDay: Int) -> [MovieSelection.Candidate] {
        (0..<days).flatMap { day in
            (0..<perDay).map { index in
                MovieSelection.Candidate(
                    id: UUID(), capturedAt: start.addingTimeInterval(Double(day) * 86_400 + Double(index) * 7_200), day: 20261001 + day
                )
            }
        }
    }

    @Test func fullTakesEveryMomentInTheOrderTheyHappened() {
        let all = candidates(days: 3, perDay: 2).shuffled()
        let picked = MovieSelection.pick(all, target: nil, seed: 1)
        #expect(picked == all.sorted { $0.capturedAt < $1.capturedAt }.map(\.id))
    }

    @Test func theSameSeedPicksTheSameMoments() {
        let all = candidates(days: 21, perDay: 3)
        let first = MovieSelection.pick(all, target: 60, seed: 42)
        #expect(MovieSelection.pick(all.reversed(), target: 60, seed: 42) == first)
        #expect(Set((1...5).map { MovieSelection.pick(all, target: 60, seed: $0) }).count > 1, "other seeds pick otherwise")
    }

    /// F01/F05: about a minute out of a month - every day before any day twice, and never past the minute.
    @Test func quickSpreadsOverEveryDayFirst() {
        let all = candidates(days: 21, perDay: 2)
        let picked = MovieSelection.pick(all, target: 60, seed: 7)
        #expect(picked.count == 24)
        let chosen = all.filter { picked.contains($0.id) }
        #expect(Set(chosen.map(\.day)).count == 21)
        #expect(MovieSelection.seconds(of: chosen) <= 60)
    }

    /// Fewer clips than days: the ones taken still cover the start, the end and the middle.
    @Test func aShortPickStillSpansThePeriod() {
        let all = candidates(days: 30, perDay: 1)
        let picked = MovieSelection.pick(all, target: 5 * MovieSelection.photoSeconds, seed: 3)
        let days = all.filter { picked.contains($0.id) }.map(\.day).sorted()
        #expect(days.count == 5)
        #expect(days.first == 20261001)
        #expect(days.last == 20261030)
        #expect(zip(days, days.dropFirst()).allSatisfy { $1 - $0 >= 5 })
    }

    /// Two photos seconds apart are near-duplicates: the evening one goes in before the second of them.
    @Test func farApartMomentsComeBeforeNearDuplicates() {
        let noon = MovieSelection.Candidate(id: UUID(), capturedAt: start, day: 20261001)
        let noonAgain = MovieSelection.Candidate(id: UUID(), capturedAt: start.addingTimeInterval(5), day: 20261001)
        let evening = MovieSelection.Candidate(id: UUID(), capturedAt: start.addingTimeInterval(6 * 3_600), day: 20261001)
        for seed in 0..<20 as Range<UInt64> {
            let picked = Set(MovieSelection.pick([noon, noonAgain, evening], target: 2 * MovieSelection.photoSeconds, seed: seed))
            #expect(picked.contains(evening.id))
            #expect(picked.count == 2)
        }
    }

    @Test func videosPlayAtMostFiveSeconds() {
        #expect(MovieSelection.seconds(of: .init(id: UUID(), capturedAt: start, day: 1, videoDuration: 3)) == 3)
        #expect(MovieSelection.seconds(of: .init(id: UUID(), capturedAt: start, day: 1, videoDuration: 14)) == 5)
        #expect(MovieSelection.seconds(of: .init(id: UUID(), capturedAt: start, day: 1)) == 2.5)
    }

    @Test func spreadOrderVisitsEveryIndexOnceEndsFirst() {
        #expect(MovieSelection.spreadOrder(0) == [])
        #expect(MovieSelection.spreadOrder(1) == [0])
        #expect(MovieSelection.spreadOrder(5) == [0, 4, 2, 1, 3])
        #expect(Set(MovieSelection.spreadOrder(31)) == Set(0..<31))
    }
}
