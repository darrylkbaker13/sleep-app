import SwiftUI

/// "Last night's highlights": the loudest few noises played back to back, each named by the
/// sound classifier, with skip and per-clip share.
struct HighlightsView: View {
    let session: SleepSession
    let audio: URL
    let events: [LoudEvent]
    /// Night's background level in dBFS, used by the playback boost.
    let background: Double?

    @StateObject private var player = ClipPlayer()
    @AppStorage(ClipGain.settingKey) private var boost = true
    @Environment(\.dismiss) private var dismiss
    @State private var highlights: [Highlight]?
    @State private var current = 0
    @State private var errorText: String?

    private var playing: Bool { player.playingID != nil }

    var body: some View {
        NavigationStack {
            Group {
                if let highlights, !highlights.isEmpty {
                    content(highlights)
                } else if let errorText {
                    ContentUnavailableView("Couldn't prepare highlights", systemImage: "exclamationmark.triangle",
                                           description: Text(errorText))
                } else {
                    ProgressView("Finding last night's highlights…")
                }
            }
            .loopBackground()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Highlights").font(.loop(.headline))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Color.loopMidnight)
        .task {
            let audio = audio, events = events, background = background, boost = boost
            do {
                let built = try await Task.detached(priority: .userInitiated) {
                    try Highlights.build(audio: audio, events: events, background: background, boost: boost)
                }.value
                highlights = built
                if !built.isEmpty { play(0) }
            } catch {
                errorText = error.localizedDescription
            }
        }
        .onDisappear { player.stop() }
    }

    private func content(_ highlights: [Highlight]) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                nowPlaying(highlights[current], index: current, of: highlights.count)

                HStack(spacing: 16) {
                    Button {
                        if playing { player.stop() } else { play(current) }
                    } label: {
                        Label(playing ? "Stop" : "Play", systemImage: playing ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.loopAccent)
                    .foregroundStyle(Color.loopOnAccent)

                    Button {
                        play(current + 1)
                    } label: {
                        Label("Skip", systemImage: "forward.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.loopAccent)
                    .disabled(current + 1 >= highlights.count)
                }
                .controlSize(.large)

                Card("All highlights") {
                    ForEach(Array(highlights.enumerated()), id: \.element.id) { i, h in
                        row(h, isCurrent: i == current) { play(i) }
                        if i < highlights.count - 1 { Divider() }
                    }
                }

                Text("Named by Apple's sound classifier, so treat it as a guess. Sounds it isn't sure about show as Unknown.")
                    .font(.loop(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private func nowPlaying(_ h: Highlight, index: Int, of count: Int) -> some View {
        VStack(spacing: 10) {
            Text("\(index + 1) of \(count)")
                .font(.loop(.caption))
                .foregroundStyle(.secondary)
            Image(systemName: h.category.symbol)
                .font(.system(size: 52))
                .foregroundStyle(h.category == .unknown ? Color.loopSilver : Color.loopAccent)
                .symbolEffect(.pulse, isActive: playing)
                .frame(height: 70)
            Text(h.title)
                .font(.loop(.title2))
                .multilineTextAlignment(.center)
            Text("\(h.event.start.formatted(date: .omitted, time: .shortened)) · \(Int(h.event.peak.rounded())) dB")
                .font(.loop(.subheadline))
                .monospacedDigit()
                .foregroundStyle(levelColor(h.event.peak))
            if let file = h.shareFile {
                ShareLink(item: file, subject: Text(h.title), message: Text(Highlights.shareText(for: h))) {
                    Label("Save or share this clip", systemImage: "square.and.arrow.up")
                        .font(.loop(.subheadline))
                }
                .foregroundStyle(Color.loopAccent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.loopSurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Highlight \(index + 1) of \(count): \(h.title), \(h.event.start.formatted(date: .omitted, time: .shortened)), \(Int(h.event.peak.rounded())) decibels")
    }

    private func row(_ h: Highlight, isCurrent: Bool, play: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 12) {
                    Image(systemName: isCurrent && playing ? "speaker.wave.2.fill" : h.category.symbol)
                        .foregroundStyle(h.category == .unknown ? Color.loopSilver : Color.loopAccent)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.title)
                        Text(h.event.start.formatted(date: .omitted, time: .shortened))
                            .font(.loop(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(h.event.peak.rounded())) dB")
                        .monospacedDigit()
                        .foregroundStyle(levelColor(h.event.peak))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let file = h.shareFile {
                ShareLink(item: file, subject: Text(h.title), message: Text(Highlights.shareText(for: h))) {
                    Image(systemName: "square.and.arrow.up")
                }
                .foregroundStyle(Color.loopAccent)
                .accessibilityLabel("Share \(h.title) clip")
            }
        }
        .padding(.vertical, 4)
    }

    /// Plays clip `index`; when it ends, the next one starts on its own.
    private func play(_ index: Int) {
        guard let highlights, highlights.indices.contains(index) else { return }
        current = index
        let h = highlights[index]
        player.play(url: audio, from: h.clipStart, duration: h.clipDuration, id: h.id, background: background) {
            if index + 1 < highlights.count { play(index + 1) }
        }
    }
}
