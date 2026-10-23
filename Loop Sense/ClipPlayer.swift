import AVFoundation
import Combine
import Foundation

/// How much to boost a noise clip for playback, and a soft limiter so loud bangs don't clip.
/// Recordings use .measurement mode (no automatic gain), so clips are quiet as recorded.
/// Playback only: the saved audio and every dB reading are untouched.
nonisolated enum ClipGain {
    static let settingKey = "boostClips"
    /// Aim for clips to sit around this level (dBFS RMS).
    static let targetRMS = -20.0
    static let maxBoost = 30.0
    /// A clip less than this far above the room's background is mostly hiss, so its boost is capped.
    static let hissMargin = 6.0
    static let hissBoost = 12.0
    /// The limiter starts easing peaks above this sample level and never lets them pass 1.0.
    static let limiterThreshold: Float = 0.7

    /// Gain in dB for a clip, from its RMS and peak (both dBFS) and the night's background (dBFS).
    static func boost(rms: Double, peak: Double, background: Double?) -> Double {
        var gain = min(maxBoost, max(0, targetRMS - rms))
        if let background, rms - background < hissMargin {
            gain = min(gain, hissBoost)
        }
        // The limiter can absorb about 9 dB of overshoot cleanly; beyond that it would squash the sound.
        gain = min(gain, max(0, 9 - peak))
        return gain
    }

    /// Soft-knee limiter: unchanged below the threshold, smoothly approaching ±1.0 above it.
    static func limit(_ x: Float) -> Float {
        let a = abs(x)
        guard a > limiterThreshold else { return x }
        let t = limiterThreshold
        let y = t + (1 - t) * Float(tanh(Double((a - t) / (1 - t))))
        return x < 0 ? -y : y
    }

    /// RMS and peak of a buffer in dBFS (-120 for silence).
    static func levels(_ samples: UnsafeBufferPointer<Float>) -> (rms: Double, peak: Double) {
        guard !samples.isEmpty else { return (-120, -120) }
        var sum = 0.0, peak: Float = 0
        for s in samples {
            sum += Double(s * s)
            peak = max(peak, abs(s))
        }
        let rms = sqrt(sum / Double(samples.count))
        return (max(-120, 20 * log10(max(rms, 1e-12))), max(-120, 20 * log10(max(Double(peak), 1e-12))))
    }

    /// Applies the gain and the limiter to every channel, in place.
    static func apply(gainDB: Double, to buffer: AVAudioPCMBuffer) {
        guard gainDB > 0, let channels = buffer.floatChannelData else { return }
        let g = Float(pow(10, gainDB / 20))
        for c in 0..<Int(buffer.format.channelCount) {
            let data = channels[c]
            for i in 0..<Int(buffer.frameLength) {
                data[i] = limit(data[i] * g)
            }
        }
    }
}

/// Plays a few seconds of a night's recording around a noise event.
@MainActor
final class ClipPlayer: ObservableObject {
    @Published private(set) var playingID: UUID?
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var stopTask: Task<Void, Never>?

    init() {
        engine.attach(node)
    }

    /// `background` is the night's background level in dBFS, used to avoid boosting hiss.
    func play(url: URL, from start: TimeInterval, duration: TimeInterval, id: UUID, background: Double?) {
        stop()
        do {
            let file = try AVAudioFile(forReading: url)
            let rate = file.processingFormat.sampleRate
            let first = AVAudioFramePosition(max(0, start) * rate)
            guard first < file.length else { return }
            let count = AVAudioFrameCount(min(Double(file.length - first), duration * rate))
            guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { return }
            file.framePosition = first
            try file.read(into: buffer, frameCount: count)

            if UserDefaults.standard.object(forKey: ClipGain.settingKey) as? Bool ?? true,
               let samples = buffer.floatChannelData?[0] {
                let levels = ClipGain.levels(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
                ClipGain.apply(gainDB: ClipGain.boost(rms: levels.rms, peak: levels.peak, background: background), to: buffer)
            }

            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            if connectedFormat != buffer.format {
                engine.disconnectNodeOutput(node)
                engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
                connectedFormat = buffer.format
            }
            if !engine.isRunning { try engine.start() }
            node.scheduleBuffer(buffer)
            node.play()
            playingID = id
            let seconds = Double(buffer.frameLength) / rate
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { self?.stop() }
            }
        } catch {
            print("Playback failed: \(error)")
            stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        node.stop()
        // Release the audio hardware so recording can start straight after.
        if engine.isRunning { engine.stop() }
        playingID = nil
    }
}
