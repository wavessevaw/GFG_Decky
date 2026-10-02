import AVFoundation
import Foundation
import SSMTAudio
import SSMTCore
import SwiftUI

/// Signal source for the measurement session.
enum SignalSource: Hashable {
    case simulation
    /// One duplex interface.
    case device(uid: String)
    /// Microphone and output on different interfaces → private aggregate device (drift-compensated).
    case split(inputUID: String, outputUID: String)
}

enum AutoLevelState: Equatable {
    case idle
    case measuringNoise
    case raising
    case done(AutoLevelController.Outcome, level: Double)
}

/// Noise types offered in the UI (index into the generator bank).
enum NoiseChoice: Int, CaseIterable, Identifiable {
    case pink = 0, white = 1, periodicPink = 2
    var id: Int { rawValue }
    var key: String {
        switch self {
        case .pink: return "noise.pink"
        case .white: return "noise.white"
        case .periodicPink: return "noise.periodic"
        }
    }
}

enum GraphKind: String, CaseIterable, Identifiable {
    case magnitude, phase, coherence
    var id: String { rawValue }
}

/// Application state. The measurement engine lives here (not in a view), so minimizing or
/// closing windows never interrupts averaging.
@MainActor
final class AppModel: ObservableObject {
    // Setup
    @Published var devices: [AudioDeviceInfo] = []
    @Published var source: SignalSource = .simulation
    @Published var microphoneChannel = 0
    @Published var referenceChannel = 1
    @Published var outputChannel = 0
    @Published var referenceMode: ReferenceMode = .internalSignal
    @Published var temperatureCelsius: Double = 20

    // Generator
    @Published var noise: NoiseChoice = .pink
    @Published var levelDBFS: Double = -40
    @Published var maximumLevelDBFS: Double = -12
    @Published private(set) var noiseOn = false

    // Live state
    @Published private(set) var isRunning = false
    @Published private(set) var snapshot: LiveSnapshot?
    @Published private(set) var delay: DelayEstimate?
    @Published private(set) var delaySearchRunning = false
    @Published var lastError: String?
    @Published private(set) var microphonePermission: AVAuthorizationStatus = .notDetermined

    // Calibration
    @Published private(set) var calibration = CalibrationLibrary.load()
    @Published private(set) var autoLevelState: AutoLevelState = .idle
    @Published private(set) var noiseFloor: [Double]?

    // Display
    @Published var smoothing: SmoothingResolution = .oct12
    @Published var coherenceThreshold: Double = 0.6
    @Published var visibleGraphs: Set<GraphKind> = [.magnitude, .phase, .coherence]
    @Published var stageMode = false

    // Simulation controls (stand-in for muting groups on the processor)
    @Published var simulationSubOn = true { didSet { applySimulationGroups() } }
    @Published var simulationMainOn = true { didSet { applySimulationGroups() } }

    private(set) var engine: MeasurementEngine?
    private var simulationBackend: SimulatedAudioBackend?
    private var aggregate: AggregateDevice?

