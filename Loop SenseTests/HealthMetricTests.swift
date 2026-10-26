import Foundation
import Testing
@testable import Loop_Sense

struct HealthMetricTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    private func day(_ d: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d))!
    }

    /// 14 days of resting HR at 55 and HRV at 50, ending the day before `day(22)`.
    private var history: [DailySnapshot] {
        (8...21).map { d in
            var s = DailySnapshot(day: day(d))
            s.restingHR = 55; s.hrv = 50; s.steps = 8000
            return s
        }
    }

    @Test func lowerRestingHRIsGood() throws {
        let c = try #require(UsualComparison(metric: .restingHR, value: 53, day: day(22), history: history, calendar: calendar))
        #expect(c.usual == 55)
        #expect(c.direction == .down)
        #expect(c.isGood)
        #expect(c.text(for: .restingHR) == "▼ 2 vs usual")
    }

    @Test func higherRestingHRIsAmber() throws {
        let c = try #require(UsualComparison(metric: .restingHR, value: 59, day: day(22), history: history, calendar: calendar))
        #expect(c.direction == .up)
        #expect(!c.isGood)
        #expect(c.text(for: .restingHR) == "▲ 4 vs usual")
    }

    @Test func lowerHRVIsAmber() throws {
        let c = try #require(UsualComparison(metric: .hrv, value: 42, day: day(22), history: history, calendar: calendar))
        #expect(!c.isGood)
        #expect(c.text(for: .hrv) == "▼ 8 vs usual")
    }

    @Test func smallChangesReadAsUsual() throws {
        let c = try #require(UsualComparison(metric: .restingHR, value: 56, day: day(22), history: history, calendar: calendar))
        #expect(c.direction == .same)
        #expect(c.isGood)
        #expect(c.text(for: .restingHR) == "≈ usual")
    }

    @Test func stepsUseThousandsSeparators() throws {
        let c = try #require(UsualComparison(metric: .steps, value: 9500, day: day(22), history: history, calendar: calendar))
        #expect(c.text(for: .steps) == "▲ \(1500.formatted()) vs usual")
    }

    @Test func usualNeedsAtLeastThreeDays() {
        let short = Array(history.suffix(2))
        #expect(UsualComparison(metric: .restingHR, value: 50, day: day(22), history: short, calendar: calendar) == nil)
    }

    @Test func usualOnlyLooksAtThePrevious14Days() throws {
        var old = DailySnapshot(day: day(1)); old.restingHR = 90   // too old to count
        var today = DailySnapshot(day: day(22)); today.restingHR = 99   // the day itself doesn't count
        let c = try #require(UsualComparison(metric: .restingHR, value: 55, day: day(22), history: history + [old, today], calendar: calendar))
        #expect(c.usual == 55)
    }

    @Test func stepsAreYesterdaysAndOvernightIsLastNights() {
        var yesterday = DailySnapshot(day: day(21)); yesterday.steps = 7000; yesterday.restingHR = 54
        var today = DailySnapshot(day: day(22)); today.steps = 1200; today.restingHR = 52
        let snaps = [yesterday, today]
        let now = calendar.date(byAdding: .hour, value: 9, to: day(22))!
        #expect(HealthMetric.steps.days(snaps, range: .day, today: now, calendar: calendar).map(\.day) == [day(21)])
        #expect(HealthMetric.restingHR.days(snaps, range: .day, today: now, calendar: calendar).map(\.day) == [day(22)])
        #expect(HealthMetric.restingHR.days(history + [today], range: .week, today: now, calendar: calendar).count == 7)
    }

    @Test func tileHiddenWithoutData() {
        let snaps = history   // no oxygen anywhere
        #expect(HealthMetric.oxygen.days(snaps, range: .month, today: day(22), calendar: calendar).isEmpty)
    }

    @Test func missingMetricsForSettings() {
        #expect(HealthCoverage.missing(in: history) == [.respiratoryRate, .oxygen, .activeEnergy])
        #expect(HealthCoverage.missing(in: []) == HealthMetric.allCases)
    }
}
