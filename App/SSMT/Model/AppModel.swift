import AVFoundation
import Foundation
import SSMTAudio
import SSMTCore
import SwiftUI

/// Signal source for the measurement session.
enum SignalSource: Hashable {
    case simulation
    case device(uid: String)
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

    init() {
        refreshDevices()
        microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    var selectedDevice: AudioDeviceInfo? {
        if case .device(let uid) = source { return devices.first { $0.uid == uid } }
        return nil
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
        case .device(let uid):
            guard microphonePermission == .authorized else {
                requestMicrophoneAccess()
                return
            }
            do {
                let routing = HALRouting(deviceUID: uid, microphoneChannel: microphoneChannel,
                                         referenceChannel: referenceMode == .internalSignal ? nil : referenceChannel,
                                         outputChannels: [outputChannel])
                backend = try HALAudioBackend(routing: routing, safety: safety)
            } catch {
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
        self.engine = engine
        isRunning = true
        delay = nil
    }

    func stopEngine() {
        engine?.stop()
        engine = nil
        simulationBackend = nil
        isRunning = false
        noiseOn = false
        snapshot = nil
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
