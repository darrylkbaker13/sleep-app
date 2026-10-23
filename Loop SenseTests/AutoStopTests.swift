import Foundation
import Testing
@testable import Loop_Sense

struct AutoStopTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func eveningStartStopsNextMorning() {
        #expect(AutoStop.stopDate(after: date(21, 23, 0), minutes: 7 * 60 + 30, calendar: calendar) == date(22, 7, 30))
    }

    @Test func afterMidnightStartStopsSameMorning() {
        #expect(AutoStop.stopDate(after: date(22, 1, 15), minutes: 7 * 60 + 30, calendar: calendar) == date(22, 7, 30))
    }

    @Test func startCloseToStopTimeWaitsForTheNextDay() {
        // Starting at 07:00 with 07:30 set: under the 1-hour minimum, so it's tomorrow's 07:30.
        #expect(AutoStop.stopDate(after: date(22, 7, 0), minutes: 7 * 60 + 30, calendar: calendar) == date(23, 7, 30))
    }

    @Test func startJustOverAnHourBeforeStopsToday() {
        #expect(AutoStop.stopDate(after: date(22, 6, 29), minutes: 7 * 60 + 30, calendar: calendar) == date(22, 7, 30))
    }

    @Test func clocksGoingBackOvernight() {
        // UK clocks go back on 25 Oct 2026; a 23:00 start still stops at 07:30 local time.
        #expect(AutoStop.stopDate(after: date(24, 23, 0), minutes: 7 * 60 + 30, calendar: calendar) == date(25, 7, 30))
    }

    @Test func pickerRoundTrip() {
        for minutes in [0, 7 * 60 + 30, 23 * 60 + 59] {
            #expect(AutoStop.minutes(from: AutoStop.pickerDate(minutes: minutes, calendar: calendar), calendar: calendar) == minutes)
        }
    }

    @Test func defaultIsHalfPastSeven() {
        #expect(AutoStop.defaultMinutes == 450)
    }
}
