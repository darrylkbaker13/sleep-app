import Foundation
import Testing
@testable import Loop_Sense

struct NightChartTests {
    @Test("Summary line", arguments: [
        (5, Optional(1), "5 loud noises · 1 woke you"),
        (1, Optional(0), "1 loud noise · none woke you"),
        (3, nil, "3 loud noises"),
        (0, nil, "No loud noises"),
        (0, Optional(0), "No loud noises"),
        (0, Optional(2), "No loud noises · 2 woke you"),
    ])
    func summary(loud: Int, woke: Int?, expected: String) {
        #expect(NightChartSummary.text(loud: loud, woke: woke) == expected)
    }

    private func event(_ peak: Double, at second: Double) -> LoudEvent {
        LoudEvent(start: Date(timeIntervalSince1970: second), duration: 3, peak: peak, audioOffset: second)
    }

    @Test func onlyNoisesOver45AreMarked() {
        let events = [event(40, at: 0), event(45, at: 10), event(46, at: 20), event(70, at: 30)]
        let marks = NightChartSummary.marks(events, nightLength: 10)
        #expect(marks.loud.map(\.peak) == [46, 70])
        #expect(marks.labelled.count == 2)
    }

    @Test func onlyTheLoudestFewAreLabelled() {
        // 20 noises two hours apart (more than the label gap): no two are close, so the 5 loudest get labels.
        let events = (0..<20).map { event(50 + Double($0), at: Double($0) * 7200) }
        let marks = NightChartSummary.marks(events, nightLength: 20 * 3600)
        #expect(marks.loud.count == 20)
        #expect(marks.labelled.count == NightChartSummary.maxLabels)
        let labelledPeaks = marks.loud.filter { marks.labelled.contains($0.id) }.map(\.peak)
        #expect(labelledPeaks.min() == 65)
    }

    @Test func closeNoisesDontBothGetLabels() {
        // 61 and 57 dB two minutes apart on an 8-hour night: only the louder is labelled.
        let events = [event(61, at: 7000), event(57, at: 7120), event(56, at: 20000)]
        let marks = NightChartSummary.marks(events, nightLength: 8 * 3600)
        let labelled = marks.loud.filter { marks.labelled.contains($0.id) }.map(\.peak)
        #expect(labelled.sorted() == [56, 61])
    }

    @Test func fourAxisTimesFromStartToEnd() {
        let start = Date(timeIntervalSince1970: 0)
        let times = NightChartSummary.axisTimes(from: start, to: start.addingTimeInterval(9 * 3600))
        #expect(times.map { $0.timeIntervalSince(start) / 3600 } == [0, 3, 6, 9])
    }
}
