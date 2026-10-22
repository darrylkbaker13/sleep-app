import SwiftUI

/// Loop brand palette. Apple Blossom red, white and black are Loop's published brand colours;
/// the charcoal comes from the Loop logo artwork. The level and sleep-stage colours are tints
/// chosen to sit alongside the red. Tweak them here and the whole app follows.
extension Color {
    static let loopMidnight = Color(hex: 0x000000)   // app background (Loop black)
    static let loopSurface = Color(hex: 0x1D1D1F)    // cards and list rows (logo charcoal)
    static let loopAccent = Color(hex: 0xAC4549)     // primary accent (Loop Apple Blossom)
    static let loopOnAccent = Color(hex: 0xFFFFFF)   // text and icons on the accent (Loop white)
    static let loopRoseGold = Color(hex: 0xD9A3A5)   // secondary accent, a light Apple Blossom tint
    static let loopSilver = Color(hex: 0xC7C7CC)     // secondary text, quiet levels
    static let loopCoral = Color(hex: 0xC9676B)      // between the tint and the accent
    static let loopRed = Color(hex: 0xE0283F)        // loud levels, stop button, errors

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Quiet nights read as neutral silver, loud ones warm up through Apple Blossom tints to red.
func levelColor(_ db: Double) -> Color {
    switch db {
    case ..<30: return .loopSilver
    case ..<40: return .loopRoseGold
    case ..<50: return .loopCoral
    case ..<60: return .loopAccent
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
