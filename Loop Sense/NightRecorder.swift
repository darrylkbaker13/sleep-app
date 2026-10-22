import AVFoundation
import Foundation
import Combine

/// Turns raw microphone samples into one dBFS reading per second.
/// Called from the audio tap thread, read from the main thread, so everything is behind a lock.
nonisolated final class LevelAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var sumSquares = 0.0
    private var count = 0
    private var samplesPerReading = 48_000
    private var start = Date()
    private var levels: [Float] = []
    private var latest: Float = -120

    func reset(start: Date, sampleRate: Double) {
        lock.lock(); defer { lock.unlock() }
        self.start = start
        samplesPerReading = max(1, Int(sampleRate))
        sumSquares = 0
        count = 0
        levels = []
        levels.reserveCapacity(12 * 3600)
        latest = -120
    }

    func setSampleRate(_ sampleRate: Double) {
        lock.lock(); defer { lock.unlock() }
        samplesPerReading = max(1, Int(sampleRate))
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let samples = channels[0]
        let n = Int(buffer.frameLength)
        lock.lock(); defer { lock.unlock() }
        for i in 0..<n {
            let s = Double(samples[i])
            sumSquares += s * s
            count += 1
            if count >= samplesPerReading { emit() }
        }
    }

    private func emit() {
        let meanSquare = sumSquares / Double(max(count, 1))
        let db = Float(max(10 * log10(max(meanSquare, 1e-12)), -120))
        // If the mic was off for a while (interruption), pad the gap so readings stay aligned to the clock.
        let expected = Int(Date().timeIntervalSince(start)) - 1
        if expected - levels.count > 5 {
            levels.append(contentsOf: repeatElement(Float.nan, count: expected - levels.count))
        }
        levels.append(db)
        latest = db
        sumSquares = 0
        count = 0
    }

    func snapshot() -> (levels: [Float], latest: Float) {
        lock.lock(); defer { lock.unlock() }
        return (levels, latest)
    }
}

enum RecorderError: LocalizedError {
    case noInput
    var errorDescription: String? { "No microphone input is available." }
}

@MainActor
final class NightRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var currentLevel: Float = -120
    @Published private(set) var startDate: Date?
    @Published private(set) var activeSessionID: UUID?
    @Published var errorMessage: String?

    private let store: SessionStore
    private let engine = AVAudioEngine()
    private let accumulator = LevelAccumulator()
    private var audioFile: AVAudioFile?
    private var session: SleepSession?
    private var timer: Timer?
    private var lastSave = Date()
    private var observers: [NSObjectProtocol] = []

    init(store: SessionStore) {
        self.store = store
    }

    func start(calibrationOffset: Double, saveAudio: Bool) async {
        guard !isRecording else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access is off. Enable it in Settings › Privacy & Security › Microphone."
            return
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // .measurement disables the automatic gain and noise processing that would distort levels.
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)

            let now = Date()
            var newSession = SleepSession(id: UUID(), start: now, end: nil,
                                          calibrationOffset: calibrationOffset, levels: [], audioFileName: nil)
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw RecorderError.noInput }

            if saveAudio {
                // CAF survives being cut off mid-write (e.g. the app is killed) better than M4A.
                let name = "\(newSession.id.uuidString).caf"
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVEncoderBitRateKey: 32_000 * Int(format.channelCount),
                ]
                audioFile = try AVAudioFile(forWriting: store.directory.appendingPathComponent(name),
                                            settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                newSession.audioFileName = name
            }

            accumulator.reset(start: now, sampleRate: format.sampleRate)
            try startEngine()

            session = newSession
            store.save(newSession)
            activeSessionID = newSession.id
            startDate = now
            lastSave = now
            isRecording = true
            observeInterruptions()
            // Scheduled on the main run loop, so the callback is already on the main actor.
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioFile = nil
        }
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        timer?.invalidate()
        timer = nil
        audioFile = nil // closes the file
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []

        if var s = session {
            s.levels = accumulator.snapshot().levels
            s.end = Date()
            store.save(s)
        }
        session = nil
        activeSessionID = nil
        startDate = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func tick() {
        let snap = accumulator.snapshot()
        currentLevel = snap.latest
        // Persist every minute so a crash or a dead battery doesn't lose the night.
        if Date().timeIntervalSince(lastSave) >= 60, var s = session {
            s.levels = snap.levels
            session = s
            store.save(s)
            lastSave = Date()
        }
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw RecorderError.noInput }
        accumulator.setSampleRate(format.sampleRate)
        input.removeTap(onBus: 0)
        Self.installTap(on: input, format: format, accumulator: accumulator, file: audioFile)
        engine.prepare()
        try engine.start()
    }

    /// Nonisolated so the tap closure isn't treated as main-actor code; it runs on an audio thread.
    private nonisolated static func installTap(on input: AVAudioInputNode, format: AVAudioFormat,
                                               accumulator: LevelAccumulator, file: AVAudioFile?) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            accumulator.process(buffer)
            try? file?.write(from: buffer)
        }
    }

    /// Phone calls, alarms, Siri etc. stop the engine. Restart it when they're done.
    /// Observers use the main queue, so the callbacks are already on the main actor.
    private func observeInterruptions() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            MainActor.assumeIsolated { self?.resume() }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        })
    }

    private func resume() {
        guard isRecording, !engine.isRunning else { return }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
            try startEngine()
        } catch {
            // Try again shortly; the interrupting app may still hold the mic.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.resume()
            }
        }
    }
}
