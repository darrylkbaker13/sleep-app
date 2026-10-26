import SwiftUI
import UIKit

/// The Sleep tab: start tracking, last night at a glance, then past nights.
struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var recorder: NightRecorder
    @AppStorage("calibrationOffset") private var calibrationOffset = 95.0
    @AppStorage("saveAudio") private var saveAudio = true
    @AppStorage(AutoStop.enabledKey) private var autoStopEnabled = true
    @AppStorage(AutoStop.minutesKey) private var autoStopMinutes = AutoStop.defaultMinutes
    /// The night just recorded, shown in the morning check-in.
    @State private var checkInSession: SleepSession?

    private var pastSessions: [SleepSession] {
        store.sessions.filter { $0.id != recorder.activeSessionID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RecordPanel(calibrationOffset: calibrationOffset, saveAudio: saveAudio,
                                autoStopMinutes: autoStopEnabled ? autoStopMinutes : nil)
                } header: {
                    // Drawn here rather than as a navigation title so it can use the brand font.
                    Text("Loop Sense")
                        .font(.loop(.largeTitle))
                        .foregroundStyle(Color.primary)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 8)
                }
                .listRowBackground(Color.loopSurface)

                if let lastNight = pastSessions.first, !recorder.isRecording {
                    Section("Last night") {
                        NavigationLink {
                            SessionDetailView(session: lastNight)
                        } label: {
                            LastNightCard(session: lastNight)
                        }
                    }
                    .listRowBackground(Color.loopSurface)
                }

                Section("Past nights") {
                    if pastSessions.isEmpty {
                        Text("No recordings yet. Tap Start before bed.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(pastSessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            SessionRow(session: session)
                        }
                    }
                    .onDelete { offsets in
                        for session in offsets.map({ pastSessions[$0] }) {
                            store.delete(session)
                        }
                    }
                }
                .listRowBackground(Color.loopSurface)
            }
            .loopBackground()
            .onChange(of: recorder.activeSessionID) { finished, current in
                // A recording just stopped: ask how the night went.
                if let finished, current == nil {
                    checkInSession = store.sessions.first { $0.id == finished }
                }
            }
            .sheet(item: $checkInSession) { session in
                CheckInView(session: session) { updated in
                    if let updated { store.save(updated) }
                    checkInSession = nil
                }
            }
            .navigationTitle("Loop Sense")
            .toolbar(.hidden, for: .navigationBar)
            .alert("Recording problem", isPresented: Binding(
                get: { recorder.errorMessage != nil },
                set: { if !$0 { recorder.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recorder.errorMessage ?? "")
            }
        }
    }
}

private struct RecordPanel: View {
    @EnvironmentObject private var recorder: NightRecorder
    let calibrationOffset: Double
    let saveAudio: Bool
    /// Morning stop time in minutes after midnight, or nil when automatic stop is off.
    let autoStopMinutes: Int?
    @State private var bedtimeWarnings: [String] = []

