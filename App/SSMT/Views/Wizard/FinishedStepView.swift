import SSMTCore
import SwiftUI

/// Step 5 result: verdict, before/after metrics and concrete advice.
struct FinishedStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let r = model.wizard.report {
                InstructionHeader(marking: "STEP 5 · VERIFY", title: loc.t("verdict.\(r.verdict.rawValue)"),
                                  text: loc.t("verdict.\(r.verdict.rawValue).text"))
                HStack(spacing: 12) {
                    metric(loc.t("verify.dip"), before: r.before?.dipDepthDB, after: r.after?.dipDepthDB, lowerIsBetter: true)
                    metric(loc.t("verify.sum"), before: r.before?.summationGainDB, after: r.after?.summationGainDB, lowerIsBetter: false)
                    metricSingle(loc.t("verify.predictionError"), value: r.predictionErrorDB)
                }
                if r.advice != .none {
                    HazardNotice(text: loc.t("advice.\(r.advice.rawValue)"),
                                 color: r.verdict == .checkSettings ? Theme.statusError : Theme.signalYellow)
                }
                Panel(title: loc.t("verify.curves"), marking: "A/B") {
                    ComparisonPlotView(curves: curves, band: model.wizard.alignment?.overlapBand).frame(height: 240)
                }
            } else {
                InstructionHeader(marking: "DONE", title: loc.t("finished.noSub"), text: "")
            }
            HStack(spacing: 12) {
                Button(loc.t("verify.again")) { model.wizardBeginVerification() }.buttonStyle(SSMTButtonStyle())
                Button(loc.t("wizard.restart")) { model.wizardRestart() }.buttonStyle(SSMTButtonStyle())
                Spacer()
                Text(loc.t("wizard.next.eq")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var curves: [ComparisonPlotView.Curve] {
        var c: [ComparisonPlotView.Curve] = []
        if let b = model.wizard.baseline?.transfer { c.append(.init(label: loc.t("curve.before"), transfer: b, color: Theme.textMuted)) }
        if let p = model.wizard.prediction { c.append(.init(label: loc.t("curve.prediction"), transfer: p, color: Theme.dataBlue, dashed: true)) }
        if let v = model.wizard.verification?.transfer { c.append(.init(label: loc.t("curve.after"), transfer: v, color: Theme.accent)) }
        return c
    }

    private func metric(_ title: String, before: Double?, after: Double?, lowerIsBetter: Bool) -> some View {
        let improved: Bool? = {
            guard let b = before, let a = after else { return nil }
            return lowerIsBetter ? a < b : a > b
        }()
        return VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Theme.label(11)).tracking(1).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(before.map { String(format: "%.1f", $0) } ?? "—").font(Theme.mono(18)).foregroundStyle(Theme.textMuted)
                Image(systemName: "arrow.right").foregroundStyle(Theme.textMuted)
                Text(after.map { String(format: "%.1f dB", $0) } ?? "—").font(Theme.mono(26, weight: .bold))
                    .foregroundStyle(improved == false ? Theme.statusWarning : Theme.textPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CutCornerShape().fill(Theme.panel))
        .overlay(CutCornerShape().stroke(Theme.hairline, lineWidth: 1))
    }

    private func metricSingle(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Theme.label(11)).tracking(1).foregroundStyle(Theme.textSecondary)
            Text(value.isFinite ? String(format: "%.1f dB", value) : "—").font(Theme.mono(26, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CutCornerShape().fill(Theme.panel))
        .overlay(CutCornerShape().stroke(Theme.hairline, lineWidth: 1))
    }
}
