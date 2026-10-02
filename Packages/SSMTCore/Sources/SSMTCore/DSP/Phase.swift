import Foundation

public enum PhaseTools {
    /// Unwraps a phase sequence in radians (NaNs are carried through and skipped).
    public static func unwrap(_ phase: [Double]) -> [Double] {
        var out = phase
        var offset = 0.0
        var last: Double?
        for i in phase.indices {
            guard phase[i].isFinite else { continue }
            if let l = last {
                var d = phase[i] - l
                while d > .pi { d -= 2 * .pi; offset -= 2 * .pi }
                while d < -.pi { d += 2 * .pi; offset += 2 * .pi }
            }
            last = phase[i]
            out[i] = phase[i] + offset
        }
        return out
    }

    /// Wraps radians into (−π, π].
    public static func wrap(_ x: Double) -> Double {
        var y = fmod(x + .pi, 2 * .pi)
        if y < 0 { y += 2 * .pi }
        return y - .pi
    }

    /// Phase in degrees after removing a pure delay τ (seconds).
    public static func delayCompensatedPhaseDegrees(_ tf: TransferFunction, delay tau: Double,
                                                    unwrapped: Bool) -> [Double] {
        let raw = tf.frequencies.indices.map { i -> Double in
            let v = tf.response[i] * Complex.expj(2 * .pi * tf.frequencies[i] * tau)
            return v.phase
        }
        let p = unwrapped ? unwrap(raw) : raw
        return p.map { $0 * 180 / .pi }
    }

    /// Estimates the residual pure delay (s) from the phase slope of coherent points
    /// in [fLow, fHigh] by weighted least squares on the unwrapped phase.
    public static func phaseSlopeDelay(_ tf: TransferFunction, from fLow: Double, to fHigh: Double,
                                       coherenceThreshold: Double = 0.8) -> Double? {
        let idx = tf.frequencies.indices.filter {
            tf.frequencies[$0] >= fLow && tf.frequencies[$0] <= fHigh &&
                tf.isValid($0) && tf.coherence[$0] >= coherenceThreshold
        }
        guard idx.count >= 4 else { return nil }
        let ph = unwrap(idx.map { tf.response[$0].phase })
        let f = idx.map { tf.frequencies[$0] }
        let n = Double(f.count)
        let mf = f.reduce(0, +) / n, mp = ph.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for i in f.indices {
            num += (f[i] - mf) * (ph[i] - mp)
            den += (f[i] - mf) * (f[i] - mf)
        }
        guard den > 0 else { return nil }
        // phase = −2π f τ
        return -(num / den) / (2 * .pi)
    }
}
