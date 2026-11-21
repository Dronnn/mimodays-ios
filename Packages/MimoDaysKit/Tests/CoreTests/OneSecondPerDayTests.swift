@testable import Core
import Foundation
import Testing

/// P8.9: one second for each day with a moment, the day's first surprise, else its earliest moment.
struct OneSecondPerDayTests {
    private func candidate(_ day: Int, hour: Double, surprise: Bool = false, playable: Bool = true, id: UUID = UUID()) -> OneSecondPerDay.Candidate {
        OneSecondPerDay.Candidate(
            id: id, capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(day) * 86_400 + hour * 3_600), day: day,
            isSurprise: surprise, isPlayable: playable
        )
    }

    @Test func theFirstSurpriseElseTheEarliestMoment() {
        let early = candidate(20261102, hour: 8)
        let laterSurprise = candidate(20261102, hour: 18, surprise: true)
        let firstSurprise = candidate(20261102, hour: 12, surprise: true)
        let onlyOne = candidate(20261101, hour: 20)
        let days = OneSecondPerDay.days([early, laterSurprise, onlyOne, firstSurprise])
        // Days oldest first; empty days skipped.
        #expect(days.map(\.day) == [20261101, 20261102])
        #expect(days[0].picked == onlyOne.id)
        #expect(days[1].picked == firstSurprise.id)
        // What "Change moment" offers, in the same order.
        #expect(days[1].choices == [firstSurprise.id, laterSurprise.id, early.id])
    }

    /// Two at the same instant: the id decides, the same way every time.
    @Test func tiesGoByID() {
        let a = candidate(20261103, hour: 9, id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!)
        let b = candidate(20261103, hour: 9, id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!)
        #expect(OneSecondPerDay.days([b, a]).first?.picked == a.id)
    }

    /// A broken moment is skipped for the day's next; a day with none left drops out.
    @Test func brokenMomentsAreSkipped() {
        let broken = candidate(20261104, hour: 7, surprise: true, playable: false)
        let next = candidate(20261104, hour: 9)
        let onlyBroken = candidate(20261105, hour: 9, playable: false)
        let days = OneSecondPerDay.days([broken, next, onlyBroken])
        #expect(days.map(\.day) == [20261104])
        #expect(days[0].picked == next.id && days[0].choices == [next.id])
    }

    /// A photo holds one second; a video plays one second from its start; a shorter one holds its last frame.
    @Test func everyBeatIsOneSecond() {
        #expect(OneSecondPerDay.beat(videoDuration: nil) == .init(play: 0, hold: 1))
        #expect(OneSecondPerDay.beat(videoDuration: 7.5) == .init(play: 1, hold: 0))
        #expect(OneSecondPerDay.beat(videoDuration: 0.4) == .init(play: 0.4, hold: 0.6))
        for duration in [nil, 0.1, 0.4, 1, 3] as [Double?] {
            let beat = OneSecondPerDay.beat(videoDuration: duration)
            #expect(abs(beat.play + beat.hold - 1) < 0.000_001)
        }
    }

    /// Periods as day keys, February with its leap day.
    @Test func monthsAndYears() {
        #expect(OneSecondPerDay.days(ofMonth: 202402) == 20240201...20240229)
        #expect(OneSecondPerDay.days(ofMonth: 202502) == 20250201...20250228)
        #expect(OneSecondPerDay.days(ofMonth: 202612) == 20261201...20261231)
        #expect(OneSecondPerDay.days(ofYear: 2024) == 20240101...20241231)
    }
}
