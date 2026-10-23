import AVFoundation
import Foundation

/// One clip in the morning highlights reel.
nonisolated struct Highlight: Identifiable {
    var id: UUID { event.id }
    let event: LoudEvent
    /// Where the clip sits in the saved audio, in seconds.
    let clipStart: TimeInterval
    let clipDuration: TimeInterval
    let labels: [SoundClassifier.Label]
    let category: NoiseCategory
    /// The clip, boosted like playback, ready to save or share. nil if writing it failed.
    var shareFile: URL?

    /// "Snoring", or "Possibly Aircraft" for the kinds that were least reliable in the spike.
    var title: String {
        if category == .unknown { return "Unknown sound" }
        return Highlights.uncertainKinds.contains(category) ? "Possibly \(category.name)" : category.name
    }
}

/// Picks and classifies the night's highlights: the loudest few noises, a few seconds each.
nonisolated enum Highlights {
    static let count = 5
    static let clipSeconds: TimeInterval = 5
    /// Start each clip a moment before the noise so its onset is heard.
    static let leadIn: TimeInterval = 1
    /// Aircraft, wind and rain were the weakest through a speaker in the I2a spike, so they're hedged.
    static let uncertainKinds: Set<NoiseCategory> = [.aircraft, .weather]

    /// The loudest noises, loudest first.
    static func pick(_ events: [LoudEvent]) -> [LoudEvent] {
        Array(events.sorted { $0.peak > $1.peak }.prefix(count))
    }

    /// Where to cut the clip for an event, kept inside the recording.
    static func clipRange(for event: LoudEvent, audioLength: TimeInterval) -> (start: TimeInterval, duration: TimeInterval) {
        let start = min(max(0, event.audioOffset - leadIn), max(0, audioLength - clipSeconds))
        return (start, min(clipSeconds, audioLength - start))
    }

    /// Text that goes with a shared clip, e.g. "Loop Sense · Tue 20 Oct, 03:13 · 61 dB · Snoring".
    static func shareText(for h: Highlight) -> String {
        let when = h.event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        return "Loop Sense · \(when) · \(Int(h.event.peak.rounded())) dB · \(h.title)"
    }

    /// Reads, classifies and exports just the highlight clips, so it's quick even for a long night.
    /// `background` (dBFS) caps the boost on near-silent clips, as in playback.
    /// Labels for a night could later come from stored per-event labels (I2c) instead of classifying here.
    static func build(audio url: URL, events: [LoudEvent], background: Double?, boost: Bool) throws -> [Highlight] {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        let length = Double(file.length) / rate
        return try pick(events).compactMap { event in
            let range = clipRange(for: event, audioLength: length)
            let frames = AVAudioFrameCount(range.duration * rate)
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { return nil }
            file.framePosition = AVAudioFramePosition(range.start * rate)
            try file.read(into: buffer, frameCount: frames)

            let labels = SoundClassifier.topLabels(windows: try SoundClassifier.classify(buffer: buffer),
                                                   eventSeconds: event.duration)
            let category = NoiseCategory.category(for: labels.map { (identifier: $0.identifier, confidence: $0.confidence) })
            var highlight = Highlight(event: event, clipStart: range.start, clipDuration: range.duration,
                                      labels: labels, category: category)
            highlight.shareFile = try? export(buffer, for: highlight, background: background, boost: boost)
            return highlight
        }
    }

    /// Writes the clip (boosted like playback) to a temporary .m4a named after its time and category.
    private static func export(_ buffer: AVAudioPCMBuffer, for h: Highlight, background: Double?, boost: Bool) throws -> URL {
        if boost, let samples = buffer.floatChannelData?[0] {
            let levels = ClipGain.levels(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
            ClipGain.apply(gainDB: ClipGain.boost(rms: levels.rms, peak: levels.peak, background: background), to: buffer)
        }
        let stamp = h.event.start.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let name = "LoopSense-\(stamp)-\(h.title.replacingOccurrences(of: " ", with: "-")).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVEncoderBitRateKey: 96_000,
        ]
        let out = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try out.write(from: buffer)
        return url
    }
}
