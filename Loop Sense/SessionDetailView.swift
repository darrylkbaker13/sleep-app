import AVFoundation
import Combine
import Charts
import SwiftUI

struct SessionDetailView: View {
    let session: SleepSession
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var recorder: NightRecorder
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var player = ClipPlayer()
    @State private var analysis: NightAnalysis?
    @State private var loaded = false
    @State private var csvURL: URL?
    @State private var editingCheckIn = false
    @State private var showingAbout = false
    @State private var moreDetailOpen = false
    @State private var showingHighlights = false
    /// Garmin sleep stages, loaded by the night chart and shared with the sleep card.
    @State private var stages: [SleepInterval]?

    /// The latest saved copy, so check-in edits show straight away.
    private var current: SleepSession {
        store.sessions.first { $0.id == session.id } ?? session
    }

    var body: some View {
        Group {
            if let analysis {
                report(analysis)
            } else if loaded {
                ScrollView {
                    VStack(spacing: 20) {
                        ContentUnavailableView("Not enough data", systemImage: "waveform.slash",
                                               description: Text("This recording is shorter than a minute."))
                        SleepNotesCard(session: current) { editingCheckIn = true }
                    }
                    .padding()
                }
            } else {
                ProgressView("Analyzing…")
            }
        }
        .navigationTitle(session.start.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .loopBackground()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(session.start.formatted(.dateTime.month().day()))
                    .font(.loop(.headline))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAbout = true } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About these readings")
            }
        }
        .task {
            let session = session
            let result = await Task.detached(priority: .userInitiated) {
                (NightAnalysis(session: session), try? CSVExporter.write(session))
            }.value
            analysis = result.0
            csvURL = result.1
            loaded = true
        }
        .onDisappear { player.stop() }
        .sheet(isPresented: $editingCheckIn) {
            CheckInView(session: current) { updated in
                if let updated { store.save(updated) }
                editingCheckIn = false
            }
        }
        .sheet(isPresented: $showingAbout) { AboutReadingsSheet() }
    }

    @ViewBuilder
    private func report(_ a: NightAnalysis) -> some View {
        let byLoudness = a.events.sorted { $0.peak > $1.peak }
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Above the fold: the answer, the numbers and the night at a glance.
                    ReportHeadline(
                        title: a.headline, tone: a.verdictTone, subline: a.subline,
                        caption: "\(a.start.formatted(date: .omitted, time: .shortened)) – \(a.end.formatted(date: .omitted, time: .shortened)) · \(formatDuration(a.end.timeIntervalSince(a.start)))",
                        chips: a.chips)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                             count: typeSize.isAccessibilitySize ? 2 : 4),
                              spacing: 8) {
                        StatTile(title: "Average", value: a.average, caption: "WHO ≤ 30")
                        StatTile(title: "Background", value: a.background, caption: "fans, traffic")
                        StatTile(title: "Loudest", value: a.peak, caption: a.peakTime.formatted(date: .omitted, time: .shortened))
                        StatTile(title: "Noises", count: a.events.count, caption: "\(a.eventsOverWHOPeak) over 45")
                    }

                    NightChartCard(session: session, analysis: a, stages: $stages)

                    // Highlights need the saved audio; hidden when it was off for this night.
                    if !byLoudness.isEmpty, let audio = store.audioURL(for: session) {
                        Button { showingHighlights = true } label: {
                            Label("Play highlights", systemImage: "play.square.stack.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.loopAccent)
                        .foregroundStyle(Color.loopOnAccent)
                        .controlSize(.large)
                        .disabled(recorder.isRecording)
                        .sheet(isPresented: $showingHighlights, onDismiss: { player.stop() }) {
                            HighlightsView(session: session, audio: audio, events: a.events,
                                           background: a.background - session.calibrationOffset)
                        }
                    }

                    if !byLoudness.isEmpty {
                        Card("Loudest moments") {
                            ForEach(byLoudness.prefix(3)) { event in
                                eventRow(event)
                                if event.id != byLoudness.prefix(3).last?.id { Divider() }
                            }
                            if byLoudness.count > 3 {
                                Button("See all \(byLoudness.count)") {
                                    withAnimation { moreDetailOpen = true }
                                    // Wait for the list to appear before scrolling to it.
                                    Task {
                                        try? await Task.sleep(for: .milliseconds(350))
                                        withAnimation { scroller.scrollTo("allNoises", anchor: .top) }
                                    }
                                }
                                .font(.loop(.subheadline))
                                .foregroundStyle(Color.loopAccent)
                            }
                        }
                    }

                    SleepNotesCard(session: current) { editingCheckIn = true }

                    // The chart card shows only the most important sleep insight; the rest live here.
                    if let stages, !stages.isEmpty {
                        let more = SleepInsights(intervals: stages, session: session, analysis: a).chips.dropFirst()
                        if !more.isEmpty {
                            Card("Your sleep") {
                                ChipRow(chips: Array(more))
                            }
                        }
                    }

                    EarplugCard(recommendation: EarplugRecommendation(average: a.average, peak: a.peak))

                    moreDetail(a, byLoudness: byLoudness)
                }
                .padding()
            }
        }
    }

    /// Everything that isn't needed to answer "how was my night?".
    private func moreDetail(_ a: NightAnalysis, byLoudness: [LoudEvent]) -> some View {
        DisclosureGroup(isExpanded: $moreDetailOpen) {
            VStack(alignment: .leading, spacing: 16) {
                Card("Time at each level") {
                    ForEach(a.bands) { band in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(band.label)
                                Text(band.range).foregroundStyle(.secondary)
                                Spacer()
                                Text(band.fraction, format: .percent.precision(.fractionLength(0)))
                                    .monospacedDigit()
                            }
                            .font(.loop(.subheadline))
                            ProgressView(value: band.fraction)
                                .tint(levelColor(band.lowerBound))
                        }
                    }
                }

                if !a.hours.isEmpty {
                    Card("Hour by hour") {
                        Chart(a.hours) { h in
                            BarMark(x: .value("Hour", h.hour, unit: .hour), y: .value("Average", h.average))
                                .foregroundStyle(levelColor(h.average))
                        }
                        .chartYAxisLabel("dB")
                        .frame(height: 160)
                    }
                }

                if !byLoudness.isEmpty {
                    Card("All noises") {
                        Text("At least \(Int(a.eventThreshold.rounded())) dB, 10 dB over background.")
                            .font(.loop(.caption))
                            .foregroundStyle(.secondary)
                        ForEach(byLoudness) { event in
                            eventRow(event)
                            Divider()
                        }
                    }
                    .id("allNoises")
                }

                Card("Export") {
                    if let csvURL {
                        ShareLink("Levels (CSV)", item: csvURL)
                    }
                    if let audio = store.audioURL(for: session) {
                        ShareLink("Audio recording", item: audio)
                    }
                }
                .foregroundStyle(Color.loopAccent)

                #if DEBUG
                if let audio = store.audioURL(for: session) {
                    ClassifierSpikeCard(session: session, audio: audio, events: a.events)
                }
                #endif
            }
            .padding(.top, 12)
        } label: {
            Text("More detail").font(.loop(.headline))
        }
        .tint(Color.loopAccent)
    }

    private func eventRow(_ event: LoudEvent) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(event.start.formatted(date: .omitted, time: .standard)).monospacedDigit()
                Text(formatDuration(event.duration)).font(.loop(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(event.peak.rounded())) dB")
                .bold()
                .monospacedDigit()
                .foregroundStyle(levelColor(event.peak))
            if let audio = store.audioURL(for: session) {
                Button {
                    if player.playingID == event.id {
                        player.stop()
                    } else {
                        player.play(url: audio, from: event.audioOffset - 2, duration: event.duration + 4, id: event.id,
                                    background: analysis.map { $0.background - session.calibrationOffset })
                    }
                } label: {
                    Image(systemName: player.playingID == event.id ? "stop.circle.fill" : "play.circle.fill")
                        .font(.loop(.title2))
                }
                .buttonStyle(.borderless)
                .disabled(recorder.isRecording)
                .accessibilityLabel(player.playingID == event.id ? "Stop" : "Play this noise")
            }
        }
    }
}

