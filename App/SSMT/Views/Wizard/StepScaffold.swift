import SwiftUI

/// Common layout of every wizard step: one-line title, short subtitle, optional details behind an
/// info button, the content in the middle and one row of actions at the bottom.
struct StepScaffold<Content: View, Actions: View>: View {
    var title: String
    var subtitle: String = ""
    var info: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 36) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    if let info { InfoButton(text: info) }
                }
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            content
            actions
        }
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 32)
    }
}

/// "i" button showing longer explanations on demand instead of paragraphs on screen.
struct InfoButton: View {
    var text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 16)).foregroundStyle(Theme.textMuted)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $shown) {
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(width: 320)
                .background(Theme.panel)
        }
    }
}

/// Bottom action row: quiet secondary actions on the left, one primary button on the right.
struct ActionRow<Secondary: View>: View {
    var primaryTitle: String
    var primaryIcon: String
    var primaryEnabled = true
    var primaryAction: () -> Void
    @ViewBuilder var secondary: Secondary

    var body: some View {
        HStack(spacing: 18) {
            secondary
            Spacer()
            WizardPrimaryButton(title: primaryTitle, systemImage: primaryIcon, enabled: primaryEnabled, action: primaryAction)
                .frame(minWidth: 220)
                .fixedSize()
        }
    }
}

/// Text-only secondary action.
struct QuietButton: View {
    var title: String
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(Theme.label(13)).foregroundStyle(Theme.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Collapsed-by-default section for secondary information (graphs, filter lists, simulation).
struct Collapsible<Content: View>: View {
    var title: String
    @State var expanded = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title)
                    Spacer()
                }
                .font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded { content.transition(.opacity) }
        }
    }
}

/// Small rounded value chip ("+7.44 ms", "Invert").
struct ValueChip: View {
    var label: String
    var value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(Theme.numeral(22)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Theme.label(11)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panel))
    }
}

/// Status tile for the preparation checklist: icon, title, one value, one action.
struct StatusTile<Action: View>: View {
    var icon: String
    var title: String
    var value: String
    var state: Double?   // closeness 0…1, nil = not started
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 20, weight: .light))
                .foregroundStyle(state.map { Theme.closeness($0) } ?? Theme.textSecondary)
                .frame(height: 24)
            Text(value).font(.system(size: 17, weight: .medium)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
            action.padding(.top, 4)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panel))
    }
}

/// Thin step progress for the top bar: segments + "4 / 8 · TUNER".
struct ProgressStrip: View {
    @EnvironmentObject var loc: Localizer
    var step: SSMTCoreStep

    private let total = 9

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i < step.index ? Theme.textSecondary : (i == step.index ? Theme.accent : Theme.hairlineStrong))
                        .frame(width: 14, height: 3)
                }
            }
            Text("\(min(step.index, total - 1)) / \(total - 1) · " + loc.t("wizard.step.\(step.index)"))
                .font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

/// Lightweight wrapper so the strip does not depend on the wizard type directly.
struct SSMTCoreStep { var index: Int }
