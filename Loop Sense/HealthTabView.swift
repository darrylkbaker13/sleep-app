import Charts
import SwiftUI

/// The Health tab: last night's Garmin sleep and key body numbers compared with your usual (H2).
struct HealthTabView: View {
    @EnvironmentObject private var health: HealthDataStore
    @EnvironmentObject private var store: SessionStore
    @State private var range: HealthRange = .day
    @State private var connecting = false
    /// Made-up Garmin data for the demo nights (debug builds), worked out once in the background.
    @State private var demoSnapshots: [DailySnapshot] = []

    /// Real snapshots, with the demo ones on top while demo nights exist.
    private var snapshots: [DailySnapshot] {
        guard !demoSnapshots.isEmpty else { return health.snapshots }
        let days = Set(demoSnapshots.map(\.day))
        return (health.snapshots.filter { !days.contains($0.day) } + demoSnapshots).sorted { $0.day < $1.day }
    }

    var body: some View {
        NavigationStack {
            Group {
                if snapshots.isEmpty {
                    connectView
                } else {
                    dashboard
                }
            }
            .loopBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Health").font(.loop(.headline)) }
            }
            .refreshable { await health.refresh() }
            #if DEBUG
            .task(id: store.sessions.filter(DemoData.isDemo).map(\.id)) {
                let demo = store.sessions.filter(DemoData.isDemo)
                demoSnapshots = demo.isEmpty ? [] : await Task.detached(priority: .userInitiated) {
                    DemoHealth.snapshots(for: demo)
                }.value
            }
            #endif
        }
    }

    private var connectView: some View {
        ContentUnavailableView {
            Label("Connect Apple Health", systemImage: "heart.text.square")
        } description: {
            Text(health.connected
                 ? "No Garmin data has arrived yet. Check that Garmin Connect is sharing with Apple Health, then pull to refresh."
                 : "See last night's sleep, resting heart rate, HRV and more from your Garmin, compared with what's normal for you. Garmin Connect shares them through Apple Health.")
        } actions: {
            if !health.connected {
                Button(connecting ? "Connecting…" : "Connect Apple Health") {
                    connecting = true
                    Task { await health.connect(); connecting = false }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.loopAccent)
                .foregroundStyle(Color.loopOnAccent)
                .disabled(connecting)
            }
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(HealthRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                SleepSummaryCard(snapshots: snapshots, range: range)

                let tiles = HealthMetric.allCases.filter { !$0.days(snapshots, range: range, today: Date()).isEmpty }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(tiles) { metric in
                        NavigationLink {
                            MetricDetailView(metric: metric, snapshots: snapshots)
                        } label: {
                            MetricTile(metric: metric, snapshots: snapshots, range: range)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if health.isRefreshing {
                    ProgressView().frame(maxWidth: .infinity)
                }
                Text("From Garmin via Apple Health. \"Usual\" is your average over the previous 14 days.")
                    .font(.loop(.caption))
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

/// Last night's time asleep, bed and wake times and a stage bar; averages for Week and Month.
private struct SleepSummaryCard: View {
    let snapshots: [DailySnapshot]
    let range: HealthRange

    private var nights: [DailySnapshot] {
        let withSleep = snapshots.filter { $0.asleep != nil }
        return Array(withSleep.suffix(range.days))
    }

    var body: some View {
        let nights = nights
        Card(range == .day ? "Last night's sleep" : "Sleep, \(range == .week ? "last 7 nights" : "last 30 nights")") {
            if nights.isEmpty {
                Text("No Garmin sleep in this period.").foregroundStyle(.secondary)
            } else {
                let avg = { (k: KeyPath<DailySnapshot, TimeInterval?>) in
                    nights.compactMap { $0[keyPath: k] }.reduce(0, +) / Double(nights.count)
                }
                let asleep = avg(\.asleep)
                HStack(alignment: .firstTextBaseline) {
                    Text(formatDuration(asleep)).font(.loop(.title)).monospacedDigit()
                    Text(range == .day ? "asleep" : "asleep on average").foregroundStyle(.secondary)
                    Spacer()
                }
                if range == .day, let n = nights.last, let bed = n.bedtime, let wake = n.wake {
                    Text("\(bed.formatted(date: .omitted, time: .shortened)) – \(wake.formatted(date: .omitted, time: .shortened))")
                        .font(.loop(.subheadline)).foregroundStyle(.secondary)
                }
                let parts: [(SleepStage, TimeInterval)] = [(.deep, avg(\.deep)), (.light, avg(\.light)), (.rem, avg(\.rem)), (.awake, avg(\.awake))]
                StageBar(parts: parts)
                HStack {
                    ForEach(parts, id: \.0) { stage, seconds in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle().fill(stage.color).frame(width: 8, height: 8)
                                Text(stage.label)
                            }
                            .font(.loop(.caption)).foregroundStyle(.secondary)
                            Text(formatDuration(seconds)).font(.loop(.subheadline)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// One horizontal bar split by sleep stage.
private struct StageBar: View {
    let parts: [(SleepStage, TimeInterval)]

    var body: some View {
        let total = max(parts.map(\.1).reduce(0, +), 1)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(parts, id: \.0) { stage, seconds in
                    Rectangle()
                        .fill(stage.color)
                        .frame(width: max(0, geo.size.width * seconds / total - 2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel(parts.map { "\($0.0.label) \(formatDuration($0.1))" }.joined(separator: ", "))
    }
}

/// One number with its comparison with usual (Day) or its average and a sparkline (Week, Month).
struct MetricTile: View {
    let metric: HealthMetric
    let snapshots: [DailySnapshot]
    let range: HealthRange

    var body: some View {
        let days = metric.days(snapshots, range: range, today: Date())
        let values = days.compactMap { metric.value(in: $0) }
        let shown = range == .day ? values.last : values.reduce(0, +) / Double(max(values.count, 1))
        VStack(alignment: .leading, spacing: 4) {
            Label(metric.name, systemImage: metric.symbol)
                .font(.loop(.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let shown {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(metric.format(shown)).font(.loop(.title2)).monospacedDigit()
                    Text(metric.unit).font(.loop(.caption)).foregroundStyle(.secondary)
                }
            }
            if range == .day, let today = days.last, let v = values.last,
               let c = UsualComparison(metric: metric, value: v, day: today.day, history: snapshots) {
                Text(c.text(for: metric))
                    .font(.loop(.caption))
                    .foregroundStyle(c.isGood ? Color.loopGood : Color.loopWarn)
            } else if range != .day, values.count > 1 {
                Chart(Array(days.enumerated()), id: \.offset) { i, d in
                    LineMark(x: .value("Day", i), y: .value(metric.name, metric.value(in: d) ?? 0))
                        .foregroundStyle(Color.loopAccent)
                        .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 22)
            } else {
                Text(range == .day ? (metric.isOvernight ? "last night" : "yesterday") : " ")
                    .font(.loop(.caption)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.loopSurface, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }
}

/// Detail for one metric. H3 adds the overnight chart against bedroom noise.
struct MetricDetailView: View {
    let metric: HealthMetric
    let snapshots: [DailySnapshot]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card("Last 14 days") {
                    let recent = Array(snapshots.filter { metric.value(in: $0) != nil }.suffix(14))
                    Chart(recent) { s in
                        BarMark(x: .value("Day", s.day, unit: .day), y: .value(metric.name, metric.value(in: s) ?? 0))
                            .foregroundStyle(Color.loopAccent)
                    }
                    .frame(height: 180)
                }
            }
            .padding()
        }
        .loopBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text(metric.name).font(.loop(.headline)) }
        }
    }
}
