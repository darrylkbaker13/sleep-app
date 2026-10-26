import Charts
import HealthKit
import SwiftUI

/// Detail for one Health tile (H3). Overnight metrics are charted across last night with the bedroom
/// noise underneath on the same time axis; daytime ones show the last 14 days.
struct MetricDetailView: View {
    let metric: HealthMetric
    let snapshots: [DailySnapshot]

    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var health: HealthDataStore
    @State private var readings: [SnapshotBuilder.Sample]?
    @State private var analysis: NightAnalysis?
    @State private var night: SleepSession?
    @State private var span: ClosedRange<Date>?

    /// Heart rate is charted for the Resting HR tile; the others chart their own readings.
    private var overnightName: String {
        switch metric {
        case .restingHR: "Heart rate"
        default: metric.name
        }
    }

    private var usual: Double? {
        let recent = snapshots.suffix(UsualComparison.window).compactMap { metric.value(in: $0) }
        return recent.count >= UsualComparison.minimumDays ? recent.reduce(0, +) / Double(recent.count) : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if metric.isOvernight {
                    overnight
                }
                Card("Last 14 days") {
                    let recent = Array(snapshots.filter { metric.value(in: $0) != nil }.suffix(14))
                    Chart(recent) { s in
                        BarMark(x: .value("Day", s.day, unit: .day), y: .value(metric.name, metric.value(in: s) ?? 0))
                            .foregroundStyle(Color.loopAccent)
                    }
                    .chartYScale(domain: .automatic(includesZero: !metric.isOvernight))
                    .frame(height: 160)
                    if let usual {
                        Text("Your usual: \(metric.format(usual)) \(metric.unit)")
                            .font(.loop(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .loopBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text(metric.name).font(.loop(.headline)) }
        }
        .task { await load() }
    }

    // MARK: Overnight

    @ViewBuilder
    private var overnight: some View {
        if let readings, let span, !readings.isEmpty {
            Card("Last night") {
                bodyChart(readings, span: span)
                if let a = analysis {
                    noiseChart(a, span: span)
                    Text("Bedroom noise from Loop Sense. Marks are noises over 45 dB.")
                        .font(.loop(.caption2)).foregroundStyle(.secondary)
                }
                if let low = NoiseReactions.lowest(readings) {
                    HStack {
                        stat("Lowest", "\(metric.format(low.value)) \(unit)", low.start.formatted(date: .omitted, time: .shortened))
                        if let usual {
                            stat("Your usual", "\(metric.format(usual)) \(metric.unit)", metric == .restingHR ? "resting HR, 14 nights" : "14 nights")
                        }
                    }
                }
            }
            if metric == .restingHR {
                noticedCard(readings)
            }
        } else if readings != nil {
            Card("Last night") {
                Text("No overnight \(overnightName.lowercased()) readings from Garmin for last night.")
                    .foregroundStyle(.secondary)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private var unit: String { metric == .restingHR ? "bpm" : metric.unit }

    private func stat(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.loop(.caption)).foregroundStyle(.secondary)
            Text(value).font(.loop(.title3)).monospacedDigit()
            Text(caption).font(.loop(.caption2)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bodyChart(_ readings: [SnapshotBuilder.Sample], span: ClosedRange<Date>) -> some View {
        Chart {
            ForEach(Array(readings.enumerated()), id: \.offset) { _, r in
                LineMark(x: .value("Time", r.start), y: .value(overnightName, r.value))
                    .foregroundStyle(Color.loopRoseGold)
                    .interpolationMethod(.monotone)
            }
            ForEach(loudNoises, id: \.time) { n in
                RuleMark(x: .value("Noise", n.time))
                    .foregroundStyle((n.category?.color ?? Color.loopRed).opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: span)
        .chartXAxis(analysis == nil ? .automatic : .hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel(unit)
        .frame(height: 170)
        .accessibilityLabel("\(overnightName) through the night")
    }

    private func noiseChart(_ a: NightAnalysis, span: ClosedRange<Date>) -> some View {
        Chart {
            ForEach(a.chart) { p in
                AreaMark(x: .value("Time", p.time), y: .value("dB", p.average))
                    .foregroundStyle(Color.loopSilver.opacity(0.25))
                LineMark(x: .value("Time", p.time), y: .value("dB", p.average))
                    .foregroundStyle(Color.loopSilver)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            ForEach(loudNoises, id: \.time) { n in
                PointMark(x: .value("Time", n.time), y: .value("dB", n.peak))
                    .symbolSize(22)
                    .foregroundStyle(n.category?.color ?? levelColor(n.peak))
            }
        }
        .chartXScale(domain: span)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("dB")
        .frame(height: 90)
        .accessibilityLabel("Bedroom noise, \(loudNoises.count) loud noises")
    }

    private var loudNoises: [LoudNoise] {
        guard let a = analysis, let night else { return [] }
        return a.events.filter { $0.peak > NoiseReactions.loudLevel }.map {
            LoudNoise(time: $0.start, peak: $0.peak, category: night.label(for: $0)?.noiseCategory)
        }
    }

    private func noticedCard(_ readings: [SnapshotBuilder.Sample]) -> some View {
        Card("What we noticed") {
            if analysis == nil {
                Text("No Loop Sense recording last night, so there's no noise to compare with.")
                    .foregroundStyle(.secondary)
            } else {
                let reactions = NoiseReactions.find(heartRate: readings, noises: loudNoises)
                if reactions.isEmpty {
                    Text(NoiseReactions.calmText(loudCount: loudNoises.count))
                } else {
                    ForEach(reactions.prefix(3), id: \.noiseTime) { r in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: r.category?.symbol ?? "waveform").foregroundStyle(r.category?.color ?? Color.loopWarn)
                            Text(r.text())
                        }
                    }
                    if reactions.count > 3 {
                        Text("And \(reactions.count - 3) more.").font(.loop(.caption)).foregroundStyle(.secondary)
                    }
                    Text("A reaction is a rise of \(Int(NoiseReactions.minimumRise)) bpm or more within 2 minutes of a noise over 45 dB.")
                        .font(.loop(.caption2)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Loading

    /// Last night: the Garmin sleep window (or the latest recording), its readings and the recording's noise.
    private func load() async {
        guard metric.isOvernight else { return }
        let latestSleep = snapshots.last { $0.bedtime != nil && $0.wake != nil }
        let recording = store.sessions.first { s in
            guard let sleep = latestSleep, let bed = sleep.bedtime, let wake = sleep.wake else { return true }
            return s.start < wake && s.effectiveEnd > bed
        }
        let from = [latestSleep?.bedtime, recording?.start].compactMap { $0 }.min()
        let to = [latestSleep?.wake, recording?.effectiveEnd].compactMap { $0 }.max()
        guard let from, let to, to > from else { readings = []; return }
        span = from...to
        night = recording
        if let recording {
            analysis = await Task.detached(priority: .userInitiated) { NightAnalysis(session: recording) }.value
        }
        readings = await fetch(from: from, to: to, recording: recording)
    }

    private func fetch(from: Date, to: Date, recording: SleepSession?) async -> [SnapshotBuilder.Sample] {
        #if DEBUG
        if let recording, DemoData.isDemo(recording) { return DemoHealth.overnight(metric, for: recording) }
        #endif
        guard health.connected, HealthSleep.isAvailable else { return [] }
        let samples: [SnapshotBuilder.Sample]?
        switch metric {
        case .restingHR: samples = try? await HealthReader.heartRate(from: from, to: to)
        case .hrv: samples = try? await HealthReader.samples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: from, to: to)
        case .respiratoryRate: samples = try? await HealthReader.samples(.respiratoryRate, unit: .count().unitDivided(by: .minute()), from: from, to: to)
        case .oxygen: samples = try? await HealthReader.samples(.oxygenSaturation, unit: .percent(), from: from, to: to).map {
            SnapshotBuilder.Sample(start: $0.start, end: $0.end, value: $0.value * 100, source: $0.source)
        }
        default: samples = []
        }
        return samples ?? []
    }
}
