import Foundation
import SoundAnalysis

/// Runs Apple's built-in sound classifier (about 300 labels) over a saved night recording and
/// names each noise event. Part of the I2 "Name the noise" spike: kept free of UIKit so the same
/// file also compiles into the Mac runner in tools/classify-night.swift.
nonisolated enum SoundClassifier {
    struct Label: Hashable {
        let identifier: String
        let confidence: Double
    }

    /// One classifier window (about a second of audio).
    struct Window {
        let start: TimeInterval
        let duration: TimeInterval
        let labels: [Label]
    }

    struct EventResult {
        let event: LoudEvent
        /// Highest confidence per label across the windows overlapping the event, best first.
        let top: [Label]
    }

    struct Result {
        let audioDuration: TimeInterval
        let processingTime: TimeInterval
        let windows: [Window]
        let events: [EventResult]
    }

    /// Classifies the whole file, then matches windows to the night's noise events.
    /// `events` use `audioOffset`, which already skips gaps where the mic was off.
    static func classify(fileAt url: URL, events: [LoudEvent], topCount: Int = 3) throws -> Result {
        let started = Date()
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let observer = Observer()
        try analyzer.add(request, withObserver: observer)
        analyzer.analyze()
        if let error = observer.error { throw error }

        let windows = observer.windows
        let audioDuration = windows.map { $0.start + $0.duration }.max() ?? 0
        let results = events.map { event in
            // Pad by half a second either side: events are timed to the second.
            let from = event.audioOffset - 0.5
            let to = event.audioOffset + event.duration + 0.5
            var best: [String: Double] = [:]
            for w in windows where w.start < to && w.start + w.duration > from {
                for l in w.labels where l.identifier != "silence" {
                    best[l.identifier] = max(best[l.identifier] ?? 0, l.confidence)
                }
            }
            let top = best.sorted { $0.value > $1.value }.prefix(topCount)
                .map { Label(identifier: $0.key, confidence: $0.value) }
            return EventResult(event: event, top: top)
        }
        return Result(audioDuration: audioDuration, processingTime: Date().timeIntervalSince(started),
                      windows: windows, events: results)
    }

    /// Plain-text report for sharing or pasting into the spike write-up.
    static func report(_ r: Result, title: String) -> String {
        var lines = [title,
                     String(format: "Audio %.1f min, processed in %.1f s (%.0fx real time), %d windows, %d events",
                            r.audioDuration / 60, r.processingTime,
                            r.audioDuration / max(r.processingTime, 0.001), r.windows.count, r.events.count),
                     ""]
        for e in r.events.sorted(by: { $0.event.peak > $1.event.peak }) {
            let labels = e.top.isEmpty ? "(no labels)"
                : e.top.map { String(format: "%@ %.2f", $0.identifier, $0.confidence) }.joined(separator: ", ")
            lines.append(String(format: "%@  %3.0f dB  %4.0f s  %@",
                                e.event.start.formatted(date: .omitted, time: .standard), e.event.peak,
                                e.event.duration, labels))
        }
        // Which labels win most often, to see what the classifier thinks the night was made of.
        let winners = Dictionary(grouping: r.events.compactMap { $0.top.first?.identifier }, by: { $0 })
            .mapValues(\.count).sorted { $0.value > $1.value }
        if !winners.isEmpty {
            lines.append("")
            lines.append("Top label per event: " + winners.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    private final class Observer: NSObject, SNResultsObserving {
        var windows: [Window] = []
        var error: Error?

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult else { return }
            let labels = r.classifications.prefix(10).map {
                Label(identifier: $0.identifier, confidence: $0.confidence)
            }
            windows.append(Window(start: r.timeRange.start.seconds, duration: r.timeRange.duration.seconds,
                                  labels: labels))
        }

        func request(_ request: SNRequest, didFailWithError error: Error) {
            self.error = error
        }
    }
}
