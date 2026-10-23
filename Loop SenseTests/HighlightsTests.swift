import AVFoundation
import Foundation
import Testing
@testable import Loop_Sense

struct HighlightsTests {
    private func event(_ peak: Double, at second: Double, lasting: Double = 3) -> LoudEvent {
        LoudEvent(start: Date(timeIntervalSince1970: 1_790_000_000 + second), duration: lasting, peak: peak, audioOffset: second)
    }

    private func window(_ labels: (String, Double)...) -> SoundClassifier.Window {
        SoundClassifier.Window(start: 0, duration: 1, labels: labels.map { SoundClassifier.Label(identifier: $0.0, confidence: $0.1) })
    }

    // MARK: Picking and cutting clips

    @Test func picksTheFiveLoudest() {
        let events = [50, 70, 45, 62, 58, 66, 41].enumerated().map { event(Double($0.element), at: Double($0.offset) * 100) }
        #expect(Highlights.pick(events).map(\.peak) == [70, 66, 62, 58, 50])
    }

    @Test func fewerThanFiveNoisesGivesThemAll() {
        #expect(Highlights.pick([event(50, at: 0), event(60, at: 10)]).count == 2)
    }

    @Test func clipStartsJustBeforeTheNoise() {
        let r = Highlights.clipRange(for: event(60, at: 100), audioLength: 3600)
        #expect(r.start == 99 && r.duration == 5)
    }

    @Test func clipStaysInsideTheRecording() {
        let atStart = Highlights.clipRange(for: event(60, at: 0.3), audioLength: 3600)
        #expect(atStart.start == 0 && atStart.duration == 5)
        let atEnd = Highlights.clipRange(for: event(60, at: 3598), audioLength: 3600)
        #expect(atEnd.start == 3595 && atEnd.duration == 5)
        let tiny = Highlights.clipRange(for: event(60, at: 1), audioLength: 3)
        #expect(tiny.start == 0 && tiny.duration == 3)
    }

    // MARK: Ranking labels

    @Test func shortNoiseUsesHighestScore() {
        let windows = [window(("speech", 0.6), ("music", 0.3)), window(("music", 0.9))]
        #expect(SoundClassifier.topLabels(windows: windows, eventSeconds: 2).first?.identifier == "music")
    }

    @Test func longNoiseUsesWindowsWon() {
        // Snoring wins 3 windows; one misfire scores higher but only once.
        let windows = [window(("snoring", 0.7)), window(("snoring", 0.72)), window(("whale_vocalization", 0.81)),
                       window(("snoring", 0.65), ("breathing", 0.6))]
        let top = SoundClassifier.topLabels(windows: windows, eventSeconds: 10)
        #expect(top.map(\.identifier) == ["snoring", "whale_vocalization", "breathing"])
        #expect(top.first?.confidence == 0.72)   // its best score, used for the threshold
    }

    @Test func silenceIsIgnored() {
        let windows = [window(("silence", 0.99), ("dog_bark", 0.6))]
        #expect(SoundClassifier.topLabels(windows: windows, eventSeconds: 1).map(\.identifier) == ["dog_bark"])
    }

    // MARK: What's shown

    private func highlight(_ category: NoiseCategory) -> Highlight {
        Highlight(event: event(61, at: 0), clipStart: 0, clipDuration: 5, labels: [], category: category)
    }

    @Test func titles() {
        #expect(highlight(.snoring).title == "Snoring")
        #expect(highlight(.unknown).title == "Unknown sound")
        #expect(highlight(.aircraft).title == "Possibly Aircraft")
        #expect(highlight(.weather).title == "Possibly Weather")
    }

    @Test func shareTextIncludesTimeLevelAndCategory() {
        let text = Highlights.shareText(for: highlight(.animals))
        #expect(text.hasPrefix("Loop Sense · "))
        #expect(text.contains("61 dB"))
        #expect(text.hasSuffix("Animals"))
    }

    @Test func belowThresholdLabelsAreUnknown() {
        let labels = SoundClassifier.topLabels(windows: [window(("dog", 0.44), ("dog_bark", 0.40))], eventSeconds: 1)
        #expect(NoiseCategory.category(for: labels.map { (identifier: $0.identifier, confidence: $0.confidence) }) == .unknown)
    }

    // MARK: Classifying a real buffer

    @Test func classifiesABufferInMemory() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        let data = try #require(buffer.floatChannelData?[0])
        for i in 0..<48_000 { data[i] = 0.3 * sin(2 * .pi * 880 * Float(i) / 16_000) }  // 3 s tone
        let windows = try SoundClassifier.classify(buffer: buffer)
        #expect(!windows.isEmpty)
        #expect(windows.allSatisfy { !$0.labels.isEmpty })
    }
}
