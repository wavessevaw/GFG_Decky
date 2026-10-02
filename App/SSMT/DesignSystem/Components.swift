import SwiftUI

/// Quiet card: soft surface, continuous corners, optional small title.
struct Panel<Content: View>: View {
    var title: String?
    var marking: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || marking != nil {
                HStack(spacing: 8) {
                    if let title {
                        Text(title).font(Theme.heading(13)).foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    if let marking {
                        Text(marking).font(Theme.mono(11)).foregroundStyle(Theme.textMuted)
                    }
                }
            }
            content
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panel))
    }
}

enum SSMTButtonKind { case primary, secondary, danger }

struct SSMTButtonStyle: ButtonStyle {
    var kind: SSMTButtonKind = .secondary
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        let fg: Color
        switch kind {
        case .primary: fill = Theme.accent; fg = .black
        case .secondary: fill = active ? Theme.accent.opacity(0.22) : Color.white.opacity(0.08)
            fg = active ? Theme.accent : Theme.textPrimary
        case .danger: fill = Theme.statusError; fg = .white
        }
        return configuration.label
            .font(.system(size: 13, weight: kind == .secondary ? .regular : .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(fill))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

enum StatusLevel { case good, warning, error, idle }

/// Status label: small icon + word + colour (never colour alone).
struct StatusBadge: View {
    var level: StatusLevel
    var text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private var icon: String {
        switch level {
        case .good: return "checkmark"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .idle: return "minus"
        }
    }

    private var color: Color {
        switch level {
        case .good: return Theme.statusGood
        case .warning: return Theme.statusWarning
        case .error: return Theme.statusError
        case .idle: return Theme.textMuted
        }
    }
}

/// Slim input meter (−60…0 dBFS) with a peak tick and a clip label.
struct MeterBar: View {
    var label: String
    var rmsDBFS: Double
    var peakDBFS: Double
    var clipped: Bool
    var clipText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: "%.1f dBFS", rmsDBFS)).font(Theme.mono(12)).foregroundStyle(Theme.textPrimary)
                if clipped {
                    Text(clipText).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.statusError)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(clipped ? Theme.statusError : Theme.textPrimary.opacity(0.85))
                        .frame(width: max(4, w * fraction(rmsDBFS)))
                    Capsule().fill(Theme.textPrimary).frame(width: 2).offset(x: w * fraction(peakDBFS) - 1)
                }
            }
            .frame(height: 4)
            .animation(.easeOut(duration: 0.12), value: rmsDBFS)
        }
    }

    private func fraction(_ db: Double) -> CGFloat {
        CGFloat(min(1, max(0, (db + 60) / 60)))
    }
}

/// Hairline divider.
struct TechDivider: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}
