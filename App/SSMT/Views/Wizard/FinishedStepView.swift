import SSMTCore
import SwiftUI

/// Step 5 after the verification capture: tuner gauges for the crossover result.
struct AlignmentCheckView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let r = model.wizard.report {
                InstructionHeader(marking: "STEP 5 · VERIFY", title: loc.t("verdict.\(r.verdict.rawValue)"),
                                  text: loc.t("verdict.\(r.verdict.rawValue).text"))
                HStack(alignment: .top, spacing: 12) {
                    let dip = r.after?.dipDepthDB
                    TunerGauge(title: loc.t("verify.dip"), value: dip.map { 1 - $0 / 9 }, mode: .oneSided,
                               tolerance: 1 - 3.0 / 9,
                               readout: dip.map { String(format: "%.1f dB", $0) } ?? "—",
                               instruction: r.before.map { String(format: loc.t("gauge.before"), $0.dipDepthDB) } ?? "",
                               large: model.stageMode,
                               scaleLabels: ["9", "6.8", "4.5", "2.3", "0"], unit: "dB",
                               telemetry: (String(format: "XO %.0f Hz", model.wizard.alignment?.crossover ?? 0), "TARGET <3"))
                    TunerGauge(title: loc.t("verify.predictionError"),
                               value: r.predictionErrorDB.isFinite ? 1 - r.predictionErrorDB / 4 : 0, mode: .oneSided,
                               tolerance: 1 - 2.0 / 4,
                               readout: r.predictionErrorDB.isFinite ? String(format: "±%.1f dB", r.predictionErrorDB) : "—",
                               instruction: loc.t(r.predictionErrorDB < 2 ? "gauge.matches" : "gauge.differs"),
                               large: model.stageMode,
                               scaleLabels: ["4", "3", "2", "1", "0"], unit: "dB",
                               telemetry: ("RMS Δ", "TARGET <2"))
                }
                if r.advice != .none {
                    HazardNotice(text: loc.t("advice.\(r.advice.rawValue)"),
                                 color: r.verdict == .checkSettings ? Theme.statusError : Theme.signalYellow)
                }
                Panel(title: loc.t("verify.curves"), marking: "A/B") {
                    ComparisonPlotView(curves: curves, band: model.wizard.alignment?.overlapBand).frame(height: 220)
                }
                HStack(spacing: 12) {
                    Button(loc.t("wizard.back")) { model.wizardBack() }.buttonStyle(SSMTButtonStyle())
                    Button(loc.t("verify.again")) { model.wizardBeginVerification() }.buttonStyle(SSMTButtonStyle())
                    WizardPrimaryButton(title: loc.t("wizard.next.eq"), systemImage: "slider.horizontal.3") {
                        model.wizardBeginEQ()
                    }
                }
            }
        }
    }

    private var curves: [ComparisonPlotView.Curve] {
        var c: [ComparisonPlotView.Curve] = []
        if let b = model.wizard.baseline?.transfer { c.append(.init(label: loc.t("curve.before"), transfer: b, color: Theme.textMuted)) }
        if let p = model.wizard.prediction { c.append(.init(label: loc.t("curve.prediction"), transfer: p, color: Theme.dataBlue, dashed: true)) }
        if let v = model.wizard.verification?.transfer {
            let dip = model.wizard.report?.after?.dipDepthDB ?? 9
            c.append(.init(label: loc.t("curve.after"), transfer: v, color: Theme.closeness(1 - max(0, dip - 3) / 6)))
        }
        return c
    }
}

/// Final summary: alignment settings, entered EQ, scores and export.
struct FinishedStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(marking: "DONE", title: loc.t("finished.title"), text: loc.t("finished.text"))
            if !model.wizard.actionCards.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(model.wizard.actionCards.enumerated()), id: \.offset) { _, card in
                        ActionCardView(card: card)
                    }
                }
            }
            EQResultGauges()
            Panel(title: loc.t("eq.bands"), marking: "EXPORT") {
                Text(model.exportText).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button(loc.t("export.copy")) { model.copyExportToClipboard() }.buttonStyle(SSMTButtonStyle())
                    Button(loc.t("export.text")) { model.saveExport(csv: false) }.buttonStyle(SSMTButtonStyle())
                    Button(loc.t("export.csv")) { model.saveExport(csv: true) }.buttonStyle(SSMTButtonStyle())
                }
                HStack {
                    Button(loc.t("report.pdf")) { model.exportReport(pdf: true, localizer: loc) }.buttonStyle(SSMTButtonStyle(kind: .primary))
                    Button(loc.t("report.png")) { model.exportReport(pdf: false, localizer: loc) }.buttonStyle(SSMTButtonStyle())
                    Button(loc.t("session.save")) { model.saveSession() }.buttonStyle(SSMTButtonStyle())
                }
            }
            HStack(spacing: 12) {
                Button(loc.t("wizard.back")) { model.wizardBack() }.buttonStyle(SSMTButtonStyle())
                Button(loc.t("wizard.restart")) { model.wizardRestart() }.buttonStyle(SSMTButtonStyle())
            }
        }
    }
}
