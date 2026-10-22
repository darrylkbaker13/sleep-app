import Foundation

nonisolated struct LoudEvent: Identifiable {
    let id = UUID()
    let start: Date
    let duration: TimeInterval
    let peak: Double
    /// Position in the saved audio file (which skips any gaps where the mic was off).
    let audioOffset: TimeInterval
}

nonisolated struct ChartPoint: Identifiable {
    var id: Date { time }
    let time: Date
    let average: Double
    let peak: Double
}

nonisolated struct HourSummary: Identifiable {
    var id: Date { hour }
    let hour: Date
    let average: Double
    let events: Int
}

nonisolated struct LevelBand: Identifiable {
    var id: String { label }
    let label: String
    let range: String
    let lowerBound: Double
    let fraction: Double
}

/// Reference values from the WHO Guidelines for Community Noise: bedroom average under 30 dB,
/// and individual noises above 45 dB no more than 10–15 times a night.
nonisolated enum WHO {
    static let averageLimit = 30.0
    static let peakLimit = 45.0
}

nonisolated struct NightAnalysis {
    let start: Date
    let end: Date
    let recordedSeconds: Int
    let missingSeconds: Int
    let average: Double      // energy-averaged level (Leq)
    let median: Double
    let background: Double   // L90: level exceeded 90% of the time — the steady noise floor
    let busy: Double         // L10: level exceeded 10% of the time
    let peak: Double
    let peakTime: Date
    let eventThreshold: Double
    let events: [LoudEvent]
    let eventsOverWHOPeak: Int
    let bands: [LevelBand]
    let chart: [ChartPoint]
    let hours: [HourSummary]
    let verdict: String
    let findings: [String]

    init?(session: SleepSession) {
        let offset = session.calibrationOffset
        // (second index, dB SPL, seconds of audio before this point)
        var readings: [(index: Int, db: Double, audioPos: Int)] = []
        readings.reserveCapacity(session.levels.count)
        var audioPos = 0
        for (i, l) in session.levels.enumerated() where l.isFinite {
            readings.append((i, Double(l) + offset, audioPos))
            audioPos += 1
        }
        guard readings.count >= 60 else { return nil }

        start = session.start
        end = session.effectiveEnd
        recordedSeconds = readings.count
        missingSeconds = session.levels.count - readings.count

        func energyAverage<S: Sequence>(_ values: S) -> Double where S.Element == Double {
            var sum = 0.0, n = 0
            for v in values { sum += pow(10, v / 10); n += 1 }
            return n == 0 ? 0 : 10 * log10(sum / Double(n))
        }
        func time(_ index: Int) -> Date { session.start.addingTimeInterval(Double(index)) }

        let sorted = readings.map(\.db).sorted()
        func percentile(_ p: Double) -> Double {
            sorted[min(sorted.count - 1, max(0, Int(p * Double(sorted.count - 1))))]
        }
        average = energyAverage(readings.map(\.db))
        median = percentile(0.5)
        background = percentile(0.10)
        busy = percentile(0.90)
        let loudest = readings.max { $0.db < $1.db }!
        peak = loudest.db
        peakTime = time(loudest.index)

        // Events: anything 10 dB over the noise floor, merging bursts less than 10 s apart.
        let threshold = background + 10
        eventThreshold = threshold
        var events: [LoudEvent] = []
        var current: (first: Int, last: Int, peak: Double, audioPos: Int)?
        for r in readings where r.db >= threshold {
            if let c = current, r.index - c.last <= 10 {
                current = (c.first, r.index, max(c.peak, r.db), c.audioPos)
            } else {
                if let c = current {
                    events.append(LoudEvent(start: time(c.first), duration: Double(c.last - c.first + 1),
                                            peak: c.peak, audioOffset: Double(c.audioPos)))
                }
                current = (r.index, r.index, r.db, r.audioPos)
            }
        }
        if let c = current {
            events.append(LoudEvent(start: time(c.first), duration: Double(c.last - c.first + 1),
                                    peak: c.peak, audioOffset: Double(c.audioPos)))
        }
        self.events = events
        eventsOverWHOPeak = events.filter { $0.peak > WHO.peakLimit }.count

        let bandDefs: [(String, String, Double, Double)] = [
            ("Very quiet", "< 30 dB", -.infinity, 30),
            ("Quiet", "30–40 dB", 30, 40),
            ("Moderate", "40–50 dB", 40, 50),
            ("Loud", "50–60 dB", 50, 60),
            ("Very loud", "≥ 60 dB", 60, .infinity),
        ]
        bands = bandDefs.map { label, range, lo, hi in
            let n = readings.filter { $0.db >= lo && $0.db < hi }.count
            return LevelBand(label: label, range: range, lowerBound: lo, fraction: Double(n) / Double(readings.count))
        }

        let byMinute = Dictionary(grouping: readings) { $0.index / 60 }
        chart = byMinute.keys.sorted().map { minute in
            let values = byMinute[minute]!.map(\.db)
            return ChartPoint(time: time(minute * 60), average: energyAverage(values), peak: values.max()!)
        }

        let calendar = Calendar.current
        let byHour = Dictionary(grouping: readings) { calendar.dateInterval(of: .hour, for: time($0.index))!.start }
        hours = byHour.keys.sorted().map { hour in
            let hourEnd = hour.addingTimeInterval(3600)
            return HourSummary(hour: hour,
                               average: energyAverage(byHour[hour]!.map(\.db)),
                               events: events.filter { $0.start >= hour && $0.start < hourEnd }.count)
        }

        switch average {
        case ..<30: verdict = "Very quiet night"
        case ..<35: verdict = "Quiet night"
        case ..<45: verdict = "Moderately noisy night"
        default: verdict = "Noisy night"
        }

        let timeFmt = Date.FormatStyle(date: .omitted, time: .shortened)
        let hoursRecorded = Double(readings.count) / 3600
        var findings: [String] = []

        let avgComparison = average <= WHO.averageLimit
            ? "within the WHO's recommended 30 dB for bedrooms"
            : String(format: "%.0f dB above the WHO's recommended 30 dB for bedrooms", average - WHO.averageLimit)
        findings.append(String(format: "Your room averaged %.0f dB over %.1f hours, %@.", average, hoursRecorded, avgComparison))

        findings.append(String(format: "The steady background noise (the level it rarely dropped below) was %.0f dB. That's your room's baseline: fans, air conditioning, distant traffic.", background))

        if events.isEmpty {
            findings.append("There were no distinct noise spikes. The night was steady throughout.")
        } else {
            let perHour = Double(events.count) / max(hoursRecorded, 0.1)
            findings.append(String(format: "%d noise events rose 10 dB or more above the background (about %.1f per hour). The loudest hit %.0f dB at %@.",
                                   events.count, perHour, peak, peakTime.formatted(timeFmt)))
        }

        if eventsOverWHOPeak > 15 {
            findings.append("\(eventsOverWHOPeak) events peaked above 45 dB. The WHO suggests keeping that to about 10–15 per night, because sounds this loud are likely to cause brief awakenings.")
        } else if eventsOverWHOPeak > 0 {
            findings.append("\(eventsOverWHOPeak) events peaked above 45 dB, within the WHO's guideline of no more than 10–15 per night.")
        }

        if hours.count >= 2,
           let loudHour = hours.max(by: { $0.average < $1.average }),
           let quietHour = hours.min(by: { $0.average < $1.average }) {
            let hourFmt = Date.FormatStyle(date: .omitted, time: .shortened)
            findings.append(String(format: "The noisiest hour started at %@ (%.0f dB average). The quietest started at %@ (%.0f dB).",
                                   loudHour.hour.formatted(hourFmt), loudHour.average,
                                   quietHour.hour.formatted(hourFmt), quietHour.average))
        }

        if missingSeconds > 60 {
            findings.append(String(format: "Recording was paused for %.0f minutes in total, probably by a call or alarm.", Double(missingSeconds) / 60))
        }
        self.findings = findings
    }
}

nonisolated enum CSVExporter {
    static func write(_ session: SleepSession) throws -> URL {
        let iso = ISO8601DateFormatter()
        var csv = "seconds_from_start,timestamp,db_spl\n"
        for (i, l) in session.levels.enumerated() {
            let t = session.start.addingTimeInterval(Double(i))
            let value = l.isFinite ? String(format: "%.1f", Double(l) + session.calibrationOffset) : ""
            csv += "\(i),\(iso.string(from: t)),\(value)\n"
        }
        let day = session.start.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LoopSense-\(day).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
