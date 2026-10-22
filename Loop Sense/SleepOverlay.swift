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
        case .awake: return .loopRed
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
    let findings: [String]

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

        var findings: [String] = []
        let asleepSeconds = (seconds[.light] ?? 0) + (seconds[.deep] ?? 0) + (seconds[.rem] ?? 0)
        if asleepSeconds > 0 {
            findings.append("Garmin recorded \(formatDuration(asleepSeconds)) asleep: \(formatDuration(seconds[.deep] ?? 0)) deep, \(formatDuration(seconds[.light] ?? 0)) light and \(formatDuration(seconds[.rem] ?? 0)) REM, plus \(formatDuration(seconds[.awake] ?? 0)) awake.")
        }

        if awakenings.isEmpty {
            findings.append("You didn't wake up during the night.")
        } else if noiseWakeups.isEmpty {
            findings.append("You woke \(awakenings.count) time\(awakenings.count == 1 ? "" : "s"), but none came right after a noise, so something else probably woke you.")
        } else {
            findings.append("You woke \(awakenings.count) time\(awakenings.count == 1 ? "" : "s"). \(noiseWakeups.count) of those came within 2 minutes of a noise.")
            let list = noiseWakeups.prefix(5).map {
                "\($0.time.formatted(date: .omitted, time: .shortened)) (\(Int($0.peak.rounded())) dB)"
            }
            findings.append("Noise-linked wake-ups: \(list.joined(separator: ", ")).")
        }

        if let deep = average(.deep), let awake = average(.awake) {
            findings.append(String(format: "Your room averaged %.0f dB during deep sleep and %.0f dB while you were awake.", deep, awake))
        } else if let deep = average(.deep) {
            findings.append(String(format: "Your room averaged %.0f dB during deep sleep.", deep))
        }
        self.findings = findings
    }
}

struct SleepStagesCard: View {
    let session: SleepSession
    let analysis: NightAnalysis
    @AppStorage("healthConnected") private var healthConnected = false
    @State private var intervals: [SleepInterval]?
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        Card("Sleep stages") {
            if let intervals, !intervals.isEmpty {
                hypnogram(intervals)
                let insights = SleepInsights(intervals: intervals, session: session, analysis: analysis)
                ForEach(insights.findings, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                        Text(line)
                    }
                }
            } else if loading {
                ProgressView()
            } else if intervals != nil {
                Text("No sleep data found in Apple Health for this night. Check that your watch has synced to Garmin Connect, and that Garmin Connect is sharing sleep with Apple Health.")
                    .foregroundStyle(.secondary)
            } else {
                Text("See how noise lined up with your sleep. Garmin Connect can share your sleep stages with Apple Health, and Loop Sense reads them from there.")
                    .foregroundStyle(.secondary)
                Button("Connect Apple Health") {
                    Task { await load(requestAccess: true) }
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Color.loopOnAccent)
            }
            if let errorText {
                Text(errorText).font(.loop(.caption)).foregroundStyle(Color.loopRed)
            }
        }
        .task {
            #if DEBUG
            if DemoData.isDemo(session) {
                intervals = DemoData.stages(for: session)
                return
            }
            #endif
            if healthConnected { await load(requestAccess: false) }
        }
    }

    private func hypnogram(_ intervals: [SleepInterval]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(intervals) { s in
                    RectangleMark(xStart: .value("Start", s.start),
                                  xEnd: .value("End", s.end),
                                  y: .value("Stage", s.stage.label))
                        .foregroundStyle(s.stage.color)
                }
                ForEach(analysis.events) { e in
                    RuleMark(x: .value("Noise", e.start))
                        .foregroundStyle(Color.loopRed.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
            .chartXScale(domain: analysis.start...analysis.end)
            .chartYScale(domain: SleepStage.allCases.map(\.label))
            .frame(height: 150)
            Text("Dashed red lines are noise events.")
                .font(.loop(.caption))
                .foregroundStyle(.secondary)
        }
    }

    private func load(requestAccess: Bool) async {
        guard HealthSleep.isAvailable else {
            errorText = "Apple Health isn't available on this device."
            return
        }
        loading = true
        defer { loading = false }
        do {
            if requestAccess { try await HealthSleep.requestAccess() }
            intervals = try await HealthSleep.intervals(from: analysis.start, to: analysis.end)
            healthConnected = true
            errorText = nil
        } catch {
            errorText = "Couldn't read Apple Health: \(error.localizedDescription)"
        }
    }
}