    init() {
        refreshDevices()
        microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    var selectedDevice: AudioDeviceInfo? {
        switch source {
        case .device(let uid): return devices.first { $0.uid == uid }
        default: return nil
        }
    }

    var inputDevice: AudioDeviceInfo? {
        switch source {
        case .device(let uid), .split(let uid, _): return devices.first { $0.uid == uid }
        case .simulation: return nil
        }
    }

    var outputDevice: AudioDeviceInfo? {
        switch source {
        case .device(let uid), .split(_, let uid): return devices.first { $0.uid == uid }
        case .simulation: return nil
        }
    }

    var isSplitSource: Bool {
        if case .split = source { return true }
        return false
    }

    var safety: GeneratorSafety {
        var s = GeneratorSafety()
        s.maximumLevelDBFS = maximumLevelDBFS
        return s
    }

    func refreshDevices() {
        devices = DeviceCatalog.allDevices().filter { $0.inputChannels > 0 || $0.outputChannels > 0 }
    }

    // MARK: - Engine lifecycle

    func startEngine() {
        guard !isRunning else { return }
        lastError = nil
        let backend: AudioIOBackend
        switch source {
        case .simulation:
            let sim = SimulatedAudioBackend(system: Self.demoSystem(), deviceLatency: 512, safety: safety)
            simulationBackend = sim
            backend = sim
            applySimulationGroups()
        case .device, .split:
            guard microphonePermission == .authorized else {
                requestMicrophoneAccess()
                return
            }
            do {
                backend = try makeHardwareBackend()
            } catch {
                aggregate = nil
                lastError = String(describing: error)
                return
            }
            simulationBackend = nil
        }
        var config = MeasurementEngine.Configuration()
        config.referenceMode = referenceMode
        let engine = MeasurementEngine(backend: backend, configuration: config)
        engine.setSnapshotHandler { [weak self] snap in
            Task { @MainActor in self?.snapshot = snap }
        }
        do {
            try engine.start()
        } catch {
            lastError = String(describing: error)
            return
        }
        engine.setSPLCalibration(calibration.spl)
        self.engine = engine
        isRunning = true
        delay = nil
        noiseFloor = nil
        autoLevelState = .idle
    }

    private func makeHardwareBackend() throws -> AudioIOBackend {
        let refChannel = referenceMode == .internalSignal ? nil : referenceChannel
        switch source {
        case .device(let uid):
            return try HALAudioBackend(routing: HALRouting(deviceUID: uid, microphoneChannel: microphoneChannel,
                                                           referenceChannel: refChannel,
                                                           outputChannels: [outputChannel]), safety: safety)
        case .split(let inUID, let outUID):
            let agg = try AggregateDevice(inputUID: inUID, outputUID: outUID)
            aggregate = agg
            return try HALAudioBackend(
                routing: HALRouting(deviceUID: agg.uid,
                                    microphoneChannel: agg.inputChannelOffset + microphoneChannel,
                                    referenceChannel: refChannel.map { agg.inputChannelOffset + $0 },
                                    outputChannels: [agg.outputChannelOffset + outputChannel]),
                safety: safety)
        case .simulation:
            fatalError("not a hardware source")
        }
    }

    func stopEngine() {
        engine?.stop()
        engine = nil
        simulationBackend = nil
        aggregate = nil
        isRunning = false
        noiseOn = false
        snapshot = nil
        autoLevelState = .idle
    }

    // MARK: - Generator

    func setNoise(on: Bool) {
        guard let engine else { return }
        let c = engine.backend.generatorControl
        c.kindIndex.value = UInt64(noise.rawValue)
        c.targetLevelDBFS.value = Float(min(levelDBFS, maximumLevelDBFS))
        c.run.value = on
        noiseOn = on
    }

    func toggleNoise() {
        if !isRunning { startEngine() }
        setNoise(on: !noiseOn)
    }

    func applyLevel() {
        engine?.backend.generatorControl.targetLevelDBFS.value = Float(min(levelDBFS, maximumLevelDBFS))
    }

    func applyNoiseKind() {
        engine?.backend.generatorControl.kindIndex.value = UInt64(noise.rawValue)
    }

    /// STOP: mutes the output on the next audio buffer, from any state.
    func emergencyStop() {
        engine?.emergencyStop()
        noiseOn = false
    }

    // MARK: - Measurement

    func findDelay() {
        guard let engine, noiseOn else { return }
        delaySearchRunning = true
        engine.findDelay(seconds: 3) { [weak self] estimate in
            Task { @MainActor in
                self?.delay = estimate
                self?.delaySearchRunning = false
            }
        }
    }

    /// Measures the room noise (generator silent), then raises the level until SNR ≥ 20 dB
    /// or the user maximum is reached.
    func runAutoLevel() {
        guard let engine else { return }
        autoLevelState = .measuringNoise
        noiseOn = false
        engine.measureNoiseFloor(seconds: 5) { [weak self] floor in
            Task { @MainActor in
                guard let self, let engine = self.engine else { return }
                self.noiseFloor = floor
                self.autoLevelState = .raising
                self.noiseOn = true
                var settings = AutoLevelController.Settings()
                settings.maximumLevelDBFS = self.maximumLevelDBFS
                engine.runAutoLevel(settings: settings, noiseFloor: floor) { level, outcome in
                    Task { @MainActor in
                        self.levelDBFS = level
                        self.autoLevelState = .done(outcome, level: level)
                        if outcome == .clipped { self.noiseOn = true }
                    }
                }
            }
        }
    }

    func cancelAutoLevel() {
        engine?.cancelAutoLevel()
        engine?.cancelCapture()
        autoLevelState = .idle
    }

    // MARK: - Calibration

    func importMicrophoneCalibration(from url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let mic = try MicrophoneCalibration.parse(text, name: url.deletingPathExtension().lastPathComponent)
            calibration.microphones.append(mic)
            calibration.selectedMicrophoneID = mic.id
            calibration.save()
        } catch {
            lastError = "\(url.lastPathComponent): \(error)"
        }
    }

