import Foundation

/// Crossover-region summation metrics of a combined measurement against the separate
/// sub and mains measurements.
public struct SummationMetrics: Equatable, Codable, Sendable {
    /// Median of 20·log|H_total| − 10·log(|H_m|² + |H_s|²) in the overlap band (dB).
    /// +3 dB = perfectly coherent equal-level sum, 0 = incoherent, negative = cancellation.
    public var summationGainDB: Double
    /// Depth of the worst cancellation in the overlap band (dB, ≥ 0).
    public var dipDepthDB: Double

    public static func evaluate(total: TransferFunction, main hm: TransferFunction, sub hs: TransferFunction,
                                band: ClosedRange<Double>, coherenceThreshold: Double = 0.5) -> SummationMetrics? {
        let idx = total.frequencies.indices.filter { i in
            band.contains(total.frequencies[i]) && total.isValid(i) && hm.isValid(i) && hs.isValid(i)
                && min(hm.coherence[i], hs.coherence[i]) >= coherenceThreshold
        }
        guard idx.count >= 3 else { return nil }
        let d = idx.map { i in
            Decibel.fromAmplitude(total.response[i].magnitude)
                - Decibel.fromPower(hm.response[i].magnitudeSquared + hs.response[i].magnitudeSquared)
        }
        let sorted = d.sorted()
        return SummationMetrics(summationGainDB: sorted[sorted.count / 2], dipDepthDB: max(0, -(sorted.first ?? 0)))
    }
}

public enum VerificationVerdict: String, Codable, Sendable {
    case excellent
    case goodBut
    case checkSettings
}

/// What most likely went wrong when the verification does not match the prediction.
public enum VerificationAdvice: String, Codable, Sendable {
    case none
    case polarityNotApplied
    case delayNotApplied
    case delayWrongSign
    case levelMismatch
    case conditionsChanged
}

public struct VerificationReport: Equatable, Codable, Sendable {
    public var before: SummationMetrics?
    public var after: SummationMetrics?
    /// RMS difference between the verification and the prediction in the overlap band (dB).
    public var predictionErrorDB: Double
    public var verdict: VerificationVerdict
    public var advice: VerificationAdvice

    /// Compares the verification capture with the prediction and with the baseline.
    /// Hypotheses (settings applied as recommended / polarity missing / delay missing / delay
    /// on the wrong group) are scored against the measurement to give concrete advice.
    public static func evaluate(baseline: TransferFunction?, verification: TransferFunction,
                                main hm: TransferFunction, sub hs: TransferFunction,
                                alignment a: AlignmentResult) -> VerificationReport {
        let band = a.overlapBand
        let before = baseline.flatMap { SummationMetrics.evaluate(total: $0, main: hm, sub: hs, band: band) }
        // After the change the sub/mains references are the aligned versions.
        let alignedSub = SubAlignment.predictSum(main: hm.scaled(by: 0), sub: hs, delay: a.roundedDelay,
                                                 invertPolarity: a.best.invertPolarity, subGainDB: a.subGainDB)
        let after = SummationMetrics.evaluate(total: verification, main: hm, sub: alignedSub, band: band)

        func prediction(delay: Double, invert: Bool, gain: Double) -> TransferFunction {
            SubAlignment.predictSum(main: hm, sub: hs, delay: delay, invertPolarity: invert, subGainDB: gain)
        }
        func error(_ p: TransferFunction) -> Double {
            let idx = band.isEmpty ? [] : verification.frequencies.indices.filter {
                band.contains(verification.frequencies[$0]) && verification.isValid($0) && p.isValid($0)
                    && verification.coherence[$0] >= 0.5
            }
            guard !idx.isEmpty else { return .infinity }
            // Compare shapes: remove the mean level offset first.
            let d = idx.map { Decibel.fromAmplitude(verification.response[$0].magnitude) - Decibel.fromAmplitude(p.response[$0].magnitude) }
            let mean = d.reduce(0, +) / Double(d.count)
            return (d.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(d.count)).squareRoot()
        }
        let recommended = error(prediction(delay: a.roundedDelay, invert: a.best.invertPolarity, gain: a.subGainDB))
        let hypotheses: [(VerificationAdvice, Double)] = [
            (.polarityNotApplied, error(prediction(delay: a.roundedDelay, invert: !a.best.invertPolarity, gain: a.subGainDB))),
            (.delayNotApplied, error(prediction(delay: 0, invert: a.best.invertPolarity, gain: a.subGainDB))),
            (.delayWrongSign, error(prediction(delay: -a.roundedDelay, invert: a.best.invertPolarity, gain: a.subGainDB))),
            (.levelMismatch, error(prediction(delay: a.roundedDelay, invert: a.best.invertPolarity, gain: 0))),
        ]

        let dip = after?.dipDepthDB ?? .infinity
        var verdict: VerificationVerdict
        var advice: VerificationAdvice = .none
        if dip < 3 && recommended < 2 {
            verdict = .excellent
        } else if dip < 6 && recommended < 3 {
            verdict = .goodBut
            advice = recommended >= 2 ? .conditionsChanged : .none
        } else {
            verdict = .checkSettings
            let bestHypothesis = hypotheses.filter { abs(a.roundedDelay) > 1e-6 || $0.0 != .delayNotApplied && $0.0 != .delayWrongSign }
                .min { $0.1 < $1.1 }
            if let h = bestHypothesis, h.1 < recommended * 0.7 {
                advice = h.0
            } else {
                advice = .conditionsChanged
            }
        }
        return VerificationReport(before: before, after: after, predictionErrorDB: recommended,
                                  verdict: verdict, advice: advice)
    }
}

extension TransferFunction {
    /// Complex difference H − other (fast mode: H_mains = H_total − H_sub). Coherence is the
    /// minimum of both, since the estimate is only as good as the weaker measurement.
    public func subtracting(_ other: TransferFunction) -> TransferFunction {
        precondition(frequencies == other.frequencies)
        var out = self
        for i in frequencies.indices {
            out.response[i] = response[i] - other.response[i]
            out.coherence[i] = min(coherence[i], other.coherence[i])
        }
        return out
    }
}
