import SwiftUI

/// Palette inspired by Loop earplug finishes (Midnight Black, Glorious Gold, Rose Gold,
/// Swinging Silver, Raving Red). Loop doesn't publish hex codes, so these are approximations:
/// tweak them here and the whole app follows.
extension Color {
    static let loopMidnight = Color(hex: 0x0E0E12)   // app background
    static let loopSurface = Color(hex: 0x1B1B21)    // cards and list rows
    static let loopGold = Color(hex: 0xD4AF63)       // primary accent
    static let loopRoseGold = Color(hex: 0xE3A894)   // secondary accent
    static let loopSilver = Color(hex: 0xBFC3CA)     // secondary text, quiet levels
    static let loopCoral = Color(hex: 0xE8664F)      // between rose gold and red
    static let loopRed = Color(hex: 0xE0283F)        // loud levels, stop button

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Quiet nights read as cool silver, loud ones warm up through gold and rose gold to red.
func levelColor(_ db: Double) -> Color {
    switch db {
    case ..<30: return .loopSilver
    case ..<40: return .loopGold
    case ..<50: return .loopRoseGold
    case ..<60: return .loopCoral
    default: return .loopRed
    }
}

extension View {
    /// Midnight background behind a List or ScrollView.
    func loopBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.loopMidnight.ignoresSafeArea())
    }
}
