import Foundation
import UIKit

/// Things that could spoil a night's recording, checked when the user taps Start.
struct BedtimeChecks {
    /// Below this, an unplugged phone may not last the night.
    static let minimumUnpluggedBattery: Float = 0.5

    let warnings: [String]

    init(batteryLevel: Float, batteryState: UIDevice.BatteryState, lowPowerMode: Bool) {
        var warnings: [String] = []
        let charging = batteryState == .charging || batteryState == .full
        // A level of -1 means unknown (e.g. the Simulator), so don't warn about it.
        if !charging, batteryLevel >= 0, batteryLevel < Self.minimumUnpluggedBattery {
            warnings.append("Your phone isn't charging and the battery is at \(Int((batteryLevel * 100).rounded()))%. A full night of recording may run it flat. Plug it in before you sleep.")
        }
        if lowPowerMode {
            warnings.append("Low Power Mode is on. iOS may pause background recording to save battery. Turn it off in Settings › Battery.")
        }
        self.warnings = warnings
    }

    /// Reads the phone's current state.
    @MainActor static func current() -> BedtimeChecks {
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = wasMonitoring }
        return BedtimeChecks(batteryLevel: device.batteryLevel, batteryState: device.batteryState,
                             lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}
