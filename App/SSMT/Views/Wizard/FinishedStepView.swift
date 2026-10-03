import SSMTCore
import SwiftUI

/// Step 5 result: verdict, two instruments, advice only when something is wrong.
struct AlignmentCheckView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        if let r = model.wizard.report {
            StepScaffold(title: loc.t("verdict.\(r.verdict.rawValue)"), subtitle: loc.t("verdict.\(r.verdict.rawValue).text")) {
                VStack(spacing: 22) {
                    HStack(alignment: .top, spacing: 18) {
                        let dip = r.after?.dipDepthDB
                        TunerGauge(title: loc.t("verify.dip"), value: dip.map { 1 - $0 / 9 }, mode: .oneSided,
                                   tolerance: 1 - 3.0 / 9,
                                   readout: dip.map { String(format: "%.1f", $0) } ?? "—",
                                   instruction: r.before.map { String(format: loc.t("gauge.before"), $0.dipDepthDB) } ?? "",
                                   large: model.stageMode,
                                   scaleLabels: ["9", "", "4.5", "", "0"], unit: "dB")
                        TunerGauge(title: loc.t("verify.predictionError"),
                                   value: r.predictionErrorDB.isFinite ? 1 - r.predictionErrorDB / 4 : 0, mode: .oneSided,
                                   tolerance: 1 - 2.0 / 4,
                                   readout: r.predictionErrorDB.isFinite ? String(format: "%.1f", r.predictionErrorDB) : "—",
                                   instruction: loc.t(r.predictionErrorDB < 2 ? "gauge.matches" : "gauge.differs"),
                                   large: model.stageMode,
                                   scaleLabels: ["4", "", "2", "", "0"], unit: "dB")
                    }
                    if r.advice != .none {
                        Text(loc.t("advice.\(r.advice.rawValue)")).font(.system(size: 14))
                            .foregroundStyle(r.verdict == .checkSettings ? Theme.statusError : Theme.signalYellow)
                            .multilineTextAlignment(.center)
                    }
                    Collapsible(title: loc.t("verify.curves")) {
                        ComparisonPlotView(curves: curves, band: model.wizard.alignment?.overlapBand).frame(height: 220)
                    }
                }
            } actions: {
                ActionRow(primaryTitle: loc.t("wizard.next.eq"), primaryIcon: "slider.horizontal.3",
                          primaryAction: { model.wizardBeginEQ() }) {
                    QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.wizardBack() }
                    QuietButton(title: loc.t("verify.again"), icon: "arrow.counterclockwise") { model.wizardBeginVerification() }
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

/// Final summary: settings in one row, two result instruments, export.
struct FinishedStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        StepScaffold(title: loc.t("finished.title"), subtitle: loc.t("finished.subtitle")) {
            VStack(spacing: 24) {
                if !model.wizard.actionCards.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(model.wizard.actionCards.enumerated()), id: \.offset) { _, card in
                            ActionCardView(card: card)
                        }
                    }
                }
                EQResultGauges()
                HStack(spacing: 10) {
                    Button(loc.t("report.pdf.short")) { model.exportReport(pdf: true, localizer: loc) }.buttonStyle(SSMTButtonStyle(kind: .primary))
                    Button(loc.t("report.png.short")) { model.exportReport(pdf: false, localizer: loc) }.buttonStyle(SSMTButtonStyle())
                    Button(loc.t("export.text.short")) { model.saveExport(csv: false) }.buttonStyle(SSMTButtonStyle())
                    Button("CSV") { model.saveExport(csv: true) }.buttonStyle(SSMTButtonStyle())
                    Button(loc.t("session.save.short")) { model.saveSession() }.buttonStyle(SSMTButtonStyle())
                }
                Collapsible(title: loc.t("eq.bands")) {
                    Text(model.exportText).font(Theme.mono(11)).foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } actions: {
            HStack(spacing: 18) {
                QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.wizardBack() }
                Spacer()
                QuietButton(title: loc.t("wizard.restart"), icon: "arrow.counterclockwise") { model.wizardRestart() }
            }
        }
    }
}
