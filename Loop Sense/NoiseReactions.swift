import Foundation

/// A loud noise as the body-reaction finder sees it.
nonisolated struct LoudNoise {
    let time: Date
    let peak: Double
    let category: NoiseCategory?
}

/// A heart-rate jump right after a loud noise (H3).
nonisolated struct Reaction: Equatable {
    let noiseTime: Date
    let noisePeak: Double
    let category: NoiseCategory?
    let before: Double
    let peak: Double
    let peakTime: Date
    /// Minutes from the peak until heart rate was back near where it started; nil if it didn't settle.
    let settledAfter: Int?

    /// "Your heart rate jumped from 60 to 78 bpm at 02:58, right after a 52 dB noise (Traffic). It settled within 6 minutes."
    func text(timeZone: TimeZone = .current) -> String {
        let f = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        let what = category.map { $0 == .unknown ? "" : " (\($0.name))" } ?? ""
        var s = "Your heart rate jumped from \(Int(before.rounded())) to \(Int(peak.rounded())) bpm at \(peakTime.formatted(f)), right after a \(Int(noisePeak.rounded())) dB noise\(what)."
        if let m = settledAfter {
            s += m <= 1 ? " It settled within a minute." : " It settled within \(m) minutes."
        }
        return s
    }
}

/// Finds heart-rate reactions to loud noises. All the rules live here.
nonisolated enum NoiseReactions {
    /// A rise of at least this many bpm counts as a reaction.
    static let minimumRise = 10.0
    /// Look for the rise this long after the noise starts.
    static let window: TimeInterval = 120
    /// "Before" is the average over this long before the noise.
    static let baselineWindow: TimeInterval = 120
    /// Settled once back within this many bpm of "before".
    static let settleMargin = 3.0
    /// Only noises above this count as loud (the WHO 45 dB guideline).
    static let loudLevel = WHO.peakLimit

    static func find(heartRate: [SnapshotBuilder.Sample], noises: [LoudNoise]) -> [Reaction] {
        let hr = heartRate.sorted { $0.start < $1.start }
        return noises.filter { $0.peak > loudLevel }.sorted { $0.time < $1.time }.compactMap { noise in
            let before = hr.filter { $0.start >= noise.time.addingTimeInterval(-baselineWindow) && $0.start < noise.time }
            // Without readings just before, fall back to the last one before the noise.
            let baseline = before.isEmpty ? hr.last { $0.start < noise.time }.map { [$0] } ?? [] : before
            guard !baseline.isEmpty else { return nil }
            let start = baseline.map(\.value).reduce(0, +) / Double(baseline.count)
            let after = hr.filter { $0.start >= noise.time && $0.start <= noise.time.addingTimeInterval(window) }
            guard let top = after.max(by: { $0.value < $1.value }), top.value - start >= minimumRise else { return nil }
            let settled = hr.first { $0.start > top.start && $0.value <= start + settleMargin }
            let minutes = settled.map { Int(($0.start.timeIntervalSince(top.start) / 60).rounded(.up)) }
            return Reaction(noiseTime: noise.time, noisePeak: noise.peak, category: noise.category,
                            before: start, peak: top.value, peakTime: top.start, settledAfter: minutes)
        }
    }

    /// The lowest reading and when it was.
    static func lowest(_ samples: [SnapshotBuilder.Sample]) -> SnapshotBuilder.Sample? {
        samples.min { $0.value < $1.value }
    }

    /// The "What we noticed" summary when nothing jumped.
    static func calmText(loudCount: Int) -> String {
        switch loudCount {
        case 0: "There were no loud noises, so there was nothing for your heart to react to."
        case 1: "Your heart rate didn't jump after the one loud noise."
        default: "Your heart rate didn't jump after any of the \(loudCount) loud noises."
        }
    }
}
