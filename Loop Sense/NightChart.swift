import Charts
import SwiftUI

/// One chart for the whole night: noise level on top, Garmin sleep stages as a band underneath,
/// and noise events marked on the same time axis. Loads the stages itself.
struct NightChartCard: View {
    let session: SleepSession
    let analysis: NightAnalysis
    @AppStorage("healthConnected") private var healthConnected = false
    @State private var stages: [SleepInterval]?
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        Card("Through the night") {
            noiseChart
            if let stages, !stages.isEmpty {
                stageBand(stages)
                ChipRow(chips: SleepInsights(intervals: stages, session: session, analysis: analysis).chips)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if stages != nil {
                Text("No Garmin sleep data for this night.")
                    .font(.loop(.caption)).foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await load(requestAccess: true) }
                } label: {
                    Label("Add Garmin sleep stages", systemImage: "heart.text.square")
                        .font(.loop(.subheadline))
                }
                .foregroundStyle(Color.loopAccent)
            }
            if let errorText {
                Text(errorText).font(.loop(.caption)).foregroundStyle(Color.loopRed)
            }
        }
        .task {
            #if DEBUG
            if DemoData.isDemo(session) {
                stages = DemoData.stages(for: session)
                return
            }
            #endif
            if healthConnected { await load(requestAccess: false) }
        }
    }

    private var hasStages: Bool { !(stages ?? []).isEmpty }

    private var noiseChart: some View {
        Chart {
            ForEach(analysis.chart) { p in
                AreaMark(x: .value("Time", p.time), yStart: .value("Avg", p.average), yEnd: .value("Peak", p.peak))
                    .foregroundStyle(Color.loopRoseGold.opacity(0.3))
                LineMark(x: .value("Time", p.time), y: .value("Average", p.average))
                    .foregroundStyle(Color.loopAccent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(analysis.events) { e in
                PointMark(x: .value("Time", e.start), y: .value("Peak", e.peak))
                    .symbolSize(18)
                    .foregroundStyle(levelColor(e.peak))
            }
            RuleMark(y: .value("WHO", WHO.averageLimit))
                .foregroundStyle(Color.loopSilver.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("WHO 30 dB").font(.loop(.caption2)).foregroundStyle(Color.loopSilver)
                }
        }
        .chartXScale(domain: analysis.start...analysis.end)
        .chartXAxis(hasStages ? .hidden : .automatic)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("dB")
        .frame(height: 170)
        .accessibilityLabel("Noise through the night, \(analysis.events.count) noise events")
    }

    private func stageBand(_ stages: [SleepInterval]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(stages) { s in
                    RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end),
                                  yStart: .value("Bottom", 0), yEnd: .value("Top", 1))
                        .foregroundStyle(s.stage.color)
                }
                ForEach(analysis.events) { e in
                    RuleMark(x: .value("Noise", e.start))
                        .foregroundStyle(Color.white.opacity(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: analysis.start...analysis.end)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...1)
            .frame(height: 50)
            .accessibilityLabel("Sleep stages from Garmin")

            HStack(spacing: 12) {
                ForEach(SleepStage.allCases, id: \.self) { stage in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(stage.color).frame(width: 10, height: 10)
                        Text(stage.label)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.loop(.caption2))
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
            stages = try await HealthSleep.intervals(from: analysis.start, to: analysis.end)
            healthConnected = true
            errorText = nil
        } catch {
            errorText = "Couldn't read Apple Health: \(error.localizedDescription)"
        }
    }
}
