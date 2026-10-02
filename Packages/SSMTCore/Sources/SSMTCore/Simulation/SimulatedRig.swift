import Foundation

/// Offline/real-time simulation of the full measurement chain:
/// generator → interface output → (loopback cable | virtual system) → interface inputs.
/// Device latency applies equally to both input channels, exactly like a real interface.
public final class SimulatedRig {
    public let sampleRate: Double
    public let generator: SignalGenerator
    public let processor: VirtualSystemProcessor
    /// Round-trip latency of the virtual interface (samples).
    public let deviceLatency: Int

    private var latencyLine: [Float]

    public struct Block {
        /// Exactly what was sent to the output (internal reference, mode B).
        public var generated: [Float]
        /// Loopback input (hardware reference, mode A).
        public var loopback: [Float]
        /// Measurement microphone input.
        public var microphone: [Float]
    }

    public init(system: VirtualSystem, noise: NoiseKind = .pink, deviceLatency: Int = 256,
                seed: UInt64 = 1, safety: GeneratorSafety = GeneratorSafety()) {
        sampleRate = system.sampleRate
        generator = SignalGenerator(kind: noise, sampleRate: system.sampleRate, seed: seed, safety: safety)
        processor = VirtualSystemProcessor(system: system, seed: seed &+ 1)
        self.deviceLatency = deviceLatency
        latencyLine = [Float](repeating: 0, count: deviceLatency)
    }

    public func render(count: Int, run: Bool = true, levelDBFS: Double = -20) -> Block {
        let gen = generator.render(count: count, run: run, targetLevelDBFS: levelDBFS)
        latencyLine.append(contentsOf: gen)
        let delayed = Array(latencyLine[0..<count])
        latencyLine.removeFirst(count)
        let mic = processor.process(delayed).map { max(-1, min(1, $0)) }
        return Block(generated: gen, loopback: delayed, microphone: mic)
    }
}
