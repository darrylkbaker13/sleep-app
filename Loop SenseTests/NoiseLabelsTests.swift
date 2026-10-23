import Foundation
import Testing
@testable import Loop_Sense

@MainActor
struct NoiseLabelsTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func event(at second: Double) -> LoudEvent {
        LoudEvent(start: start.addingTimeInterval(second), duration: 3, peak: 60, audioOffset: second)
    }

    private func session(_ labels: [(Int, NoiseCategory)]) -> SleepSession {
        var s = SleepSession(id: UUID(), start: start, end: start.addingTimeInterval(3600), calibrationOffset: 95,
                             levels: [], audioFileName: "night.caf")
        s.eventLabels = labels.map { EventLabel(second: $0.0, category: $0.1.rawValue, confidence: 0.8, label: nil) }
        return s
    }

    private var events: [LoudEvent] { [event(at: 10), event(at: 20), event(at: 30), event(at: 40)] }
    private var night: SleepSession { session([(10, .traffic), (20, .snoring), (30, .traffic)]) }

    @Test func categoryOfEachEvent() {
        #expect(NoiseLabels.category(of: event(at: 10), in: night, hasAudio: true) == .traffic)
        #expect(NoiseLabels.category(of: event(at: 40), in: night, hasAudio: true) == nil)       // still to be labelled
        #expect(NoiseLabels.category(of: event(at: 40), in: night, hasAudio: false) == .unknown) // no audio, never will be
    }

    @Test func countsMostFirst() {
        let counts = NoiseLabels.counts(events, in: night, hasAudio: true)
        #expect(counts.map(\.category) == [.traffic, .snoring])
        #expect(counts.map(\.count) == [2, 1])
    }

    @Test func noAudioCountsAsUnknown() {
        let counts = NoiseLabels.counts(events, in: session([]), hasAudio: false)
        #expect(counts.map(\.category) == [.unknown])
        #expect(counts.first?.count == 4)
    }

    @Test func filterByCategory() {
        #expect(NoiseLabels.filter(events, by: .traffic, in: night, hasAudio: true).map(\.audioOffset) == [10, 30])
        #expect(NoiseLabels.filter(events, by: nil, in: night, hasAudio: true).count == 4)
        #expect(NoiseLabels.filter(events, by: .animals, in: night, hasAudio: true).isEmpty)
    }

    @Test func correctionReplacesTheLabel() {
        var s = night
        s.correctLabel(for: event(at: 20), to: .speech)
        let label = s.label(for: event(at: 20))
        #expect(label?.noiseCategory == .speech)
        #expect(label?.corrected == true)
        #expect(s.eventLabels?.count == 3)
    }

    @Test func correctionAddsALabelWhenThereWasNone() {
        var s = night
        s.correctLabel(for: event(at: 40), to: .animals)
        #expect(s.label(for: event(at: 40))?.noiseCategory == .animals)
        #expect(s.eventLabels?.count == 4)
    }

    @Test func correctionIsSavedAndSurvivesRelabelling() throws {
        var s = night
        s.correctLabel(for: event(at: 10), to: .aircraft)
        let loaded = try SessionStore.decoder.decode(SleepSession.self, from: SessionStore.encoder.encode(s))
        #expect(loaded.label(for: event(at: 10))?.noiseCategory == .aircraft)
        let window = SoundClassifier.Window(start: 10, duration: 1, labels: [SoundClassifier.Label(identifier: "car_passing_by", confidence: 0.9)])
        let relabelled = EventLabelling.labels(for: [event(at: 10)], in: loaded, windows: [window])
        #expect(relabelled.first?.noiseCategory == .aircraft)
    }

    @Test func unknownIsNotOfferedAsACorrection() {
        #expect(!NoiseLabels.choices.contains(.unknown))
        #expect(NoiseLabels.choices.contains(.other))
    }
}
