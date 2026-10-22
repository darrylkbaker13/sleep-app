import Charts
import SwiftUI

/// One night's headline numbers, from the same analysis the night report uses.
nonisolated struct NightSummary: Identifiable {
    let id: UUID
    let start: Date
    let average: Double
    let events: Int
    /// Short unique chart label, e.g. "21 Oct" (with the time added if two nights share a date).
    var label: String

    static func make(from sessions: [SleepSession]) -> [NightSummary] {
        var nights = sessions
            .sorted { $0.start < $1.start }
            .compactMap { s -> NightSummary? in
                guard let a = NightAnalysis(session: s) else { return nil }
                return NightSummary(id: s.id, start: s.start, average: a.average, events: a.events.count,
                                    label: s.start.formatted(.dateTime.day().month()))
            }
        let counts = Dictionary(grouping: nights, by: \.label).mapValues(\.count)
        for i in nights.indices where counts[nights[i].label, default: 0] > 1 {
            nights[i].label += " " + nights[i].start.formatted(date: .omitted, time: .shortened)
        }
        return nights
    }
}

struct TrendsView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var recorder: NightRecorder
    @State private var all: [NightSummary]?
    @State private var range = 7
    @State private var openSessionID: UUID?
    @State private var earplugComparison: EarplugComparison?
    @AppStorage("healthConnected") private var healthConnected = false

    private var nights: [NightSummary] { Array((all ?? []).suffix(range)) }
    private var quietest: NightSummary? { nights.min { $0.average < $1.average } }
    private var noisiest: NightSummary? { nights.max { $0.average < $1.average } }

    var body: some View {
        Group {
            if all == nil {
                ProgressView("Analyzing nights…")
            } else if nights.count < 2 {
                ContentUnavailableView("Not enough nights yet", systemImage: "chart.bar.xaxis",
                                       description: Text("Record at least two nights longer than a minute to see trends."))
            } else {
                content
            }
        }
        .loopBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Trends").font(.loop(.headline))
            }
        }
        .navigationDestination(item: $openSessionID) { id in
            if let session = store.sessions.first(where: { $0.id == id }) {
                SessionDetailView(session: session)
            }
        }
        .task(id: ComparisonKey(range: range, sessions: store.sessions)) {
            await loadEarplugComparison()
        }
        .task(id: store.sessions.map(\.id)) {
            let sessions = store.sessions.filter { $0.id != recorder.activeSessionID }
            all = await Task.detached(priority: .userInitiated) { NightSummary.make(from: sessions) }.value
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Range", selection: $range) {
                    Text("Last 7 nights").tag(7)
                    Text("Last 30 nights").tag(30)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    if let quietest { highlightTile("Quietest night", quietest) }
                    if let noisiest { highlightTile("Noisiest night", noisiest) }
                }

                Card("Average level") {
                    Chart {
                        ForEach(nights) { n in
                            BarMark(x: .value("Night", n.label), y: .value("Average", n.average))
                                .foregroundStyle(levelColor(n.average))
                                .annotation(position: .top) { badge(for: n) }
                        }
                        RuleMark(y: .value("WHO", WHO.averageLimit))
                            .foregroundStyle(Color.loopSilver.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("WHO 30 dB").font(.loop(.caption2)).foregroundStyle(Color.loopSilver)
                            }
                    }
                    .chartOverlay(content: tapToOpen)
                    .chartYAxisLabel("dB")
                    .chartXAxis { xAxis }
                    .frame(height: 200)
                }

                Card("Noise events") {
                    Chart(nights) { n in
                        BarMark(x: .value("Night", n.label), y: .value("Events", n.events))
                            .foregroundStyle(Color.loopRoseGold)
                    }
                    .chartOverlay(content: tapToOpen)
                    .chartXAxis { xAxis }
                    .frame(height: 160)
                    Text("Noises at least 10 dB above that night's background. Tap a bar to open the night.")
                        .font(.loop(.caption))
                        .foregroundStyle(.secondary)
                }

                if let earplugComparison {
                    EarplugComparisonCard(comparison: earplugComparison)
                }

                Card("Nights") {
                    ForEach(nights.reversed()) { n in
                        Button { openSessionID = n.id } label: { nightRow(n) }
                            .buttonStyle(.plain)
                        if n.id != nights.first?.id { Divider() }
                    }
                }
            }
            .padding()
        }
    }

    /// With many nights the date labels would overlap, so label at most seven of them.
    private var xAxis: some AxisContent {
        let step = max(1, Int((Double(nights.count) / 7).rounded(.up)))
        let shown = nights.enumerated().filter { $0.offset % step == 0 }.map(\.element.label)
        return AxisMarks(values: shown) { _ in
            AxisValueLabel().font(.loop(.caption2))
        }
    }

    /// Reloads when the range changes or a night's earplug tag is edited.
    private struct ComparisonKey: Equatable {
        let range: Int
        let tags: [String]
        init(range: Int, sessions: [SleepSession]) {
            self.range = range
            tags = sessions.map { "\($0.id)|\($0.earplugs ?? "")" }
        }
    }

    /// Analyses the nights in range and fetches their sleep stages, then compares earplug nights.
    private func loadEarplugComparison() async {
        let sessions = Array(store.sessions
            .filter { $0.id != recorder.activeSessionID }
            .sorted { $0.start < $1.start }
            .suffix(range))
        let analysed = await Task.detached(priority: .userInitiated) {
            sessions.compactMap { s in NightAnalysis(session: s).map { (s, $0) } }
        }.value
        var nights: [EarplugComparison.Night] = []
        for (session, analysis) in analysed {
            nights.append(.init(session: session, analysis: analysis, stages: await stages(for: session)))
        }
        earplugComparison = EarplugComparison(nights: nights)
    }

    private func stages(for session: SleepSession) async -> [SleepInterval] {
        #if DEBUG
        if DemoData.isDemo(session) { return DemoData.stages(for: session) }
        #endif
        guard healthConnected, HealthSleep.isAvailable else { return [] }
        return (try? await HealthSleep.intervals(from: session.start, to: session.effectiveEnd)) ?? []
    }

    /// Tapping a bar opens that night's report.
    private func tapToOpen(_ proxy: ChartProxy) -> some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onTapGesture { location in
                    guard let plot = proxy.plotFrame else { return }
                    let x = location.x - geo[plot].origin.x
                    guard let label: String = proxy.value(atX: x),
                          let night = nights.first(where: { $0.label == label }) else { return }
                    openSessionID = night.id
                }
        }
    }

    @ViewBuilder
    private func badge(for n: NightSummary) -> some View {
        if n.id == quietest?.id {
            Text("Quietest").font(.loop(.caption2)).foregroundStyle(Color.loopSilver).fixedSize()
        } else if n.id == noisiest?.id {
            Text("Noisiest").font(.loop(.caption2)).foregroundStyle(Color.loopRed).fixedSize()
        }
    }

    private func highlightTile(_ title: String, _ n: NightSummary) -> some View {
        Button { openSessionID = n.id } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.loop(.caption)).foregroundStyle(.secondary)
                Text("\(Int(n.average.rounded())) dB")
                    .font(.loop(.title)).monospacedDigit()
                    .foregroundStyle(levelColor(n.average))
                Text(n.start.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.loop(.caption2)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.loopSurface, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func nightRow(_ n: NightSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(n.start.formatted(.dateTime.weekday(.wide).day().month()))
                Text("\(n.events) noise events").font(.loop(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(n.average.rounded())) dB")
                .monospacedDigit()
                .foregroundStyle(levelColor(n.average))
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
