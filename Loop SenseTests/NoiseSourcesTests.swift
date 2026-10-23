import Foundation
import Testing
@testable import Loop_Sense

struct NoiseSourcesTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// 23:00 UTC on 22 Oct 2026; nights run 8 hours.
    private let start = Date(timeIntervalSince1970: 1_792_710_000)

    private func night(_ noises: [(hour: Double, NoiseCategory?)], hours: Double = 8, labelled: Bool = true)
        -> (events: [LoudEvent], session: SleepSession) {
        let events = noises.map { n in
            LoudEvent(start: start.addingTimeInterval(n.hour * 3600), duration: 3, peak: 55, audioOffset: n.hour * 3600)
        }
        var s = SleepSession(id: UUID(), start: start, end: start.addingTimeInterval(hours * 3600),
                             calibrationOffset: 95, levels: [], audioFileName: "a.caf")
        if labelled {
            s.eventLabels = zip(events, noises).compactMap { e, n in
                n.1.map { EventLabel(second: EventLabel.second(of: e, in: s), category: $0.rawValue, confidence: 0.8) }
            }
        }
        return (events, s)
    }

    private func finding(_ noises: [(hour: Double, NoiseCategory?)], hours: Double = 8) -> String? {
        let n = night(noises, hours: hours)
        return NoiseSources(events: n.events, session: n.session, calendar: calendar)?.finding
    }

    @Test func mostlyTrafficInTheMorning() {
        // 6 traffic noises between 05:00 and 07:00 (hours 6–8 after 23:00), plus a little else.
        let noises: [(Double, NoiseCategory?)] = [(6.1, .traffic), (6.3, .traffic), (6.6, .traffic), (7.0, .traffic),
                                                  (7.4, .traffic), (7.8, .traffic), (2.0, .snoring), (3.0, .animals)]
        let f = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone)
        let five = start.addingTimeInterval(6 * 3600), seven = start.addingTimeInterval(8 * 3600)   // 05:00 and 07:00
        #expect(finding(noises) == "Most noises were traffic (6 of 8), mainly between \(five.formatted(f)) and \(seven.formatted(f)).")
    }

    @Test func mostCommonButNotMost() {
        let noises: [(Double, NoiseCategory?)] = [(0.5, .snoring), (3.5, .snoring), (6.5, .snoring), (4, .traffic), (5, .animals),
                                                  (6, .speech), (7, .household)]
        #expect(finding(noises) == "The most common noise was snoring (3 of 7).")
    }

    @Test func mostCouldntBeIdentified() {
        let noises: [(Double, NoiseCategory?)] = [(1, .unknown), (2, .unknown), (3, .unknown), (4, .traffic)]
        #expect(finding(noises) == "Most noises couldn't be identified (3 of 4).")
    }

    @Test func mentionsTheUnidentifiedOnes() {
        let noises: [(Double, NoiseCategory?)] = [(1, .speech), (1.5, .speech), (2, .unknown)]
        #expect(finding(noises) == "Most noises were people talking or coughing (2 of 3). 1 couldn't be identified.")
    }

    @Test func noWindowWhenNoisesAreSpreadOut() {
        let noises: [(Double, NoiseCategory?)] = [(0.5, .traffic), (3.5, .traffic), (6.5, .traffic), (1, .snoring)]
        #expect(finding(noises) == "Most noises were traffic (3 of 4).")
    }

    @Test func noWindowOnShortRecordings() {
        let noises: [(Double, NoiseCategory?)] = [(0.1, .musicTV), (0.2, .musicTV), (0.3, .musicTV)]
        #expect(finding(noises, hours: 0.5) == "Most noises were music or TV (3 of 3).")
    }

    @Test func breakdownCountsMostFirst() throws {
        let n = night([(1, .snoring), (2, .snoring), (3, .traffic), (4, .unknown)])
        let sources = try #require(NoiseSources(events: n.events, session: n.session, calendar: calendar))
        #expect(sources.total == 4)
        #expect(sources.counts.map(\.category) == [.snoring, .traffic, .unknown])
        #expect(sources.counts.map(\.count) == [2, 1, 1])
    }

    @Test func nothingUntilLabelled() {
        let n = night([(1, .snoring)], labelled: false)
        #expect(NoiseSources(events: n.events, session: n.session, calendar: calendar) == nil)
    }

    @Test func nothingWithoutNoises() {
        let n = night([])
        #expect(NoiseSources(events: n.events, session: n.session, calendar: calendar) == nil)
    }

    @Test func eventsMissingALabelCountAsUnidentified() throws {
        let n = night([(1, .traffic), (2, .traffic), (3, nil)])
        let sources = try #require(NoiseSources(events: n.events, session: n.session, calendar: calendar))
        #expect(sources.counts.first { $0.category == .unknown }?.count == 1)
    }
}
