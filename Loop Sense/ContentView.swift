import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var recorder: NightRecorder
    @AppStorage("calibrationOffset") private var calibrationOffset = 95.0
    @AppStorage("saveAudio") private var saveAudio = true

    private var pastSessions: [SleepSession] {
        store.sessions.filter { $0.id != recorder.activeSessionID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RecordPanel(calibrationOffset: calibrationOffset, saveAudio: saveAudio)
                }
                .listRowBackground(Color.loopSurface)

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

                Section {
                    Toggle("Save audio recording", isOn: $saveAudio)
                    VStack(alignment: .leading) {
                        Text("Calibration offset: +\(Int(calibrationOffset)) dB")
                        Slider(value: $calibrationOffset, in: 70...120, step: 1)
                    }
                } header: {
                    Text("Settings")
                } footer: {
                    Text("Saving audio lets you play back loud moments (about 15 MB per hour). The calibration offset converts the microphone's digital level to approximate real-world decibels. To calibrate, compare with a sound meter and adjust until the live readings match. Changes apply to new recordings.")
                }
                .listRowBackground(Color.loopSurface)
                .disabled(recorder.isRecording)
            }
            .loopBackground()
            .navigationTitle("Sleep Sound")
            .toolbarBackground(Color.loopMidnight, for: .navigationBar)
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

    var body: some View {
        VStack(spacing: 16) {
            if recorder.isRecording, let start = recorder.startDate {
                Text("\(Int((Double(recorder.currentLevel) + calibrationOffset).rounded())) dB")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: recorder.currentLevel)
                Text("Recording for \(Text(start, style: .timer))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("You can lock your phone. Recording continues in the background.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.loopGold)
                Text("Plug in your phone and place it near your bed, mic uncovered.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    Task { await recorder.start(calibrationOffset: calibrationOffset, saveAudio: saveAudio) }
                }
            } label: {
                Label(recorder.isRecording ? "Stop & analyze" : "Start sleep recording",
                      systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? Color.loopRed : Color.loopGold)
            .foregroundStyle(recorder.isRecording ? Color.white : Color.loopMidnight)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct SessionRow: View {
    let session: SleepSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.start, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                Text("\(session.start.formatted(date: .omitted, time: .shortened)) – \(session.effectiveEnd.formatted(date: .omitted, time: .shortened)) · \(formatDuration(session.duration))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let avg = session.quickAverage {
                Text("\(Int(avg.rounded())) dB")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(levelColor(avg))
            }
        }
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let f = DateComponentsFormatter()
    f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
    f.unitsStyle = .abbreviated
    return f.string(from: seconds) ?? ""
}
