import Foundation
import Combine

/// One night's recording. Levels are stored once per second in dBFS (digital full scale, ≤ 0).
/// Adding `calibrationOffset` converts them to approximate dB SPL (what a sound meter reads).
/// Seconds where the microphone wasn't running (e.g. a phone call interrupted us) are NaN.
nonisolated struct SleepSession: Codable, Identifiable {
    let id: UUID
    var start: Date
    var end: Date?
    var calibrationOffset: Double
    var levels: [Float]
    var audioFileName: String?
    /// Morning check-in: how the night felt, 1 (awful) to 5 (great). nil until answered.
    var rating: Int? = nil
    /// Sleep notes such as "Window open". Earplugs are kept separately in `earplugs`.
    var tags: [String]? = nil
    /// Earplugs worn that night: a Loop model name or `SleepNotes.otherEarplugs`. nil means none.
    var earplugs: String? = nil

    var effectiveEnd: Date { end ?? start.addingTimeInterval(Double(levels.count)) }
    var duration: TimeInterval { effectiveEnd.timeIntervalSince(start) }

    /// Energy-averaged level in dB SPL, cheap enough to show in a list row.
    var quickAverage: Double? {
        var energy = 0.0, n = 0
        for l in levels where l.isFinite {
            energy += pow(10, (Double(l) + calibrationOffset) / 10)
            n += 1
        }
        return n == 0 ? nil : 10 * log10(energy / Double(n))
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SleepSession] = []
    let directory: URL

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("Sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? Self.decoder.decode(SleepSession.self, from: data)
            }
            .sorted { $0.start > $1.start }
    }

    func save(_ session: SleepSession) {
        do {
            let data = try Self.encoder.encode(session)
            try data.write(to: jsonURL(for: session), options: .atomic)
        } catch {
            print("Failed to save session: \(error)")
        }
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[i] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    func delete(_ session: SleepSession) {
        try? FileManager.default.removeItem(at: jsonURL(for: session))
        if let audio = audioURL(for: session) {
            try? FileManager.default.removeItem(at: audio)
        }
        sessions.removeAll { $0.id == session.id }
    }

    func audioURL(for session: SleepSession) -> URL? {
        guard let name = session.audioFileName else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func jsonURL(for session: SleepSession) -> URL {
        directory.appendingPathComponent("\(session.id.uuidString).json")
    }
}
