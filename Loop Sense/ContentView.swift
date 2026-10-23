import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var recorder: NightRecorder
    @AppStorage("calibrationOffset") private var calibrationOffset = 95.0
    @AppStorage("saveAudio") private var saveAudio = true
    @AppStorage(ClipGain.settingKey) private var boostClips = true
    @AppStorage(AutoStop.enabledKey) private var autoStopEnabled = true
    @AppStorage(AutoStop.minutesKey) private var autoStopMinutes = AutoStop.defaultMinutes
    /// The night just recorded, shown in the morning check-in.
    @State private var checkInSession: SleepSession?
    #if DEBUG
    @State private var addingDemo = false
    #endif

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

                Section("Past nights") {
                    if pastSessions.isEmpty {
                        Text("No recordings yet. Tap Start before bed.")
                            .foregroundStyle(.secondary)
                    }
                    if pastSessions.count >= 2 {
                        NavigationLink {
                            TrendsView()
                        } label: {
                            Label("Trends across nights", systemImage: "chart.bar.xaxis")
                                .foregroundStyle(Color.loopAccent)
                        }
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

                Section {
                    Toggle("Save audio recording", isOn: $saveAudio)
                    if saveAudio {
                        Toggle("Boost quiet clips", isOn: $boostClips)
                    }
                    Toggle("Stop automatically", isOn: $autoStopEnabled)
                    if autoStopEnabled {
                        DatePicker("Stop at", selection: Binding(
                            get: { AutoStop.pickerDate(minutes: autoStopMinutes) },
                            set: { autoStopMinutes = AutoStop.minutes(from: $0) }
                        ), displayedComponents: .hourAndMinute)
                    }
                    VStack(alignment: .leading) {
                        Text("Calibration offset: +\(Int(calibrationOffset)) dB")
                        Slider(value: $calibrationOffset, in: 70...120, step: 1)
                    }
                } header: {
                    Text("Settings")
                } footer: {
                    Text("Saving audio lets you play back loud moments (about 15 MB per hour). Boost makes played-back noises easier to hear; recordings and readings aren't changed. With automatic stop on, recording ends at the set time and the report is ready when you wake. The calibration offset converts the microphone's digital level to approximate real-world decibels. To calibrate, compare with a sound meter and adjust until the live readings match. Changes apply to new recordings.")
                }
                .listRowBackground(Color.loopSurface)
                .disabled(recorder.isRecording)

                #if DEBUG
                Section {
                    Button(addingDemo ? "Adding demo nights…" : "Add 7 demo nights") {
                        addingDemo = true
                        Task {
                            await DemoData.add(to: store)
                            addingDemo = false
                        }
                    }
                    .disabled(addingDemo)
                    if DemoData.count(in: store) > 0 {
                        Button("Remove demo nights", role: .destructive) { DemoData.remove(from: store) }
                    }
                } header: {
                    Text("Demo data")
                } footer: {
                    Text("Debug builds only. Adds seven made-up nights with Garmin-style sleep stages for testing. Remove deletes only these, never real recordings.")
                }
                .listRowBackground(Color.loopSurface)
                .disabled(recorder.isRecording)
                #endif
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
                Label(recorder.isRecording ? "Stop & analyze" : "Start sleep recording",
                      systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? Color.loopRed : Color.loopAccent)
            .foregroundStyle(Color.loopOnAccent)
            .controlSize(.large)
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
