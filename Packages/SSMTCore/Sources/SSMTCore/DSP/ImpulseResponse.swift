import Foundation

public struct ImpulseResponse: Equatable, Codable, Sendable {
    public var sampleRate: Double
    /// Samples; index 0 corresponds to zero lag. Negative lags are wrapped to the end (circular IR).
    public var samples: [Double]

    public init(sampleRate: Double, samples: [Double]) {
        self.sampleRate = sampleRate
        self.samples = samples
    }

    /// IR from a linear-bin transfer function (N/2+1 bins from DC to Nyquist).
    public static func fromSpectrum(re: [Double], im: [Double], sampleRate: Double,
                                    backend: FFTBackend = FFT.defaultBackend) -> ImpulseResponse {
        let n = (re.count - 1) * 2
        let engine = FFT.make(size: n, backend: backend)
        return ImpulseResponse(sampleRate: sampleRate, samples: FFT.realInverse(re: re, im: im, engine: engine))
    }

    /// Hilbert envelope |x + j·H{x}| computed via the analytic signal.
    public func envelope(backend: FFTBackend = FFT.defaultBackend) -> [Double] {
        Hilbert.envelope(samples, backend: backend)
    }

    /// Arrival = lag of the envelope peak, with parabolic sub-sample interpolation.
    /// Lags in the second half of the buffer are reported as negative.
    public func arrivalTime(backend: FFTBackend = FFT.defaultBackend) -> Double {
        let env = envelope(backend: backend)
        guard let (k, _) = env.enumerated().max(by: { $0.element < $1.element }) else { return 0 }
        let frac = Peak.parabolicOffset(env, at: k)
        var lag = Double(k) + frac
        if lag > Double(env.count) / 2 { lag -= Double(env.count) }
        return lag / sampleRate
    }
}

public enum Hilbert {
    public static func envelope(_ x: [Double], backend: FFTBackend = FFT.defaultBackend) -> [Double] {
        var n = 1
        while n < x.count { n <<= 1 }
        let engine = FFT.make(size: max(n, 2), backend: backend)
        n = engine.size
        var re = [Double](repeating: 0, count: n)
        var im = [Double](repeating: 0, count: n)
        for i in x.indices { re[i] = x[i] }
        engine.forward(re: &re, im: &im)
        // Analytic signal: keep DC and Nyquist, double positive frequencies, zero negative ones.
        for k in 1..<(n / 2) {
            re[k] *= 2
            im[k] *= 2
        }
        for k in (n / 2 + 1)..<n {
            re[k] = 0
            im[k] = 0
        }
        engine.inverse(re: &re, im: &im)
        return (0..<x.count).map { (re[$0] * re[$0] + im[$0] * im[$0]).squareRoot() }
    }
}

public enum Peak {
    /// Sub-sample offset (−0.5…0.5) of a peak at index k via parabolic interpolation.
    public static func parabolicOffset(_ y: [Double], at k: Int) -> Double {
        let n = y.count
        guard n >= 3 else { return 0 }
        let a = y[(k - 1 + n) % n], b = y[k], c = y[(k + 1) % n]
        let den = a - 2 * b + c
        guard den != 0 else { return 0 }
        return min(max(0.5 * (a - c) / den, -0.5), 0.5)
    }
}
