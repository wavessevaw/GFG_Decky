import Foundation

/// Paul Kellet's refined pink filter (−3 dB/oct within ±0.05 dB above ~10 Hz at 44.1/48 kHz),
/// normalized to unit RMS for unit-variance Gaussian input.
public struct PinkFilter: Sendable {
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
    private let normalization: Double

    public init() {
        self.init(rawNormalization: PinkFilter.unitRMSNormalization)
    }

    private init(rawNormalization: Double) {
        normalization = rawNormalization
    }

    /// Measured once, lazily, over a deterministic noise run (never on the audio thread
    /// as long as a PinkFilter is created before streaming starts).
    private static let unitRMSNormalization: Double = {
        var probe = PinkFilter(rawNormalization: 1)
        var rng = RandomSource(seed: 0x5EED_1234)
        var sumSq = 0.0
        let count = 1 << 18, skip = 4096
        for i in 0..<count {
            let v = probe.process(rng.nextGaussian())
            if i >= skip { sumSq += v * v }
        }
        return 1 / (sumSq / Double(count - skip)).squareRoot()
    }()

    @inline(__always)
    public mutating func process(_ white: Double) -> Double {
        b0 = 0.99886 * b0 + white * 0.0555179
        b1 = 0.99332 * b1 + white * 0.0750759
        b2 = 0.96900 * b2 + white * 0.1538520
        b3 = 0.86650 * b3 + white * 0.3104856
        b4 = 0.55000 * b4 + white * 0.5329522
        b5 = -0.7616 * b5 - white * 0.0168980
        let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
        b6 = white * 0.115926
        return pink * normalization
    }
}

/// One period of periodic pink noise built in the frequency domain:
/// magnitude ∝ 1/√f (exact −3 dB/oct on every bin), random phase, unit RMS.
/// With an FFT length equal to the period, leakage is zero and synchronous averaging is possible.
public enum PeriodicNoise {
    public static func pinkPeriod(length n: Int, sampleRate: Double, seed: UInt64,
                                  lowCut: Double = 10, highCut: Double? = nil,
                                  backend: FFTBackend = FFT.defaultBackend) -> [Double] {
        precondition(n >= 16 && n & (n - 1) == 0)
        var rng = RandomSource(seed: seed)
        let df = sampleRate / Double(n)
        let fHigh = highCut ?? sampleRate / 2
        var re = [Double](repeating: 0, count: n / 2 + 1)
        var im = [Double](repeating: 0, count: n / 2 + 1)
        for k in 1..<(n / 2) {
            let f = Double(k) * df
            guard f >= lowCut, f <= fHigh else { continue }
            let mag = 1 / f.squareRoot()
            let ph = 2 * Double.pi * rng.nextUniform()
            re[k] = mag * cos(ph)
            im[k] = mag * sin(ph)
        }
        var x = FFT.realInverse(re: re, im: im, engine: FFT.make(size: n, backend: backend))
        let rms = (x.reduce(0) { $0 + $1 * $1 } / Double(n)).squareRoot()
        if rms > 0 { x = x.map { $0 / rms } }
        return x
    }
}
