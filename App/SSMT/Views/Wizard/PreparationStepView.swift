import SSMTCore
import SwiftUI

/// Step 0: three status tiles (audio, level, delay), one SNR instrument, a one-line system summary.
struct PreparationStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    var showSettings: Binding<Bool> = .constant(false)
    @State private var editingSystem = false

    var body: some View {
        StepScaffold(title: loc.t("prep.title"), subtitle: loc.t("prep.subtitle"), info: loc.t("prep.info")) {
            VStack(spacing: 26) {
                HStack(spacing: 14) {
                    StatusTile(icon: "hifispeaker.fill", title: loc.t("prep.audio"),
                               value: model.isRunning ? (model.engine?.backend.displayName ?? "") : "—",
                               state: model.isRunning ? (micClipped ? 0 : 1) : nil) {
                        if model.isRunning {
                            QuietButton(title: loc.t("prep.change"), icon: "slider.horizontal.3") { showSettings.wrappedValue = true }
                        } else {
                            Button(loc.t("engine.start")) { model.startEngine() }.buttonStyle(SSMTButtonStyle(kind: .primary))
                        }
                    }
                    StatusTile(icon: "dial.medium", title: loc.t("prep.level"), value: levelValue, state: levelState) {
                        if case .measuringNoise = model.autoLevelState { ProgressView().controlSize(.small) }
                        else if case .raising = model.autoLevelState { ProgressView().controlSize(.small) }
                        else {
                            Button(loc.t("autolevel.run")) { model.runAutoLevel() }
                                .buttonStyle(SSMTButtonStyle()).disabled(!model.isRunning)
                        }
                    }
                    StatusTile(icon: "scope", title: loc.t("prep.delay"), value: delayValue,
                               state: model.wizard.isPrepared ? 1.0 : model.delay.map { $0.isReliable ? 1.0 : 0.0 }) {
                        if model.wizardDelaySearch { ProgressView().controlSize(.small) }
                        else {
                            Button(loc.t("delay.find.short")) { model.wizardLockDelay() }
                                .buttonStyle(SSMTButtonStyle()).disabled(!model.isRunning)
                        }
                    }
                }
                SNRGauge().frame(maxWidth: 480)
                Button { editingSystem = true } label: {
                    HStack(spacing: 8) {
                        Text(systemSummary).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                        Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $editingSystem) { systemOptions }
            }
        } actions: {
            ActionRow(primaryTitle: loc.t("wizard.begin"), primaryIcon: "play.fill",
                      primaryEnabled: model.wizard.isPrepared, primaryAction: { model.wizardStart() }) {
                EmptyView()
            }
        }
    }

    // MARK: Values

    private var micClipped: Bool { model.snapshot?.microphone.clipped ?? false }

    private var levelValue: String {
        switch model.autoLevelState {
        case .idle: return "—"
        case .measuringNoise: return loc.t("prep.level.noise")
        case .raising: return loc.t("prep.level.raising")
        case .done(.targetReached, let level), .done(.maximumReached, let level): return String(format: "%.0f dBFS", level)
        case .done(.clipped, _): return loc.t("meters.clip")
        }
    }

    private var levelState: Double? {
        switch model.autoLevelState {
        case .done(.targetReached, _): return 1
        case .done(.maximumReached, _): return 0.6
        case .done(.clipped, _): return 0
        default: return nil
        }
    }

    private var delayValue: String {
        guard let d = model.delay else { return "—" }
        return d.isReliable ? String(format: "%.2f ms", d.milliseconds) : loc.t("prep.delay.bad")
    }

    private var systemSummary: String {
        let c = model.wizard.configuration
        var parts = [loc.t(c.hasSubwoofer ? "prep.sum.sub" : "prep.sum.nosub")]
        parts.append(c.crossover.map { String(format: "XO %.0f Hz", $0) } ?? loc.t("prep.sum.xoAuto"))
        parts.append(String(format: "%.2f ms · %.1f dB", c.delayStep * 1000, c.levelStep))
        if c.fastMode { parts.append(loc.t("prep.sum.fast")) }
        return parts.joined(separator: "  ·  ")
    }

    private var systemOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(loc.t("prep.hasSub"), isOn: $model.wizard.configuration.hasSubwoofer)
            HStack {
                Toggle(loc.t("prep.knownCrossover"), isOn: Binding(
                    get: { model.wizard.configuration.crossover != nil },
                    set: { model.wizard.configuration.crossover = $0 ? 90 : nil }))
                Spacer()
                if let fc = model.wizard.configuration.crossover {
                    Stepper(value: Binding(get: { fc }, set: { model.wizard.configuration.crossover = $0 }), in: 40...250, step: 5) {
                        Text(String(format: "%.0f Hz", fc)).font(Theme.mono(13))
                    }
                }
            }
            Picker(loc.t("prep.delayStep"), selection: $model.wizard.configuration.delayStep) {
                Text("0.01 ms").tag(0.00001); Text("0.02 ms").tag(0.00002); Text("0.1 ms").tag(0.0001)
            }
            Picker(loc.t("prep.levelStep"), selection: $model.wizard.configuration.levelStep) {
                Text("0.1 dB").tag(0.1); Text("0.5 dB").tag(0.5); Text("1 dB").tag(1.0)
            }
            Toggle(loc.t("prep.fastMode"), isOn: $model.wizard.configuration.fastMode)
            if model.wizard.configuration.fastMode {
                Text(loc.t("prep.fastMode.warning")).font(.system(size: 11)).foregroundStyle(Theme.signalYellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(Theme.panel)
    }
}
