import SwiftUI

/// Settings tab: recording settings, and demo data in debug builds.
struct SettingsView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var recorder: NightRecorder
    @EnvironmentObject private var health: HealthDataStore
    @AppStorage("calibrationOffset") private var calibrationOffset = 95.0
    @AppStorage("saveAudio") private var saveAudio = true
    @AppStorage(ClipGain.settingKey) private var boostClips = true
    @AppStorage(AutoStop.enabledKey) private var autoStopEnabled = true
    @AppStorage(AutoStop.minutesKey) private var autoStopMinutes = AutoStop.defaultMinutes
    #if DEBUG
    @State private var addingDemo = false
    #endif

    var body: some View {
        NavigationStack {
            List {
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
                    Text("Recording")
                } footer: {
                    Text("Saving audio lets you play back loud moments (about 15 MB per hour). Boost makes played-back noises easier to hear; recordings and readings aren't changed. With automatic stop on, recording ends at the set time and the report is ready when you wake. The calibration offset converts the microphone's digital level to approximate real-world decibels. To calibrate, compare with a sound meter and adjust until the live readings match. Changes apply to new recordings.")
                }
                .listRowBackground(Color.loopSurface)
                .disabled(recorder.isRecording)

                Section {
                    if health.connected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.loopGood)
                        let missing = HealthCoverage.missing(in: health.snapshots)
                        if !health.snapshots.isEmpty, !missing.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Not arriving from Garmin")
                                Text(missing.map(\.name).joined(separator: ", "))
                                    .font(.loop(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button("Connect Apple Health") { Task { await health.connect() } }
                            .foregroundStyle(Color.loopAccent)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Loop Sense reads your Garmin data from Apple Health and never writes to it. Missing tiles on the Health tab mean Garmin Connect isn't sharing that data. \(HealthCoverage.neverSynced)")
                }
                .listRowBackground(Color.loopSurface)

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
                    Text("Debug builds only. Adds seven made-up nights with Garmin-style sleep stages, plus 21 days of made-up Garmin health data on the Health tab, for testing. Remove deletes only these, never real recordings.")
                }
                .listRowBackground(Color.loopSurface)
                .disabled(recorder.isRecording)
                #endif
            }
            .loopBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings").font(.loop(.headline))
                }
            }
        }
    }
}
