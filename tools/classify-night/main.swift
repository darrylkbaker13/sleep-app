// Mac runner for the I2a sound classifier spike.
// Usage: tools/classify-night.sh <session.json> [more.json ...]
// Each .json needs its matching .caf next to it (export both from the app's Sessions folder).
import Foundation

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")

let paths = CommandLine.arguments.dropFirst()
guard !paths.isEmpty else {
    print("Usage: classify-night <session.json> [more.json ...]")
    exit(1)
}

for path in paths {
    let jsonURL = URL(fileURLWithPath: path)
    do {
        let session = try decoder.decode(SleepSession.self, from: Data(contentsOf: jsonURL))
        let audioURL = jsonURL.deletingLastPathComponent()
            .appendingPathComponent(session.audioFileName ?? jsonURL.deletingPathExtension().lastPathComponent + ".caf")
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("\(jsonURL.lastPathComponent): no audio file (\(audioURL.lastPathComponent)), skipping\n")
            continue
        }
        let events = NightAnalysis(session: session)?.events ?? []
        let result = try SoundClassifier.classify(fileAt: audioURL, events: events)
        let title = "Night of \(session.start.formatted(date: .abbreviated, time: .shortened)) (\(jsonURL.lastPathComponent))"
        print(SoundClassifier.report(result, title: title))
        print("")
    } catch {
        print("\(jsonURL.lastPathComponent): \(error)\n")
    }
}
