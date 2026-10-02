import Foundation

public struct DelayEstimate: Equatable, Codable, Sendable {
    /// Delay of the measurement relative to the reference, in samples (sub-sample precision).
    public var samples: Double
    public var sampleRate: Double
    /// Peak-to-second-peak ratio of the GCC-PHAT function (≥ ~3 is reliable).
    public var confidence: Double
    /// Peak height relative to the correlation noise floor (dB).
    public var peakToNoiseDB: Double

    public var seconds: Double { samples / sampleRate }
    public var milliseconds: Double { seconds * 1000 }
    public func meters(celsius: Double) -> Double { Acoustics.meters(forDelaySeconds: seconds, celsius: celsius) }
    public var isReliable: Bool { confidence >= 2 && peakToNoiseDB >= 12 }
}

/// Generalized cross-correlation with phase transform (GCC-PHAT) delay finder.
public enum DelayFinder {
    /// - Parameters:
    ///   - reference: reference signal x
    ///   - measurement: measured signal y (expected to lag x)
    ///   - maxLagSeconds: search range [0, maxLag] (500 ms by default)
    ///   - band: frequency range used for the estimate (rejects LF rumble and HF noise)
    public static func estimate(reference x: [Float], measurement y: [Float], sampleRate: Double,
                                maxLagSeconds: Double = 0.5, band: ClosedRange<Double> = 100...12000,
                                backend: FFTBackend = FFT.defaultBackend) -> DelayEstimate? {
        let count = min(x.count, y.count)
        let maxLag = Int(maxLagSeconds * sampleRate)
        guard count > maxLag * 2, count >= 4096 else { return nil }
        var n = 1
        while n < 2 * count { n <<= 1 }
        let engine = FFT.make(size: n, backend: backend)
        var xr = [Double](repeating: 0, count: n), xi = xr
        var yr = xr, yi = xr
        for i in 0..<count {
            xr[i] = Double(x[i])
            yr[i] = Double(y[i])
        }
        engine.forward(re: &xr, im: &xi)
        engine.forward(re: &yr, im: &yi)
        let df = sampleRate / Double(n)
        let kLo = max(1, Int(band.lowerBound / df)), kHi = min(n / 2 - 1, Int(band.upperBound / df))
        var rr = [Double](repeating: 0, count: n), ri = rr
        for k in kLo...kHi {
            // conj(X)·Y / |conj(X)·Y|
            let cr = xr[k] * yr[k] + xi[k] * yi[k]
            let ci = xr[k] * yi[k] - xi[k] * yr[k]
            let m = (cr * cr + ci * ci).squareRoot()
            guard m > 1e-30 else { continue }
            rr[k] = cr / m
            ri[k] = ci / m
            // Hermitian mirror for a real correlation.
            rr[n - k] = rr[k]
            ri[n - k] = -ri[k]
        }
        engine.inverse(re: &rr, im: &ri)
        // Lags 0…maxLag live at the start of the circular result.
        let corr = Array(rr[0...maxLag])
        guard let (peakIndex, peak) = corr.enumerated().max(by: { $0.element < $1.element }).map({ ($0.offset, $0.element) }),
              peak > 0 else { return nil }
        let frac = Peak.parabolicOffset(corr, at: peakIndex)
        // Second peak: largest value outside ±2 ms of the main peak.
        let guardBand = max(4, Int(0.002 * sampleRate))
        var second = 0.0
        var sumSq = 0.0
        for (i, v) in corr.enumerated() {
            sumSq += v * v
            if abs(i - peakIndex) > guardBand { second = max(second, v) }
        }
        let rms = (sumSq / Double(corr.count)).squareRoot()
        return DelayEstimate(samples: Double(peakIndex) + frac, sampleRate: sampleRate,
                             confidence: second > 0 ? peak / second : .infinity,
                             peakToNoiseDB: Decibel.fromAmplitude(peak / max(rms, 1e-30)))
    }
}
