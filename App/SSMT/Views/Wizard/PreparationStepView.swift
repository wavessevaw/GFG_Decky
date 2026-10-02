import SSMTCore
import SwiftUI

/// Step 0: interface, levels, room noise, delay lock and system description.
struct PreparationStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InstructionHeader(marking: "STEP 0 · PREP", title: loc.t("prep.title"), text: loc.t("prep.text"))

            Panel(title: loc.t("prep.checklist"), marking: "CHK") {
                checkRow(done: model.isRunning, title: loc.t("prep.audio"),
                         detail: model.isRunning ? (model.engine?.backend.displayName ?? "") : loc.t("prep.audio.hint")) {
                    if !model.isRunning {
                        Button(loc.t("engine.start")) { model.startEngine() }.buttonStyle(SSMTButtonStyle(kind: .primary))
                    }
                }
                TechDivider()
                checkRow(done: micOK, warn: micClipped, title: loc.t("prep.mic"),
                         detail: micClipped ? loc.t("prep.mic.clip") : (micOK ? loc.t("prep.mic.ok") : loc.t("prep.mic.hint"))) {
                    if let s = model.snapshot {
                        Text(String(format: "%.0f dBFS", s.microphone.rmsDBFS)).font(Theme.mono(13))
                    }
                }
                TechDivider()
                checkRow(done: levelDone, warn: levelWarn, title: loc.t("prep.level"), detail: levelDetail) {
                    switch model.autoLevelState {
                    case .measuringNoise, .raising:
                        ProgressView().controlSize(.small)
                    default:
                        Button(loc.t("autolevel.run")) { model.runAutoLevel() }
                            .buttonStyle(SSMTButtonStyle())
                            .disabled(!model.isRunning)
                    }
                }
                TechDivider()
                checkRow(done: model.wizard.isPrepared, warn: delayWarn, title: loc.t("prep.delay"), detail: delayDetail) {
                    if model.wizardDelaySearch {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(loc.t("delay.find")) { model.wizardLockDelay() }
                            .buttonStyle(SSMTButtonStyle())
                            .disabled(!model.isRunning)
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                SNRGauge()
                SignalQualityGauge(band: 40...16000)
            }

            Panel(title: loc.t("prep.system"), marking: "SYS") {
                Toggle(loc.t("prep.hasSub"), isOn: $model.wizard.configuration.hasSubwoofer)
                HStack {
                    Toggle(loc.t("prep.knownCrossover"), isOn: Binding(
                        get: { model.wizard.configuration.crossover != nil },
                        set: { model.wizard.configuration.crossover = $0 ? 90 : nil }))
                    Spacer()
                    if let fc = model.wizard.configuration.crossover {
                        Stepper(value: Binding(get: { fc }, set: { model.wizard.configuration.crossover = $0 }),
                                in: 40...250, step: 5) {
                            Text(String(format: "%.0f Hz", fc)).font(Theme.mono(13))
                        }
                    } else {
                        Text(loc.t("prep.crossover.auto")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                }
                HStack {
                    Text(loc.t("prep.delayStep")).font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Picker("", selection: $model.wizard.configuration.delayStep) {
                        Text("0.01 ms").tag(0.00001)
                        Text("0.02 ms").tag(0.00002)
                        Text("0.1 ms").tag(0.0001)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 240)
                }
                HStack {
                    Text(loc.t("prep.levelStep")).font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Picker("", selection: $model.wizard.configuration.levelStep) {
                        Text("0.1 dB").tag(0.1)
                        Text("0.5 dB").tag(0.5)
                        Text("1 dB").tag(1.0)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 240)
                }
                Toggle(loc.t("prep.fastMode"), isOn: $model.wizard.configuration.fastMode)
                if model.wizard.configuration.fastMode {
                    HazardNotice(text: loc.t("prep.fastMode.warning"))
                }
            }

            WizardPrimaryButton(title: loc.t("wizard.begin"), systemImage: "play.fill",
                                enabled: model.wizard.isPrepared) {
                model.wizardStart()
            }
            if !model.wizard.isPrepared {
                Text(loc.t("prep.notReady")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
        }
    }

    // MARK: Status

    private var micClipped: Bool { model.snapshot?.microphone.clipped ?? false }
    private var micOK: Bool { (model.snapshot?.microphone.rmsDBFS ?? -120) > -90 && !micClipped }

    private var levelDone: Bool {
        if case .done(.targetReached, _) = model.autoLevelState { return true }
        return false
    }
    private var levelWarn: Bool {
        switch model.autoLevelState {
        case .done(.maximumReached, _), .done(.clipped, _): return true
        default: return false
        }
    }
    private var levelDetail: String {
        switch model.autoLevelState {
        case .idle: return loc.t("prep.level.hint")
        case .measuringNoise: return loc.t("autolevel.noise")
        case .raising: return loc.t("autolevel.raising")
        case .done(.targetReached(let snr), let level): return loc.t("autolevel.ok", level, snr)
        case .done(.maximumReached(let snr), _): return loc.t("autolevel.max", snr)
        case .done(.clipped, _): return loc.t("autolevel.clipped")
        }
    }

    private var delayWarn: Bool { model.delay.map { !$0.isReliable } ?? false }
    private var delayDetail: String {
        guard let d = model.delay else { return loc.t("prep.delay.hint") }
        guard d.isReliable else { return loc.t("delay.unreliable") }
        return String(format: "%.2f ms · %.2f m", d.milliseconds, d.meters(celsius: model.temperatureCelsius))
    }

    private func checkRow<Trailing: View>(done: Bool, warn: Bool = false, title: String, detail: String,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.square.fill" : (warn ? "exclamationmark.triangle.fill" : "square"))
                .font(.system(size: 18))
                .foregroundStyle(done ? Theme.statusGood : (warn ? Theme.statusWarning : Theme.textMuted))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.label(14)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing()
        }
    }
}
