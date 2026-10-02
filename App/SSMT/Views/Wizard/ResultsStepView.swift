import SSMTCore
import SwiftUI

/// Step 4: the target in one row of chips, then the live tuner (polarity lamp + two needles).
struct ResultsStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        StepScaffold(title: loc.t("results.title"), subtitle: loc.t("results.subtitle"), info: loc.t("results.text")) {
            if let error = model.wizard.alignmentError {
                Text(loc.t("results.failed") + "\n" + error).font(.system(size: 13)).foregroundStyle(Theme.statusError)
                    .multilineTextAlignment(.center)
            } else if let a = model.wizard.alignment {
                VStack(spacing: 24) {
                    HStack(spacing: 10) {
                        ForEach(Array(model.wizard.actionCards.enumerated()), id: \.offset) { _, card in
                            ValueChip(label: chipLabel(card), value: chipValue(card))
                        }
                    }
                    if a.isAmbiguous {
                        Text(loc.t("results.ambiguous.short")).font(.system(size: 13)).foregroundStyle(Theme.signalYellow)
                    }
                    if let maxMs = model.wizard.configuration.processor.maxDelayMs,
                       !model.wizard.configuration.processor.canEnter(delaySeconds: a.roundedDelay) {
                        HazardNotice(text: String(format: loc.t("processor.delayTooLong"), abs(a.roundedDelay) * 1000, maxMs))
                    }
                    TunerPanel()
                    VStack(spacing: 12) {
                        if model.isSimulation {
                            Collapsible(title: loc.t("vproc.title")) { VirtualProcessorPanel() }
                        }
                        Collapsible(title: loc.t("results.prediction")) {
                            ComparisonPlotView(curves: predictionCurves, band: a.overlapBand).frame(height: 220)
                        }
                    }
                }
            }
        } actions: {
            TunerActions()
        }
        .onAppear { model.startTuner() }
        .onDisappear { model.stopTuner() }
    }


    private func chipLabel(_ c: ActionCard) -> String {
        switch c {
        case .delaySub, .noDelayChange: return loc.t("card.delay.sub")
        case .delayMains: return loc.t("card.delay.mains")
        case .polarity: return loc.t("card.polarity")
        case .subLevel: return loc.t("card.level")
        }
    }

    private func chipValue(_ c: ActionCard) -> String {
        switch c {
        case .delaySub(let s, _), .delayMains(let s, _): return String(format: "+%.2f ms", s * 1000)
        case .noDelayChange: return "0.00 ms"
        case .polarity(let invert): return loc.t(invert ? "polarity.invert" : "polarity.normal")
        case .subLevel(let db): return String(format: "%+.1f dB", db)
        }
    }

    private var predictionCurves: [ComparisonPlotView.Curve] {
        var c: [ComparisonPlotView.Curve] = []
        if let b = model.wizard.baseline?.transfer { c.append(.init(label: loc.t("curve.before"), transfer: b, color: Theme.textMuted)) }
        if let p = model.wizard.prediction { c.append(.init(label: loc.t("curve.prediction"), transfer: p, color: Theme.dataBlue, dashed: true)) }
        return c
    }
}

/// Kept for the final summary screen: one large "do this on the processor" card.
struct ActionCardView: View {
    @EnvironmentObject var loc: Localizer
    @EnvironmentObject var model: AppModel
    var card: ActionCard

    var body: some View {
        ValueChip(label: label, value: value)
    }

    private var label: String {
        switch card {
        case .delaySub, .noDelayChange: return loc.t("card.delay.sub")
        case .delayMains: return loc.t("card.delay.mains")
        case .polarity: return loc.t("card.polarity")
        case .subLevel: return loc.t("card.level")
        }
    }

    private var value: String {
        switch card {
        case .delaySub(let s, _), .delayMains(let s, _): return String(format: "+%.2f ms", s * 1000)
        case .noDelayChange: return "0.00 ms"
        case .polarity(let invert): return loc.t(invert ? "polarity.invert" : "polarity.normal")
        case .subLevel(let db): return String(format: "%+.1f dB", db)
        }
    }
}

/// Tuner step actions; their titles follow the live reading, so they observe it on their own.
struct TunerActions: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tuning: TuningData
    @EnvironmentObject var loc: Localizer

    var body: some View {
        if model.tunerNeedsMainsStage && model.tunerStage == .adjustSub {
            ActionRow(primaryTitle: loc.t("tuner.next.mains"), primaryIcon: "arrow.right",
                      primaryEnabled: subStageDone, primaryAction: { model.tunerAdvanceToMains() }) {
                QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.wizardBack() }
            }
        } else {
            ActionRow(primaryTitle: loc.t(allInTune ? "tuner.verify.ready" : "results.applied"),
                      primaryIcon: "checkmark", primaryAction: { model.wizardBeginVerification() }) {
                QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.wizardBack() }
            }
        }
    }

    private var allInTune: Bool { tuning.alignment?.allInTune ?? false }
    private var subStageDone: Bool {
        guard let r = tuning.alignment else { return false }
        return !r.polarityWrong && r.levelInTune
    }
}
