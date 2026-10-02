import SSMTCore
import SwiftUI

/// Step 0: checklist (audio, microphone, level, delay), the SNR instrument and the system options.
struct PreparationStepView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        StepScaffold(title: loc.t("prep.title"), subtitle: loc.t("prep.text"), info: loc.t("prep.info")) {
            VStack(spacing: 16) {
                checklist
                HStack(alignment: .top, spacing: 16) {
                    SNRGauge().frame(maxWidth: 420)
                    systemCard
                }
            }
        } actions: {
            ActionRow(primaryTitle: loc.t("wizard.begin"), primaryIcon: "play.fill",
                      primaryEnabled: model.wizard.isPrepared, primaryAction: { model.wizardStart() }) {
                EmptyView()
            }
        }
    }

    // MARK: Checklist

    private var checklist: some View {
        Panel(title: loc.t("prep.checklist")) {
            VStack(spacing: 0) {
                ChecklistRow(done: model.isRunning, failed: false, icon: "hifispeaker.fill", title: loc.t("prep.audio"),
                             detail: model.isRunning ? (model.engine?.backend.displayName ?? "") : loc.t("prep.audio.hint")) {
                    if model.isRunning {
                        Button(loc.t("prep.change")) { model.showSettings = true }.buttonStyle(SSMTButtonStyle())
                    } else {
                        Button(loc.t("engine.start")) { model.startEngine() }.buttonStyle(SSMTButtonStyle(kind: .primary))
                    }
                }
                divider
                ChecklistRow(done: micPresent && !micClipped, failed: micClipped, icon: "mic.fill", title: loc.t("prep.mic"),
                             detail: loc.t(micClipped ? "prep.mic.clip" : (micPresent ? "prep.mic.ok" : "prep.mic.hint"))) {
                    LevelStrip(dbfs: model.snapshot?.microphone.rmsDBFS, clipped: micClipped)
                }
                divider
                ChecklistRow(done: levelState == 1, failed: levelState == 0, icon: "dial.medium", title: loc.t("prep.level"),
                             detail: levelState == nil ? loc.t("prep.level.hint") : levelValue) {
                    if case .measuringNoise = model.autoLevelState { busy(loc.t("prep.level.noise")) }
                    else if case .raising = model.autoLevelState { busy(loc.t("prep.level.raising")) }
                    else {
                        Button(loc.t("autolevel.run")) { model.runAutoLevel() }
                            .buttonStyle(SSMTButtonStyle()).disabled(!model.isRunning)
                    }
                }
                divider
                ChecklistRow(done: model.wizard.isPrepared, failed: model.delay.map { !$0.isReliable } ?? false,
                             icon: "scope", title: loc.t("prep.delay"),
                             detail: model.delay == nil ? loc.t("prep.delay.hint") : delayValue) {
                    if model.wizardDelaySearch { busy("") }
                    else {
                        Button(loc.t("delay.find")) { model.wizardLockDelay() }
                            .buttonStyle(SSMTButtonStyle()).disabled(!model.isRunning)
                    }
                }
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 92)
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            if !text.isEmpty { Text(text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary) }
        }
    }

    // MARK: System options (inline, no popover)

    private var systemCard: some View {
        Panel(title: loc.t("prep.system"), tint: Theme.dataSecondary) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Toggle(loc.t("prep.hasSub"), isOn: $model.wizard.configuration.hasSubwoofer)
                    Spacer()
                    Toggle(loc.t("prep.fastMode.short"), isOn: $model.wizard.configuration.fastMode)
                }
                HStack {
                    Toggle(loc.t("prep.knownCrossover"), isOn: Binding(
                        get: { model.wizard.configuration.crossover != nil },
                        set: { model.wizard.configuration.crossover = $0 ? 90 : nil }))
                    Spacer()
                    if let fc = model.wizard.configuration.crossover {
                        Stepper(value: Binding(get: { fc }, set: { model.wizard.configuration.crossover = $0 }), in: 40...250, step: 5) {
                            Text(String(format: "%.0f Hz", fc)).font(Theme.mono(13))
                        }
                    } else {
                        Text(loc.t("prep.crossover.auto")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    }
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc.t("prep.delayStep")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Picker("", selection: $model.wizard.configuration.delayStep) {
                            Text("0.01 ms").tag(0.00001); Text("0.02 ms").tag(0.00002); Text("0.1 ms").tag(0.0001)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc.t("prep.levelStep")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        Picker("", selection: $model.wizard.configuration.levelStep) {
                            Text("0.1 dB").tag(0.1); Text("0.5 dB").tag(0.5); Text("1 dB").tag(1.0)
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                }
                if model.wizard.configuration.fastMode {
                    Text(loc.t("prep.fastMode.warning")).font(.system(size: 11)).foregroundStyle(Theme.signalYellow)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 13))
        }
    }

    // MARK: Values

    private var micClipped: Bool { model.snapshot?.microphone.clipped ?? false }
    private var micPresent: Bool { (model.snapshot?.microphone.rmsDBFS ?? -120) > -70 }

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
}

/// One checklist line: check · icon tile · title and one-line detail · control on the right.
struct ChecklistRow<Trailing: View>: View {
    var done: Bool
    var failed: Bool
    var icon: String
    var title: String
    var detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            CheckDot(done: done, failed: failed)
            IconTile(systemName: icon, tint: done ? Theme.textPrimary : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.system(size: 12)).foregroundStyle(failed ? Theme.statusError : Theme.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 12)
    }
}

/// Small segmented input level strip with the value.
struct LevelStrip: View {
    var dbfs: Double?
    var clipped: Bool
    var segments = 18

    var body: some View {
        let x = dbfs.map { min(1, max(0, ($0 + 70) / 70)) } ?? 0
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { i in
                    let p = (Double(i) + 0.5) / Double(segments)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(p <= x ? (clipped || p > 0.92 ? Theme.statusError : (p > 0.75 ? Theme.signalYellow : Theme.statusGood))
                              : Color.white.opacity(0.10))
                        .frame(width: 4, height: 16)
                }
            }
            Text(dbfs.map { String(format: "%.0f dB", $0) } ?? "—").font(Theme.mono(13))
                .foregroundStyle(Theme.textPrimary).frame(width: 54, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.12), value: x)
    }
}
