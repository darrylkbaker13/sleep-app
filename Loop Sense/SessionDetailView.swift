import AVFoundation
import Combine
import Charts
import SwiftUI

struct SessionDetailView: View {
    let session: SleepSession
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var recorder: NightRecorder
    @StateObject private var player = ClipPlayer()
    @State private var analysis: NightAnalysis?
    @State private var loaded = false
    @State private var csvURL: URL?
    @State private var editingCheckIn = false

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
                Menu {
                    if let csvURL {
                        ShareLink("Export levels (CSV)", item: csvURL)
                    }
                    if let audio = store.audioURL(for: session) {
                        ShareLink("Export audio", item: audio)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
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
    }

    @ViewBuilder
    private func report(_ a: NightAnalysis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Headline
                VStack(alignment: .leading, spacing: 4) {
                    Text(a.verdict).font(.loop(.title2))
                    Text("\(a.start.formatted(date: .omitted, time: .shortened)) – \(a.end.formatted(date: .omitted, time: .shortened)) · \(formatDuration(a.end.timeIntervalSince(a.start)))")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Average", value: a.average, caption: "WHO target ≤ 30")
                    StatTile(title: "Background", value: a.background, caption: "steady noise floor")
                    StatTile(title: "Loudest", value: a.peak, caption: a.peakTime.formatted(date: .omitted, time: .shortened))
                    StatTile(title: "Noise events", count: a.events.count, caption: "\(a.eventsOverWHOPeak) above 45 dB")
                }

                Card("Through the night") {
                    Chart {
                        ForEach(a.chart) { p in
                            AreaMark(x: .value("Time", p.time), yStart: .value("Avg", p.average), yEnd: .value("Peak", p.peak))
                                .foregroundStyle(Color.loopRoseGold.opacity(0.3))
                            LineMark(x: .value("Time", p.time), y: .value("Average", p.average))
                                .foregroundStyle(Color.loopAccent)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                        RuleMark(y: .value("WHO", WHO.averageLimit))
                            .foregroundStyle(Color.loopSilver.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("WHO 30 dB").font(.loop(.caption2)).foregroundStyle(Color.loopSilver)
                            }
                    }
                    .chartYAxisLabel("dB")
                    .chartXScale(domain: a.start...a.end)
                    .frame(height: 220)
                    HStack(spacing: 16) {
                        Legend(color: .loopAccent, label: "Minute average")
                        Legend(color: .loopRoseGold.opacity(0.6), label: "Minute peak")
                    }
                    .font(.loop(.caption))
                }

                SleepNotesCard(session: current) { editingCheckIn = true }

                SleepStagesCard(session: session, analysis: a)

                Card("What this means") {
                    ForEach(a.findings, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(line)
                        }
                    }
                }

                EarplugCard(recommendation: EarplugRecommendation(average: a.average, peak: a.peak))

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

                if !a.events.isEmpty {
                    Card("Loudest moments") {
                        Text("Noises at least \(Int(a.eventThreshold.rounded())) dB (10 dB above background).")
                            .font(.loop(.caption))
                            .foregroundStyle(.secondary)
                        ForEach(a.events.sorted { $0.peak > $1.peak }.prefix(25)) { event in
                            eventRow(event)
                            Divider()
                        }
                    }
                }

                Text("Readings are approximate and unweighted. Phone microphones aren't calibrated sound meters, so treat the numbers as a guide and compare nights with each other.")
                    .font(.loop(.footnote))
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
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
                        player.play(url: audio, from: event.audioOffset - 2, duration: event.duration + 4, id: event.id)
                    }
                } label: {
                    Image(systemName: player.playingID == event.id ? "stop.circle.fill" : "play.circle.fill")
                        .font(.loop(.title2))
                }
                .buttonStyle(.borderless)
                .disabled(recorder.isRecording)
            }
        }
    }
}

private struct StatTile: View {
    let title: String
    var value: Double? = nil
    var count: Int? = nil
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.loop(.caption)).foregroundStyle(.secondary)
            if let value {
                Text("\(Int(value.rounded())) dB")
                    .font(.loop(.title)).monospacedDigit()
                    .foregroundStyle(levelColor(value))
            } else if let count {
                Text("\(count)").font(.loop(.title)).monospacedDigit()
            }
            Text(caption).font(.loop(.caption2)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.loopSurface, in: RoundedRectangle(cornerRadius: 12))
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
            Text(recommendation.reason)
            Text("A guide only. SNR is a lab rating; real-world reduction is usually lower and depends on fit.")
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

private struct Legend: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class ClipPlayer: ObservableObject {
    @Published private(set) var playingID: UUID?
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(url: URL, from start: TimeInterval, duration: TimeInterval, id: UUID) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.currentTime = max(0, start)
            p.play()
            player = p
            playingID = id
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled { self?.stop() }
            }
        } catch {
            print("Playback failed: \(error)")
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        playingID = nil
    }
}
