import Foundation

/// The optional morning stop time. Stored as minutes after midnight so it's independent of the date.
nonisolated enum AutoStop {
    static let enabledKey = "autoStopEnabled"
    static let minutesKey = "autoStopMinutes"
    /// 07:30
    static let defaultMinutes = 7 * 60 + 30
    /// Never stop a recording sooner than this after it starts, e.g. a short nap started at 07:20.
    static let minimumRecording: TimeInterval = 60 * 60

    /// The first time the clock reads `minutes` after midnight that is at least `minimumRecording`
    /// after `start`. Starting at 23:00 with 07:30 set gives 07:30 the next morning; starting at
    /// 07:00 gives 07:30 the following day.
    static func stopDate(after start: Date, minutes: Int, calendar: Calendar = .current) -> Date {
        let earliest = start.addingTimeInterval(minimumRecording)
        let components = DateComponents(hour: minutes / 60, minute: minutes % 60)
        return calendar.nextDate(after: earliest, matching: components, matchingPolicy: .nextTime) ?? earliest
    }

    /// The stop-time setting as a Date today, for a time picker.
    static func pickerDate(minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
