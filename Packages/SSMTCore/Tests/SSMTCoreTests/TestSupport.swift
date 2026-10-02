import Foundation
@testable import SSMTCore

enum TestSignals {
    /// Runs a simulated rig through an analyzer for `seconds` and returns the snapshot.
    /// The analyzer reference (mode B) is delayed by the device latency plus `extraDelay` samples.
    static func measure(system: VirtualSystem, seconds: Double, config: MultiWindowConfig? = nil,
                        referenceDelay: Int? = nil, level: Double = -20, seed: UInt64 = 1,
                        noise: NoiseKind = .pink, blockSize: Int = 4800) -> TransferFunction {
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 0.001
        safety.startLevelDBFS = level
        safety.maximumLevelDBFS = 0
        safety.peakCeilingDBFS = 0
        let rig = SimulatedRig(system: system, noise: noise, deviceLatency: 128, seed: seed, safety: safety)
        let analyzer = MultiWindowAnalyzer(config: config ?? .standard(sampleRate: system.sampleRate))
        analyzer.setReferenceDelay(samples: referenceDelay ?? (128 + system.main.delaySamples))
        // Settle the generator and fill the system's delay lines before analysis.
        _ = rig.render(count: 48000, levelDBFS: level)
        let total = Int(seconds * system.sampleRate)
        var done = 0
        while done < total {
            let n = min(blockSize, total - done)
            let b = rig.render(count: n, levelDBFS: level)
            analyzer.ingest(reference: b.generated, measurement: b.microphone)
            done += n
        }
        return analyzer.snapshot()
    }

    static func rms(_ x: [Float]) -> Double {
        (x.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(x.count, 1))).squareRoot()
    }
}
