import SwiftUI

/// SSMT design tokens. Black surfaces with an emerald-green accent and system typography.
/// The accent marks actions and the live trace; the closeness scale (red → yellow → green) marks how
/// far a value is from its target, so "green" always means "good / go". The logo stays white.
enum Theme {
    // Surfaces
    static let background = Color(hex: 0x070908)
    static let panel = Color(hex: 0x121513)
    static let panelRaised = Color(hex: 0x1B1F1C)
    static let hairline = Color.white.opacity(0.08)
    static let hairlineStrong = Color.white.opacity(0.16)

    // Text
    static let textPrimary = Color(hex: 0xF3F6F4)
    static let textSecondary = Color(hex: 0x939C96)
    static let textMuted = Color(hex: 0x5F6862)

    // Accents
    /// Primary accent: emerald green (actions, current stage, main trace).
    static let accent = Color(hex: 0x2EE59D)
    /// Deeper green: end of accent gradients, "live" emphasis.
    static let accentHot = Color(hex: 0x10A86E)
    /// Secondary data colour: pale mint (coherence trace, group tags, secondary card marks).
    static let dataSecondary = Color(hex: 0xA7F3D0)
    /// Warning yellow (caution notes only).
    static let signalYellow = Color(hex: 0xFFD60A)
    /// Cool blue reserved for comparison data (prediction / reference traces) so it never reads as a status.
    static let dataBlue = Color(hex: 0x64D2FF)

    // Status (always paired with an icon or a word — never colour alone)
    static let statusGood = Color(hex: 0x34D399)
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
            (1.0, (0.204, 0.827, 0.600)),  // #34D399 green
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
