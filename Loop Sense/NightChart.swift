import Charts
import SwiftUI

/// The words and marks for the "Through the night" card, kept apart from the view so they can be tested.
nonisolated enum NightChartSummary {
    /// Noises above this are marked on the chart; quieter ones are left out to keep it readable.
    static let loudLimit = WHO.peakLimit
    /// With many loud noises, only the loudest few are labelled with their dB value.
    static let maxLabels = 5
    /// Labels closer together than this share of the night would overlap, so only the louder one is kept.
    static let minLabelGap = 0.08

    /// "5 loud noises · 1 woke you", "No loud noises". `woke` is nil without Garmin data.
    static func text(loud: Int, woke: Int?) -> String {
        let noises = loud == 0 ? "No loud noises" : "\(loud) loud noise\(loud == 1 ? "" : "s")"
        guard let woke, loud > 0 || woke > 0 else { return noises }
        if woke == 0 { return noises + " · none woke you" }
        return noises + " · \(woke) woke you"
    }

    /// The loud events, and which of them get a dB label: the loudest few, spaced so labels don't overlap.
    static func marks(_ events: [LoudEvent], nightLength: TimeInterval) -> (loud: [LoudEvent], labelled: Set<UUID>) {
        let loud = events.filter { $0.peak > loudLimit }
        let gap = nightLength * minLabelGap
        var chosen: [LoudEvent] = []
        for e in loud.sorted(by: { $0.peak > $1.peak }) where chosen.count < maxLabels {
            if chosen.allSatisfy({ abs($0.start.timeIntervalSince(e.start)) >= gap }) { chosen.append(e) }
        }
        return (loud, Set(chosen.map(\.id)))
    }

    /// Start, two times in between, and the end of the night.
    static func axisTimes(from start: Date, to end: Date) -> [Date] {
        let span = end.timeIntervalSince(start)
        return [0, 1.0 / 3, 2.0 / 3, 1].map { start.addingTimeInterval(span * $0) }
    }
}

/// One chart for the whole night: Garmin sleep stages as soft shading behind a single noise line,
/// a green quiet zone below 30 dB, and only the loud noises marked. Loads the stages itself and
/// hands them back through `stages` so the report can show the other sleep insights elsewhere.
struct NightChartCard: View {
    let session: SleepSession
    let analysis: NightAnalysis
    @Binding var stages: [SleepInterval]?
    @AppStorage("healthConnected") private var healthConnected = false
    @State private var loading = false
    @State private var errorText: String?

    private var insights: SleepInsights? {
        guard let stages, !stages.isEmpty else { return nil }
        return SleepInsights(intervals: stages, session: session, analysis: analysis)
    }

    var body: some View {
        let marks = NightChartSummary.marks(analysis.events, nightLength: analysis.end.timeIntervalSince(analysis.start))
        Card("Through the night") {
            Text(NightChartSummary.text(loud: marks.loud.count, woke: insights?.noiseLinkedWakeups))
                .font(.loop(.subheadline))
                .foregroundStyle(.secondary)
            chart(loud: marks.loud, labelled: marks.labelled)
            if hasStages {
                legend
            }
            if let chip = insights?.chips.first {
                ChipRow(chips: [chip])
            } else if stages == nil, !loading {
                Button {
                    Task { await load(requestAccess: true) }
                } label: {
                    Label("Add Garmin sleep stages", systemImage: "heart.text.square")
                        .font(.loop(.caption))
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

    /// dB range shown: always includes the quiet zone, with room above the loudest marked noise for its label.
    private func yRange(loud: [LoudEvent]) -> ClosedRange<Double> {
        let averages = analysis.chart.map(\.average)
        let low = min(averages.min() ?? WHO.averageLimit, WHO.averageLimit) - 5
        let high = max(averages.max() ?? 50, loud.map(\.peak).max() ?? 0) + 8
        return low...high
    }

    private func chart(loud: [LoudEvent], labelled: Set<UUID>) -> some View {
        let y = yRange(loud: loud)
        return Chart {
            // Sleep stages behind everything, faint; awake a little stronger.
            ForEach(stages ?? []) { s in
                RectangleMark(xStart: .value("Start", s.start), xEnd: .value("End", s.end),
                              yStart: .value("Bottom", y.lowerBound), yEnd: .value("Top", y.upperBound))
                    .foregroundStyle(s.stage.color.opacity(s.stage == .awake ? 0.3 : 0.12))
            }
            // Quiet zone: below the WHO bedroom guideline.
            RectangleMark(xStart: .value("Start", analysis.start), xEnd: .value("End", analysis.end),
                          yStart: .value("Bottom", y.lowerBound), yEnd: .value("Top", WHO.averageLimit))
                .foregroundStyle(Color.loopGood.opacity(0.2))
            ForEach(analysis.chart) { p in
                LineMark(x: .value("Time", p.time), y: .value("Level", p.average))
                    .foregroundStyle(Color.loopAccent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(loud) { e in
                PointMark(x: .value("Time", e.start), y: .value("Level", e.peak))
                    .symbolSize(26)
                    .foregroundStyle(levelColor(e.peak))
                    .annotation(position: .top, spacing: 2) {
                        if labelled.contains(e.id) {
                            Text("\(Int(e.peak.rounded()))")
                                .font(.loop(.caption2))
                                .foregroundStyle(levelColor(e.peak))
                        }
                    }
            }
        }
        .chartXScale(domain: analysis.start...analysis.end)
        .chartYScale(domain: y)
        .chartXAxis {
            let times = NightChartSummary.axisTimes(from: analysis.start, to: analysis.end)
            AxisMarks(values: times) { value in
                AxisValueLabel(anchor: anchor(for: value.index, of: times.count)) {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(date: .omitted, time: .shortened)).font(.loop(.caption2))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [y.lowerBound + 3, y.upperBound - 3]) { value in
                AxisValueLabel {
                    Text(value.index == 0 ? "Quiet" : "Loud").font(.loop(.caption2))
                }
            }
        }
        .frame(height: 190)
        .accessibilityElement()
        .accessibilityLabel("Noise through the night")
        .accessibilityValue(accessibilityText(loud: loud))
    }

    /// Keep the first and last time labels inside the chart.
    private func anchor(for index: Int, of count: Int) -> UnitPoint {
        switch index {
        case 0: .topLeading
        case count - 1: .topTrailing
        default: .top
        }
    }

    private func accessibilityText(loud: [LoudEvent]) -> String {
        var text = "Average \(Int(analysis.average.rounded())) decibels. "
            + NightChartSummary.text(loud: loud.count, woke: insights?.noiseLinkedWakeups) + "."
        if let loudest = loud.max(by: { $0.peak < $1.peak }) {
            text += " Loudest \(Int(loudest.peak.rounded())) decibels at \(loudest.start.formatted(date: .omitted, time: .shortened))."
        }
        if hasStages { text += " Sleep stages from Garmin are shaded behind." }
        return text
    }

    /// Small and muted: it explains the shading but shouldn't compete with the noise line.
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(SleepStage.allCases, id: \.self) { stage in
                HStack(spacing: 3) {
                    Circle()
                        .fill(stage.color.opacity(stage == .awake ? 0.6 : 0.35))
                        .frame(width: 7, height: 7)
                    Text(stage.label)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.loop(.caption2))
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
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
