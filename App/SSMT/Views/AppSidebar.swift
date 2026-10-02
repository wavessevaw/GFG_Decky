import SSMTCore
import SwiftUI

/// The five stages shown in the sidebar; each covers one or more wizard steps.
enum WizardStage: Int, CaseIterable {
    case prepare, capture, align, eq, done

    static func of(_ step: WizardStep) -> WizardStage {
        switch step {
        case .preparation: return .prepare
        case .baseline, .subOnly, .mainsOnly: return .capture
        case .results, .verification: return .align
        case .eqPoints, .eqTuning, .eqVerification: return .eq
        case .finished: return .done
        }
    }

    var icon: String {
        switch self {
        case .prepare: return "checklist"
        case .capture: return "waveform"
        case .align: return "dial.medium"
        case .eq: return "slider.vertical.3"
        case .done: return "doc.text"
        }
    }
}

/// Glass sidebar: brand, the wizard stages (or the expert setup panels) and a few utility items.
struct AppSidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    var brandNamespace: Namespace.ID? = nil
    var showBrand = true
    @State private var showAbout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 22)
            if model.appMode == .wizard {
                stages
                Spacer(minLength: 16)
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 18)
                utilities.padding(.vertical, 10)
            } else {
                SetupSidebar(expert: true)
            }
        }
        .frame(width: 272)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlassBackground(radius: 22))
    }

    private var brand: some View {
        Button { showAbout = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    if showBrand {
                        BrandMark(variant: .compact, height: 40).modifier(MatchedBrand(namespace: brandNamespace))
                    }
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SSMT").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("SoundSolution Multi Tool").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(loc.t("about.title"))
        .popover(isPresented: $showAbout) { AboutView() }
    }

    private var stages: some View {
        let current = WizardStage.of(model.wizard.step)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(WizardStage.allCases, id: \.rawValue) { stage in
                StageRow(number: stage.rawValue + 1,
                         title: loc.t("stage.\(stage.rawValue).title"),
                         subtitle: loc.t("stage.\(stage.rawValue).subtitle"),
                         state: stage == current ? .current : (stage.rawValue < current.rawValue ? .done : .upcoming),
                         isLast: stage == .done)
            }
        }
        .padding(.horizontal, 10)
    }

    private var utilities: some View {
        VStack(alignment: .leading, spacing: 2) {
            UtilityRow(icon: "slider.horizontal.3", title: loc.t("settings.title")) { model.showSettings = true }
            UtilityRow(icon: "square.and.arrow.down", title: loc.t("session.save.short")) { model.saveSession() }
            UtilityRow(icon: "doc.richtext", title: loc.t("report.pdf.short")) { model.exportReport(pdf: true, localizer: loc) }
        }
        .padding(.horizontal, 10)
    }
}

/// One stage in the vertical stepper: numbered circle on a connecting line, title and subtitle.
struct StageRow: View {
    enum Phase { case done, current, upcoming }
    var number: Int
    var title: String
    var subtitle: String
    var state: Phase
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    switch state {
                    case .current:
                        Circle().fill(LinearGradient(colors: [Theme.accent, Theme.accentHot], startPoint: .top, endPoint: .bottom))
                        Text("\(number)").font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                    case .done:
                        Circle().fill(Color.white.opacity(0.10))
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.statusGood)
                    case .upcoming:
                        Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5)
                        Text("\(number)").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 32, height: 32)
                if !isLast {
                    Rectangle().fill(Color.white.opacity(state == .done ? 0.25 : 0.12)).frame(width: 1.5, height: 26)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: state == .current ? .semibold : .regular))
                    .foregroundStyle(state == .upcoming ? Theme.textSecondary : Theme.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .background(alignment: .top) {
            if state == .current {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(0.35)))
                    .frame(height: 46)
            }
        }
    }
}

struct UtilityRow: View {
    var icon: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.textSecondary).frame(width: 22)
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
