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
    static let loopGood = Color(hex: 0x6CC28A)       // report verdicts: within guidelines
    static let loopWarn = Color(hex: 0xE8A54F)       // report verdicts: worth a look

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Brand typeface. Loop uses Century Gothic; Didact Gothic (SIL Open Font License, bundled in
/// Fonts/) is a free lookalike. To switch, bundle a licensed font, list it under UIAppFonts in
/// Loop-Sense-Info.plist and change this name. It has a single weight, so bold styles read regular.
enum LoopFont {
    static let name = "DidactGothic-Regular"
}

extension Font {
    /// The brand font at a Dynamic Type text style, so it still follows the user's text size.
    static func loop(_ style: Font.TextStyle) -> Font {
        .custom(LoopFont.name, size: style.defaultSize, relativeTo: style)
    }

    static func loop(size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(LoopFont.name, size: size, relativeTo: style)
    }
}

private extension Font.TextStyle {
    /// Point sizes at the default (Large) text size.
    var defaultSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
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

extension NoiseCategory {
    /// Marker colour for this kind of noise on charts and in the event list.
    var color: Color {
        switch self {
        case .snoring: Color(hex: 0xD9A3A5)    // Apple Blossom tint
        case .speech: Color(hex: 0x8FB8DE)     // soft blue
        case .traffic: Color(hex: 0xE8664F)    // coral
        case .aircraft: Color(hex: 0xE8A54F)   // amber
        case .animals: Color(hex: 0x6CC28A)    // green
        case .household: Color(hex: 0xBFC3CA)  // silver
        case .weather: Color(hex: 0x5FB3C9)    // teal
        case .musicTV: Color(hex: 0xB591D6)    // lavender
        case .alarmPhone: Color(hex: 0xE0283F) // red
        case .other: Color(hex: 0x8E8E93)
        case .unknown: Color(hex: 0x5A5A60)
        }
    }
}
