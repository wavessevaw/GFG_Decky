import Foundation

public enum SmoothingResolution: Int, Codable, Sendable, CaseIterable {
    case none = 0
    case oct48 = 48
    case oct24 = 24
    case oct12 = 12
    case oct6 = 6
    case oct3 = 3

    /// Bandwidth in octaves (0 for none).
    public var octaves: Double { rawValue == 0 ? 0 : 1.0 / Double(rawValue) }
}

/// Fractional-octave smoothing on a log grid (rectangular window in log frequency).
public enum Smoothing {
    /// Smooths a power-like quantity (e.g. |H|²) in the linear power domain.
    /// Points that are NaN or masked out are ignored.
    public static func smoothPower(_ values: [Double], frequencies: [Double], octaves: Double,
                                   weights: [Double]? = nil) -> [Double] {
        guard octaves > 0 else { return values }
        let half = octaves / 2
        return frequencies.indices.map { i in
            let lo = frequencies[i] * pow(2, -half), hi = frequencies[i] * pow(2, half)
            var sum = 0.0, wsum = 0.0
            var j = i
            while j >= 0 && frequencies[j] >= lo { j -= 1 }
            j += 1
            while j < frequencies.count && frequencies[j] <= hi {
                let w = weights?[j] ?? 1
                if values[j].isFinite && w > 0 {
                    sum += w * values[j]
                    wsum += w
                }
                j += 1
            }
            return wsum > 0 ? sum / wsum : .nan
        }
    }

    /// Smooths a complex response: magnitude in the power domain, phase by complex averaging
    /// of unit phasors (so phase wraps are handled correctly).
    public static func smoothComplex(_ values: [Complex], frequencies: [Double], octaves: Double,
                                     weights: [Double]? = nil) -> [Complex] {
        guard octaves > 0 else { return values }
        let power = smoothPower(values.map { $0.magnitudeSquared }, frequencies: frequencies,
                                octaves: octaves, weights: weights)
        let half = octaves / 2
        // Frequencies ascend, so each window is a contiguous index range found by moving two pointers.
        var start = 0, end = 0
        return frequencies.indices.map { i in
            let lo = frequencies[i] * pow(2, -half), hi = frequencies[i] * pow(2, half)
            while start < frequencies.count && frequencies[start] < lo { start += 1 }
            if end < start { end = start }
            while end < frequencies.count && frequencies[end] <= hi { end += 1 }
            var acc = Complex.zero
            for j in start..<end {
                let v = values[j]
                let m = v.magnitude
                guard m > 0, m.isFinite else { continue }
                acc += (v / m) * (weights?[j] ?? 1)
            }
            let p = power[i]
            guard p.isFinite, acc.magnitude > 0 else { return Complex(.nan, .nan) }
            return Complex.polar(magnitude: p.squareRoot(), phase: acc.phase)
        }
    }

    public static func smooth(_ tf: TransferFunction, resolution: SmoothingResolution) -> TransferFunction {
        guard resolution != .none else { return tf }
        var out = tf
        out.response = smoothComplex(tf.response, frequencies: tf.frequencies, octaves: resolution.octaves)
        out.coherence = smoothPower(tf.coherence, frequencies: tf.frequencies, octaves: resolution.octaves)
        return out
    }
}
