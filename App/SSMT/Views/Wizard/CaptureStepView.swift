import SSMTCore
import SwiftUI

/// Steps 1, 2, 3 and 5: "set up the groups like this, then capture".
struct CaptureStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    private var step: WizardStep { model.wizard.step }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(marking: "STEP \(step.rawValue) · CAPTURE",
                              title: loc.t("capture.\(step.rawValue).title"),
                              text: loc.t("capture.\(step.rawValue).text"))
            groupsDiagram
            if model.isSimulation, let g = step.requiredGroups,
               model.simulationSubOn != g.sub || model.simulationMainOn != g.mains {
                Button(loc.t("sim.doIt")) { model.simulateGroupsForStep() }.buttonStyle(SSMTButtonStyle())
            }
            if step == .verification && model.isSimulation && !model.simulationSettingsApplied {
                Button(loc.t("sim.applySettings")) { model.simulateApplyRecommendation() }.buttonStyle(SSMTButtonStyle())
            }

            progressPanel

            if let acc = model.lastAcceptance { acceptanceNotice(acc) }

            HStack(spacing: 12) {
                Button(loc.t("wizard.back")) { model.wizardBack() }.buttonStyle(SSMTButtonStyle())
                if model.wizardCaptureRunning {
                    Button(loc.t("action.cancel")) { model.wizardCancelCapture() }.buttonStyle(SSMTButtonStyle())
                } else {
                    WizardPrimaryButton(title: retry ? loc.t("capture.repeat") : loc.t("capture.start"),
                                        systemImage: "record.circle", enabled: model.isRunning) {
                        model.wizardCapture()
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
    }

    private var retry: Bool {
        if case .rejected = model.lastAcceptance { return true }
        return false
    }

    /// Two big tiles: which group must be ON / MUTED.
    private var groupsDiagram: some View {
        let g = step.requiredGroups ?? (sub: true, mains: true)
        return HStack(spacing: 12) {
            groupTile(loc.t("group.subs"), on: g.sub, icon: "speaker.wave.1.fill")
            groupTile(loc.t("group.mains"), on: g.mains, icon: "hifispeaker.2.fill")
        }
    }

    private func groupTile(_ name: String, on: Bool, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: on ? icon : "speaker.slash.fill").font(.system(size: 28))
                .foregroundStyle(on ? Theme.accent : Theme.textMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.uppercased()).font(Theme.label(13)).tracking(1).foregroundStyle(Theme.textPrimary)
                Text(on ? loc.t("group.on") : loc.t("group.muted"))
                    .font(Theme.heading(20)).foregroundStyle(on ? Theme.accent : Theme.textMuted)
            }
            Spacer()
        }
        .padding(14)
        .background(CutCornerShape().fill(on ? Theme.accent.opacity(0.08) : Theme.panel))
        .overlay(CutCornerShape().stroke(on ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: 1))
    }

    private var progressPanel: some View {
        let p = model.snapshot?.capture
        return HStack(alignment: .top, spacing: 12) {
            SignalQualityGauge(band: step.qualityBand(crossover: model.wizard.configuration.crossover))
            Panel(title: loc.t("capture.progress"), marking: "REC") {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black)
                            Rectangle().fill(Theme.closeness(p?.fraction ?? 0))
                                .frame(width: geo.size.width * CGFloat(p?.fraction ?? 0))
                                .shadow(color: Theme.closeness(p?.fraction ?? 0).opacity(0.6), radius: 6)
                        }
                    }
                    .frame(height: 16)
                    .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1))
                    Text(p.map { String(format: "%.0f / %.0f s", $0.elapsed, $0.duration) }
                         ?? String(format: "%.0f s", model.wizard.configuration.captureSeconds))
                        .font(Theme.mono(18, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(loc.t(model.wizardCaptureRunning ? "capture.running" : "capture.ready"))
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 320)
        }
    }

    @ViewBuilder private func acceptanceNotice(_ a: CaptureAcceptance) -> some View {
        switch a {
        case .accepted(let q):
            StatusBadge(level: q == .good ? .good : .warning, text: loc.t(q == .good ? "capture.accepted" : "capture.acceptedWeak"))
        case .rejected(let reasons):
            HazardNotice(text: loc.t("capture.rejected") + " " + reasons.map { loc.t("reason.\($0.rawValue)") }.joined(separator: " "),
                         color: Theme.statusError)
        case .streamRestarted:
            HazardNotice(text: loc.t("capture.streamRestarted"), color: Theme.statusError)
        }
    }
}
