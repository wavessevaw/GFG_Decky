import SwiftUI

/// SSMT design tokens. Industrial black with signal orange / yellow accents.
/// The brand logo stays strictly white and is never tinted with these colors.
enum Theme {
    // Surfaces
    static let background = Color(hex: 0x0A0A0B)
    static let panel = Color(hex: 0x121316)
    static let panelRaised = Color(hex: 0x1A1C20)
    static let hairline = Color.white.opacity(0.12)
    static let hairlineStrong = Color.white.opacity(0.22)

    // Text
    static let textPrimary = Color(hex: 0xF2F2F2)
    static let textSecondary = Color(hex: 0xA3A6AD)
    static let textMuted = Color(hex: 0x6C7078)

    // Accents
    /// Primary accent: signal orange (actions, active state, main trace).
    static let accent = Color(hex: 0xFF6B1A)
    /// Orange-red for "live/armed" emphasis (noise on, capture running).
    static let accentHot = Color(hex: 0xFF4419)
    /// Secondary accent: signal yellow (secondary traces, highlights, hazard stripes with black).
    static let signalYellow = Color(hex: 0xFFC21A)
    /// Cold blue reserved for comparison data (prediction / reference traces) so it never reads as a status.
    static let dataBlue = Color(hex: 0x4CC9F0)

    // Status (always paired with an icon and a word — never color alone)
    static let statusGood = Color(hex: 0x4BE08A)
    static let statusWarning = Color(hex: 0xFFC21A)
    static let statusError = Color(hex: 0xFF2D3D)

    // Typography
    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .default).width(.condensed)
    }
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .default).width(.condensed)
    }
    /// Monospaced, tabular digits so numbers do not jump.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
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
