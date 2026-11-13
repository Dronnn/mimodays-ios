import Core
import Foundation
import Testing
import TestSupport

struct CaptureTimeTests {
    private func zone(_ id: String) throws -> TimeZone { try #require(TimeZone(identifier: id)) }

    private func instant(_ iso: String) throws -> Date { try Date(iso, strategy: .iso8601) }

    @Test func localDayRoundTripsThroughKey() throws {
        let day = LocalDay(year: 2026, month: 11, day: 11)
        #expect(day.key == 2026_11_11)
        #expect(LocalDay(key: day.key) == day)
        #expect(LocalDay(key: 2026_13_01) == nil)
    }

    @Test func travelKeepsTheOriginalLocalDayAndTime() throws {
        // 2026-11-11 23:30 in Los Angeles is already Nov 12 in Berlin.
        let time = CaptureTime(instant: try instant("2026-11-12T07:30:00Z"), timeZone: try zone("America/Los_Angeles"))
        #expect(time.localDay == LocalDay(year: 2026, month: 11, day: 11))
        #expect(LocalDay(time.instant, in: try zone("Europe/Berlin")) == LocalDay(year: 2026, month: 11, day: 12))
        // iOS separates "PM" with a narrow no-break space.
        let shown = time.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US")).hour().minute())
        #expect(shown.replacingOccurrences(of: "\u{202F}", with: " ") == "11:30 PM")
    }

    @Test func sameInstantFallsOnDifferentDaysAcrossTheDateLine() throws {
        let now = try instant("2026-11-11T12:00:00Z")
        let samoa = CaptureTime(instant: now, timeZone: try zone("Pacific/Apia"))
        let americanSamoa = CaptureTime(instant: now, timeZone: try zone("Pacific/Pago_Pago"))
        #expect(samoa.localDay == LocalDay(year: 2026, month: 11, day: 12))
        #expect(americanSamoa.localDay == LocalDay(year: 2026, month: 11, day: 11))
    }

    @Test func repeatedHourAtFallBackKeepsDistinctOffsets() throws {
        // 2026-11-01 01:30 happens twice in Los Angeles: PDT (-7) then PST (-8).
        let la = try zone("America/Los_Angeles")
        let first = CaptureTime(instant: try instant("2026-11-01T08:30:00Z"), timeZone: la)
        let second = CaptureTime(instant: try instant("2026-11-01T09:30:00Z"), timeZone: la)
        #expect(first.utcOffset == -7 * 3600)
        #expect(second.utcOffset == -8 * 3600)
        #expect(first.localDay == second.localDay)
        #expect(first.instant < second.instant)
    }

    @Test func dayStartWhenMidnightIsSkipped() throws {
        // Santiago springs forward at midnight on 2026-09-06: the day starts at 01:00.
        let santiago = try zone("America/Santiago")
        let start = try #require(LocalDay(year: 2026, month: 9, day: 6).start(in: santiago))
        #expect(LocalDay(start, in: santiago) == LocalDay(year: 2026, month: 9, day: 6))
    }

    @Test func captureUsesInjectedClock() throws {
        let clock = TestDateProvider(try instant("2026-11-11T14:37:00Z"))
        let time = CaptureTime.now(clock, timeZone: try zone("Europe/Berlin"))
        #expect(time.instant == clock.now())
        #expect(time.timeZoneID == "Europe/Berlin")
    }

    @Test func unknownZoneFallsBackToGMT() {
        let time = CaptureTime(instant: Date(timeIntervalSince1970: 0), timeZoneID: "Mars/Olympus")
        #expect(time.timeZone == .gmt)
    }

    @Test func codableRoundTrip() throws {
        let time = CaptureTime(instant: try instant("2026-11-11T14:37:00Z"), timeZoneID: "Asia/Tokyo")
        let decoded = try JSONDecoder().decode(CaptureTime.self, from: JSONEncoder().encode(time))
        #expect(decoded == time)
    }
}
