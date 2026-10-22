import Foundation

/// Loop's earplug range. This table is the single source for recommendations: edit it here
/// when Loop's line-up or ratings change.
nonisolated struct LoopModel: Identifiable {
    var id: String { name }
    let name: String
    /// Single Number Rating range in dB (equal for fixed-filter models).
    let snr: ClosedRange<Double>
    let note: String
    /// Suitable to wear in bed. Concert and social models are listed but not recommended for sleep.
    let goodForSleep: Bool
    /// Children only: never recommended from an adult's night.
    let kidsOnly: Bool

    var snrText: String {
        snr.lowerBound == snr.upperBound
            ? "\(Int(snr.upperBound)) dB"
            : "\(Int(snr.lowerBound))–\(Int(snr.upperBound)) dB"
    }

    static let all: [LoopModel] = [
        LoopModel(name: "Loop Dream", snr: 27...27, note: "Made for sleep, up to 27 dB",
                  goodForSleep: true, kidsOnly: false),
        LoopModel(name: "Loop Quiet 2", snr: 24...24, note: "Soft, low-profile, 24 dB",
                  goodForSleep: true, kidsOnly: false),
        LoopModel(name: "Loop Switch 2", snr: 20...26, note: "Adjustable from 20 to 26 dB",
                  goodForSleep: true, kidsOnly: false),
        LoopModel(name: "Loop Experience 2 / Experience 2 Plus", snr: 17...17, note: "For concerts and noisy venues",
                  goodForSleep: false, kidsOnly: false),
        LoopModel(name: "Loop Engage 2", snr: 16...16, note: "For conversations and social settings",
                  goodForSleep: false, kidsOnly: false),
        LoopModel(name: "Loop Engage Kids", snr: 16...16, note: "For children",
                  goodForSleep: false, kidsOnly: true),
    ]

    static let siteURL = URL(string: "https://www.loopearplugs.com")!
}

/// Picks a Loop model for one night, aiming to bring the room down to WHO bedroom levels.
nonisolated struct EarplugRecommendation {
    /// Reduction needed to reach the WHO targets: average 30 dB and individual noises 45 dB.
    let neededReduction: Double
    /// nil when the room already met the WHO targets.
    let model: LoopModel?
    let reason: String
    /// One short line for the report, e.g. "Needs about 25 dB less to reach WHO levels".
    let summary: String

    init(average: Double, peak: Double, models: [LoopModel] = LoopModel.all) {
        let forAverage = average - WHO.averageLimit
        let forPeak = peak - WHO.peakLimit
        let needed = max(forAverage, forPeak, 0).rounded(.up)
        neededReduction = needed
        let driver = forPeak > forAverage
            ? String(format: "the loudest noise (%.0f dB) down to %.0f dB", peak, WHO.peakLimit)
            : String(format: "the average (%.0f dB) down to %.0f dB", average, WHO.averageLimit)

        // Gentlest sleep model that covers the need: less blocking means alarms stay audible.
        let candidates = models
            .filter { $0.goodForSleep && !$0.kidsOnly }
            .sorted { $0.snr.upperBound < $1.snr.upperBound }

        summary = needed <= 0
            ? "Your room met WHO bedroom levels"
            : "Needs about \(Int(needed)) dB less to reach WHO levels"
        if needed <= 0 {
            model = nil
            reason = "Your room met the WHO's bedroom guidelines, so earplugs aren't essential. If you're a light sleeper, Loop Dream is designed for sleep."
        } else if let fit = candidates.first(where: { $0.snr.upperBound >= needed }) {
            model = fit
            let setting = fit.snr.lowerBound < needed && fit.snr.lowerBound < fit.snr.upperBound
                ? " Use it on its strongest setting." : ""
            reason = String(format: "Bringing %@ needs about %.0f dB of reduction. %@ is rated %@.%@",
                            driver, needed, fit.name, fit.snrText, setting)
        } else {
            model = candidates.last
            reason = String(format: "Bringing %@ needs about %.0f dB of reduction, more than any Loop model is rated for. %@ (%@) gives the most protection; consider reducing the noise at its source too.",
                            driver, needed, candidates.last?.name ?? "Loop Dream", candidates.last?.snrText ?? "27 dB")
        }
    }
}
