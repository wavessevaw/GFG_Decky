import SSMTCore
import SwiftUI

/// Polarity lamp: green "correct" / blinking orange-red "switch".
struct PolarityLamp: View {
    @EnvironmentObject var loc: Localizer
    var wrong: Bool?
    var large = false
    @State private var blink = false

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: large ? 34 : 24, height: large ? 34 : 24)
                .shadow(color: color.opacity(0.8), radius: 10)
                .opacity(wrong == true && blink ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("card.polarity").uppercased()).font(Theme.label(11)).tracking(1.2).foregroundStyle(Theme.textSecondary)
                Text(text).font(Theme.heading(large ? 26 : 20)).foregroundStyle(color)
            }
            Spacer()
            Image(systemName: wrong == false ? "checkmark.circle.fill" : (wrong == true ? "arrow.up.arrow.down.circle.fill" : "circle.dashed"))
                .font(.system(size: large ? 30 : 22)).foregroundStyle(color)
        }
        .padding(14)
        .background(CutCornerShape(cut: 12).fill(Theme.panel))
        .overlay(CutCornerShape(cut: 12).stroke(color.opacity(0.7), lineWidth: 1))
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

/// Live tuning screen block: polarity lamp, delay needle, level needle.
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
        let tolPhase = 10.0

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc.t(mainsStage ? "tuner.stage.mains" : "tuner.stage.sub"))
                    .font(Theme.heading(20)).foregroundStyle(Theme.textPrimary)
                Spacer()
                if r != nil && !reliable {
                    StatusBadge(level: .warning, text: loc.t("tuner.unreliable"))
                } else if r == nil {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(loc.t("tuner.waiting")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Text(loc.t("tuner.hint")).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !mainsStage {
                PolarityLamp(wrong: r.map(\.polarityWrong), large: large)
            }
            HStack(alignment: .top, spacing: 12) {
                if showDelay {
                    TunerGauge(
                        title: loc.t(mainsStage ? "card.delay.mains" : "card.delay.sub"),
                        value: r.map { $0.delayPhaseError / 90 },
                        tolerance: tolPhase / 90,
                        readout: r.map { String(format: "%+.2f ms", $0.delayError * 1000) } ?? "—",
                        instruction: delayInstruction(r, mainsStage: mainsStage),
                        reliable: reliable,
                        leftLabel: loc.t("tuner.less"), rightLabel: loc.t("tuner.more"),
                        large: large)
                }
                if !mainsStage {
                    TunerGauge(
                        title: loc.t("card.level"),
                        value: r.map { $0.levelError / 6 },
                        tolerance: 0.5 / 6,
                        readout: r.map { String(format: "%+.1f dB", $0.levelError) } ?? "—",
                        instruction: levelInstruction(r),
                        reliable: reliable,
                        leftLabel: loc.t("tuner.quieter"), rightLabel: loc.t("tuner.louder"),
                        large: large)
                }
            }
            if !showDelay {
                Text(loc.t("tuner.mainsLater")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
            Text(String(format: loc.t("tuner.scale"), 90 / (fc * 360) * 1000))
                .font(Theme.mono(10)).foregroundStyle(Theme.textMuted)
        }
    }

    private func delayInstruction(_ r: AlignmentTuner.Reading?, mainsStage: Bool) -> String {
        guard let r else { return "" }
        if r.delayInTune { return loc.t("tuner.inTune") }
        let more = r.delayError > 0
        return loc.t(mainsStage ? (more ? "tuner.mains.more" : "tuner.mains.less") : (more ? "tuner.sub.more" : "tuner.sub.less"))
    }

    private func levelInstruction(_ r: AlignmentTuner.Reading?) -> String {
        guard let r else { return "" }
        if r.levelInTune { return loc.t("tuner.inTune") }
        return loc.t(r.levelError > 0 ? "tuner.level.up" : "tuner.level.down")
    }
}

/// Simulation only: knobs of the virtual loudspeaker processor.
struct VirtualProcessorPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        Panel(title: loc.t("vproc.title"), marking: "SIM DSP") {
            Text(loc.t("vproc.hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            knob(loc.t("vproc.subDelay"), value: $model.simProcessor.subDelayMs, range: 0...20, step: 0.01, format: "%.2f ms")
            knob(loc.t("vproc.mainsDelay"), value: $model.simProcessor.mainsDelayMs, range: 0...20, step: 0.01, format: "%.2f ms")
            knob(loc.t("vproc.subLevel"), value: $model.simProcessor.subGainDB, range: -12...6, step: 0.5, format: "%+.1f dB")
            Toggle(loc.t("vproc.subPolarity"), isOn: $model.simProcessor.subPolarityInverted)
        }
    }

    private func knob(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                      format: String) -> some View {
        HStack {
            Text(title).font(Theme.label(12)).foregroundStyle(Theme.textSecondary).frame(width: 150, alignment: .leading)
            Slider(value: value, in: range, step: step).tint(Theme.accent)
            Stepper("", value: value, in: range, step: step).labelsHidden()
            Text(String(format: format, value.wrappedValue)).font(Theme.mono(12)).frame(width: 80, alignment: .trailing)
        }
    }
}
