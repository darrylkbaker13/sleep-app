#if DEBUG
import Foundation

/// TEMPORARY test data: seven made-up nights with Garmin-style sleep stages, for trying the app
/// without recording real nights. Debug builds only. To remove it, delete this file and the
/// `#if DEBUG` DemoData blocks in ContentView.swift and SleepOverlay.swift.
nonisolated enum DemoData {
    /// Demo nights use fixed IDs with this prefix, so Remove never touches real recordings.
    private static let idPrefix = "DE300000"

    static func isDemo(_ session: SleepSession) -> Bool {
        session.id.uuidString.hasPrefix(idPrefix)
    }

    @MainActor static func count(in store: SessionStore) -> Int {
        store.sessions.filter(isDemo).count
    }

    /// Adds (or refreshes) the last seven nights, ending this morning. Generated off the main thread.
    @MainActor static func add(to store: SessionStore) async {
        let sessions = await Task.detached(priority: .userInitiated) {
            profiles.enumerated().map { makeSession(nightsAgo: $0.offset + 1, profile: $0.element) }
        }.value
        remove(from: store)
        sessions.forEach(store.save)
        store.load() // re-sort so the newest night is first
    }

    @MainActor static func remove(from store: SessionStore) {
        for session in store.sessions where isDemo(session) {
            store.delete(session)
        }
    }

    /// Garmin-style sleep stages for a demo night, regenerated from the same seed each time.
    static func stages(for session: SleepSession) -> [SleepInterval] {
        guard let n = nightNumber(of: session), profiles.indices.contains(n - 1) else { return [] }
        var rng = SeededRNG(seed: UInt64(n) &* 7919)
        let analysis = NightAnalysis(session: session)
        let loudEvents = (analysis?.events ?? []).filter { $0.peak >= 52 }
        return makeStages(session: session, loudEvents: loudEvents, rng: &rng)
    }

    // MARK: - Night profiles

    private struct Profile {
        let background: Double        // steady dB SPL
        let eventsPerHour: Double     // short noises (cars, voices, creaks)
        let eventPeak: ClosedRange<Double>
        var snoring: ClosedRange<Double>? = nil   // hours into the night
        var bigBang: Double? = nil                // hours into the night: one very loud noise
        var rain = false
        // Morning check-in.
        var rating: Int? = nil
        var tags: [String] = []
        var earplugs: String? = nil
    }

    /// Most recent night first.
    private static let profiles: [Profile] = [
        Profile(background: 29, eventsPerHour: 1.5, eventPeak: 42...52,                         // quiet
                rating: 5, tags: ["Window open"]),
        Profile(background: 34, eventsPerHour: 5, eventPeak: 48...64,                           // traffic
                rating: 4, earplugs: "Loop Dream"),
        Profile(background: 30, eventsPerHour: 1.5, eventPeak: 42...50, snoring: 1.5...3.5,     // partner snoring
                rating: 2),
        Profile(background: 28, eventsPerHour: 1, eventPeak: 40...48, bigBang: 4.2,             // door slam
                rating: 3, tags: ["Partner away"]),
        Profile(background: 38, eventsPerHour: 8, eventPeak: 52...70,                           // noisy weekend street
                rating: 2, tags: ["Alcohol", "Window open"]),
        Profile(background: 41, eventsPerHour: 1, eventPeak: 48...55, rain: true,               // rain
                rating: 4, tags: ["Fan or AC on"], earplugs: "Loop Quiet 2"),
        Profile(background: 32, eventsPerHour: 3, eventPeak: 45...58),                          // average, no check-in
    ]

    private static let calibrationOffset = 95.0

    private static func nightNumber(of session: SleepSession) -> Int? {
        guard isDemo(session) else { return nil }
        return Int(session.id.uuidString.suffix(2))
    }

    private static func makeSession(nightsAgo n: Int, profile p: Profile) -> SleepSession {
        var rng = SeededRNG(seed: UInt64(n))
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let evening = calendar.date(byAdding: .day, value: -n, to: today)!
        let start = evening.addingTimeInterval(22.75 * 3600 + Double(rng.int(0...45)) * 60)
        let seconds = Int((7.25 + rng.double(0...1.25)) * 3600)

        var db = (0..<seconds).map { _ in p.background + rng.gaussian() * 1.2 }

        // Slow drift, and the dawn chorus in the last 40 minutes.
        var drift = 0.0
        for i in 0..<seconds {
            if i % 60 == 0 { drift = max(-3, min(3, drift + rng.gaussian() * 0.4)) }
            db[i] += drift
            let toEnd = seconds - i
            if toEnd < 2400 { db[i] += 6 * (1 - Double(toEnd) / 2400) }
        }

        // Short noises.
        let eventCount = Int(p.eventsPerHour * Double(seconds) / 3600)
        for _ in 0..<eventCount {
            let at = rng.int(0...(seconds - 30))
            addEvent(&db, at: at, length: rng.int(2...12), peak: rng.double(p.eventPeak), rng: &rng)
        }

        if let snore = p.snoring {
            // A snore roughly every 4 seconds, about 1.5 s long.
            var t = Int(snore.lowerBound * 3600)
            while t < min(seconds, Int(snore.upperBound * 3600)) {
                let peak = 44 + rng.gaussian() * 2.5
                for k in 0..<2 where t + k < seconds { db[t + k] = max(db[t + k], peak) }
                t += 3 + rng.int(0...2)
            }
        }

        if let bang = p.bigBang {
            addEvent(&db, at: Int(bang * 3600), length: 2, peak: 72, rng: &rng)
        }

        if p.rain {
            // Heavier showers come and go.
            for i in 0..<seconds {
                db[i] += 3 * max(0, sin(Double(i) / 1700))
            }
        }

        let levels = db.map { Float($0 - calibrationOffset) }
        let id = UUID(uuidString: String(format: "\(idPrefix)-0000-4000-8000-%012d", n))!
        var session = SleepSession(id: id, start: start, end: start.addingTimeInterval(Double(seconds)),
                                   calibrationOffset: calibrationOffset, levels: levels, audioFileName: nil)
        session.rating = p.rating
        session.tags = p.tags.isEmpty ? nil : p.tags
        session.earplugs = p.earplugs
        return session
    }

    private static func addEvent(_ db: inout [Double], at: Int, length: Int, peak: Double, rng: inout SeededRNG) {
        for k in 0..<length where at + k < db.count {
            // Rise fast, fade out.
            let shape = k == 0 ? 0.8 : 1 - Double(k) / Double(length + 1) * 0.6
            db[at + k] = max(db[at + k], peak * shape + rng.gaussian())
        }
    }

    // MARK: - Sleep stages

    private static func makeStages(session: SleepSession, loudEvents: [LoudEvent], rng: inout SeededRNG) -> [SleepInterval] {
        let minutes = Int(session.duration / 60)
        guard minutes > 30 else { return [] }
        var stage = [SleepStage](repeating: .light, count: minutes)

        // Falling asleep, then roughly 90-minute cycles: more deep sleep early, more REM later.
        let onset = rng.int(8...22)
        for m in 0..<onset { stage[m] = .awake }
        var m = onset
        var cycle = 0
        while m < minutes {
            let length = 85 + rng.int(0...15)
            let progress = Double(m) / Double(minutes)
            let deep = Int(Double(length) * max(0.04, 0.32 - 0.3 * progress))
            let rem = Int(Double(length) * min(0.35, 0.08 + 0.3 * progress))
            let light1 = (length - deep - rem) * 3 / 5
            var plan: [(SleepStage, Int)] = [(.light, light1), (.deep, deep), (.light, length - deep - rem - light1), (.rem, rem)]
            if cycle > 0, rng.double(0...1) < 0.35 { plan.append((.awake, rng.int(1...3))) }
            for (s, len) in plan {
                for _ in 0..<len where m < minutes { stage[m] = s; m += 1 }
            }
            cycle += 1
        }
        for k in max(0, minutes - rng.int(4...9))..<minutes { stage[k] = .awake }

        // Some loud noises wake you briefly, starting within a minute of the noise.
        for event in loudEvents where rng.double(0...1) < 0.55 {
            let at = Int(event.start.timeIntervalSince(session.start) / 60) + rng.int(0...1)
            for k in at..<min(minutes, at + rng.int(2...5)) where k >= onset { stage[k] = .awake }
        }

        // Join minutes into intervals.
        var intervals: [SleepInterval] = []
        var runStart = 0
        for k in 1...minutes where k == minutes || stage[k] != stage[runStart] {
            intervals.append(SleepInterval(start: session.start.addingTimeInterval(Double(runStart * 60)),
                                           end: session.start.addingTimeInterval(Double(k * 60)),
                                           stage: stage[runStart], source: "com.garmin.connect.mobile (demo)"))
            runStart = k
        }
        return intervals
    }
}

/// Repeatable random numbers, so each demo night looks the same every time.
nonisolated private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func double(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }

    /// Standard normal, by Box–Muller.
    mutating func gaussian() -> Double {
        let u = max(double(0...1), 1e-12)
        return sqrt(-2 * log(u)) * cos(2 * .pi * double(0...1))
    }
}
#endif
