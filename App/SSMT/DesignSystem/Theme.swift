import SwiftUI

/// SSMT design tokens. Quiet near-black surfaces, system typography, one warm accent.
/// Colour is reserved for meaning: the accent marks actions, the closeness scale marks how far
/// a value is from its target. The brand logo stays strictly white and is never tinted.
enum Theme {
    // Surfaces
    static let background = Color(hex: 0x0B0B0C)
    static let panel = Color(hex: 0x161618)
    static let panelRaised = Color(hex: 0x202023)
    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.16)

    // Text
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0x98989D)
    static let textMuted = Color(hex: 0x636366)

    // Accents
    /// Primary accent: warm orange (actions, active state, main trace).
    static let accent = Color(hex: 0xFF9F0A)
    /// Orange-red for "live" emphasis (noise on, capture running).
    static let accentHot = Color(hex: 0xFF6A2B)
    /// Secondary data colour: yellow (secondary traces, highlights).
    static let signalYellow = Color(hex: 0xFFD60A)
    /// Cool blue reserved for comparison data (prediction / reference traces) so it never reads as a status.
    static let dataBlue = Color(hex: 0x64D2FF)

    // Status (always paired with an icon or a word — never colour alone)
    static let statusGood = Color(hex: 0x30D158)
    static let statusWarning = Color(hex: 0xFFD60A)
    static let statusError = Color(hex: 0xFF453A)

    // Geometry
    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 8

    /// Continuous "how close to the target" colour: 0 = far (red) → orange → yellow → 1 = on target (green).
    /// Used by every gauge so the whole UI reads the same way.
    static func closeness(_ c: Double) -> Color {
        let stops: [(Double, (Double, Double, Double))] = [
            (0.0, (1.00, 0.271, 0.227)),   // #FF453A red
            (0.40, (1.00, 0.624, 0.039)),  // #FF9F0A orange
            (0.75, (1.00, 0.839, 0.039)),  // #FFD60A yellow
            (1.0, (0.188, 0.820, 0.345)),  // #30D158 green
        ]
        let x = min(max(c.isFinite ? c : 0, 0), 1)
        for i in 1..<stops.count where x <= stops[i].0 {
            let (x0, a) = stops[i - 1], (x1, b) = stops[i]
            let t = (x - x0) / (x1 - x0)
            return Color(.sRGB, red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t,
                         blue: a.2 + (b.2 - a.2) * t, opacity: 1)
        }
        return statusGood
    }

    // Typography: the system font (SF Pro, Cyrillic included) everywhere.
    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular)
    }
    /// Tabular digits so numbers do not jump (SF Pro, not a code font).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
    /// Large light numerals for instrument readouts.
    static func numeral(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
