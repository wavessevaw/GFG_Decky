import SwiftUI

/// Graphite panel with hairline metal border, cut corners and a technical caption.
struct Panel<Content: View>: View {
    var title: String?
    var marking: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || marking != nil {
                HStack(spacing: 8) {
                    Rectangle().fill(Theme.accent).frame(width: 3, height: 12)
                    if let title {
                        Text(title.uppercased()).font(Theme.label(12)).tracking(1.2).foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    if let marking {
                        Text(marking).font(Theme.mono(9)).foregroundStyle(Theme.textMuted)
                    }
                }
            }
            content
        }
        .padding(12)
        .background(CutCornerShape().fill(Theme.panel))
        .overlay(
            CutCornerShape().stroke(
                LinearGradient(colors: [Theme.hairlineStrong, Theme.hairline], startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        )
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
        case .primary: fill = active ? Theme.accentHot : Theme.accent; fg = .black
        case .secondary: fill = active ? Theme.panelRaised.opacity(1) : Theme.panelRaised; fg = Theme.textPrimary
        case .danger: fill = Theme.statusError; fg = .white
        }
        return configuration.label
            .font(Theme.label(13))
            .tracking(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(CutCornerShape(cut: 7).fill(fill.opacity(configuration.isPressed ? 0.75 : 1)))
            .overlay(CutCornerShape(cut: 7).stroke(active ? Theme.accent : Theme.hairlineStrong, lineWidth: 1))
            .shadow(color: (kind == .primary || active) ? Theme.accent.opacity(0.45) : .clear, radius: active ? 8 : 4)
            .contentShape(Rectangle())
    }
}

enum StatusLevel { case good, warning, error, idle }

/// Status pill: icon + word + color (never color alone).
struct StatusBadge: View {
    var level: StatusLevel
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text.uppercased()).font(Theme.label(10)).tracking(0.8)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().stroke(color.opacity(0.5), lineWidth: 1))
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

/// Horizontal input meter (−60…0 dBFS) with peak marker and clip lamp.
struct MeterBar: View {
    var label: String
    var rmsDBFS: Double
    var peakDBFS: Double
    var clipped: Bool
    var clipText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label.uppercased()).font(Theme.label(10)).tracking(1).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: "%6.1f dBFS", rmsDBFS)).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 3) {
                    Image(systemName: clipped ? "exclamationmark.octagon.fill" : "circle")
                        .font(.system(size: 9, weight: .bold))
                    Text(clipText).font(Theme.label(9))
                }
                .foregroundStyle(clipped ? Theme.statusError : Theme.textMuted)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.black)
                    Rectangle()
                        .fill(LinearGradient(colors: [Theme.accent.opacity(0.7), Theme.accent, Theme.signalYellow],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * fraction(rmsDBFS))
                    Rectangle().fill(Theme.textPrimary).frame(width: 2).offset(x: w * fraction(peakDBFS) - 1)
                }
            }
            .frame(height: 8)
            .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private func fraction(_ db: Double) -> CGFloat {
        CGFloat(min(1, max(0, (db + 60) / 60)))
    }
}

/// Hairline divider with a small technical tick.
struct TechDivider: View {
    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(Theme.accent).frame(width: 6, height: 1)
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}
