import Foundation

/// Signal-to-noise estimate per grid point from a room-noise measurement and a live measurement.
public enum SNREstimator {
    /// SNR (dB) per point: (P_signal+noise − P_noise) / P_noise. NaN where undefined.
    public static func snr(measurementPower: [Double], noiseFloor: [Double]) -> [Double] {
        zip(measurementPower, noiseFloor).map { p, n in
            guard p.isFinite, n.isFinite, n > 0 else { return .nan }
            return Decibel.fromPower(max(p - n, n * 1e-6) / n)
        }
    }

    /// Median SNR over a frequency band.
    public static func medianSNR(_ snr: [Double], frequencies: [Double], band: ClosedRange<Double>) -> Double? {
        let v = frequencies.indices.filter { band.contains(frequencies[$0]) && snr[$0].isFinite }.map { snr[$0] }.sorted()
        return v.isEmpty ? nil : v[v.count / 2]
    }
}

/// Raises the test-signal level step by step until the microphone SNR reaches the target in the
/// working band, the user maximum is reached, or clipping occurs (then backs off).
public struct AutoLevelController: Sendable {
    public struct Settings: Equatable, Codable, Sendable {
        public var targetSNRDB: Double = 20
        public var band: ClosedRange<Double> = 50...12000
        public var stepDB: Double = 3
        public var clipBackoffDB: Double = 6
        public var startLevelDBFS: Double = -60
        public var maximumLevelDBFS: Double = -12
        /// Seconds to wait after each step so the live average reflects the new level.
        public var settleSeconds: Double = 2
        public init() {}
    }

    public enum Outcome: Equatable, Sendable {
        case targetReached(snrDB: Double)
        /// Maximum allowed level reached before the SNR target.
        case maximumReached(snrDB: Double)
        case clipped
    }

    public enum Decision: Equatable, Sendable {
        case setLevel(Double)
        case wait
        case finished(level: Double, outcome: Outcome)
    }

    public let settings: Settings
    public let noiseFloor: [Double]
    public let frequencies: [Double]
    public private(set) var level: Double
    private var lastChange: Double = -.infinity

    public init(settings: Settings, noiseFloor: [Double], frequencies: [Double]) {
        self.settings = settings
        self.noiseFloor = noiseFloor
        self.frequencies = frequencies
        level = settings.startLevelDBFS
    }

    /// Call periodically with the current time (s), live measurement power and clip state.
    public mutating func update(time: Double, measurementPower: [Double], clipped: Bool) -> Decision {
        if clipped {
            level = max(settings.startLevelDBFS, level - settings.clipBackoffDB)
            return .finished(level: level, outcome: .clipped)
        }
        guard time - lastChange >= settings.settleSeconds else { return .wait }
        let snr = SNREstimator.snr(measurementPower: measurementPower, noiseFloor: noiseFloor)
        let median = SNREstimator.medianSNR(snr, frequencies: frequencies, band: settings.band) ?? -.infinity
        if median >= settings.targetSNRDB {
            return .finished(level: level, outcome: .targetReached(snrDB: median))
        }
        if level >= settings.maximumLevelDBFS {
            return .finished(level: level, outcome: .maximumReached(snrDB: median))
        }
        // Step size grows when far from the target, but never above 2 steps.
        let deficit = settings.targetSNRDB - median
        let step = deficit > 2 * settings.stepDB ? settings.stepDB * 2 : settings.stepDB
        level = min(settings.maximumLevelDBFS, level + step)
        lastChange = time
        return .setLevel(level)
    }
}
