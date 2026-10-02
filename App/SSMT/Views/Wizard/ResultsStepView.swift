import AppKit
import SSMTCore
import SwiftUI

/// Step 4 — sub ↔ satellites phase match: the recommendation (who gets how much delay, polarity,
/// level) in one large card, the phase of both groups in the crossover region now / after, and the
/// live needles to check what was entered.
struct ResultsStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        StepScaffold(title: loc.t("results.title"), subtitle: loc.t("results.subtitle"), info: loc.t("results.text")) {
            if let error = model.wizard.alignmentError {
                Text(loc.t("results.failed") + "\n" + error).font(.system(size: 13)).foregroundStyle(Theme.statusError)
            } else if let a = model.wizard.alignment {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        RecommendationCard(alignment: a)
                        if let hm = model.wizard.mainsResponse, let hs = model.wizard.subOnly?.transfer {
                            PhaseMatchView(mains: hm, sub: hs, alignment: a)
                        }
                    }
                    if a.isAmbiguous {
                        HazardNotice(text: loc.t("results.ambiguous.short"))
                    }
                    CardTitle(title: loc.t("match.tuner"))
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

/// "Do this on the processor": who gets the delay and how much, polarity and level.
struct RecommendationCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    var alignment: AlignmentResult

    var body: some View {
        let a = alignment
        let ms = abs(a.roundedDelay) * 1000
        let meters = abs(a.roundedDelay) * Acoustics.speedOfSound(celsius: model.wizard.configuration.temperatureCelsius)
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t(headlineKey)).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "+%.2f", ms)).font(Theme.numeral(58)).foregroundStyle(Theme.textPrimary)
                Text(loc.t("unit.ms")).font(.system(size: 18)).foregroundStyle(Theme.textSecondary)
            }
            Text(String(format: loc.t("match.meters"), meters)).font(Theme.mono(13)).foregroundStyle(Theme.textSecondary)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Label(loc.t(a.best.invertPolarity ? "match.polarity.invert" : "match.polarity.normal"),
                  systemImage: a.best.invertPolarity ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                .foregroundStyle(a.best.invertPolarity ? Theme.signalYellow : Theme.textPrimary)
            Label(String(format: loc.t("match.level"), a.subGainDB), systemImage: "speaker.wave.2")
                .foregroundStyle(Theme.textPrimary)
            Button { copy(ms: ms) } label: { Label(loc.t("match.copy"), systemImage: "doc.on.doc") }
                .buttonStyle(SSMTButtonStyle())
        }
        .font(.system(size: 14))
        .frame(width: 300, alignment: .leading)
        .glassCard(padding: 20, highlighted: true)
    }

    private var headlineKey: String {
        switch alignment.delayTarget {
        case .sub: return "match.headline.sub"
        case .mains: return "match.headline.mains"
        case .none: return "match.headline.none"
        }
    }

    private func copy(ms: Double) {
        let a = alignment
        let text = [loc.t(headlineKey) + String(format: ": +%.2f ", ms) + loc.t("unit.ms"),
                    loc.t(a.best.invertPolarity ? "match.polarity.invert" : "match.polarity.normal"),
                    String(format: loc.t("match.level"), a.subGainDB)].joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Phase of the subwoofers and the satellites around the crossover, now and after the recommended
/// delay / polarity: when the two curves lie on top of each other in the shaded band, they are glued.
struct PhaseMatchView: View {
    @EnvironmentObject var loc: Localizer
    var mains: TransferFunction
    var sub: TransferFunction
    var alignment: AlignmentResult
    @State private var after = true

    var body: some View {
        let curves = phaseCurves(after: after)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(title: loc.t("match.phase.title"))
                Picker("", selection: $after) {
                    Text(loc.t("match.phase.before")).tag(false)
                    Text(loc.t("match.phase.after")).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            }
            Canvas { ctx, size in draw(&ctx, size: size, curves: curves) }
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Color.white.opacity(0.03)))
            HStack(spacing: 16) {
                legend(Theme.dataSecondary, loc.t("match.phase.mains"))
                legend(Theme.accent, loc.t("match.phase.sub"))
                Spacer()
                if let gap = curves.gap {
                    Text(String(format: loc.t("match.phase.gap"), gap))
                        .font(Theme.mono(13))
                        .foregroundStyle(Theme.closeness(max(0, 1 - (gap - 15) / 75)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 18)
        .animation(.easeInOut(duration: 0.25), value: after)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 3)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Data

    struct Curves {
        var frequencies: [Double]
        var mains: [Double?]
        var sub: [Double?]
        var gap: Double?
    }

    private var range: ClosedRange<Double> {
        let fc = alignment.crossover
        return max(20, fc / 4)...min(2000, fc * 4)
    }

    private func phaseCurves(after: Bool) -> Curves {
        let m = Smoothing.smooth(mains, resolution: .oct6)
        let s = Smoothing.smooth(sub, resolution: .oct6)
        guard m.frequencies.count == s.frequencies.count else { return Curves(frequencies: [], mains: [], sub: [], gap: nil) }
        let tau = after ? alignment.roundedDelay : 0
        let sign = after && alignment.best.invertPolarity ? -1.0 : 1.0
        var fs: [Double] = [], pm: [Double?] = [], ps: [Double?] = [], gaps: [Double] = []
        for i in m.frequencies.indices where range.contains(m.frequencies[i]) {
            let f = m.frequencies[i]
            let hm = m.response[i]
            let hs = s.response[i] * Complex.polar(magnitude: sign, phase: -2 * .pi * f * tau)
            let okM = hm.magnitude.isFinite && hm.magnitude > 0
            let okS = hs.magnitude.isFinite && hs.magnitude > 0
            fs.append(f)
            pm.append(okM ? hm.phase * 180 / .pi : nil)
            ps.append(okS ? hs.phase * 180 / .pi : nil)
            if okM && okS && alignment.overlapBand.contains(f) {
                gaps.append(abs((hs / hm).phase) * 180 / .pi)
            }
        }
        return Curves(frequencies: fs, mains: pm, sub: ps, gap: gaps.isEmpty ? nil : gaps.reduce(0, +) / Double(gaps.count))
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, curves: Curves) {
        let plot = CGRect(x: 40, y: 8, width: size.width - 52, height: size.height - 28)
        let lo = log10(range.lowerBound), hi = log10(range.upperBound)
        func x(_ f: Double) -> CGFloat { plot.minX + CGFloat((log10(f) - lo) / (hi - lo)) * plot.width }
        func y(_ deg: Double) -> CGFloat { plot.midY - CGFloat(deg / 180) * plot.height / 2 }
        // Overlap band.
        let band = alignment.overlapBand
        let bx0 = x(max(band.lowerBound, range.lowerBound)), bx1 = x(min(band.upperBound, range.upperBound))
        ctx.fill(Path(CGRect(x: bx0, y: plot.minY, width: max(0, bx1 - bx0), height: plot.height)),
                 with: .color(Theme.accent.opacity(0.07)))
        // Grid.
        for deg in [-180.0, -90, 0, 90, 180] {
            var g = Path(); g.move(to: CGPoint(x: plot.minX, y: y(deg))); g.addLine(to: CGPoint(x: plot.maxX, y: y(deg)))
            ctx.stroke(g, with: .color(.white.opacity(deg == 0 ? 0.14 : 0.06)), lineWidth: 1)
            ctx.draw(Text(String(format: "%+.0f°", deg)).font(Theme.mono(10)).foregroundColor(Theme.textMuted),
                     at: CGPoint(x: plot.minX - 20, y: y(deg)))
        }
        for f in [20.0, 30, 50, 70, 100, 150, 200, 300, 500, 700, 1000, 2000] where range.contains(f) {
            var g = Path(); g.move(to: CGPoint(x: x(f), y: plot.minY)); g.addLine(to: CGPoint(x: x(f), y: plot.maxY))
            ctx.stroke(g, with: .color(.white.opacity(0.05)), lineWidth: 1)
            ctx.draw(Text(FrequencyAxis.label(f)).font(Theme.mono(10)).foregroundColor(Theme.textMuted),
                     at: CGPoint(x: x(f), y: plot.maxY + 10))
        }
        let fc = alignment.crossover
        var xo = Path(); xo.move(to: CGPoint(x: x(fc), y: plot.minY)); xo.addLine(to: CGPoint(x: x(fc), y: plot.maxY))
        ctx.stroke(xo, with: .color(Theme.accent.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        // Curves; wrapped phase, broken at the ±180° jumps.
        func trace(_ values: [Double?], color: Color) {
            var p = Path()
            var last: Double?
            for (i, v) in values.enumerated() {
                guard let v else { last = nil; continue }
                let pt = CGPoint(x: x(curves.frequencies[i]), y: y(v))
                if let l = last, abs(v - l) < 180 { p.addLine(to: pt) } else { p.move(to: pt) }
                last = v
            }
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        trace(curves.mains, color: Theme.dataSecondary)
        trace(curves.sub, color: Theme.accent)
    }
}
