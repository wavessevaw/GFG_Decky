import Foundation

/// Dual-channel measurement result on a log frequency grid.
/// H = Gxy/Gxx (reference x → measurement y), γ² = |Gxy|²/(Gxx·Gyy).
public struct TransferFunction: Equatable, Codable, Sendable {
    public var frequencies: [Double]
    public var response: [Complex]
    public var coherence: [Double]
    /// Measurement-channel auto-spectrum density (for SNR and level estimates).
    public var measurementPower: [Double]
    /// Reference-channel auto-spectrum density.
    public var referencePower: [Double]
    /// Number of averages of the window that contributes least (quality indicator).
    public var averages: Int
    /// Reference delay (s) that was compensated before the analysis.
    public var compensatedDelay: Double

    public init(frequencies: [Double], response: [Complex], coherence: [Double],
                measurementPower: [Double], referencePower: [Double], averages: Int,
                compensatedDelay: Double = 0) {
        self.frequencies = frequencies
        self.response = response
        self.coherence = coherence
        self.measurementPower = measurementPower
        self.referencePower = referencePower
        self.averages = averages
        self.compensatedDelay = compensatedDelay
    }

    public var count: Int { frequencies.count }

    public var magnitudeDB: [Double] { response.map { Decibel.fromAmplitude($0.magnitude) } }

    /// Wrapped phase in degrees (−180…180].
    public var phaseDegrees: [Double] { response.map { $0.phase * 180 / .pi } }

    public func isValid(_ i: Int) -> Bool {
        response[i].re.isFinite && response[i].im.isFinite && coherence[i].isFinite
    }

    /// Mask of points whose coherence reaches the threshold.
    public func coherenceMask(threshold: Double) -> [Bool] {
        coherence.map { $0.isFinite && $0 >= threshold }
    }

    /// Returns a copy with an extra delay τ (s) removed from the phase: H·e^(+j2πfτ).
    public func removingDelay(_ tau: Double) -> TransferFunction {
        var copy = self
        for i in 0..<count {
            copy.response[i] = response[i] * Complex.expj(2 * .pi * frequencies[i] * tau)
        }
        copy.compensatedDelay += tau
        return copy
    }

    /// Returns a copy scaled by a linear gain and polarity.
    public func scaled(by gain: Double) -> TransferFunction {
        var copy = self
        copy.response = response.map { $0 * gain }
        return copy
    }
}
