import SSMTCore
import SwiftUI

/// Step 4: action cards (delay, polarity, level), confidence and predicted sum.
struct ResultsStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(marking: "STEP 4 · TUNE", title: loc.t("results.title"), text: loc.t("results.text"))

            if let error = model.wizard.alignmentError {
                HazardNotice(text: loc.t("results.failed") + "\n" + error, color: Theme.statusError)
                Button(loc.t("wizard.back")) { model.wizardBack() }.buttonStyle(SSMTButtonStyle())
            } else if let a = model.wizard.alignment {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(model.wizard.actionCards.enumerated()), id: \.offset) { _, card in
                        ActionCardView(card: card)
                    }
                }
                if a.isAmbiguous { ambiguity(a) }
                if model.wizard.configuration.fastMode {
                    HazardNotice(text: loc.t("results.fastMode"))
                }

                Panel(title: loc.t("tuner.title"), marking: "LIVE") {
                    TunerPanel()
                }
                if model.isSimulation { VirtualProcessorPanel() }

                DisclosureGroup(loc.t("results.prediction")) {
                    ComparisonPlotView(curves: predictionCurves, band: a.overlapBand)
                        .frame(height: 220)
                }
                .font(Theme.label(12))

                HStack(spacing: 12) {
                    Button(loc.t("wizard.back")) { model.wizardBack() }.buttonStyle(SSMTButtonStyle())
                    if model.tunerNeedsMainsStage && model.tunerStage == .adjustSub {
                        WizardPrimaryButton(title: loc.t("tuner.next.mains"), systemImage: "arrow.right.circle.fill",
                                            enabled: subStageDone) {
                            model.tunerAdvanceToMains()
                        }
                    } else {
                        WizardPrimaryButton(title: loc.t(allInTune ? "tuner.verify.ready" : "results.applied"),
                                            systemImage: "checkmark.seal.fill") {
                            model.wizardBeginVerification()
                        }
                    }
                }
            }
        }
        .onAppear { model.startTuner() }
        .onDisappear { model.stopTuner() }
    }

    private var allInTune: Bool { model.tunerReading?.allInTune ?? false }
    private var subStageDone: Bool {
        guard let r = model.tunerReading else { return false }
        return !r.polarityWrong && r.levelInTune
    }

    private var predictionCurves: [ComparisonPlotView.Curve] {
        var c: [ComparisonPlotView.Curve] = []
        if let b = model.wizard.baseline?.transfer {
            c.append(.init(label: loc.t("curve.before"), transfer: b, color: Theme.textMuted))
        }
        if let p = model.wizard.prediction {
            c.append(.init(label: loc.t("curve.prediction"), transfer: p, color: Theme.dataBlue, dashed: true))
        }
        return c
    }

    private func ambiguity(_ a: AlignmentResult) -> some View {
        let alts = a.alternatives.map { alt in
            String(format: "%+.2f ms · %@", alt.delay * 1000,
                   loc.t(alt.invertPolarity ? "polarity.invert" : "polarity.normal"))
        }.joined(separator: "; ")
        return HazardNotice(text: loc.t("results.ambiguous") + " " + loc.t("results.alternatives") + " " + alts)
    }
}

/// One large "do this on the processor" card.
struct ActionCardView: View {
    @EnvironmentObject var loc: Localizer
    @EnvironmentObject var model: AppModel
    var card: ActionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.accent)
                Text(title.uppercased()).font(Theme.label(12)).tracking(1.2).foregroundStyle(Theme.textSecondary)
            }
            Text(value)
                .font(Theme.mono(model.stageMode ? 44 : 32, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(CutCornerShape(cut: 14).fill(Theme.panel))
        .overlay(CutCornerShape(cut: 14).stroke(Theme.accent.opacity(0.55), lineWidth: 1))
        .shadow(color: Theme.accent.opacity(0.18), radius: 10)
    }

    private var icon: String {
        switch card {
        case .delaySub, .delayMains, .noDelayChange: return "timer"
        case .polarity: return "arrow.up.arrow.down"
        case .subLevel: return "slider.vertical.3"
        }
    }

    private var title: String {
        switch card {
        case .delaySub: return loc.t("card.delay.sub")
        case .delayMains: return loc.t("card.delay.mains")
        case .noDelayChange: return loc.t("card.delay.sub")
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

    private var detail: String {
        switch card {
        case .delaySub(_, let m): return loc.t("card.delay.sub.detail", m)
        case .delayMains(_, let m): return loc.t("card.delay.mains.detail", m)
        case .noDelayChange: return loc.t("card.delay.none.detail")
        case .polarity(let invert): return loc.t(invert ? "card.polarity.invert.detail" : "card.polarity.normal.detail")
        case .subLevel: return loc.t("card.level.detail")
        }
    }
}
