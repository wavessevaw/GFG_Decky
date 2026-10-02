import SSMTCore
import SwiftUI

/// Automatic setup wizard: one instruction, one action per screen. No phase/coherence here.
struct WizardView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(spacing: 14) {
            StepIndicator(step: model.wizard.step)
            ScrollView {
                Group {
                    switch model.wizard.step {
                    case .preparation: PreparationStepView()
                    case .baseline, .subOnly, .mainsOnly: CaptureStepView()
                    case .verification:
                        if model.wizard.report == nil { CaptureStepView() } else { AlignmentCheckView() }
                    case .results: ResultsStepView()
                    case .eqPoints, .eqVerification: EQPointsView()
                    case .eqTuning: EQTuningView()
                    case .finished: FinishedStepView()
                    }
                }
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
    }
}

/// Numbered step strip with the active step glowing.
struct StepIndicator: View {
    @EnvironmentObject var loc: Localizer
    var step: WizardStep

    private let steps: [WizardStep] = [.preparation, .baseline, .subOnly, .mainsOnly, .results, .verification,
                                       .eqPoints, .eqTuning, .eqVerification]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { s in
                let active = s == step || (step == .finished && s == .eqVerification)
                let done = s < step
                HStack(spacing: 8) {
                    Text("\(s.rawValue)")
                        .font(Theme.mono(13, weight: .bold))
                        .foregroundStyle(active ? Color.black : (done ? Theme.accent : Theme.textMuted))
                        .frame(width: 24, height: 24)
                        .background(CutCornerShape(cut: 5).fill(active ? Theme.accent : Theme.panelRaised))
                        .overlay(CutCornerShape(cut: 5).stroke(done ? Theme.accent : Theme.hairlineStrong, lineWidth: 1))
                        .shadow(color: active ? Theme.accent.opacity(0.6) : .clear, radius: 6)
                    Text(loc.t("wizard.step.\(s.rawValue)").uppercased())
                        .font(Theme.label(10)).tracking(0.5)
                        .foregroundStyle(active ? Theme.textPrimary : Theme.textMuted)
                        .lineLimit(1)
                    if done { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if s != steps.last {
                    Rectangle().fill(done ? Theme.accent : Theme.hairline).frame(width: 8, height: 1)
                }
            }
        }
        .padding(10)
        .background(CutCornerShape().fill(Theme.panel))
        .overlay(CutCornerShape().stroke(Theme.hairline, lineWidth: 1))
    }
}

/// Large instruction block used on every step.
struct InstructionHeader: View {
    var marking: String
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(marking).font(Theme.mono(10)).foregroundStyle(Theme.accent).tracking(1.5)
            Text(title).font(Theme.heading(30)).foregroundStyle(Theme.textPrimary)
            Text(text).font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hazard-striped warning block.
struct HazardNotice: View {
    var text: String
    var color: Color = Theme.signalYellow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HazardStripes(color: color).frame(height: 6)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(color)
                Text(text).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
        }
        .background(color.opacity(0.06))
        .overlay(Rectangle().stroke(color.opacity(0.4), lineWidth: 1))
    }
}

/// Big primary action button for wizard screens.
struct WizardPrimaryButton: View {
    var title: String
    var systemImage: String
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(Theme.heading(20))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(SSMTButtonStyle(kind: .primary))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