    func selectMicrophone(_ id: UUID?) {
        calibration.selectedMicrophoneID = id
        calibration.save()
    }

    func removeMicrophone(_ id: UUID) {
        calibration.microphones.removeAll { $0.id == id }
        if calibration.selectedMicrophoneID == id { calibration.selectedMicrophoneID = nil }
        calibration.save()
    }

    func setSPLCalibration(dBFSAt94: Double?) {
        calibration.spl = dBFSAt94.map { SPLCalibration(dBFSAt94dBSPL: $0) }
        calibration.save()
        engine?.setSPLCalibration(calibration.spl)
        engine?.resetSoundLevel()
    }

    /// Uses the current microphone RMS (calibrator on the mic, test signal off) as the reference.
    func calibrateWithCalibrator(level: Double) {
        guard let rms = snapshot?.microphone.rmsDBFS, rms > -100 else { return }
        emergencyStop()
        let c = SPLCalibration.fromCalibrator(measuredDBFS: rms, calibratorSPL: level)
        setSPLCalibration(dBFSAt94: c.dBFSAt94dBSPL)
    }

    func resetSoundLevel() { engine?.resetSoundLevel() }

    /// Transfer function for display: microphone response removed when a calibration is selected.
    var displayTransfer: TransferFunction? {
        guard let tf = snapshot?.transfer else { return nil }
        return calibration.selectedMicrophone?.apply(to: tf) ?? tf
    }

    func setReferenceMode(_ mode: ReferenceMode) {
        referenceMode = mode
        engine?.setReferenceMode(mode)
    }

    func resetAverages() { engine?.resetLiveAverages() }
    func resetClips() { engine?.resetClipIndicators() }

    func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                self.microphonePermission = granted ? .authorized : .denied
                if granted { self.startEngine() }
            }
        }
    }

    // MARK: - Simulation

    private func applySimulationGroups() {
        simulationBackend?.setActiveGroups(sub: simulationSubOn, main: simulationMainOn)
    }

    /// Demo room: sub and mains 1.5 m apart in depth, a floor bounce and two LF modes.
    static func demoSystem() -> VirtualSystem {
        let fs = 48000.0
        let room = VirtualRoom(
            reflections: [VirtualReflection(delaySamples: 168, gain: 0.35),
                          VirtualReflection(delaySamples: 1900, gain: 0.2)],
            modes: [Biquad.design(.peaking, frequency: 63, q: 6, gainDB: 7, sampleRate: fs),
                    Biquad.design(.peaking, frequency: 160, q: 5, gainDB: 4, sampleRate: fs)])
        return VirtualSystem.typicalPA(sampleRate: fs, crossover: 90, subDistance: 8, mainDistance: 9.5,
                                       room: room, micNoiseDBFS: -75)
    }
}
