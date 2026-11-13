@testable import AppFeature
import Foundation
import Persistence
import Testing

struct ReminderScheduleTests {
    @Test func defaultsMatchTheSpec() {
        let schedule = ReminderSchedule()
        let stored = SurpriseSchedule()
        #expect(schedule.frequency == .onceADay)
        #expect(schedule.weekdayMask == stored.weekdayMask)
        #expect(schedule.earliestMinute == stored.earliestMinute)
        #expect(schedule.latestMinute == stored.latestMinute)
    }

    @Test func maskBitsFollowCalendarWeekdays() {
        var schedule = ReminderSchedule()
        schedule.toggle(1)
        #expect(!schedule.isOn(1))
        #expect(schedule.weekdayMask == 0b111_1110)
        schedule.toggle(7)
        #expect(schedule.weekdayMask == 0b011_1110)
        schedule.toggle(1)
        #expect(schedule.isOn(1))
    }

    @Test func theLastDayCannotBeTurnedOff() {
        var schedule = ReminderSchedule()
        for day in 1...6 { schedule.toggle(day) }
        #expect(schedule.weekdayMask == 0b100_0000)
        schedule.toggle(7)
        #expect(schedule.isOn(7))
    }

    @Test func windowStaysAtLeastAnHour() {
        var schedule = ReminderSchedule()
        schedule.setEarliest(23 * 60)
        #expect(schedule.earliestMinute == 21 * 60)
        schedule.setLatest(0)
        #expect(schedule.latestMinute == 22 * 60)
        schedule.setLatest(23 * 60 + 59)
        schedule.setEarliest(9 * 60 + 30)
        #expect(schedule.earliestMinute == 9 * 60 + 30)
        #expect(schedule.latestRange == (10 * 60 + 30)...(23 * 60 + 59))
        #expect(schedule.earliestRange == 0...(22 * 60 + 59))
    }

    @Test(arguments: [(1, [1, 2, 3, 4, 5, 6, 7]), (2, [2, 3, 4, 5, 6, 7, 1]), (7, [7, 1, 2, 3, 4, 5, 6])])
    func weekStartsOnTheCalendarsFirstDay(firstWeekday: Int, order: [Int]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        #expect(calendar.orderedWeekdays == order)
    }

    @Test func minutesRoundTripThroughClockTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        for minute in [0, 2 * 60 + 30, 8 * 60, 22 * 60, 23 * 60 + 59] {
            #expect(ReminderSchedule.minute(of: ReminderSchedule.date(minute, calendar: calendar), calendar: calendar) == minute)
        }
    }

    @Test func summaryNamesCadenceAndHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let locale = Locale(identifier: "en_US")
        var schedule = ReminderSchedule()
        let text = String(localized: schedule.summary(calendar: calendar, locale: locale))
        #expect(text == "Once a day, between 8:00\u{202F}AM and 10:00\u{202F}PM. You can change this any time in Settings.")
        schedule.frequency = .threeAWeek
        #expect(String(localized: schedule.summary(calendar: calendar, locale: locale)).hasPrefix("Three times a week, between 8:00"))
    }

    @Test func summaryUsesTheLocalesClock() {
        let calendar = Calendar(identifier: .gregorian)
        let text = String(localized: ReminderSchedule().summary(calendar: calendar, locale: Locale(identifier: "en_GB")))
        #expect(text.contains("between 8:00 and 22:00"))
    }
}
