import Foundation
import Testing
@testable import Loop_Sense

struct DailySnapshotTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/London")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func stage(_ stage: SleepStage, _ from: Date, _ minutes: Double, source: String = "com.garmin.connect.mobile") -> SleepInterval {
        SleepInterval(start: from, end: from.addingTimeInterval(minutes * 60), stage: stage, source: source)
    }

    private func sample(_ at: Date, _ value: Double, source: String = "com.garmin.connect.mobile") -> SnapshotBuilder.Sample {
        SnapshotBuilder.Sample(start: at, end: at.addingTimeInterval(60), value: value, source: source)
    }

    /// A night from 23:00 on the 20th to 07:00 on the 21st.
    private var night: [SleepInterval] {
        [stage(.awake, date(20, 23), 15), stage(.light, date(20, 23, 15), 120), stage(.deep, date(21, 1, 15), 90),
         stage(.rem, date(21, 2, 45), 60), stage(.awake, date(21, 3, 45), 5), stage(.light, date(21, 3, 50), 190)]
    }

    @Test func sleepBelongsToTheMorningItEnds() {
        var inputs = SnapshotBuilder.Inputs()
        inputs.sleep = night
        let s = SnapshotBuilder.build(day: date(21, 0), from: inputs, calendar: calendar)
        #expect(s.day == date(21, 0))
        #expect(s.deep == TimeInterval(90 * 60))
        #expect(s.light == TimeInterval(310 * 60))
        #expect(s.rem == TimeInterval(60 * 60))
        #expect(s.awake == TimeInterval(20 * 60))
        #expect(s.asleep == TimeInterval(460 * 60))
        #expect(s.bedtime == date(20, 23, 15))
        #expect(s.wake == date(21, 7))
        // The day before doesn't get this night.
        #expect(SnapshotBuilder.build(day: date(20, 0), from: inputs, calendar: calendar).asleep == nil)
    }

    @Test func garminWinsOverOtherApps() {
        var inputs = SnapshotBuilder.Inputs()
        inputs.sleep = night + [stage(.light, date(20, 22), 600, source: "com.apple.health")]
        inputs.steps = [sample(date(21, 9), 1000, source: "com.apple.health"), sample(date(21, 10), 4000)]
        let s = SnapshotBuilder.build(day: date(21, 0), from: inputs, calendar: calendar)
        #expect(s.light == TimeInterval(310 * 60))
        #expect(s.steps == 4000)
    }

    @Test func otherAppsUsedWhenGarminHasNone() {
        var inputs = SnapshotBuilder.Inputs()
        inputs.steps = [sample(date(21, 9), 1000, source: "com.apple.health"), sample(date(21, 12), 500, source: "com.apple.health")]
        #expect(SnapshotBuilder.build(day: date(21, 0), from: inputs, calendar: calendar).steps == 1500)
    }

    @Test func overnightReadingsAreAveragedDuringSleep() {
        var inputs = SnapshotBuilder.Inputs()
        inputs.sleep = night
        inputs.hrv = [sample(date(21, 1), 40), sample(date(21, 4), 50), sample(date(21, 15), 90)]   // afternoon one ignored
        inputs.respiratoryRate = [sample(date(21, 2), 14), sample(date(21, 5), 16)]
        inputs.oxygen = [sample(date(21, 3), 0.96), sample(date(21, 6), 0.94)]
        let s = SnapshotBuilder.build(day: date(21, 0), from: inputs, calendar: calendar)
        #expect(s.hrv == 45)
        #expect(s.respiratoryRate == 15)
        #expect(abs((s.oxygen ?? 0) - 95) < 0.001)
    }

    @Test func dailyTotalsAndRestingHeartRate() {
        var inputs = SnapshotBuilder.Inputs()
        inputs.restingHR = [sample(date(21, 8), 56), sample(date(20, 8), 70)]
        inputs.steps = [sample(date(21, 9), 3000), sample(date(21, 18), 2500), sample(date(22, 0, 5), 99)]
        inputs.activeEnergy = [sample(date(21, 9), 200), sample(date(21, 17), 150)]
        inputs.exerciseMinutes = [sample(date(21, 17), 30)]
        let s = SnapshotBuilder.build(day: date(21, 0), from: inputs, calendar: calendar)
        #expect(s.restingHR == 56)
        #expect(s.steps == 5500)
        #expect(s.activeEnergy == 350)
        #expect(s.exerciseMinutes == 30)
    }

    @Test func workoutsWithIntensity() {
        var inputs = SnapshotBuilder.Inputs()
        let run = WorkoutSummary(type: "Running", start: date(21, 7), duration: 30 * 60, energy: 300)
        let walk = WorkoutSummary(type: "Walking", start: date(21, 12), duration: 60 * 60, energy: 180)
        inputs.workouts = [(run, "com.garmin.connect.mobile"), (walk, "com.garmin.connect.mobile")]
        let s = SnapshotBuilder.build(day: date(21, 0), from: inputs, calendar: calendar)
        #expect(s.workouts.map(\.type) == ["Running", "Walking"])
        #expect(run.intensity == "Vigorous")
        #expect(walk.intensity == "Light")
        #expect(WorkoutSummary(type: "Yoga", start: date(21, 9), duration: 1800, energy: nil).intensity == nil)
    }

    @Test func missingDataStaysEmpty() {
        let s = SnapshotBuilder.build(day: date(21, 0), from: SnapshotBuilder.Inputs(), calendar: calendar)
        #expect(!s.hasAnyData)
        #expect(s.asleep == nil && s.restingHR == nil && s.steps == nil && s.workouts.isEmpty)
    }

    @Test func daysWithNoDataAreLeftOut() {
        var inputs = SnapshotBuilder.Inputs()
        inputs.sleep = night
        let days = [date(19, 0), date(20, 0), date(21, 0)]
        #expect(SnapshotBuilder.build(days: days, from: inputs, calendar: calendar).map(\.day) == [date(21, 0)])
    }

    @Test func snapshotsSurviveSavingAndLoading() throws {
        var inputs = SnapshotBuilder.Inputs()
        inputs.sleep = night
        inputs.restingHR = [sample(date(21, 8), 56)]
        let s = SnapshotBuilder.build(day: date(21, 0), from: inputs, calendar: calendar)
        let loaded = try SessionStore.decoder.decode([DailySnapshot].self, from: SessionStore.encoder.encode([s]))
        #expect(loaded == [s])
    }
}
