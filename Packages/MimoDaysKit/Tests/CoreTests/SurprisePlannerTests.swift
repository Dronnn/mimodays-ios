import Core
import Foundation
import Testing
import TestSupport

struct SurprisePlannerTests {
    private static func calendar(_ zone: String = "Europe/Berlin", firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static func date(_ string: String, in calendar: Calendar) -> Date {
        let parts = string.split(whereSeparator: { "- :".contains($0) }).map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4]))!
    }

    private static let everyDay = 0b111_1111
    private static func rules(_ cadence: SurpriseRules.Cadence, mask: Int = everyDay, from: Int = 8 * 60, to: Int = 22 * 60) -> SurpriseRules {
        SurpriseRules(cadence: cadence, weekdayMask: mask, earliestMinute: from, latestMinute: to)
    }

    /// Minutes after local midnight.
    private static func minute(of date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return parts.hour! * 60 + parts.minute!
    }

    // Wednesday 2026-11-11, before the window opens.
    private let calendar = Self.calendar()
    private var morning: Date { Self.date("2026-11-11 06:00", in: calendar) }

    private func draw(_ rules: SurpriseRules, now: Date, planned: [Date] = [], seed: UInt64 = 1, planner: SurprisePlanner? = nil) -> [Date] {
        var generator = SeededRandomNumberGenerator(seed: seed)
        return (planner ?? SurprisePlanner(calendar: calendar)).draw(rules, now: now, planned: planned, using: &generator)
    }

    @Test(arguments: [(1, 1), (2, 2), (3, 3)])
    func dailyCadenceFillsEveryDayOfTheHorizon(perDay: Int, expected: Int) {
        let times = draw(Self.rules(.daily(perDay)), now: morning)
        let days = Dictionary(grouping: times) { calendar.startOfDay(for: $0) }
        #expect(days.count == 14)
        #expect(days.values.allSatisfy { $0.count == expected })
    }

    @Test(arguments: 1...40)
    func timesStayInTheWindowWholeMinutesAndTwoHoursApart(seed: UInt64) {
        let times = draw(Self.rules(.daily(3)), now: morning, seed: seed)
        #expect(times == times.sorted())
        for time in times {
            #expect((8 * 60...22 * 60).contains(Self.minute(of: time, calendar)))
            #expect(time.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) == 0)
        }
        for (a, b) in zip(times, times.dropFirst()) where calendar.isDate(a, inSameDayAs: b) {
            #expect(b.timeIntervalSince(a) >= 2 * 3600)
        }
    }

    @Test func narrowWindowShrinksTheGapToFit() {
        let times = draw(Self.rules(.daily(3), from: 12 * 60, to: 13 * 60), now: morning)
        let today = times.filter { calendar.isDate($0, inSameDayAs: morning) }
        #expect(today.count == 3)
        #expect(today.allSatisfy { (12 * 60...13 * 60).contains(Self.minute(of: $0, calendar)) })
        for (a, b) in zip(today, today.dropFirst()) { #expect(b.timeIntervalSince(a) >= 20 * 60) }
    }

    @Test func disabledWeekdaysGetNothing() {
        let weekdaysOnly = 0b011_1110 // Monday-Friday
        let times = draw(Self.rules(.daily(2), mask: weekdaysOnly), now: morning)
        #expect(times.allSatisfy { !calendar.isDateInWeekend($0) })
        #expect(times.count == 2 * 10)
    }

    @Test func noDaysMeansNoSurprises() {
        #expect(draw(Self.rules(.daily(1), mask: 0), now: morning).isEmpty)
    }

    @Test func aDayUnderWayUsesWhatIsLeftFifteenMinutesOut() {
        let evening = Self.date("2026-11-11 20:50", in: calendar)
        let today = draw(Self.rules(.daily(3)), now: evening).filter { calendar.isDate($0, inSameDayAs: evening) }
        // 21:05-22:00 leaves room for one surprise with the full gap.
        #expect(today.count == 1)
        #expect(today[0] >= Self.date("2026-11-11 21:05", in: calendar))
    }

    @Test func aDayWhoseWindowHasPassedStartsTomorrow() {
        let late = Self.date("2026-11-11 21:50", in: calendar)
        let times = draw(Self.rules(.daily(1)), now: late)
        #expect(!times.contains { calendar.isDate($0, inSameDayAs: late) })
        #expect(times.count == 13)
    }

    @Test func plannedDaysAreNeverDrawnAgain() {
        let first = draw(Self.rules(.daily(2)), now: morning)
        #expect(draw(Self.rules(.daily(2)), now: morning, planned: first, seed: 99).isEmpty)
        // A day later only the new last day of the horizon is drawn.
        let tomorrow = Self.date("2026-11-12 06:00", in: calendar)
        let added = draw(Self.rules(.daily(2)), now: tomorrow, planned: first, seed: 99)
        #expect(added.count == 2)
        #expect(added.allSatisfy { calendar.isDate($0, inSameDayAs: Self.date("2026-11-25 12:00", in: calendar)) })
    }

    @Test func sameSeedSamePlan() {
        #expect(draw(Self.rules(.daily(2)), now: morning, seed: 7) == draw(Self.rules(.daily(2)), now: morning, seed: 7))
        #expect(draw(Self.rules(.daily(2)), now: morning, seed: 7) != draw(Self.rules(.daily(2)), now: morning, seed: 8))
    }

    /// Over many seeds a daily surprise lands in every hour of the window, none far more often than the rest.
    @Test func dailyTimesSpreadOverTheWholeWindow() {
        var perHour = [Int: Int]()
        for seed in UInt64(1)...300 {
            for time in draw(Self.rules(.daily(1)), now: morning, seed: seed) {
                perHour[Self.minute(of: time, calendar) / 60, default: 0] += 1
            }
        }
        #expect(Set(perHour.keys).isSuperset(of: 8..<22))
        let expected = Double(300 * 14) / 14 // 14 hours in the window
        #expect(perHour.filter { (8..<22).contains($0.key) }.values.allSatisfy { Double($0) > expected * 0.7 && Double($0) < expected * 1.3 })
    }

    // MARK: Weekly

    @Test(arguments: 1...20)
    func threeAWeekPicksThreeDifferentDaysInEveryFullWeek(seed: UInt64) {
        let monday = Self.date("2026-11-09 06:00", in: calendar)
        let times = draw(Self.rules(.weekly(3)), now: monday, seed: seed)
        let weeks = Dictionary(grouping: times) { calendar.dateInterval(of: .weekOfYear, for: $0)!.start }
        #expect(weeks.count == 2)
        for week in weeks.values {
            #expect(week.count == 3)
            #expect(Set(week.map { calendar.startOfDay(for: $0) }).count == 3)
        }
    }

    @Test func threeAWeekUsesEveryEnabledDayAlike() {
        let monday = Self.date("2026-11-09 06:00", in: calendar)
        var perWeekday = [Int: Int]()
        for seed in UInt64(1)...300 {
            for time in draw(Self.rules(.weekly(3)), now: monday, seed: seed) {
                perWeekday[calendar.component(.weekday, from: time), default: 0] += 1
            }
        }
        let expected = Double(300 * 2 * 3) / 7
        #expect(perWeekday.count == 7)
        #expect(perWeekday.values.allSatisfy { Double($0) > expected * 0.75 && Double($0) < expected * 1.25 })
    }

    @Test func weeksFollowTheCalendarsFirstWeekday() {
        let sundayFirst = Self.calendar(firstWeekday: 1)
        let saturday = Self.date("2026-11-14 06:00", in: sundayFirst)
        var generator = SeededRandomNumberGenerator(seed: 3)
        let times = SurprisePlanner(calendar: sundayFirst).draw(Self.rules(.weekly(3)), now: saturday, planned: [], using: &generator)
        let weekStarts = Set(times.map { sundayFirst.component(.weekday, from: sundayFirst.dateInterval(of: .weekOfYear, for: $0)!.start) })
        #expect(weekStarts == [1])
    }

    @Test func fewerEnabledDaysThanSurprisesMeansOneOnEach() {
        let tuesdayAndFriday = 0b010_0100
        let monday = Self.date("2026-11-09 06:00", in: calendar)
        let times = draw(Self.rules(.weekly(3), mask: tuesdayAndFriday), now: monday)
        #expect(times.count == 4)
        #expect(Set(times.map { calendar.component(.weekday, from: $0) }) == [3, 6])
    }

    @Test func aWeekUnderWayGetsItsShare() {
        // Friday morning: Fri, Sat, Sun left of 7 enabled days -> 3 × 3/7 ≈ 1.
        let friday = Self.date("2026-11-13 06:00", in: calendar)
        let times = draw(Self.rules(.weekly(3)), now: friday)
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: friday)!
        #expect(times.filter { thisWeek.contains($0) }.count == 1)
    }

    @Test func aPlannedWeekIsNotDrawnAgain() {
        let monday = Self.date("2026-11-09 06:00", in: calendar)
        let first = draw(Self.rules(.weekly(3)), now: monday)
        #expect(draw(Self.rules(.weekly(3)), now: monday, planned: first, seed: 5).isEmpty)
    }

    // MARK: Time changes

    @Test func daylightSavingDaysKeepTheirLocalWindow() {
        let spring = Self.date("2026-03-27 06:00", in: calendar) // DST starts 2026-03-29 in Berlin
        for seed in UInt64(1)...20 {
            for time in draw(Self.rules(.daily(3)), now: spring, seed: seed) {
                #expect((8 * 60...22 * 60).contains(Self.minute(of: time, calendar)))
            }
        }
        let autumn = Self.date("2026-10-23 06:00", in: calendar) // DST ends 2026-10-25
        let times = draw(Self.rules(.daily(2)), now: autumn)
        #expect(times.count == 28)
        #expect(times.allSatisfy { (8 * 60...22 * 60).contains(Self.minute(of: $0, calendar)) })
    }

    @Test func timesFollowTheCalendarsTimeZone() {
        let tokyo = Self.calendar("Asia/Tokyo")
        let now = Self.date("2026-11-11 06:00", in: tokyo)
        var generator = SeededRandomNumberGenerator(seed: 1)
        let times = SurprisePlanner(calendar: tokyo).draw(Self.rules(.daily(1)), now: now, planned: [], using: &generator)
        #expect(times.allSatisfy { (8 * 60...22 * 60).contains(Self.minute(of: $0, tokyo)) })
    }

    @Test func horizonIsConfigurable() {
        var planner = SurprisePlanner(calendar: calendar)
        planner.horizonDays = 3
        #expect(draw(Self.rules(.daily(1)), now: morning, planner: planner).count == 3)
    }
}
