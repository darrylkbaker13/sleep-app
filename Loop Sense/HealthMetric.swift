import Foundation

/// A body or activity number shown on the Health tab (H2).
nonisolated enum HealthMetric: String, CaseIterable, Identifiable {
    case restingHR, hrv, respiratoryRate, oxygen, steps, activeEnergy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .restingHR: "Resting HR"
        case .hrv: "Overnight HRV"
        case .respiratoryRate: "Breathing rate"
        case .oxygen: "Blood oxygen"
        case .steps: "Steps"
        case .activeEnergy: "Active energy"
        }
    }

    var unit: String {
        switch self {
        case .restingHR: "bpm"
        case .hrv: "ms"
        case .respiratoryRate: "br/min"
        case .oxygen: "%"
        case .steps: "steps"
        case .activeEnergy: "kcal"
        }
    }

    var symbol: String {
        switch self {
        case .restingHR: "heart.fill"
        case .hrv: "waveform.path.ecg"
        case .respiratoryRate: "lungs.fill"
        case .oxygen: "drop.fill"
        case .steps: "figure.walk"
        case .activeEnergy: "flame.fill"
        }
    }

    /// Lower resting HR and breathing rate are better; higher everything else.
    var lowerIsBetter: Bool { self == .restingHR || self == .respiratoryRate }

    /// Measured overnight (charted against noise in H3) rather than over the day.
    var isOvernight: Bool { self != .steps && self != .activeEnergy }

    /// Steps and energy are shown for yesterday (today's are still counting); overnight ones for last night.
    var dayOffset: Int { isOvernight ? 0 : -1 }

    func value(in s: DailySnapshot) -> Double? {
        switch self {
        case .restingHR: s.restingHR
        case .hrv: s.hrv
        case .respiratoryRate: s.respiratoryRate
        case .oxygen: s.oxygen
        case .steps: s.steps
        case .activeEnergy: s.activeEnergy
        }
    }

    /// Differences smaller than this read as "about usual".
    var noticeable: Double {
        switch self {
        case .restingHR: 1.5
        case .hrv: 3
        case .respiratoryRate: 0.5
        case .oxygen: 0.5
        case .steps: 500
        case .activeEnergy: 50
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .respiratoryRate: String(format: "%.1f", v)
        case .steps: Int(v.rounded()).formatted()
        default: "\(Int(v.rounded()))"
        }
    }

    /// Days the tile reads from, in a set of snapshots: Day = the latest relevant day.
    func days(_ snapshots: [DailySnapshot], range: HealthRange, today: Date, calendar: Calendar = .current) -> [DailySnapshot] {
        guard let last = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: today)),
              let first = calendar.date(byAdding: .day, value: 1 - range.days, to: last) else { return [] }
        return snapshots.filter { $0.day >= first && $0.day <= last && value(in: $0) != nil }
    }
}

nonisolated enum HealthRange: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month"
    var id: String { rawValue }
    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        }
    }
}

/// How a value compares with what's normal for this person.
nonisolated struct UsualComparison: Equatable {
    enum Direction: Equatable { case up, down, same }
    let usual: Double
    let difference: Double
    let direction: Direction
    /// True when the change is in the healthy direction (or no real change).
    let isGood: Bool

    /// "Usual" is the average of the 14 days before `day`; at least 3 of them are needed.
    static let window = 14
    static let minimumDays = 3

    init?(metric: HealthMetric, value: Double, day: Date, history: [DailySnapshot], calendar: Calendar = .current) {
        guard let from = calendar.date(byAdding: .day, value: -Self.window, to: day) else { return nil }
        let past = history.filter { $0.day >= from && $0.day < day }.compactMap { metric.value(in: $0) }
        guard past.count >= Self.minimumDays else { return nil }
        usual = past.reduce(0, +) / Double(past.count)
        difference = value - usual
        if abs(difference) < metric.noticeable {
            direction = .same
            isGood = true
        } else {
            direction = difference > 0 ? .up : .down
            isGood = metric.lowerIsBetter ? difference < 0 : difference > 0
        }
    }

    /// "▼ 2 vs usual", "▲ 1,200 vs usual", "≈ usual".
    func text(for metric: HealthMetric) -> String {
        switch direction {
        case .same: "≈ usual"
        case .up: "▲ \(metric.format(abs(difference))) vs usual"
        case .down: "▼ \(metric.format(abs(difference))) vs usual"
        }
    }
}

/// Which metrics haven't arrived in Apple Health at all (for the note in Settings).
nonisolated enum HealthCoverage {
    static func missing(in snapshots: [DailySnapshot]) -> [HealthMetric] {
        HealthMetric.allCases.filter { m in !snapshots.contains { m.value(in: $0) != nil } }
    }

    static let neverSynced = "Body Battery, stress and Garmin's Sleep Score don't sync to Apple Health, so Loop Sense can't show them."
}
