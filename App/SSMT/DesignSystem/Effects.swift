import SwiftUI

/// Rendering budget. Older Macs (Intel, integrated graphics) get "reduced effects": no large blurred
/// shadows or glows and short animations, which keeps redraws cheap. The glass look stays.
enum GraphicsQuality {
    static let defaultsKey = "ssmt.reducedEffects"

    /// Automatic choice: reduced on Intel Macs and on machines with fewer than 6 cores.
    static var automaticReduced: Bool {
        #if arch(x86_64)
        return true
        #else
        return ProcessInfo.processInfo.activeProcessorCount < 6
        #endif
    }

    /// User override if set, otherwise automatic.
    static var initialReduced: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? automaticReduced
    }
}

private struct ReducedEffectsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var reducedEffects: Bool {
        get { self[ReducedEffectsKey.self] }
        set { self[ReducedEffectsKey.self] = newValue }
    }
}

extension View {
    /// A shadow that is skipped in reduced-effects mode.
    func softShadow(_ color: Color, radius: CGFloat, y: CGFloat = 0) -> some View {
        modifier(SoftShadow(color: color, radius: radius, y: y))
    }
}

private struct SoftShadow: ViewModifier {
    @Environment(\.reducedEffects) private var reduced
    var color: Color
    var radius: CGFloat
    var y: CGFloat

    func body(content: Content) -> some View {
        if reduced { content } else { content.shadow(color: color, radius: radius, y: y) }
    }
}

extension Animation {
    /// Needle motion: a soft spring normally, a short ease in reduced-effects mode
    /// (fewer animation frames per live update).
    static func needle(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.8)
    }
}
