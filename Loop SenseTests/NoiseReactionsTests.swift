import Foundation
import Testing
@testable import Loop_Sense

struct NoiseReactionsTests {
    private let t0 = Date(timeIntervalSince1970: 1_792_710_000)   // 23:00 UTC

    /// Heart rate once a minute from `values`, starting at minute 0.
    private func hr(_ values: [Double]) -> [SnapshotBuilder.Sample] {
        values.enumerated().map { i, v in
            SnapshotBuilder.Sample(start: t0.addingTimeInterval(Double(i) * 60), end: t0.addingTimeInterval(Double(i + 1) * 60),
                                   value: v, source: "garmin")
        }
    }

    private func noise(atMinute m: Double, peak: Double = 52, _ category: NoiseCategory? = .traffic) -> LoudNoise {
        LoudNoise(time: t0.addingTimeInterval(m * 60), peak: peak, category: category)
    }

    @Test func jumpAfterALoudNoiseIsAReaction() throws {
        // Steady 60, noise at minute 5, up to 78 a minute later, back to 62 four minutes after that.
        let readings = hr([60, 60, 60, 60, 60, 60, 78, 72, 66, 64, 62, 60, 60])
        let r = try #require(NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 5)]).first)
        #expect(r.before == 60)
        #expect(r.peak == 78)
        #expect(r.peakTime == t0.addingTimeInterval(6 * 60))
        #expect(r.settledAfter == 4)
    }

    @Test func reactionWording() throws {
        let readings = hr([60, 60, 60, 60, 60, 60, 78, 72, 66, 64, 62, 60])
        let r = try #require(NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 5)]).first)
        let utc = TimeZone(identifier: "UTC")!
        let time = r.peakTime.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: utc))
        #expect(r.text(timeZone: utc) == "Your heart rate jumped from 60 to 78 bpm at \(time), right after a 52 dB noise (Traffic). It settled within 4 minutes.")
    }

    @Test func smallRiseIsNotAReaction() {
        let readings = hr([60, 60, 60, 60, 60, 60, 69, 65, 60])   // +9
        #expect(NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 5)]).isEmpty)
    }

    @Test func riseOfExactlyTenCounts() {
        let readings = hr([60, 60, 60, 60, 60, 60, 70, 60])
        #expect(NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 5)]).count == 1)
    }

    @Test func riseTooLateIsNotAReaction() {
        // Noise at minute 2, jump at minute 5: outside the 2-minute window.
        let readings = hr([60, 60, 60, 60, 60, 80, 60])
        #expect(NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 2)]).isEmpty)
    }

    @Test func quietNoisesAreIgnored() {
        let readings = hr([60, 60, 60, 60, 60, 60, 80, 60])
        #expect(NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 5, peak: 44)]).isEmpty)
    }

    @Test func noSettleWhenItStaysHigh() throws {
        let readings = hr([60, 60, 60, 60, 60, 60, 80, 78, 77, 76])
        let r = try #require(NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 5)]).first)
        #expect(r.settledAfter == nil)
        #expect(!r.text().contains("settled"))
    }

    @Test func unknownCategoryIsLeftOutOfTheText() throws {
        let readings = hr([60, 60, 60, 60, 60, 60, 78, 60])
        let r = try #require(NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 5, .unknown)]).first)
        #expect(r.text().contains("52 dB noise."))
    }

    @Test func eachNoiseIsCheckedSeparately() {
        let readings = hr([60, 60, 60, 60, 60, 60, 78, 60, 60, 60, 60, 60, 61, 60, 60])
        let found = NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 11), noise(atMinute: 5)])
        #expect(found.map(\.noiseTime) == [t0.addingTimeInterval(5 * 60)])
    }

    @Test func noReadingsBeforeTheNoiseMeansNoReaction() {
        let readings = hr([80, 80])
        #expect(NoiseReactions.find(heartRate: readings, noises: [noise(atMinute: 0)]).isEmpty)
    }

    @Test func lowestReading() {
        let low = NoiseReactions.lowest(hr([60, 55, 49, 58]))
        #expect(low?.value == 49)
        #expect(low?.start == t0.addingTimeInterval(120))
    }

    @Test func calmWording() {
        #expect(NoiseReactions.calmText(loudCount: 0).hasPrefix("There were no loud noises"))
        #expect(NoiseReactions.calmText(loudCount: 1) == "Your heart rate didn't jump after the one loud noise.")
        #expect(NoiseReactions.calmText(loudCount: 4) == "Your heart rate didn't jump after any of the 4 loud noises.")
    }

    @Test func theRuleIsTenBeatsInTwoMinutes() {
        #expect(NoiseReactions.minimumRise == 10)
        #expect(NoiseReactions.window == 120)
    }
}
