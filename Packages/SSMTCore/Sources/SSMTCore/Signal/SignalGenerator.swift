import Foundation

public enum NoiseKind: Equatable, Codable, Sendable {
    /// Random (non-periodic) pink noise — default; required for meaningful coherence.
    case pink
    case white
    /// Pink noise restricted to [low, high] Hz with 24 dB/oct slopes.
    case bandLimitedPink(low: Double, high: Double)
    /// Periodic pink noise whose period equals the FFT length (fast mode, no coherence).
    case periodicPink(periodLength: Int)
}

public struct GeneratorSafety: Equatable, Codable, Sendable {
    /// Level at which the generator starts after a fade-in (dBFS RMS).
    public var startLevelDBFS: Double = -60
    /// Absolute maximum level set by the user (dBFS RMS). Targets above are clamped.
    public var maximumLevelDBFS: Double = -12
    /// Brick-wall peak ceiling (dBFS).
    public var peakCeilingDBFS: Double = -1
    public var fadeInSeconds: Double = 2
    public var fadeOutSeconds: Double = 0.1
    /// Maximum upward level slew (dB/s); downward changes are fast.
    public var maxRiseDBPerSecond: Double = 3
    public var maxFallDBPerSecond: Double = 120

    public init() {}
}

/// Real-time safe test-signal generator: no allocation, locking or I/O inside `render`.
/// The output buffer it produces is the exact signal sent to the DAC, so it doubles
/// as the internal reference (reference mode B).
public final class SignalGenerator {
    public let kind: NoiseKind
    public let sampleRate: Double
    public private(set) var safety: GeneratorSafety

    private var rng: RandomSource
    private var pink = PinkFilter()
    private var bandFilter: BiquadCascade?
    private var bandNormalization = 1.0
    private let periodTable: [Double]
    private var periodIndex = 0

    private var fade = 0.0
    private var levelDB: Double
    private var limiterGain = 1.0
    private let limiterRelease: Double

    public init(kind: NoiseKind, sampleRate: Double, seed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000),
                safety: GeneratorSafety = GeneratorSafety()) {
        self.kind = kind
        self.sampleRate = sampleRate
        self.safety = safety
        rng = RandomSource(seed: seed)
        levelDB = safety.startLevelDBFS
        limiterRelease = exp(-1 / (0.05 * sampleRate))
        switch kind {
        case .periodicPink(let n):
            periodTable = PeriodicNoise.pinkPeriod(length: n, sampleRate: sampleRate, seed: seed)
        case .bandLimitedPink(let lo, let hi):
            periodTable = []
            bandFilter = BiquadCascade(
                CrossoverFilter.linkwitzRiley24(.highPass, frequency: lo, sampleRate: sampleRate) +
                    CrossoverFilter.linkwitzRiley24(.lowPass, frequency: min(hi, sampleRate * 0.45), sampleRate: sampleRate))
            bandNormalization = SignalGenerator.measureBandNormalization(low: lo, high: hi, sampleRate: sampleRate)
        default:
            periodTable = []
        }
    }

    /// Current output level (dBFS RMS of the source before fade), for display.
    public var currentLevelDBFS: Double { levelDB }
    public var isSilent: Bool { fade <= 0 }

    public func updateSafety(_ s: GeneratorSafety) { safety = s }

    /// Immediately silences the generator and resets the level to the start level.
    public func hardMute() {
        fade = 0
        levelDB = safety.startLevelDBFS
        limiterGain = 1
    }

    /// Renders `count` samples.
    /// - Parameters:
    ///   - run: true to play (fade in / stay on), false to fade out.
    ///   - targetLevelDBFS: desired RMS level; clamped to the safety maximum and slew-limited.
    public func render(into out: UnsafeMutablePointer<Float>, count: Int, run: Bool, targetLevelDBFS: Double) {
        let fs = sampleRate
        let target = min(targetLevelDBFS, safety.maximumLevelDBFS)
        // Level slew is applied per block with linear interpolation of the gain inside the block.
        let dt = Double(count) / fs
        let startDB = levelDB
        if target > levelDB {
            levelDB = min(target, levelDB + safety.maxRiseDBPerSecond * dt)
        } else {
            levelDB = max(target, levelDB - safety.maxFallDBPerSecond * dt)
        }
        let g0 = Decibel.toAmplitude(startDB), g1 = Decibel.toAmplitude(levelDB)
        let fadeStep = run ? 1 / max(safety.fadeInSeconds * fs, 1) : -1 / max(safety.fadeOutSeconds * fs, 1)
        let ceiling = Decibel.toAmplitude(safety.peakCeilingDBFS)
        let invCount = 1.0 / Double(max(count, 1))

        for i in 0..<count {
            fade = min(1, max(0, fade + fadeStep))
            if fade <= 0 {
                out[i] = 0
                continue
            }
            let g = g0 + (g1 - g0) * Double(i + 1) * invCount
            // Raised-cosine fade curve for a smooth start.
            let f = 0.5 - 0.5 * cos(Double.pi * fade)
            var x = nextSource() * g * f
            // Peak limiter: instant attack (guarantees the ceiling), exponential release.
            let a = abs(x)
            let needed = a > ceiling ? ceiling / a : 1
            limiterGain = min(needed, 1 - (1 - limiterGain) * limiterRelease)
            x *= limiterGain
            out[i] = Float(x)
        }
        if !run && fade <= 0 {
            levelDB = safety.startLevelDBFS
        }
    }

    /// Convenience for tests and offline simulation.
    public func render(count: Int, run: Bool = true, targetLevelDBFS: Double) -> [Float] {
        var buf = [Float](repeating: 0, count: count)
        buf.withUnsafeMutableBufferPointer { render(into: $0.baseAddress!, count: count, run: run, targetLevelDBFS: targetLevelDBFS) }
        return buf
    }

    @inline(__always)
    private func nextSource() -> Double {
        switch kind {
        case .pink:
            return pink.process(rng.nextGaussian())
        case .white:
            return rng.nextGaussian()
        case .bandLimitedPink:
            return bandFilter!.process(pink.process(rng.nextGaussian())) * bandNormalization
        case .periodicPink:
            let v = periodTable[periodIndex]
            periodIndex += 1
            if periodIndex == periodTable.count { periodIndex = 0 }
            return v
        }
    }

    private static func measureBandNormalization(low: Double, high: Double, sampleRate: Double) -> Double {
        var p = PinkFilter()
        var rng = RandomSource(seed: 42)
        var f = BiquadCascade(CrossoverFilter.linkwitzRiley24(.highPass, frequency: low, sampleRate: sampleRate) +
            CrossoverFilter.linkwitzRiley24(.lowPass, frequency: min(high, sampleRate * 0.45), sampleRate: sampleRate))
        var sum = 0.0
        let n = 1 << 18, skip = 1 << 14
        for i in 0..<n {
            let v = f.process(p.process(rng.nextGaussian()))
            if i >= skip { sum += v * v }
        }
        let rms = (sum / Double(n - skip)).squareRoot()
        return rms > 0 ? 1 / rms : 1
    }
}
