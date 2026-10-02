import SSMTCore
import SwiftUI

/// Polarity indicator: green "correct" / pulsing red "switch".
struct PolarityLamp: View {
    @EnvironmentObject var loc: Localizer
    var wrong: Bool?
    var large = false
    @State private var blink = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: wrong == true ? "arrow.triangle.2.circlepath" : (wrong == false ? "checkmark.circle.fill" : "circle.dashed"))
                .font(.system(size: large ? 26 : 22, weight: .regular))
                .foregroundStyle(color)
                .opacity(wrong == true && blink ? 0.4 : 1)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("card.polarity")).font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
                Text(text).font(.system(size: large ? 18 : 15, weight: .medium)).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Text(wrong == true ? "180°" : (wrong == false ? "0°" : "—"))
                .font(Theme.numeral(large ? 34 : 28)).foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panel))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { blink = true }
        }
    }

    private var color: Color {
        switch wrong {
        case .some(true): return Theme.closeness(0)
        case .some(false): return Theme.statusGood
        case .none: return Theme.textMuted
        }
    }

    private var text: String {
        switch wrong {
        case .some(true): return loc.t("tuner.polarity.switch")
        case .some(false): return loc.t("tuner.polarity.ok")
        case .none: return loc.t("tuner.waiting")
        }
    }
}

/// Live tuning block: polarity lamp and the delay / level instruments. No explanatory text.
struct TunerPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        let r = model.tunerReading
        let reliable = r?.isReliable ?? false
        let large = model.stageMode
        let mainsStage = model.tunerStage == .adjustMainsDelay
        let showDelay = mainsStage || !model.tunerNeedsMainsStage
        let fc = model.wizard.alignment?.crossover ?? 100

        VStack(spacing: 18) {
            if !mainsStage {
                PolarityLamp(wrong: r.map(\.polarityWrong), large: large)
                    .frame(maxWidth: 560)
            }
            HStack(alignment: .top, spacing: 18) {
                if showDelay {
                    TunerGauge(
                        title: loc.t(mainsStage ? "card.delay.mains" : "card.delay.sub"),
                        value: r.map { $0.delayPhaseError / 90 },
                        tolerance: 10.0 / 90,
                        readout: r.map { String(format: "%+.2f", $0.delayError * 1000) } ?? "—",
                        instruction: delayInstruction(r, mainsStage: mainsStage),
                        reliable: reliable, large: large,
                        scaleLabels: scale(fullScale: 250 / fc, format: "%+.1f"),
                        unit: loc.t("unit.ms"))
                }
                if !mainsStage {
                    TunerGauge(
                        title: loc.t("card.level"),
                        value: r.map { $0.levelError / 6 },
                        tolerance: 0.5 / 6,
                        readout: r.map { String(format: "%+.1f", $0.levelError) } ?? "—",
                        instruction: levelInstruction(r),
                        reliable: reliable, large: large,
                        scaleLabels: scale(fullScale: 6, format: "%+.0f"),
                        unit: "dB")
                }
            }
        }
    }

    private func scale(fullScale: Double, format: String) -> [String] {
        [-1, -0.5, 0, 0.5, 1].map { $0 == 0 ? "0" : String(format: format, $0 * fullScale) }
    }

    private func delayInstruction(_ r: AlignmentTuner.Reading?, mainsStage: Bool) -> String {
        guard let r else { return loc.t("tuner.waiting") }
        if !r.isReliable { return loc.t("tuner.unreliable") }
        if r.delayInTune { return loc.t("tuner.inTune") }
        let more = r.delayError > 0
        return loc.t(mainsStage ? (more ? "tuner.mains.more" : "tuner.mains.less") : (more ? "tuner.sub.more" : "tuner.sub.less"))
    }

    private func levelInstruction(_ r: AlignmentTuner.Reading?) -> String {
        guard let r else { return loc.t("tuner.waiting") }
        if r.levelInTune { return loc.t("tuner.inTune") }
        return loc.t(r.levelError > 0 ? "tuner.level.up" : "tuner.level.down")
    }
}

/// Simulation only: knobs of the virtual loudspeaker processor.
struct VirtualProcessorPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            knob(loc.t("vproc.subDelay"), value: $model.simProcessor.subDelayMs, range: 0...20, step: 0.01, format: "%.2f ms")
            knob(loc.t("vproc.mainsDelay"), value: $model.simProcessor.mainsDelayMs, range: 0...20, step: 0.01, format: "%.2f ms")
            knob(loc.t("vproc.subLevel"), value: $model.simProcessor.subGainDB, range: -12...6, step: 0.5, format: "%+.1f dB")
            Toggle(loc.t("vproc.subPolarity"), isOn: $model.simProcessor.subPolarityInverted)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.panel))
    }

    private func knob(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                      format: String) -> some View {
        HStack {
            Text(title).font(Theme.label(12)).foregroundStyle(Theme.textSecondary).frame(width: 150, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue },
                                  set: { value.wrappedValue = ($0 / step).rounded() * step }), in: range)
                .tint(Theme.accent)
            Stepper("", value: value, in: range, step: step).labelsHidden()
            Text(String(format: format, value.wrappedValue)).font(Theme.mono(12)).frame(width: 80, alignment: .trailing)
        }
    }
}
