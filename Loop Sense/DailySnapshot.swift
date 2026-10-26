import Foundation

/// One workout from Apple Health.
nonisolated struct WorkoutSummary: Codable, Equatable {
    /// Readable activity, e.g. "Running".
    let type: String
    let start: Date
    let duration: TimeInterval
    /// Active energy in kcal, if recorded.
    let energy: Double?

    /// Light, moderate or vigorous, from energy per minute. nil without energy.
    var intensity: String? {
        guard let energy, duration > 0 else { return nil }
        switch energy / (duration / 60) {
        case ..<4: return "Light"
        case ..<7: return "Moderate"
        default: return "Vigorous"
        }
    }
}

/// One day of Garmin data from Apple Health (M1). `day` is the start of the calendar day; sleep is the
/// night that ended that morning. Any field can be nil, e.g. when the watch wasn't worn.
nonisolated struct DailySnapshot: Codable, Equatable, Identifiable {
    var id: Date { day }
    let day: Date

    // Sleep (the night ending this morning)
    var asleep: TimeInterval?
    var awake: TimeInterval?
    var deep: TimeInterval?
    var light: TimeInterval?
    var rem: TimeInterval?
    var bedtime: Date?
    var wake: Date?

    // Body
    var restingHR: Double?
    /// Overnight heart rate variability (SDNN), ms.
    var hrv: Double?
    /// Overnight breaths per minute.
    var respiratoryRate: Double?
    /// Overnight blood oxygen, percent.
    var oxygen: Double?

    // Activity (the whole day)
    var steps: Double?
    /// kcal
    var activeEnergy: Double?
    var exerciseMinutes: Double?
    var workouts: [WorkoutSummary] = []

    var hasAnyData: Bool {
        asleep != nil || restingHR != nil || hrv != nil || respiratoryRate != nil || oxygen != nil
            || steps != nil || activeEnergy != nil || exerciseMinutes != nil || !workouts.isEmpty
    }
}

/// Builds daily snapshots from raw Apple Health samples. Pure, so it can be tested without HealthKit.
nonisolated enum SnapshotBuilder {
    /// A quantity reading: one value over a time span, from one app.
    struct Sample {
        let start: Date
        let end: Date
        let value: Double
        let source: String
    }

    struct Inputs {
        var sleep: [SleepInterval] = []
        var restingHR: [Sample] = []
        var hrv: [Sample] = []
        var respiratoryRate: [Sample] = []
        /// Fraction 0...1, as Apple Health stores it.
        var oxygen: [Sample] = []
        var steps: [Sample] = []
        var activeEnergy: [Sample] = []
        var exerciseMinutes: [Sample] = []
        var workouts: [(summary: WorkoutSummary, source: String)] = []
    }

    /// When several apps wrote the same kind of data, keep only Garmin's.
    static func preferGarmin<T>(_ items: [T], source: (T) -> String) -> [T] {
        let garmin = items.filter { source($0).lowercased().contains("garmin") }
        return garmin.isEmpty ? items : garmin
    }

    /// Sleep that ends between 18:00 the evening before and 18:00 on `day` belongs to `day`.
    static func nightWindow(for day: Date, calendar: Calendar) -> ClosedRange<Date> {
        let start = calendar.date(byAdding: .hour, value: -6, to: day)!
        return start...calendar.date(byAdding: .hour, value: 18, to: day)!
    }

    static func build(day: Date, from inputs: Inputs, calendar: Calendar = .current) -> DailySnapshot {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        var s = DailySnapshot(day: dayStart)

        // Sleep: the night ending this morning.
        let window = nightWindow(for: dayStart, calendar: calendar)
        let night = preferGarmin(inputs.sleep.filter { window.contains($0.end) }, source: \.source)
        if !night.isEmpty {
            func total(_ stage: SleepStage) -> TimeInterval {
                night.filter { $0.stage == stage }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            }
            s.deep = total(.deep)
            s.light = total(.light)
            s.rem = total(.rem)
            s.awake = total(.awake)
            s.asleep = s.deep! + s.light! + s.rem!
            let asleepParts = night.filter { $0.stage != .awake }
            s.bedtime = (asleepParts.isEmpty ? night : asleepParts).map(\.start).min()
            s.wake = (asleepParts.isEmpty ? night : asleepParts).map(\.end).max()
        }

        // Overnight body readings: during the night's sleep, or overnight if there was no sleep recorded.
        let overnight: ClosedRange<Date> = {
            if let bed = s.bedtime, let wake = s.wake, wake > bed { return bed...wake }
            return window.lowerBound...calendar.date(byAdding: .hour, value: 12, to: dayStart)!
        }()
        func overnightAverage(_ samples: [Sample]) -> Double? {
            average(preferGarmin(samples, source: \.source).filter { overnight.contains($0.start) }.map(\.value))
        }
        s.hrv = overnightAverage(inputs.hrv)
        s.respiratoryRate = overnightAverage(inputs.respiratoryRate)
        s.oxygen = overnightAverage(inputs.oxygen).map { $0 * 100 }

        // Daily readings.
        func inDay(_ samples: [Sample]) -> [Sample] {
            preferGarmin(samples, source: \.source).filter { $0.start >= dayStart && $0.start < dayEnd }
        }
        s.restingHR = average(inDay(inputs.restingHR).map(\.value))
        s.steps = sum(inDay(inputs.steps).map(\.value))
        s.activeEnergy = sum(inDay(inputs.activeEnergy).map(\.value))
        s.exerciseMinutes = sum(inDay(inputs.exerciseMinutes).map(\.value))
        s.workouts = preferGarmin(inputs.workouts, source: \.source)
            .filter { $0.summary.start >= dayStart && $0.summary.start < dayEnd }
            .map(\.summary)
        return s
    }

    /// Snapshots for each day in a range, newest last, leaving out days with no data at all.
    static func build(days: [Date], from inputs: Inputs, calendar: Calendar = .current) -> [DailySnapshot] {
        days.map { build(day: $0, from: inputs, calendar: calendar) }.filter(\.hasAnyData)
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func sum(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +)
    }
}
