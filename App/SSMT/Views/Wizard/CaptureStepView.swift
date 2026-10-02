import SSMTCore
import SwiftUI

/// Steps 1, 2, 3 and 5: set the groups as shown, wait for green, capture.
struct CaptureStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    private var step: WizardStep { model.wizard.step }

    var body: some View {
        StepScaffold(title: loc.t("capture.\(step.rawValue).title"), subtitle: loc.t("capture.\(step.rawValue).short"),
                     info: loc.t("capture.\(step.rawValue).text")) {
            VStack(spacing: 22) {
                groupPills
                SignalQualityGauge(band: step.qualityBand(crossover: model.wizard.configuration.crossover))
                    .frame(maxWidth: 480)
                if model.wizardCaptureRunning, let p = model.snapshot?.capture {
                    ProgressView(value: p.fraction).tint(Theme.closeness(p.fraction)).frame(maxWidth: 480)
                }
                if let acc = model.lastAcceptance { acceptanceNotice(acc) }
                if model.isSimulation { simulationHelpers }
            }
        } actions: {
            ActionRow(primaryTitle: model.wizardCaptureRunning ? loc.t("action.cancel") : (retry ? loc.t("capture.repeat") : loc.t("capture.start")),
                      primaryIcon: model.wizardCaptureRunning ? "xmark" : "record.circle",
                      primaryEnabled: model.isRunning,
                      primaryAction: { model.wizardCaptureRunning ? model.wizardCancelCapture() : model.wizardCapture() }) {
                QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.wizardBack() }
            }
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private var retry: Bool {
        if case .rejected = model.lastAcceptance { return true }
        return false
    }

    /// "SUBS ● ON   MAINS ○ MUTED" — what must be set on the processor.
    private var groupPills: some View {
        let g = step.requiredGroups ?? (sub: true, mains: true)
        return HStack(spacing: 12) {
            pill(loc.t("group.subs"), on: g.sub)
            pill(loc.t("group.mains"), on: g.mains)
        }
    }

    private func pill(_ name: String, on: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
            Text(name.uppercased()).tracking(1)
            Text(on ? loc.t("group.on") : loc.t("group.muted")).fontWeight(.bold)
        }
        .font(Theme.label(13))
        .foregroundStyle(on ? Theme.accent : Theme.textMuted)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Capsule().fill(on ? Theme.accent.opacity(0.1) : Theme.panel))
        .overlay(Capsule().stroke(on ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1))
    }

    @ViewBuilder private var simulationHelpers: some View {
        HStack(spacing: 16) {
            if let g = step.requiredGroups, model.simulationSubOn != g.sub || model.simulationMainOn != g.mains {
                QuietButton(title: loc.t("sim.doIt"), icon: "wand.and.stars") { model.simulateGroupsForStep() }
            }
            if step == .verification && !model.simulationSettingsApplied {
                QuietButton(title: loc.t("sim.applySettings"), icon: "wand.and.stars") { model.simulateApplyRecommendation() }
            }
        }
    }

    @ViewBuilder private func acceptanceNotice(_ a: CaptureAcceptance) -> some View {
        switch a {
        case .accepted:
            EmptyView()
        case .rejected(let reasons):
            Text(loc.t("capture.rejected") + " " + reasons.map { loc.t("reason.\($0.rawValue)") }.joined(separator: " "))
                .font(.system(size: 13)).foregroundStyle(Theme.statusError).multilineTextAlignment(.center)
        case .streamRestarted:
            Text(loc.t("capture.streamRestarted")).font(.system(size: 13)).foregroundStyle(Theme.statusError)
                .multilineTextAlignment(.center)
        }
    }
}
