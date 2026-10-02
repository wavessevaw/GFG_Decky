import SwiftUI

/// Common layout of every wizard step: "Step n of 5", a large title with a short description
/// (details behind an info button), the content and one action row at the bottom.
struct StepScaffold<Content: View, Actions: View>: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    var title: String
    var subtitle: String = ""
    var info: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(format: loc.t("stage.counter"), WizardStage.of(model.wizard.step).rawValue + 1, WizardStage.allCases.count))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title).font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    if let info { InfoButton(text: info) }
                }
                if !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
            actions
        }
        .frame(maxWidth: 1180, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, 24)
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

/// Bottom action row: quiet secondary actions on the left, the wide primary button filling the rest.
struct ActionRow<Secondary: View>: View {
    var primaryTitle: String
    var primaryIcon: String
    var primaryEnabled = true
    var primaryAction: () -> Void
    @ViewBuilder var secondary: Secondary

    var body: some View {
        HStack(spacing: 18) {
            secondary
            WizardPrimaryButton(title: primaryTitle, systemImage: primaryIcon, enabled: primaryEnabled, action: primaryAction)
                .frame(maxWidth: .infinity)
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
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded { content.transition(.opacity) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(GlassBackground(radius: 12))
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
        .background(GlassBackground())
    }
}
