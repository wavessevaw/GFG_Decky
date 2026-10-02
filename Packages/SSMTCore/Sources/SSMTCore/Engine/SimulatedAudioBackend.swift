import Foundation

/// Virtual audio interface + virtual room. Lets the whole app (and the wizard) run without hardware.
public final class SimulatedAudioBackend: AudioIOBackend, @unchecked Sendable {
    public let sampleRate: Double
    public let inputRing: RealtimeRing
    public let outputRing: RealtimeRing
    public let generatorControl = GeneratorControl()
    public let generatorBank: GeneratorBankSpec
    public let discontinuities = AtomicCounter()
    public var displayName: String { "Simulation" }
    public private(set) var isRunning = false

    /// Round-trip latency of the virtual interface (samples).
    public let deviceLatency: Int
    public let blockSize: Int

    private let bank: GeneratorBank
    private let processor: VirtualSystemProcessor
    private var latencyLine: [Float]
    private var thread: Thread?
    private let stateLock = NSLock()
    private var stopRequested = false
    private var pendingGroups: (sub: Bool, main: Bool)?
    private var pendingProcessor: ((VirtualSystem) -> VirtualSystem)?
    /// Extra analog gain of the virtual microphone preamp (dB).
    public var micPreampDB: Double = 0

    public init(system: VirtualSystem, deviceLatency: Int = 512, blockSize: Int = 256,
                bank: GeneratorBankSpec = GeneratorBankSpec(), safety: GeneratorSafety = GeneratorSafety(),
                seed: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        sampleRate = system.sampleRate
        self.deviceLatency = deviceLatency
        self.blockSize = blockSize
        generatorBank = bank
        self.bank = GeneratorBank(spec: bank, sampleRate: system.sampleRate, safety: safety, seed: seed)
        processor = VirtualSystemProcessor(system: system, seed: seed &+ 99)
        latencyLine = [Float](repeating: 0, count: deviceLatency)
        let ringFrames = Int(system.sampleRate * 4)
        inputRing = RealtimeRing(minimumFrames: ringFrames, channels: 2)
        outputRing = RealtimeRing(minimumFrames: ringFrames, channels: 1)
    }

    public var system: VirtualSystem { processor.system }

    /// Simulates the user muting/unmuting loudspeaker groups on the processor.
    public func setActiveGroups(sub: Bool, main: Bool) {
        stateLock.lock()
        pendingGroups = (sub, main)
        stateLock.unlock()
    }

    public func updateSafety(_ s: GeneratorSafety) { bank.updateSafety(s) }

    /// Simulates entering settings on the loudspeaker processor (applied on the next block).
    public func applyProcessorChange(_ change: @escaping (VirtualSystem) -> VirtualSystem) {
        stateLock.lock()
        pendingProcessor = change
        stateLock.unlock()
    }

    /// Applies an alignment recommendation to the virtual processor: delay (to the sub, or to the
    /// mains when negative), polarity and sub level.
    public func applyAlignment(delaySeconds: Double, invertPolarity: Bool, subGainDB: Double) {
        let samples = Int((delaySeconds * sampleRate).rounded())
        applyProcessorChange { sys in
            var s = sys
            if samples >= 0 { s.sub.delaySamples += samples } else { s.main.delaySamples -= samples }
            if invertPolarity { s.sub.invertPolarity.toggle() }
            s.sub.gainDB += subGainDB
            return s
        }
    }

    /// Renders `frames` frames synchronously (used by the real-time thread and by tests).
    public func pump(frames: Int) {
        stateLock.lock()
        if let g = pendingGroups {
            processor.setEnabled(sub: g.sub, main: g.main)
            pendingGroups = nil
        }
        if let change = pendingProcessor {
            let n = change(processor.system)
            processor.updateProcessor(subDelaySamples: n.sub.delaySamples, subGainDB: n.sub.gainDB,
                                      subInverted: n.sub.invertPolarity, mainDelaySamples: n.main.delaySamples)
            pendingProcessor = nil
        }
        stateLock.unlock()

        var gen = [Float](repeating: 0, count: frames)
        gen.withUnsafeMutableBufferPointer { bank.render(into: $0.baseAddress!, count: frames, control: generatorControl) }
        latencyLine.append(contentsOf: gen)
        let delayed = Array(latencyLine[0..<frames])
        latencyLine.removeFirst(frames)
        let preamp = Float(Decibel.toAmplitude(micPreampDB))
        let mic = processor.process(delayed).map { max(-1, min(1, $0 * preamp)) }
        outputRing.write([gen])
        inputRing.write([mic, delayed])
    }

    public func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRunning else { return }
        isRunning = true
        stopRequested = false
        let t = Thread { [weak self] in self?.run() }
        t.name = "SSMT.SimulatedAudio"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    public func stop() {
        stateLock.lock()
        stopRequested = true
        isRunning = false
        stateLock.unlock()
        thread = nil
    }

    private func run() {
        let period = Double(blockSize) / sampleRate
        var next = Date().timeIntervalSinceReferenceDate
        while true {
            stateLock.lock()
            let stop = stopRequested
            stateLock.unlock()
            if stop { break }
            pump(frames: blockSize)
            next += period
            let wait = next - Date().timeIntervalSinceReferenceDate
            if wait > 0 {
                Thread.sleep(forTimeInterval: wait)
            } else if wait < -0.5 {
                // Fell far behind (debugger, sleep): resynchronise. The rendered stream itself
                // stays contiguous, so this is not a discontinuity.
                next = Date().timeIntervalSinceReferenceDate
            }
        }
    }
}
