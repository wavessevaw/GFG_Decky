import Foundation

/// Which reference the analyzer uses.
public enum ReferenceMode: String, Codable, Sendable, CaseIterable {
    /// B — the generated samples themselves (no loopback cable). Default.
    case internalSignal
    /// A — a hardware loopback cable into a second input.
    case loopbackInput
    /// C — external program material on a second input (architecture only in v1).
    case externalInput
}

/// Noise variants pre-built by a backend so they can be switched from the audio thread
/// without allocation (index into the bank).
public struct GeneratorBankSpec: Equatable, Codable, Sendable {
    public var kinds: [NoiseKind]
    public init(kinds: [NoiseKind] = [.pink, .white, .periodicPink(periodLength: 65536)]) { self.kinds = kinds }
}

/// Lock-free controls written by the UI/controller and read by the audio callback.
public final class GeneratorControl: @unchecked Sendable {
    /// Noise requested on (fade in) or off (fade out).
    public let run = AtomicBool(false)
    /// Set by STOP; the audio thread silences the very next buffer and clears the flag.
    public let hardMuteRequest = AtomicBool(false)
    /// Target RMS level (dBFS).
    public let targetLevelDBFS = AtomicFloat(-60)
    /// Index into the generator bank.
    public let kindIndex = AtomicCounter()
    /// Current generator level (dBFS RMS), published by the audio thread for display.
    public let currentLevelDBFS = AtomicFloat(-120)

    public init() {}

    /// STOP: silence the output immediately, from any state.
    public func emergencyStop() {
        run.value = false
        targetLevelDBFS.value = -120
        hardMuteRequest.value = true
    }
}

/// Real-time I/O contract shared by the Core Audio backend and the simulator.
///
/// Two rings are filled by the backend:
/// - `inputRing`: 2 channels — [microphone, reference input]
/// - `outputRing`: 1 channel — exact generated samples sent to the output
/// Both streams are continuous while the backend runs; the consumer pairs them sample by sample.
/// Their fixed offset is part of the measured system delay, so it must not change during a session:
/// any dropout or restart increments `discontinuities`.
public protocol AudioIOBackend: AnyObject {
    var sampleRate: Double { get }
    var inputRing: RealtimeRing { get }
    var outputRing: RealtimeRing { get }
    var generatorControl: GeneratorControl { get }
    var generatorBank: GeneratorBankSpec { get }
    var discontinuities: AtomicCounter { get }
    var isRunning: Bool { get }
    /// Human-readable description for the UI ("Simulation", device name…).
    var displayName: String { get }
    func start() throws
    func stop()
}

/// Real-time generator bank: renders the selected generator, honouring the lock-free controls.
/// Used identically by the simulator and the Core Audio backend.
public final class GeneratorBank {
    public let generators: [SignalGenerator]
    private var lastIndex = 0

    public init(spec: GeneratorBankSpec, sampleRate: Double, safety: GeneratorSafety, seed: UInt64) {
        generators = spec.kinds.enumerated().map { i, k in
            SignalGenerator(kind: k, sampleRate: sampleRate, seed: seed &+ UInt64(i), safety: safety)
        }
    }

    /// Real-time safe.
    @inline(__always)
    public func render(into out: UnsafeMutablePointer<Float>, count: Int, control: GeneratorControl) {
        if control.hardMuteRequest.value {
            control.hardMuteRequest.value = false
            for g in generators { g.hardMute() }
        }
        var idx = Int(control.kindIndex.value)
        if idx < 0 || idx >= generators.count { idx = 0 }
        if idx != lastIndex {
            // Switching noise type restarts from silence with a fresh fade-in.
            generators[lastIndex].hardMute()
            generators[idx].hardMute()
            lastIndex = idx
        }
        let g = generators[idx]
        g.render(into: out, count: count, run: control.run.value,
                 targetLevelDBFS: Double(control.targetLevelDBFS.value))
        control.currentLevelDBFS.value = g.isSilent ? -120 : Float(g.currentLevelDBFS)
    }

    public func updateSafety(_ s: GeneratorSafety) {
        generators.forEach { $0.updateSafety(s) }
    }
}
