import SSMTAudio
import SSMTCore
import SwiftUI

struct SetupSidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    /// Expert mode shows display options (smoothing, coherence threshold, graph selection).
    var expert = true

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                sourcePanel
                generatorPanel
                CalibrationPanel()
                if model.source == .simulation { simulationPanel }
                if expert { displayPanel }
                languagePanel
            }
            .padding(12)
        }
        .scrollIndicators(.never)
    }

    // MARK: Source

    private var sourcePanel: some View {
        Panel(title: loc.t("setup.source")) {
            Toggle(loc.t("setup.split"), isOn: Binding(
                get: { model.isSplitSource },
                set: { split in
                    if split {
                        let input = model.devices.first { $0.inputChannels > 0 }
                        let output = model.devices.first { $0.outputChannels > 0 }
                        if let i = input, let o = output { model.source = .split(inputUID: i.uid, outputUID: o.uid) }
                    } else {
                        model.source = .simulation
                    }
                }))
                .disabled(model.isRunning)

            if case .split(let inUID, let outUID) = model.source {
                Picker(loc.t("setup.input.device"), selection: Binding(
                    get: { inUID }, set: { model.source = .split(inputUID: $0, outputUID: outUID) })) {
                    ForEach(model.devices.filter { $0.inputChannels > 0 }) { Text($0.name).tag($0.uid) }
                }
                .disabled(model.isRunning)
                Picker(loc.t("setup.output.device"), selection: Binding(
                    get: { outUID }, set: { model.source = .split(inputUID: inUID, outputUID: $0) })) {
                    ForEach(model.devices.filter { $0.outputChannels > 0 }) { Text($0.name).tag($0.uid) }
                }
                .disabled(model.isRunning)
                Text(loc.t("setup.split.hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(loc.t("setup.interface"), selection: $model.source) {
                    Text(loc.t("setup.simulation")).tag(SignalSource.simulation)
                    ForEach(model.devices.filter(\.isDuplex)) { d in
                        Text(d.name).tag(SignalSource.device(uid: d.uid))
                    }
                }
                .disabled(model.isRunning)
            }

            if let i = model.inputDevice, let o = model.outputDevice {
                channelPicker(loc.t("setup.mic.channel"), selection: $model.microphoneChannel, count: i.inputChannels)
                channelPicker(loc.t("setup.output.channel"), selection: $model.outputChannel, count: o.outputChannels)
                if model.referenceMode != .internalSignal {
                    channelPicker(loc.t("setup.ref.channel"), selection: $model.referenceChannel, count: i.inputChannels)
                }
                if !i.supports(sampleRate: 48000) || !o.supports(sampleRate: 48000) {
                    StatusBadge(level: .error, text: loc.t("setup.no48k"))
                }
            }

            Picker(loc.t("setup.reference"), selection: Binding(get: { model.referenceMode },
                                                                set: { model.setReferenceMode($0) })) {
                Text(loc.t("ref.internal")).tag(ReferenceMode.internalSignal)
                Text(loc.t("ref.loopback")).tag(ReferenceMode.loopbackInput)
            }
            Text(loc.t(model.referenceMode == .internalSignal ? "ref.internal.hint" : "ref.loopback.hint"))
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(loc.t("setup.temperature")).font(Theme.label(11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Stepper(value: $model.temperatureCelsius, in: -20...50, step: 1) {
                    Text(String(format: "%.0f °C", model.temperatureCelsius)).font(Theme.mono(12))
                }
            }

            HStack {
                if model.isRunning {
                    Button(loc.t("engine.stop")) { model.stopEngine() }.buttonStyle(SSMTButtonStyle())
                } else {
                    Button(loc.t("engine.start")) { model.startEngine() }.buttonStyle(SSMTButtonStyle(kind: .primary))
                }
                Button { model.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(SSMTButtonStyle())
                    .help(loc.t("setup.refresh"))
            }
            if model.microphonePermission == .denied {
                warning(loc.t("permission.denied"))
            }
            if let e = model.lastError { warning(e) }
        }
    }

    // MARK: Generator

    private var generatorPanel: some View {
        Panel(title: loc.t("setup.generator")) {
            Picker(loc.t("setup.noise"), selection: $model.noise) {
                ForEach(NoiseChoice.allCases) { Text(loc.t($0.key)).tag($0) }
            }
            .onChange(of: model.noise) { _ in model.applyNoiseKind() }
            if model.noise == .periodicPink {
                Text(loc.t("noise.periodic.hint")).font(.system(size: 11)).foregroundStyle(Theme.signalYellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
            levelSlider(loc.t("setup.level"), value: $model.levelDBFS, range: -80...0) { model.applyLevel() }
            levelSlider(loc.t("setup.max.level"), value: $model.maximumLevelDBFS, range: -60...0) { model.applyLevel() }
            GeneratorLevelRow()
            autoLevelRow
            hazard(loc.t("safety.hf.warning"))
            Button {
                model.findDelay()
            } label: {
                Label(model.delaySearchRunning ? loc.t("delay.searching") : loc.t("delay.find"),
                      systemImage: "scope")
            }
            .buttonStyle(SSMTButtonStyle())
            .disabled(!model.noiseOn || model.delaySearchRunning)
            .keyboardShortcut("d", modifiers: [.command])
            if let d = model.delay, !d.isReliable {
                warning(loc.t("delay.unreliable"))
            }
        }
    }

    @ViewBuilder private var autoLevelRow: some View {
        HStack {
            switch model.autoLevelState {
            case .measuringNoise, .raising:
                ProgressView().controlSize(.small)
                Text(loc.t(model.autoLevelState == .measuringNoise ? "autolevel.noise" : "autolevel.raising"))
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(loc.t("action.cancel")) { model.cancelAutoLevel() }.buttonStyle(SSMTButtonStyle())
            default:
                Button {
                    model.runAutoLevel()
                } label: {
                    Label(loc.t("autolevel.run"), systemImage: "dial.medium")
                }
                .buttonStyle(SSMTButtonStyle())
                .disabled(!model.isRunning)
                .help(loc.t("autolevel.help"))
                Spacer()
            }
        }
        if case .done(let outcome, let level) = model.autoLevelState {
            switch outcome {
            case .targetReached(let snr):
                StatusBadge(level: .good, text: loc.t("autolevel.ok", level, snr))
            case .maximumReached(let snr):
                StatusBadge(level: .warning, text: loc.t("autolevel.max", snr))
            case .clipped:
                StatusBadge(level: .error, text: loc.t("autolevel.clipped"))
            }
        }
    }

    // MARK: Simulation

    private var simulationPanel: some View {
        Panel(title: loc.t("sim.title")) {
            Text(loc.t("sim.hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(loc.t("sim.sub"), isOn: $model.simulationSubOn)
            Toggle(loc.t("sim.main"), isOn: $model.simulationMainOn)
        }
    }

    // MARK: Display

    private var displayPanel: some View {
        Panel(title: loc.t("display.title")) {
            Picker(loc.t("display.smoothing"), selection: $model.smoothing) {
                Text(loc.t("display.smoothing.none")).tag(SmoothingResolution.none)
                ForEach([SmoothingResolution.oct48, .oct24, .oct12, .oct6, .oct3], id: \.self) {
                    Text("1/\($0.rawValue) oct").tag($0)
                }
            }
            HStack {
                Text(loc.t("display.coherence.threshold")).font(Theme.label(11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: "%.2f", model.coherenceThreshold)).font(Theme.mono(12))
            }
            Slider(value: Binding(get: { model.coherenceThreshold },
                                  set: { model.coherenceThreshold = ($0 * 20).rounded() / 20 }), in: 0.3...0.95)
                .tint(Theme.accent)
            ForEach(GraphKind.allCases) { g in
                Toggle(loc.t("graph.\(g.rawValue)"), isOn: Binding(
                    get: { model.visibleGraphs.contains(g) },
                    set: { on in if on { model.visibleGraphs.insert(g) } else { model.visibleGraphs.remove(g) } }))
            }
            HStack {
                Button(loc.t("display.reset.avg")) { model.resetAverages() }.buttonStyle(SSMTButtonStyle())
                Button(loc.t("display.reset.clip")) { model.resetClips() }.buttonStyle(SSMTButtonStyle())
            }
        }
    }

    private var languagePanel: some View {
        Panel(title: loc.t("settings.language")) {
            Picker("", selection: Binding(get: { loc.language }, set: { loc.language = $0 })) {
                Text(loc.t("language.system")).tag(AppLanguage.system)
                Text("English").tag(AppLanguage.en)
                Text("Русский").tag(AppLanguage.ru)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    // MARK: Helpers

    private func channelPicker(_ title: String, selection: Binding<Int>, count: Int) -> some View {
        Picker(title, selection: selection) {
            ForEach(0..<max(count, 1), id: \.self) { Text("\($0 + 1)").tag($0) }
        }
        .disabled(model.isRunning)
    }

    private func levelSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                             onCommit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(Theme.label(11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: "%.0f dBFS", value.wrappedValue)).font(Theme.mono(12))
            }
            // No `step:` — on macOS that draws a tick mark per step. Values are rounded to 1 dB instead.
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0.rounded() }), in: range) { _ in onCommit() }
                .tint(Theme.accent)
                .onChange(of: value.wrappedValue) { _ in onCommit() }
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.statusWarning)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hazard(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.signalYellow)
            Text(text).font(.system(size: 11)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Theme.signalYellow.opacity(0.10)))
    }
}

/// Current generator output level (live).
struct GeneratorLevelRow: View {
    @EnvironmentObject var live: LiveData
    @EnvironmentObject var loc: Localizer

    var body: some View {
        if let s = live.snapshot {
            HStack {
                Text(loc.t("setup.output.level")).font(Theme.label(11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: "%.1f dBFS", s.generatorLevelDBFS)).font(Theme.mono(12))
            }
        }
    }
}
