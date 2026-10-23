import Combine
import Foundation
import SoundAnalysis

/// Turns classifier windows into stored labels for a night's noise events. Pure, so it can be tested.
nonisolated enum EventLabelling {
    /// Bump when the labelling or category rules change, so older nights are relabelled.
    static let version = 1

    /// One label per event. Hand corrections already on the night are kept as they are.
    static func labels(for events: [LoudEvent], in session: SleepSession,
                       windows: [SoundClassifier.Window]) -> [EventLabel] {
        let corrections = Dictionary((session.eventLabels ?? []).filter { $0.corrected == true }.map { ($0.second, $0) },
                                     uniquingKeysWith: { a, _ in a })
        return events.map { event in
            let second = EventLabel.second(of: event, in: session)
            if let fixed = corrections[second] { return fixed }
            let top = SoundClassifier.topLabels(windows: SoundClassifier.windows(windows, for: event),
                                                eventSeconds: event.duration)
            let category = NoiseCategory.category(for: top.map { (identifier: $0.identifier, confidence: $0.confidence) })
            // Store the label that decided the category (e.g. "rain" behind a vague "water"), not just the top one.
            let deciding = top.first { NoiseCategory.category(for: $0.identifier, confidence: $0.confidence) == category
                                        && !NoiseCategory.vagueLabels.contains($0.identifier) }
                ?? top.first { NoiseCategory.category(for: $0.identifier, confidence: $0.confidence) == category }
                ?? top.first
            return EventLabel(second: second, category: category.rawValue,
                              confidence: deciding?.confidence ?? 0, label: deciding?.identifier)
        }
    }

    /// Whether a night still needs labelling: it has saved audio and no labels from the current rules.
    static func needsLabels(_ session: SleepSession, hasAudio: Bool) -> Bool {
        hasAudio && (session.eventLabels == nil || session.labelsVersion != version)
    }
}

/// Labels nights in the background, one at a time, on the phone. Starts when a recording stops and
/// when an unlabelled night's report is opened. Never runs while recording: if a recording starts,
/// the current job is cancelled and picked up again afterwards. Audio never leaves the phone.
@MainActor
final class EventLabeller: ObservableObject {
    /// 0...1 for the night being labelled; absent when nothing is running for that night.
    @Published private(set) var progress: [UUID: Double] = [:]

    private let store: SessionStore
    private let recorder: NightRecorder
    private var queue: [UUID] = []
    private var running: UUID?
    private var analyzer: AnalyzerBox?
    private var cancellables: Set<AnyCancellable> = []

    init(store: SessionStore, recorder: NightRecorder) {
        self.store = store
        self.recorder = recorder
        // A recording just stopped: label that night.
        recorder.$activeSessionID
            .scan((nil, nil)) { ($0.1, $1) }
            .sink { [weak self] previous, current in
                if let finished = previous, current == nil {
                    self?.enqueue(finished)
                } else if current != nil {
                    self?.pauseForRecording()
                }
            }
            .store(in: &cancellables)
        // @Published reports changes before they land, so check again once recording has really stopped.
        recorder.$isRecording
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                Task { @MainActor in self?.startNext() }
            }
            .store(in: &cancellables)
    }

    func labelIfNeeded(_ session: SleepSession) {
        enqueue(session.id)
    }

    private func enqueue(_ id: UUID) {
        guard running != id, !queue.contains(id) else { return }
        queue.append(id)
        startNext()
    }

    private func pauseForRecording() {
        guard let running else { return }
        analyzer?.cancel()
        queue.insert(running, at: 0)
    }

    private func startNext() {
        guard running == nil, !recorder.isRecording, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let session = store.sessions.first(where: { $0.id == id }),
              let audio = store.audioURL(for: session),
              EventLabelling.needsLabels(session, hasAudio: true) else {
            startNext()
            return
        }
        running = id
        progress[id] = 0
        let box = AnalyzerBox()
        analyzer = box
        let report: @Sendable (Double) -> Void = { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self, self.running == id else { return }
                self.progress[id] = p
            }
        }
        Task {
            let result: [EventLabel]? = await Task.detached(priority: .utility) {
                guard let analysis = NightAnalysis(session: session) else { return [] }
                guard !analysis.events.isEmpty else { return [] }
                let windows = try? SoundClassifier.windows(fileAt: audio, progress: report, started: { box.set($0) })
                guard let windows, !box.isCancelled else { return nil }
                return EventLabelling.labels(for: analysis.events, in: session, windows: windows)
            }.value
            finish(id, labels: result)
        }
    }

    private func finish(_ id: UUID, labels: [EventLabel]?) {
        running = nil
        analyzer = nil
        progress[id] = nil
        // nil means cancelled or failed: leave the night as it was so it's tried again later.
        if let labels, var session = store.sessions.first(where: { $0.id == id }) {
            session.eventLabels = labels
            session.labelsVersion = EventLabelling.version
            store.save(session)
        }
        startNext()
    }
}

/// Holds the running file analyzer so it can be cancelled from the main actor.
nonisolated private final class AnalyzerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var analyzer: SNAudioFileAnalyzer?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func set(_ a: SNAudioFileAnalyzer) {
        lock.withLock {
            analyzer = a
            if cancelled { a.cancelAnalysis() }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            analyzer?.cancelAnalysis()
        }
    }
}