/// The disclaimer, now behind the ⓘ button.
private struct AboutReadingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("About these readings").font(.loop(.title3))
                    Text("Readings are approximate and unweighted. Phone microphones aren't calibrated sound meters, so treat the numbers as a guide and compare nights with each other.")
                    Text("The WHO recommends a bedroom average of 30 dB or less, and no more than 10–15 noises above 45 dB a night.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .loopBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color.loopMidnight)
    }
}

private struct StatTile: View {
    let title: String
    var value: Double? = nil
    var count: Int? = nil
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.loop(.caption2)).foregroundStyle(.secondary)
            Group {
                if let value {
                    Text("\(Int(value.rounded())) dB").foregroundStyle(levelColor(value))
                } else if let count {
                    Text("\(count)")
                }
            }
            .font(.loop(.title3)).monospacedDigit()
            .minimumScaleFactor(0.8)
            Text(caption).font(.loop(.caption2)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.loopSurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct Card<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.loop(.headline))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.loopSurface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct EarplugCard: View {
    let recommendation: EarplugRecommendation

    var body: some View {
        Card("Loop earplugs for this room") {
            if let model = recommendation.model {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.name).font(.loop(.title3))
                    Spacer()
                    Text(model.snrText)
                        .font(.loop(.subheadline)).monospacedDigit()
                        .foregroundStyle(Color.loopAccent)
                }
                Text(model.note).font(.loop(.subheadline)).foregroundStyle(.secondary)
            }
            Text(recommendation.summary)
            DisclosureGroup("Why this one") {
                Text(recommendation.reason)
                    .font(.loop(.subheadline))
                    .padding(.top, 4)
            }
            .font(.loop(.subheadline))
            .tint(Color.loopAccent)
            Text("A guide: real-world reduction is lower than SNR.")
                .font(.loop(.caption))
                .foregroundStyle(.secondary)
            Link(destination: LoopModel.siteURL) {
                Label("See Loop earplugs", systemImage: "arrow.up.right.square")
            }
            .foregroundStyle(Color.loopAccent)
            DisclosureGroup("Compare Loop models") {
                ForEach(LoopModel.all.filter { !$0.kidsOnly }) { m in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name)
                            Text(m.note).font(.loop(.caption)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(m.snrText).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.loop(.subheadline))
                    .padding(.top, 6)
                }
            }
            .font(.loop(.subheadline))
            .tint(Color.loopAccent)
        }
    }
}

