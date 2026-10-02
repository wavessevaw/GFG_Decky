import SSMTCore
import SwiftUI

/// Automatic setup wizard: one instruction, one action per screen.
struct WizardView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    @Binding var showSettings: Bool

    var body: some View {
        ScrollView {
            Group {
                switch model.wizard.step {
                case .preparation: PreparationStepView(showSettings: $showSettings)
                case .baseline, .subOnly, .mainsOnly: CaptureStepView()
                case .verification:
                    if model.wizard.report == nil { CaptureStepView() } else { AlignmentCheckView() }
                case .results: ResultsStepView()
                case .eqPoints, .eqVerification: EQPointsView()
                case .eqTuning: EQTuningView()
                case .finished: FinishedStepView()
                }
            }
            .padding(.horizontal, 32)
        }
    }
}

/// Large instruction block used on every step.
struct InstructionHeader: View {
    var marking: String
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(marking).font(Theme.mono(10)).foregroundStyle(Theme.accent)
            Text(title).font(Theme.heading(30)).foregroundStyle(Theme.textPrimary)
            Text(text).font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Soft tinted warning note.
struct HazardNotice: View {
    var text: String
    var color: Color = Theme.signalYellow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(color)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(color.opacity(0.10)))
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
                .font(Theme.heading(17))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(SSMTButtonStyle(kind: .primary))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
