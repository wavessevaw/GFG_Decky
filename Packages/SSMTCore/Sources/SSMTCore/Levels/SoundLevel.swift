import Foundation

public enum FrequencyWeighting: String, Codable, Sendable, CaseIterable {
    case a = "A", c = "C", z = "Z"

    /// Analytic IEC 61672-1 weighting (dB) at frequency f.
    public func analyticDB(at f: Double) -> Double {
        let f1 = 20.598997, f2 = 107.65265, f3 = 737.86223, f4 = 12194.217
        let f2sq = f * f
        switch self {
        case .z:
            return 0
        case .c:
            let r = (f4 * f4 * f2sq) / ((f2sq + f1 * f1) * (f2sq + f4 * f4))
            return 20 * log10(r) + 0.0619
        case .a:
            let r = (f4 * f4 * f2sq * f2sq) /
                ((f2sq + f1 * f1) * ((f2sq + f2 * f2) * (f2sq + f3 * f3)).squareRoot() * (f2sq + f4 * f4))
            return 20 * log10(r) + 2.0
        }
    }

    /// Digital filter (bilinear transform of the analog prototype), normalized to 0 dB at 1 kHz.
    public func biquads(sampleRate fs: Double) -> [Biquad] {
        let w1 = 2 * Double.pi * 20.598997, w2 = 2 * Double.pi * 107.65265
        let w3 = 2 * Double.pi * 737.86223, w4 = 2 * Double.pi * 12194.217
        // Analog sections as (b2, b1, b0, a2, a1, a0) in s.
        var sections: [(Double, Double, Double, Double, Double, Double)]
        switch self {
        case .z:
            return []
        case .c:
            sections = [(1, 0, 0, 1, 2 * w1, w1 * w1), (0, 0, 1, 1, 2 * w4, w4 * w4)]
        case .a:
            sections = [(1, 0, 0, 1, 2 * w1, w1 * w1), (1, 0, 0, 1, w2 + w3, w2 * w3), (0, 0, 1, 1, 2 * w4, w4 * w4)]
        }
        let k = 2 * fs
        var bq = sections.map { s -> Biquad in
            let (b2, b1, b0, a2, a1, a0) = s
            let n0 = b2 * k * k + b1 * k + b0, n1 = 2 * (b0 - b2 * k * k), n2 = b2 * k * k - b1 * k + b0
            let d0 = a2 * k * k + a1 * k + a0, d1 = 2 * (a0 - a2 * k * k), d2 = a2 * k * k - a1 * k + a0
            return Biquad(b0: n0 / d0, b1: n1 / d0, b2: n2 / d0, a1: d1 / d0, a2: d2 / d0)
        }
        let g = bq.reduce(Complex.one) { $0 * $1.response(at: 1000, sampleRate: fs) }.magnitude
        bq[0].b0 /= g; bq[0].b1 /= g; bq[0].b2 /= g
        return bq
    }
}

/// SPL calibration: digital level that corresponds to 94 dB SPL at the microphone input.
public struct SPLCalibration: Equatable, Codable, Sendable {
    public var dBFSAt94dBSPL: Double

    public init(dBFSAt94dBSPL: Double) { self.dBFSAt94dBSPL = dBFSAt94dBSPL }

    /// From an acoustic calibrator reading (RMS dBFS measured with the calibrator at `calibratorSPL`).
    public static func fromCalibrator(measuredDBFS: Double, calibratorSPL: Double = 94) -> SPLCalibration {
        SPLCalibration(dBFSAt94dBSPL: measuredDBFS - (calibratorSPL - 94))
    }

    /// From microphone sensitivity (mV/Pa) and the interface input level that reads 0 dBFS (dBV).
    public static func fromSensitivity(millivoltsPerPascal: Double, fullScaleDBV: Double) -> SPLCalibration {
        // 94 dB SPL = 1 Pa → output = sensitivity (V) → dBV = 20·log10(V); dBFS = dBV − full-scale dBV.
        let dbv = 20 * log10(millivoltsPerPascal / 1000)
        return SPLCalibration(dBFSAt94dBSPL: dbv - fullScaleDBV)
    }

    public func spl(fromDBFS dbfs: Double) -> Double { dbfs - dBFSAt94dBSPL + 94 }
}

public struct SoundLevelReading: Equatable, Codable, Sendable {
    /// Values in dB SPL if calibrated, otherwise dBFS.
    public var laeq: Double
    public var lceq: Double
    /// C-weighted peak.
    public var lpeak: Double
    /// A-weighted, Fast (125 ms) maximum.
    public var lmax: Double
    public var isCalibrated: Bool
    public var duration: Double
}

/// Integrating sound level meter (consumer side).
public struct SoundLevelMeter: Sendable {
    public let sampleRate: Double
    public var calibration: SPLCalibration?

    private var aFilter: BiquadCascade
    private var cFilter: BiquadCascade
    private var sumA = 0.0
    private var sumC = 0.0
    private var count = 0
    private var peakC = 0.0
    private var fastA = 0.0
    private var maxFastA = 0.0
    private let fastCoefficient: Double

    public init(sampleRate: Double, calibration: SPLCalibration? = nil) {
        self.sampleRate = sampleRate
        self.calibration = calibration
        aFilter = BiquadCascade(FrequencyWeighting.a.biquads(sampleRate: sampleRate))
        cFilter = BiquadCascade(FrequencyWeighting.c.biquads(sampleRate: sampleRate))
        fastCoefficient = 1 - exp(-1 / (0.125 * sampleRate))
    }

    public mutating func reset() {
        sumA = 0; sumC = 0; count = 0; peakC = 0; maxFastA = 0
    }

    public mutating func process(_ x: [Float]) {
        for v in x {
            let s = Double(v)
            let a = aFilter.process(s)
            let c = cFilter.process(s)
            sumA += a * a
            sumC += c * c
            peakC = max(peakC, abs(c))
            fastA += fastCoefficient * (a * a - fastA)
            maxFastA = max(maxFastA, fastA)
        }
        count += x.count
    }

    public func reading() -> SoundLevelReading {
        let n = Double(max(count, 1))
        // Full-scale sine = 0 dBFS RMS reference → +3.01 dB for peak-normalized RMS.
        func level(_ ms: Double) -> Double {
            let dbfs = Decibel.fromPower(ms) + 3.0103
            return calibration?.spl(fromDBFS: dbfs) ?? dbfs
        }
        let peak = Decibel.fromAmplitude(peakC)
        return SoundLevelReading(laeq: level(sumA / n), lceq: level(sumC / n),
                                 lpeak: calibration?.spl(fromDBFS: peak + 3.0103) ?? peak,
                                 lmax: level(maxFastA), isCalibrated: calibration != nil,
                                 duration: Double(count) / sampleRate)
    }
}