#if DEBUG
/// I2a spike: runs Apple's sound classifier over this night's audio and lists the top labels per
/// noise event. Debug builds only; the text can be shared for the write-up.
private struct ClassifierSpikeCard: View {
    let session: SleepSession
    let audio: URL
    let events: [LoudEvent]
    @State private var report: String?
    @State private var running = false

    var body: some View {
        Card("Name the noises (debug)") {
            if let report {
                Text(report)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                ShareLink("Share results", item: report)
                    .foregroundStyle(Color.loopAccent)
            } else {
                Text("Runs Apple's built-in sound classifier over this night's audio and lists the top 3 labels for each noise event.")
                    .foregroundStyle(.secondary)
                Button(running ? "Classifying…" : "Run sound classifier") { run() }
                    .disabled(running)
                    .foregroundStyle(Color.loopAccent)
            }
        }
    }

    private func run() {
        running = true
        let session = session, audio = audio, events = events
        Task {
            let text = await Task.detached(priority: .userInitiated) {
                do {
                    let result = try SoundClassifier.classify(fileAt: audio, events: events)
                    let title = "Night of \(session.start.formatted(date: .abbreviated, time: .shortened)) (on device)"
                    return SoundClassifier.report(result, title: title)
                } catch {
                    return "Classifier failed: \(error.localizedDescription)"
                }
            }.value
            report = text
            running = false
        }
    }
}
#endif
