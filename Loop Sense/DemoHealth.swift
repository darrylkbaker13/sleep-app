#if DEBUG
import Foundation

/// TEMPORARY made-up Garmin data to go with the demo nights (debug builds only). 21 days, so the
/// Health tab has a 14-day "usual" to compare with. Noisier demo nights get a slightly higher resting
/// heart rate and lower HRV. Delete with DemoData.swift.
nonisolated enum DemoHealth {
    static func snapshots(for demoNights: [SleepSession], today: Date = Date(), calendar: Calendar = .current) -> [DailySnapshot] {
        let todayStart = calendar.startOfDay(for: today)
        var rng = DemoRNG(state: 42)
        return (0..<21).reversed().compactMap { ago -> DailySnapshot? in
            guard let day = calendar.date(byAdding: .day, value: -ago, to: todayStart) else { return nil }
            var s = DailySnapshot(day: day)
            // The demo night that ended this morning, if there is one.
            let night = demoNights.first { calendar.isDate($0.effectiveEnd, inSameDayAs: day) }
            let noise = night.flatMap { NightAnalysis(session: $0) }.map { Double($0.events.count) } ?? 15
            let stress = min(1, noise / 50)   // 0 quiet ... 1 very noisy

            if let night {
                let stages = DemoData.stages(for: night)
                func total(_ st: SleepStage) -> TimeInterval {
                    stages.filter { $0.stage == st }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
                }
                s.deep = total(.deep); s.light = total(.light); s.rem = total(.rem); s.awake = total(.awake)
                s.asleep = s.deep! + s.light! + s.rem!
                let asleep = stages.filter { $0.stage != .awake }
                s.bedtime = asleep.map(\.start).min()
                s.wake = asleep.map(\.end).max()
            } else {
                let asleep = 6.8 * 3600 + rng.double(-0.6...0.8) * 3600
                s.deep = asleep * rng.double(0.15...0.22); s.rem = asleep * rng.double(0.18...0.24)
                s.light = asleep - s.deep! - s.rem!; s.awake = rng.double(15...45) * 60
                s.asleep = asleep
                s.bedtime = calendar.date(byAdding: .minute, value: -60 - rng.int(0...40), to: day)
                s.wake = s.bedtime!.addingTimeInterval(asleep + s.awake!)
            }
            s.restingHR = 53 + stress * 6 + rng.double(-1.5...1.5)
            s.hrv = 52 - stress * 14 + rng.double(-4...4)
            s.respiratoryRate = 14.2 + stress * 0.8 + rng.double(-0.4...0.4)
            s.oxygen = 96.5 - stress * 1.2 + rng.double(-0.6...0.6)
            s.steps = rng.double(5_000...11_500)
            s.activeEnergy = rng.double(320...720)
            s.exerciseMinutes = rng.double(10...55)
            return s
        }
    }
}

extension DemoHealth {
    /// Made-up overnight readings for a demo night: heart rate every minute (lower in deep sleep,
    /// higher when awake, so wake-ups after loud noises show as jumps), and the others every 5 minutes.
    static func overnight(_ metric: HealthMetric, for night: SleepSession) -> [SnapshotBuilder.Sample] {
        let stages = DemoData.stages(for: night)
        guard let first = stages.first?.start, let last = stages.last?.end else { return [] }
        var rng = DemoRNG(state: UInt64(abs(night.start.timeIntervalSince1970)) &+ UInt64(metric.rawValue.count))
        let step: TimeInterval = metric == .restingHR ? 60 : 300
        var out: [SnapshotBuilder.Sample] = []
        var t = first
        var drift = 0.0
        while t < last {
            let stage = stages.first { $0.start <= t && $0.end > t }?.stage ?? .light
            drift = max(-2, min(2, drift + rng.double(-0.4...0.4)))
            let value: Double
            switch metric {
            case .restingHR:
                let adjust: Double = switch stage { case .deep: -4; case .light: 0; case .rem: 3; case .awake: 17 }
                value = 56 + adjust + drift + rng.double(-1...1)
            case .hrv:
                value = (stage == .deep ? 60 : stage == .awake ? 32 : 48) + drift * 2 + rng.double(-4...4)
            case .respiratoryRate:
                value = 14.3 + (stage == .awake ? 1.5 : 0) + drift * 0.2 + rng.double(-0.4...0.4)
            case .oxygen:
                value = 96 + drift * 0.3 + rng.double(-0.8...0.8)
            default:
                return []
            }
            out.append(SnapshotBuilder.Sample(start: t, end: t.addingTimeInterval(step), value: value, source: "com.garmin.connect.mobile (demo)"))
            t = t.addingTimeInterval(step)
        }
        return out
    }
}

/// Repeatable random numbers so the demo looks the same every time.
nonisolated struct DemoRNG {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func double(_ r: ClosedRange<Double>) -> Double {
        r.lowerBound + (r.upperBound - r.lowerBound) * Double(next() >> 11) / Double(1 << 53)
    }
    mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
}
#endif
