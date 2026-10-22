import Foundation
import Testing
@testable import Loop_Sense

/// Builds a made-up night: a steady background, optional noises and an optional pause.
private func night(hours: Double = 2, background: Double, noises: [(atSecond: Int, peak: Double, seconds: Int)] = [],
                   pausedSeconds: Int = 0) -> SleepSession {
    let offset = 95.0
    var levels = [Float](repeating: Float(background - offset), count: Int(hours * 3600))
    for n in noises {
        for i in n.atSecond..<min(levels.count, n.atSecond + n.seconds) { levels[i] = Float(n.peak - offset) }
    }
    for i in 0..<min(pausedSeconds, levels.count) { levels[levels.count - 1 - i] = .nan }
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    return SleepSession(id: UUID(), start: start, end: start.addingTimeInterval(hours * 3600),
                        calibrationOffset: offset, levels: levels, audioFileName: nil)
}

/// Noises spaced well apart so each counts as its own event.
private func spacedNoises(_ count: Int, peak: Double) -> [(atSecond: Int, peak: Double, seconds: Int)] {
    (0..<count).map { (atSecond: 120 + $0 * 300, peak: peak, seconds: 3) }
}

@MainActor
struct ReportWordingTests {
    @Test func quietNight() throws {
        let a = try #require(NightAnalysis(session: night(background: 25)))
        #expect(a.headline == "Very quiet night · 25 dB average")
        #expect(a.subline == "Steady all night, no noise spikes")
        #expect(a.chips.map(\.text) == ["Within WHO guideline", "No noises over 45 dB", "Noisiest at \(a.hours.max { $0.average < $1.average }!.hour.formatted(date: .omitted, time: .shortened))"])
        #expect(a.chips[0].tone == .good)
    }

    @Test func noisyNight() throws {
        let a = try #require(NightAnalysis(session: night(background: 40, noises: spacedNoises(20, peak: 62))))
        #expect(a.headline.hasSuffix("dB average"))
        #expect(a.subline.hasPrefix("20 noises · noisiest around "))
        #expect(a.chips[0].text.hasSuffix("dB over WHO guideline"))
        #expect(a.chips[0].tone == .warning)
        #expect(a.chips[1].text == "20 events over 45 dB")
        #expect(a.chips[1].tone == .warning)
    }

    @Test func fewLoudNoisesAreWithinGuideline() throws {
        let a = try #require(NightAnalysis(session: night(background: 28, noises: spacedNoises(5, peak: 55))))
        #expect(a.chips[1].text == "5 over 45 dB, within WHO")
        #expect(a.chips[1].tone == .good)
    }

    @Test func pausedRecording() throws {
        let a = try #require(NightAnalysis(session: night(background: 28, pausedSeconds: 300)))
        #expect(a.chips.contains { $0.text == "Paused 5 min" })
    }

    @Test func everyChipHasAFullExplanation() throws {
        let a = try #require(NightAnalysis(session: night(background: 40, noises: spacedNoises(20, peak: 62))))
        for chip in a.chips {
            #expect(chip.detail.count > chip.text.count, "\(chip.text) has no real detail")
        }
    }

    @Test func noLineLongerThanAboutSixtyCharacters() throws {
        let nights = [
            night(background: 25),
            night(background: 33, noises: spacedNoises(3, peak: 50)),
            night(background: 44, noises: spacedNoises(20, peak: 70)),
            night(hours: 9, background: 58, noises: spacedNoises(99, peak: 85), pausedSeconds: 7200),
        ]
        for session in nights {
            let a = try #require(NightAnalysis(session: session))
            for line in [a.headline, a.subline] + a.chips.map(\.text) {
                #expect(line.count <= 60, "Too long (\(line.count)): \(line)")
            }
        }
    }

    @Test func garminChips() throws {
        // 8 hours: deep 1h 20m, three short wake-ups at 200, 300 and 400 minutes; noises just before the first two.
        let session = night(hours: 8, background: 30, noises: [(atSecond: 199 * 60 + 30, peak: 60, seconds: 3),
                                                               (atSecond: 299 * 60 + 30, peak: 60, seconds: 3)])
        let a = try #require(NightAnalysis(session: session))
        func at(_ minute: Int) -> Date { session.start.addingTimeInterval(Double(minute * 60)) }
        let plan: [(Int, Int, SleepStage)] = [
            (0, 60, .light), (60, 140, .deep), (140, 200, .light), (200, 203, .awake), (203, 300, .light),
            (300, 302, .awake), (302, 360, .rem), (360, 400, .light), (400, 402, .awake), (402, 480, .light),
        ]
        let intervals = plan.map { SleepInterval(start: at($0.0), end: at($0.1), stage: $0.2, source: "test") }
        let chips = SleepInsights(intervals: intervals, session: session, analysis: a).chips
        #expect(chips.map(\.text) == ["3 wake-ups · 2 after a noise", "7h 53m asleep · 1h 20m deep", "Deep sleep at 30 dB"])
        #expect(chips.allSatisfy { $0.text.count <= 60 })
    }
}
