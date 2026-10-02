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
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text(title).font(Theme.heading(32)).foregroundStyle(Theme.textPrimary)
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
                .frame(width: 360)
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
                    Text(title.uppercased()).tracking(1.2)
                    Spacer()
                }
                .font(Theme.label(11)).foregroundStyle(Theme.textMuted)
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
        VStack(spacing: 3) {
            Text(label.uppercased()).font(Theme.label(9)).tracking(1.2).foregroundStyle(Theme.textMuted)
            Text(value).font(Theme.mono(18, weight: .bold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
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
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 22))
                .foregroundStyle(state.map { Theme.closeness($0) } ?? Theme.textMuted)
            Text(title.uppercased()).font(Theme.label(11)).tracking(1.4).foregroundStyle(Theme.textMuted)
            Text(value).font(Theme.mono(15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(height: 20)
            action
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke((state.map { Theme.closeness($0) } ?? Theme.hairline).opacity(state == nil ? 1 : 0.5), lineWidth: 1))
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
                        .fill(i < step.index ? Theme.accent : (i == step.index ? Theme.textPrimary : Theme.hairlineStrong))
                        .frame(width: 18, height: 3)
                }
            }
            Text("\(min(step.index, total - 1)) / \(total - 1) · " + loc.t("wizard.step.\(step.index)").uppercased())
                .font(Theme.label(11)).tracking(1.2).foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}

/// Lightweight wrapper so the strip does not depend on the wizard type directly.
struct SSMTCoreStep { var index: Int }
