import SwiftUI

/// Averages for one group of nights (with or without earplugs).
nonisolated struct NightGroupStats {
    let nights: Int
    /// Nights that also have Garmin sleep stages.
    let nightsWithStages: Int
    let averageLevel: Double?
    let wakeUps: Double?
    let deepSleep: TimeInterval?
}

/// Compares nights tagged with earplugs in the morning check-in against nights without.
nonisolated struct EarplugComparison {
    let with: NightGroupStats
    let without: NightGroupStats

    /// Each night's analysis, plus its sleep stages if any were found.
    struct Night {
        let session: SleepSession
        let analysis: NightAnalysis
        let stages: [SleepInterval]
    }

    init(nights: [Night]) {
        with = Self.stats(nights.filter { $0.session.earplugs != nil })
        without = Self.stats(nights.filter { $0.session.earplugs == nil })
    }

    private static func stats(_ nights: [Night]) -> NightGroupStats {
        let staged = nights.filter { !$0.stages.isEmpty }
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        return NightGroupStats(
            nights: nights.count,
            nightsWithStages: staged.count,
            averageLevel: mean(nights.map(\.analysis.average)),
            wakeUps: mean(staged.map { Double(SleepInsights.awakenings(in: $0.stages).count) }),
            deepSleep: mean(staged.map { SleepInsights.deepSleepSeconds(in: $0.stages) }))
    }

    /// A plain-English summary, or nil when there isn't enough to compare.
    var summary: String? {
        guard with.nightsWithStages > 0, without.nightsWithStages > 0,
              let wakeWith = with.wakeUps, let wakeWithout = without.wakeUps,
              let deepWith = with.deepSleep, let deepWithout = without.deepSleep else { return nil }
        let wakeDiff = wakeWithout - wakeWith
        let wake = abs(wakeDiff) < 0.5
            ? "With earplugs you woke about as often as without"
            : String(format: "With earplugs you woke %.1f times %@ a night", abs(wakeDiff), wakeDiff > 0 ? "fewer" : "more")
        let deepDiff = deepWith - deepWithout
        let deep = abs(deepDiff) < 5 * 60
            ? "got about the same deep sleep"
            : "got \(formatDuration(abs(deepDiff))) \(deepDiff > 0 ? "more" : "less") deep sleep"
        return "\(wake), and \(deep)."
    }

    /// Few nights make for a shaky comparison.
    var isEarly: Bool { min(with.nightsWithStages, without.nightsWithStages) < 3 }
}

/// Trends card: earplug nights side by side with the rest.
struct EarplugComparisonCard: View {
    let comparison: EarplugComparison

    var body: some View {
        Card("With and without earplugs") {
            if comparison.with.nights == 0 {
                Text("Tag the nights you wear earplugs in the morning check-in, and they'll be compared with the rest here.")
                    .foregroundStyle(.secondary)
            } else if comparison.without.nights == 0 {
                Text("Every night here is tagged with earplugs. Record a few without to see whether they help.")
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("")
                        Text("Earplugs").font(.loop(.caption)).foregroundStyle(Color.loopAccent)
                        Text("Without").font(.loop(.caption)).foregroundStyle(.secondary)
                    }
                    row("Nights", "\(comparison.with.nights)", "\(comparison.without.nights)")
                    row("Wake-ups", decimal(comparison.with.wakeUps), decimal(comparison.without.wakeUps))
                    row("Deep sleep", duration(comparison.with.deepSleep), duration(comparison.without.deepSleep))
                    row("Room level", level(comparison.with.averageLevel), level(comparison.without.averageLevel))
                }
                .font(.loop(.subheadline))

                if let summary = comparison.summary {
                    Text(summary)
                    if comparison.isEarly {
                        Text("Based on only a few nights, so treat this as an early hint.")
                            .font(.loop(.caption)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Wake-ups and deep sleep need Garmin sleep stages from Apple Health on both kinds of night. Connect Apple Health from any night's report.")
                        .font(.loop(.caption)).foregroundStyle(.secondary)
                }
                Text("Wake-ups and deep sleep are averages per night. Nights not tagged with earplugs count as without.")
                    .font(.loop(.caption2)).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ title: String, _ with: String, _ without: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(with).monospacedDigit()
            Text(without).monospacedDigit()
        }
    }

    private func decimal(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "–" }
    private func duration(_ v: TimeInterval?) -> String { v.map(formatDuration) ?? "–" }
    private func level(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) dB" } ?? "–" }
}
