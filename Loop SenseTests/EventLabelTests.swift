import Foundation
import Testing
@testable import Loop_Sense

@MainActor
struct EventLabelTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func session(labels: [EventLabel]? = nil, version: Int? = nil) -> SleepSession {
        var s = SleepSession(id: UUID(), start: start, end: start.addingTimeInterval(600), calibrationOffset: 95,
                             levels: [Float](repeating: -65, count: 600), audioFileName: "night.caf")
        s.eventLabels = labels
        s.labelsVersion = version
        return s
    }

    private func event(at second: Double, lasting: Double = 3) -> LoudEvent {
        LoudEvent(start: start.addingTimeInterval(second), duration: lasting, peak: 60, audioOffset: second)
    }

    private func window(at t: Double, _ labels: (String, Double)...) -> SoundClassifier.Window {
        SoundClassifier.Window(start: t, duration: 1, labels: labels.map { SoundClassifier.Label(identifier: $0.0, confidence: $0.1) })
    }

    // MARK: Storing and loading

    @Test func labelsSurviveSavingAndLoading() throws {
        let labels = [EventLabel(second: 120, category: NoiseCategory.animals.rawValue, confidence: 0.53, label: "dog_bark"),
                      EventLabel(second: 300, category: NoiseCategory.snoring.rawValue, confidence: 0.76, label: "snoring",
                                 corrected: true)]
        let data = try SessionStore.encoder.encode(session(labels: labels, version: EventLabelling.version))
        let loaded = try SessionStore.decoder.decode(SleepSession.self, from: data)
        #expect(loaded.eventLabels == labels)
        #expect(loaded.labelsVersion == EventLabelling.version)
    }

    @Test func nightsSavedBeforeLabellingStillLoad() throws {
        let old = #"{"id":"8D51F7AD-5EEE-4239-9439-AF3BE3008DEC","start":"2026-10-21T20:06:00Z","calibrationOffset":95,"levels":[-60,-61],"audioFileName":"a.caf"}"#
        let loaded = try SessionStore.decoder.decode(SleepSession.self, from: Data(old.utf8))
        #expect(loaded.eventLabels == nil)
        #expect(loaded.labelsVersion == nil)
    }

    @Test func labelIsFoundByEventStartTime() {
        let s = session(labels: [EventLabel(second: 120, category: "animals", confidence: 0.6, label: "dog")])
        #expect(s.label(for: event(at: 120))?.noiseCategory == .animals)
        #expect(s.label(for: event(at: 200)) == nil)
    }

    @Test func unknownCategoryTextFallsBackToUnknown() {
        #expect(EventLabel(second: 0, category: "not-a-category", confidence: 0.9).noiseCategory == .unknown)
    }

    // MARK: Labelling

    @Test func eachEventGetsItsOwnWindows() {
        let windows = [window(at: 119.5, ("dog_bark", 0.8)), window(at: 120.5, ("dog_bark", 0.7)),
                       window(at: 300, ("snoring", 0.9)), window(at: 301, ("snoring", 0.85))]
        let labels = EventLabelling.labels(for: [event(at: 120, lasting: 1), event(at: 300, lasting: 2)],
                                           in: session(), windows: windows)
        #expect(labels.map(\.second) == [120, 300])
        #expect(labels.map(\.noiseCategory) == [.animals, .snoring])
        #expect(labels.map(\.label) == ["dog_bark", "snoring"])
    }

    @Test func unsureEventsAreStoredAsUnknown() {
        let labels = EventLabelling.labels(for: [event(at: 60, lasting: 1)], in: session(),
                                           windows: [window(at: 60, ("dog", 0.44))])
        #expect(labels.first?.noiseCategory == .unknown)
        #expect(labels.first?.confidence == 0.44)
    }

    @Test func storesTheLabelThatDecided() {
        // Long noise: "speech" wins most windows but is unsure; "babble" is sure and decides the category.
        let windows = [window(at: 60, ("speech", 0.43)), window(at: 61, ("speech", 0.40)),
                       window(at: 62, ("babble", 0.77)), window(at: 63, ("speech", 0.42))]
        let label = EventLabelling.labels(for: [event(at: 60, lasting: 4)], in: session(), windows: windows).first
        #expect(label?.noiseCategory == .speech)
        #expect(label?.label == "babble")
        #expect(label?.confidence == 0.77)
    }

    @Test func rainBehindWaterIsStoredAsRain() {
        let label = EventLabelling.labels(for: [event(at: 60, lasting: 1)], in: session(),
                                          windows: [window(at: 60, ("water", 0.78), ("rain", 0.70))]).first
        #expect(label?.noiseCategory == .weather)
        #expect(label?.label == "rain")
    }

    @Test func eventWithNoWindowsIsUnknown() {
        let labels = EventLabelling.labels(for: [event(at: 500)], in: session(), windows: [])
        #expect(labels.first?.noiseCategory == .unknown)
    }

    @Test func handCorrectionsAreKept() {
        let fixed = EventLabel(second: 120, category: NoiseCategory.traffic.rawValue, confidence: 1, corrected: true)
        let labels = EventLabelling.labels(for: [event(at: 120, lasting: 1)], in: session(labels: [fixed]),
                                           windows: [window(at: 120, ("dog_bark", 0.9))])
        #expect(labels == [fixed])
    }

    // MARK: When to label

    @Test func whichNightsNeedLabelling() {
        #expect(EventLabelling.needsLabels(session(), hasAudio: true))
        #expect(!EventLabelling.needsLabels(session(), hasAudio: false))
        #expect(!EventLabelling.needsLabels(session(labels: [], version: EventLabelling.version), hasAudio: true))
        #expect(EventLabelling.needsLabels(session(labels: [], version: EventLabelling.version - 1), hasAudio: true))
    }
}
