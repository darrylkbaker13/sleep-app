import Charts
import HealthKit
import SwiftUI

/// Sleep stages as Garmin Connect (or any other app) writes them to Apple Health.
nonisolated enum SleepStage: Int, CaseIterable {
    case awake, rem, light, deep

    var label: String {
        switch self {
        case .awake: return "Awake"
        case .rem: return "REM"
        case .light: return "Light"
        case .deep: return "Deep"
        }
    }

    @MainActor var color: Color {
        switch self {
        case .awake: return .loopWarn
        case .rem: return .loopRoseGold
        case .light: return .loopSilver
        case .deep: return .loopAccent
        }
    }
}

nonisolated struct SleepInterval: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let stage: SleepStage
    let source: String
}

enum HealthSleep {
    static let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [HKCategoryType(.sleepAnalysis)])
    }

    /// Sleep stages overlapping the recording, clipped to it.
    static func intervals(from start: Date, to end: Date) async throws -> [SleepInterval] {
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-3600),
                                                    end: end.addingTimeInterval(3600))
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store)

        var intervals: [SleepInterval] = samples.compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .awake: stage = .awake
            case .asleepREM: stage = .rem
            case .asleepCore, .asleepUnspecified: stage = .light
            case .asleepDeep: stage = .deep
            default: return nil // "in bed" isn't a sleep stage
            }
            let s = max(sample.startDate, start)
            let e = min(sample.endDate, end)
            guard e > s else { return nil }
            return SleepInterval(start: s, end: e, stage: stage,
                                 source: sample.sourceRevision.source.bundleIdentifier)
        }
        // If Garmin wrote stages, ignore other sources (like the iPhone's sleep schedule) so they don't overlap.
        let garmin = intervals.filter { $0.source.lowercased().contains("garmin") }
        if !garmin.isEmpty { intervals = garmin }
        return intervals
    }
}

/// Lines sleep stages up against the noise recording.
struct SleepInsights {
    /// e.g. "3 wake-ups · 2 after a noise", "7h 12m asleep · 1h 20m deep".
    let chips: [ReportChip]

    /// Awake periods between first falling asleep and last waking, merging ones under a minute apart.
    nonisolated static func awakenings(in intervals: [SleepInterval]) -> [Date] {
        let asleep = intervals.filter { $0.stage != .awake }
        var awakenings: [Date] = []
        if let firstSleep = asleep.map(\.start).min(), let lastSleep = asleep.map(\.end).max() {
            var previousEnd = Date.distantPast
            for awake in intervals.filter({ $0.stage == .awake }).sorted(by: { $0.start < $1.start }) {
                if awake.start > firstSleep, awake.start < lastSleep,
                   awake.start.timeIntervalSince(previousEnd) > 60 {
                    awakenings.append(awake.start)
                }
                previousEnd = awake.end
            }
        }
        return awakenings
    }

    nonisolated static func deepSleepSeconds(in intervals: [SleepInterval]) -> Double {
        intervals.filter { $0.stage == .deep }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    init(intervals: [SleepInterval], session: SleepSession, analysis: NightAnalysis) {
        var seconds: [SleepStage: Double] = [:]
        var energy: [SleepStage: (sum: Double, n: Int)] = [:]
        for interval in intervals {
            seconds[interval.stage, default: 0] += interval.end.timeIntervalSince(interval.start)
            let from = max(0, Int(interval.start.timeIntervalSince(session.start)))
            let to = min(session.levels.count, Int(interval.end.timeIntervalSince(session.start)))
            guard from < to else { continue }
            for i in from..<to where session.levels[i].isFinite {
                let db = Double(session.levels[i]) + session.calibrationOffset
                energy[interval.stage, default: (0, 0)].sum += pow(10, db / 10)
                energy[interval.stage, default: (0, 0)].n += 1
            }
        }
        func average(_ stage: SleepStage) -> Double? {
            guard let e = energy[stage], e.n > 0 else { return nil }
            return 10 * log10(e.sum / Double(e.n))
        }

        let awakenings = Self.awakenings(in: intervals)

        // A wake-up is "noise-linked" if a noise event started in the 2 minutes before it (or just after).
        var noiseWakeups: [(time: Date, peak: Double)] = []
        for wake in awakenings {
            let nearby = analysis.events.filter {
                $0.start >= wake.addingTimeInterval(-120) && $0.start <= wake.addingTimeInterval(30)
            }
            if let loudest = nearby.max(by: { $0.peak < $1.peak }) {
                noiseWakeups.append((wake, loudest.peak))
            }
        }

        var chips: [ReportChip] = []
        let asleepSeconds = (seconds[.light] ?? 0) + (seconds[.deep] ?? 0) + (seconds[.rem] ?? 0)

        let wakeText: String
        let wakeDetail: String
        if awakenings.isEmpty {
            wakeText = "No wake-ups"
            wakeDetail = "Garmin didn't record you waking during the night."
        } else if noiseWakeups.isEmpty {
            wakeText = "\(awakenings.count) wake-up\(awakenings.count == 1 ? "" : "s") · none after a noise"
            wakeDetail = "You woke \(awakenings.count) time\(awakenings.count == 1 ? "" : "s"), but none came right after a noise, so something else probably woke you."
        } else {
            wakeText = "\(awakenings.count) wake-up\(awakenings.count == 1 ? "" : "s") · \(noiseWakeups.count) after a noise"
            let list = noiseWakeups.prefix(5).map {
                "\($0.time.formatted(date: .omitted, time: .shortened)) (\(Int($0.peak.rounded())) dB)"
            }
            wakeDetail = "You woke \(awakenings.count) time\(awakenings.count == 1 ? "" : "s"). \(noiseWakeups.count) of those came within 2 minutes of a noise: \(list.joined(separator: ", "))."
        }
        chips.append(ReportChip(icon: "eye.fill", text: wakeText,
                                tone: noiseWakeups.isEmpty ? .good : .warning, detail: wakeDetail))

        if asleepSeconds > 0 {
            chips.append(ReportChip(icon: "bed.double.fill",
                                    text: "\(formatDuration(asleepSeconds)) asleep · \(formatDuration(seconds[.deep] ?? 0)) deep",
                                    tone: .neutral,
                                    detail: "Garmin recorded \(formatDuration(asleepSeconds)) asleep: \(formatDuration(seconds[.deep] ?? 0)) deep, \(formatDuration(seconds[.light] ?? 0)) light and \(formatDuration(seconds[.rem] ?? 0)) REM, plus \(formatDuration(seconds[.awake] ?? 0)) awake."))
        }

        if let deep = average(.deep) {
            let awakeNote = average(.awake).map { String(format: " and %.0f dB while you were awake", $0) } ?? ""
            chips.append(ReportChip(icon: "moon.zzz.fill", text: "Deep sleep at \(Int(deep.rounded())) dB", tone: .neutral,
                                    detail: String(format: "Your room averaged %.0f dB during deep sleep", deep) + awakeNote + "."))
        }
        self.chips = chips
    }
}
