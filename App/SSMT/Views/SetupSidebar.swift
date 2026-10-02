import SSMTAudio
import SSMTCore
import SwiftUI

struct SetupSidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                sourcePanel
                generatorPanel
                if model.source == .simulation { simulationPanel }
                displayPanel
                languagePanel
            }
            .padding(12)
        }
        .frame(width: 290)
        .background(Theme.background)
    }

    // MARK: Source

    private var sourcePanel: some View {
        Panel(title: loc.t("setup.source"), marking: "IO-01") {
            Picker(loc.t("setup.interface"), selection: $model.source) {
                Text(loc.t("setup.simulation")).tag(SignalSource.simulation)
                ForEach(model.devices.filter(\.isDuplex)) { d in
                    Text(d.name).tag(SignalSource.device(uid: d.uid))
                }
            }
            .disabled(model.isRunning)

            if let d = model.selectedDevice {
                channelPicker(loc.t("setup.mic.channel"), selection: $model.microphoneChannel, count: d.inputChannels)
                channelPicker(loc.t("setup.output.channel"), selection: $model.outputChannel, count: d.outputChannels)
                if model.referenceMode != .internalSignal {
                    channelPicker(loc.t("setup.ref.channel"), selection: $model.referenceChannel, count: d.inputChannels)
                }
                if !d.supports(sampleRate: 48000) {
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
        Panel(title: loc.t("setup.generator"), marking: "GEN-02") {
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
            if let s = model.snapshot {
                HStack {
                    Text(loc.t("setup.output.level")).font(Theme.label(11)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f dBFS", s.generatorLevelDBFS)).font(Theme.mono(12))
                }
            }
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

    // MARK: Simulation

    private var simulationPanel: some View {
        Panel(title: loc.t("sim.title"), marking: "SIM") {
            Text(loc.t("sim.hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(loc.t("sim.sub"), isOn: $model.simulationSubOn)
            Toggle(loc.t("sim.main"), isOn: $model.simulationMainOn)
        }
    }

    // MARK: Display

    private var displayPanel: some View {
        Panel(title: loc.t("display.title"), marking: "VIEW") {
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
            Slider(value: $model.coherenceThreshold, in: 0.3...0.95, step: 0.05).tint(Theme.accent)
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
        Panel(title: loc.t("settings.language"), marking: "L10N") {
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
            Slider(value: value, in: range, step: 1) { _ in onCommit() }
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
        VStack(alignment: .leading, spacing: 0) {
            HazardStripes().frame(height: 5)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.signalYellow)
                Text(text).font(.system(size: 11)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
        .background(Theme.signalYellow.opacity(0.06))
        .overlay(Rectangle().stroke(Theme.signalYellow.opacity(0.35), lineWidth: 1))
    }
}