    var body: some View {
        VStack(spacing: 16) {
            if recorder.isRecording, let start = recorder.startDate {
                Text("\(Int((Double(recorder.currentLevel) + calibrationOffset).rounded())) dB")
                    .font(.loop(size: 56, relativeTo: .largeTitle))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: recorder.currentLevel)
                Text("Recording for \(Text(start, style: .timer))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let stop = recorder.stopDate {
                    Label("Stops at \(stop.formatted(date: .omitted, time: .shortened))", systemImage: "alarm")
                        .font(.loop(.footnote))
                        .foregroundStyle(.secondary)
                }
                Text("You can lock your phone. Recording continues in the background.")
                    .font(.loop(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.loopAccent)
                Text("Plug in your phone and place it near your bed, mic uncovered.")
                    .font(.loop(.footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    let warnings = BedtimeChecks.current().warnings
                    if warnings.isEmpty { startRecording() } else { bedtimeWarnings = warnings }
                }
            } label: {
                Label(recorder.isRecording ? "Stop & analyze" : "Start sleep tracking",
                      systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? Color.loopRed : Color.loopAccent)
            .foregroundStyle(Color.loopOnAccent)
            .controlSize(.large)

            if !recorder.isRecording {
                RecordingStatus(saveAudio: saveAudio, autoStopMinutes: autoStopMinutes)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .alert("Before you sleep", isPresented: Binding(
            get: { !bedtimeWarnings.isEmpty },
            set: { if !$0 { bedtimeWarnings = [] } }
        )) {
            Button("Start anyway") { startRecording() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(bedtimeWarnings.joined(separator: "\n\n"))
        }
    }

    private func startRecording() {
        let stopAt = autoStopMinutes.map { AutoStop.stopDate(after: Date(), minutes: $0) }
        Task { await recorder.start(calibrationOffset: calibrationOffset, saveAudio: saveAudio, stopAt: stopAt) }
    }
}

/// Small status line under the Start button: auto stop, audio and charging.
private struct RecordingStatus: View {
    let saveAudio: Bool
    let autoStopMinutes: Int?
    @State private var battery = BatteryStatus.current()

    var body: some View {
        HStack(spacing: 14) {
            if let m = autoStopMinutes {
                Label("Stops \(AutoStop.pickerDate(minutes: m).formatted(date: .omitted, time: .shortened))", systemImage: "alarm")
            } else {
                Label("No auto stop", systemImage: "alarm")
            }
            Label(saveAudio ? "Audio on" : "Audio off", systemImage: saveAudio ? "waveform" : "waveform.slash")
            Label(battery.text, systemImage: battery.symbol)
                .foregroundStyle(battery.isConcern ? Color.loopWarn : Color.secondary)
        }
        .font(.loop(.caption))
        .foregroundStyle(.secondary)
        .labelStyle(CompactLabelStyle())
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            battery = BatteryStatus.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            battery = BatteryStatus.current()
        }
        .onAppear { battery = BatteryStatus.current() }
        .accessibilityElement(children: .combine)
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

/// Charging state for the status line. Battery monitoring stays on while the Sleep tab is shown.
struct BatteryStatus {
    let text: String
    let symbol: String
    /// Unplugged and under the bedtime-check threshold.
    let isConcern: Bool

    @MainActor static func current() -> BatteryStatus {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        switch device.batteryState {
        case .charging, .full:
            return BatteryStatus(text: "Charging", symbol: "battery.100.bolt", isConcern: false)
        case .unplugged where level >= 0:
            let pct = Int((level * 100).rounded())
            return BatteryStatus(text: "\(pct)%", symbol: "battery.50", isConcern: level < BedtimeChecks.minimumUnpluggedBattery)
        default:
            return BatteryStatus(text: "Battery", symbol: "battery.50", isConcern: false)
        }
    }
}

/// Last night at a glance: headline, noises, main source and time asleep. Opens the report.
private struct LastNightCard: View {
    let session: SleepSession
    @AppStorage("healthConnected") private var healthConnected = false
    @State private var analysis: NightAnalysis?
    @State private var asleep: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.start, format: .dateTime.weekday(.wide).day().month())
                .font(.loop(.caption)).foregroundStyle(.secondary)
            if let a = analysis {
                Text(a.headline)
                    .font(.loop(.title3))
                    .foregroundStyle(a.verdictTone.color)
                Text(a.subline).font(.loop(.subheadline))
                let source = NoiseSources(events: a.events, session: session)
                if let source, let main = source.counts.first(where: { $0.category != .unknown }) {
                    Label("Mostly \(NoiseSources.inSentence(main.category)) (\(main.count) of \(source.total))",
                          systemImage: main.category.symbol)
                        .font(.loop(.caption))
                        .foregroundStyle(main.category.color)
                }
                if let asleep {
                    Label("\(formatDuration(asleep)) asleep", systemImage: "bed.double.fill")
                        .font(.loop(.caption)).foregroundStyle(.secondary)
                }
            } else {
                Text("Recording too short for a report").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .task(id: session.id) {
            let s = session
            analysis = await Task.detached(priority: .userInitiated) { NightAnalysis(session: s) }.value
            asleep = await timeAsleep()
        }
    }

    private func timeAsleep() async -> TimeInterval? {
        var stages: [SleepInterval] = []
        #if DEBUG
        if DemoData.isDemo(session) { stages = DemoData.stages(for: session) }
        #endif
        if stages.isEmpty, healthConnected, HealthSleep.isAvailable {
            stages = (try? await HealthSleep.intervals(from: session.start, to: session.effectiveEnd)) ?? []
        }
        let total = stages.filter { $0.stage != .awake }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return total > 0 ? total : nil
    }
}

private struct SessionRow: View {
    let session: SleepSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.start, format: .dateTime.weekday(.wide).month().day())
                    .font(.loop(.headline))
                Text("\(session.start.formatted(date: .omitted, time: .shortened)) – \(session.effectiveEnd.formatted(date: .omitted, time: .shortened)) · \(formatDuration(session.duration))")
                    .font(.loop(.subheadline))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let avg = session.quickAverage {
                Text("\(Int(avg.rounded())) dB")
                    .font(.loop(.headline))
                    .monospacedDigit()
                    .foregroundStyle(levelColor(avg))
            }
        }
    }
}

nonisolated func formatDuration(_ seconds: TimeInterval) -> String {
    let f = DateComponentsFormatter()
    f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
    f.unitsStyle = .abbreviated
    return f.string(from: seconds) ?? ""
}
