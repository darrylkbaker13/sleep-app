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
    ])
    func commonLabels(label: String, expected: NoiseCategory) {
        #expect(NoiseCategory.category(for: label, confidence: 0.9) == expected)
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
