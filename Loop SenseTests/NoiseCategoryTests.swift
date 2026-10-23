import SoundAnalysis
import Testing
import UIKit
@testable import Loop_Sense

struct NoiseCategoryTests {
    @Test("Common bedroom noises land in the right category", arguments: [
        ("snoring", NoiseCategory.snoring),
        ("breathing", .snoring),
        ("speech", .speech),
        ("laughter", .speech),
        ("car_passing_by", .traffic),
        ("traffic_noise", .traffic),
        ("police_siren", .traffic),
        ("motorcycle", .traffic),
        ("airplane", .aircraft),
        ("helicopter", .aircraft),
        ("dog_bark", .animals),
        ("cat_meow", .animals),
        ("bird_chirp_tweet", .animals),
        ("door_slam", .household),
        ("toilet_flush", .household),
        ("air_conditioner", .household),
        ("mechanical_fan", .household),
        ("rain", .weather),
        ("thunder", .weather),
        ("music", .musicTV),
        ("piano", .musicTV),
        ("alarm_clock", .alarmPhone),
        ("ringtone", .alarmPhone),
        ("smoke_detector", .alarmPhone),
        ("cough", .speech),
        ("sneeze", .speech),
        ("nose_blowing", .speech),
        ("sigh", .snoring),
        ("water", .household),
        ("fire_crackle", .household),
        ("typing", .household),
        ("sea_waves", .weather),
        ("wind_chime", .weather),
    ])
    func commonLabels(label: String, expected: NoiseCategory) {
        #expect(NoiseCategory.category(for: label, confidence: 0.9) == expected)
    }

    /// Top-3 labels the classifier gave each sound in the 20-sound noise test (test-audio/), and the
    /// category a listener would expect.
    @Test("Noise test results", arguments: NoiseTestCase.all)
    func noiseTest(_ c: NoiseTestCase) {
        #expect(NoiseCategory.category(for: c.labels) == c.expected, "\(c.sound)")
    }

    @Test func vagueTopLabelWithNothingBetterStaysHousehold() {
        #expect(NoiseCategory.category(for: [(identifier: "water", confidence: 0.8), (identifier: "music", confidence: 0.3)]) == .household)
    }

    @Test func specificLabelBelowThresholdDoesNotOverrideVagueOne() {
        // "rain" is too unsure to trust, so the vague "water" stands.
        #expect(NoiseCategory.category(for: [(identifier: "water", confidence: 0.8), (identifier: "rain", confidence: 0.3)]) == .household)
    }

    @Test func noConfidentLabelIsUnknown() {
        #expect(NoiseCategory.category(for: [(identifier: "sneeze", confidence: 0.17), (identifier: "speech", confidence: 0.16)]) == .unknown)
        #expect(NoiseCategory.category(for: []) == .unknown)
    }

    @Test func belowThresholdIsUnknown() {
        let t = NoiseCategory.confidenceThreshold
        #expect(NoiseCategory.category(for: "snoring", confidence: t - 0.01) == .unknown)
        #expect(NoiseCategory.category(for: "snoring", confidence: t) == .snoring)
    }

    @Test func silenceIsUnknown() {
        #expect(NoiseCategory.category(for: "silence", confidence: 0.99) == .unknown)
    }

    @Test func unlistedLabelsAreOther() {
        #expect(NoiseCategory.category(for: "gunshot_gunfire", confidence: 0.9) == .other)
        #expect(NoiseCategory.category(for: "not_a_real_label", confidence: 0.9) == .other)
    }

    /// Catches typos and labels Apple renames: every label in the mapping must be one the classifier knows.
    @Test func everyMappedLabelIsARealClassifierLabel() throws {
        let known = Set(try SNClassifySoundRequest(classifierIdentifier: .version1).knownClassifications)
        let unknown = NoiseCategory.labelMap.keys.filter { !known.contains($0) }.sorted()
        #expect(unknown.isEmpty, "Not classifier labels: \(unknown)")
    }

    @Test func noLabelIsListedTwice() {
        let all = NoiseCategory.labels.values.flatMap { $0 }
        #expect(all.count == Set(all).count)
    }

    @Test("Every category has a name and a real SF Symbol", arguments: NoiseCategory.allCases)
    func nameAndIcon(category: NoiseCategory) {
        #expect(!category.name.isEmpty)
        #expect(UIImage(systemName: category.symbol) != nil, "\(category.symbol) isn't an SF Symbol")
    }
}

struct NoiseTestCase: CustomTestStringConvertible, Sendable {
    let sound: String
    let labels: [(identifier: String, confidence: Double)]
    let expected: NoiseCategory
    var testDescription: String { sound }

    init(_ sound: String, _ labels: [(String, Double)], _ expected: NoiseCategory) {
        self.sound = sound
        self.labels = labels.map { (identifier: $0.0, confidence: $0.1) }
        self.expected = expected
    }

    static let all: [NoiseTestCase] = [
        NoiseTestCase("Running a tap", [("water", 0.74), ("liquid_dripping", 0.73), ("liquid_filling_container", 0.68)], .household),
        NoiseTestCase("Rain outside", [("water", 0.78), ("rain", 0.70), ("waterfall", 0.46)], .weather),
        NoiseTestCase("Cough", [("cough", 0.99), ("music", 0.14), ("waterfall", 0.06)], .speech),
        NoiseTestCase("Toilet flushing", [("toilet_flush", 1.00), ("water", 0.73), ("stream_burbling", 0.62)], .household),
        NoiseTestCase("Dog barking", [("coyote_howl", 0.58), ("dog_bark", 0.53), ("dog", 0.41)], .animals),
        NoiseTestCase("Baby crying", [("babble", 0.77), ("baby_laughter", 0.46), ("crying_sobbing", 0.43)], .speech),
        NoiseTestCase("Wind outside", [("thunderstorm", 0.59), ("wind", 0.58), ("thunder", 0.58)], .weather),
        NoiseTestCase("Knocking", [("knock", 1.00), ("door", 0.96), ("hammer", 0.28)], .household),
        NoiseTestCase("Sniffing", [("gasp", 0.98), ("breathing", 0.97), ("sigh", 0.45)], .snoring),
        NoiseTestCase("Snoring", [("breathing", 0.97), ("snoring", 0.95), ("sigh", 0.92)], .snoring),
        NoiseTestCase("Doorbell", [("door_bell", 0.85), ("door", 0.76), ("tuning_fork", 0.67)], .alarmPhone),
        NoiseTestCase("Helicopter", [("aircraft", 0.77), ("insect", 0.65), ("airplane", 0.57)], .aircraft),
    ]
}
