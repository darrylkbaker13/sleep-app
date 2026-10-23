import Foundation

/// Reading and correcting a night's noise labels for the report (I2d).
nonisolated enum NoiseLabels {
    /// The category shown for an event: its stored label, Unknown when the night has no audio to
    /// classify, or nil while it's still waiting to be labelled.
    static func category(of event: LoudEvent, in session: SleepSession, hasAudio: Bool) -> NoiseCategory? {
        if let label = session.label(for: event) { return label.noiseCategory }
        return hasAudio ? nil : .unknown
    }

    /// How many events fall in each category, most first. Events still waiting are left out.
    static func counts(_ events: [LoudEvent], in session: SleepSession, hasAudio: Bool) -> [(category: NoiseCategory, count: Int)] {
        let cats = events.compactMap { category(of: $0, in: session, hasAudio: hasAudio) }
        return Dictionary(grouping: cats, by: { $0 }).map { ($0.key, $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.category.name < $1.category.name }
    }

    /// The events in one category, or all of them when `category` is nil.
    static func filter(_ events: [LoudEvent], by category: NoiseCategory?, in session: SleepSession, hasAudio: Bool) -> [LoudEvent] {
        guard let category else { return events }
        return events.filter { self.category(of: $0, in: session, hasAudio: hasAudio) == category }
    }

    /// The categories someone can pick when correcting a label.
    static let choices: [NoiseCategory] = NoiseCategory.allCases.filter { $0 != .unknown }
}

extension SleepSession {
    /// Sets an event's category by hand. Corrections are kept when the night is labelled again.
    nonisolated mutating func correctLabel(for event: LoudEvent, to category: NoiseCategory) {
        let second = EventLabel.second(of: event, in: self)
        var labels = eventLabels ?? []
        let fixed = EventLabel(second: second, category: category.rawValue, confidence: 1, label: nil, corrected: true)
        if let i = labels.firstIndex(where: { $0.second == second }) { labels[i] = fixed } else { labels.append(fixed) }
        eventLabels = labels
    }
}
