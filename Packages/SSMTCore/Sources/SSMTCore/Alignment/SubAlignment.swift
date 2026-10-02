import Foundation

/// Settings for the sub ↔ mains alignment (spec section 6).
public struct AlignmentSettings: Equatable, Codable, Sendable {
    /// Known crossover frequency (Hz); nil → detected automatically in 50–200 Hz.
    public var crossover: Double?
    public var coherenceThreshold: Double = 0.6
    /// Points whose sub/mains levels differ by more than this are not used (dB).
    public var maxLevelDifferenceDB: Double = 12
    /// Fine search range ± (s).
    public var searchRange: Double = 0.030
    /// Two solutions closer than this (relative J difference) are reported as ambiguous.
    public var ambiguityThreshold: Double = 0.10
    /// Processor delay resolution (s), e.g. 0.00001 = 0.01 ms.
    public var delayStep: Double = 0.00001
    /// Processor level resolution (dB).
    public var levelStep: Double = 0.5
    public var sampleRate: Double = 48000

    public init(crossover: Double? = nil) { self.crossover = crossover }
}

/// One candidate solution of the fine search.
public struct AlignmentCandidate: Equatable, Codable, Sendable {
    /// Delay to apply to the subwoofer (s). Negative → delay the mains by |delay| instead.
    public var delay: Double
    public var invertPolarity: Bool
    /// Quality J in the overlap band (1 = no interaction on average, 2 = perfect coherent sum).
    public var quality: Double
    /// Quality over the extended band (overlap ± 1 octave), used to resolve cycle slips.
    public var extendedQuality: Double
}

public struct AlignmentResult: Equatable, Codable, Sendable {
    public var best: AlignmentCandidate
    /// Other candidates within the ambiguity threshold (shown to the user as alternatives).
    public var alternatives: [AlignmentCandidate]
    /// Near-equal solutions discarded because their timing contradicts the IR arrival (expert view).
    public var rejectedCycleSlips: [AlignmentCandidate]
    public var isAmbiguous: Bool
    /// Delay rounded to the processor step (s).
    public var roundedDelay: Double
    /// Sub level change (dB), rounded to the processor step.
    public var subGainDB: Double
    public var overlapBand: ClosedRange<Double>
    public var crossover: Double
    public var crossoverWasDetected: Bool
    /// Coarse estimate from band-limited impulse responses (s), sub delay convention.
    public var coarseDelay: Double?
    public var pointsUsed: Int

    /// Who gets the delay on the processor.
    public enum DelayTarget: String, Codable, Sendable { case sub, mains, none }
    public var delayTarget: DelayTarget {
        if abs(roundedDelay) < 1e-9 { return .none }
        return roundedDelay > 0 ? .sub : .mains
    }
}

public enum SubAlignmentError: Error, Equatable {
    case notEnoughCoherentPoints(Int)
    case noOverlap
}

/// Sub ↔ mains alignment: overlap detection, coarse IR estimate, exhaustive (τ, polarity) search,
/// cycle-slip resolution, level match, rounding and summation prediction.
public enum SubAlignment {
    public static func align(main hm: TransferFunction, sub hs: TransferFunction,
                             settings s: AlignmentSettings) throws -> AlignmentResult {
        precondition(hm.frequencies == hs.frequencies, "Both measurements must share one grid")
        // 1. Overlap band.
        let (fc, detected) = s.crossover.map { ($0, false) } ?? (detectCrossover(main: hm, sub: hs, settings: s), true)
        let band = s.crossover != nil ? (fc / 1.5)...(fc * 1.5) : (fc / pow(2, 0.5))...(fc * pow(2, 0.5))
        let usable = usablePoints(main: hm, sub: hs, band: band, settings: s)
        guard usable.count >= 4 else { throw SubAlignmentError.notEnoughCoherentPoints(usable.count) }
        // Extended band for cycle-slip checks: wider and without the level-difference limit.
        var extSettings = s
        extSettings.maxLevelDifferenceDB = 30
        let extended = usablePoints(main: hm, sub: hs, band: (band.lowerBound / 2)...(band.upperBound * 2),
                                    settings: extSettings)

        // 2. Coarse estimate from band-limited impulse responses.
        let coarse = coarseDelay(main: hm, sub: hs, indices: usable, band: band)

        // 3. Exhaustive search of τ (1-sample step) and polarity.
        let step = 1 / s.sampleRate
        let n = Int((s.searchRange / step).rounded())
        var curves: [Bool: [Double]] = [:]
        for invert in [false, true] {
            curves[invert] = (-n...n).map { k in
                quality(main: hm, sub: hs, indices: usable, delay: Double(k) * step, invert: invert)
            }
        }

        // 4. Local maxima → candidates; resolve cycle slips with the extended band.
        var candidates: [AlignmentCandidate] = []
        for invert in [false, true] {
            let j = curves[invert]!
            for i in j.indices {
                let left = i > 0 ? j[i - 1] : -.infinity
                let right = i + 1 < j.count ? j[i + 1] : -.infinity
                guard j[i] >= left && j[i] > right else { continue }
                // Sub-sample refinement of the maximum.
                let frac = (i > 0 && i + 1 < j.count) ? Peak.parabolicOffset(j, at: i) : 0
                let tau = (Double(i - n) + frac) * step
                candidates.append(AlignmentCandidate(
                    delay: tau, invertPolarity: invert, quality: j[i],
                    extendedQuality: quality(main: hm, sub: hs, indices: extended.isEmpty ? usable : extended,
                                             delay: tau, invert: invert)))
            }
        }
        guard let topJ = candidates.map(\.quality).max() else { throw SubAlignmentError.noOverlap }
        // Contenders: everything within the ambiguity threshold of the best J in the overlap band.
        let contenders = candidates.filter { (topJ - $0.quality) / topJ < s.ambiguityThreshold }
            .sorted { $0.extendedQuality > $1.extendedQuality }
        // In a narrow overlap band J is nearly periodic: "inverted at τ" and "normal at τ ± half a
        // period" score within a few percent. The band-limited IR arrival (coarse estimate) is accurate
        // to well under a quarter period, so contenders farther than that are cycle slips, not
        // genuine alternatives. Only when the timing cannot separate them is the result ambiguous.
        let window = 0.25 / fc
        let near = coarse.map { c in contenders.filter { abs($0.delay - c) <= window } } ?? []
        let pool = near.isEmpty ? contenders : near
        let best = pool.max { $0.quality < $1.quality }!
        let alternatives = Array(pool.filter { $0 != best }.prefix(3))
        let rejected = contenders.filter { c in !pool.contains(c) }

        // 5. Level. With a known crossover: match median magnitudes in the overlap band (spec).
        // With an auto-detected crossover that band is centred on the equal-level point by
        // construction, so the medians always match; use the adjacent pass bands instead
        // (one octave below / above the crossover).
        let gain: Double
        if s.crossover != nil {
            gain = median(usable.map { Decibel.fromAmplitude(hm.response[$0].magnitude) })
                - median(usable.map { Decibel.fromAmplitude(hs.response[$0].magnitude) })
        } else {
            gain = passbandLevel(hm, band: (fc * 2)...(fc * 4), settings: s)
                - passbandLevel(hs, band: (fc / 4)...(fc / 2), settings: s)
        }

        // 6. Rounding to processor resolution.
        let roundedDelay = (best.delay / s.delayStep).rounded() * s.delayStep
        let roundedGain = (gain / s.levelStep).rounded() * s.levelStep

        return AlignmentResult(best: best, alternatives: alternatives, rejectedCycleSlips: Array(rejected.prefix(3)),
                               isAmbiguous: !alternatives.isEmpty,
                               roundedDelay: roundedDelay, subGainDB: roundedGain, overlapBand: band,
                               crossover: fc, crossoverWasDetected: detected, coarseDelay: coarse,
                               pointsUsed: usable.count)
    }

    /// 7. Predicted combined response |H_m + p·g·H_s·e^(−j2πfτ)| (τ < 0 delays the mains instead,
    /// which yields the same magnitude).
    public static func predictSum(main hm: TransferFunction, sub hs: TransferFunction, delay: Double,
                                  invertPolarity: Bool, subGainDB: Double) -> TransferFunction {
        var out = hm
        let g = Decibel.toAmplitude(subGainDB) * (invertPolarity ? -1 : 1)
        for i in hm.frequencies.indices {
            let rot = Complex.expj(-2 * .pi * hm.frequencies[i] * delay)
            out.response[i] = hm.response[i] + hs.response[i] * rot * g
            out.coherence[i] = min(hm.coherence[i], hs.coherence[i])
        }
        return out
    }

    // MARK: - Steps

    /// Frequency in 50–200 Hz where the (1/6-oct smoothed) sub and mains curves cross,
    /// sub dominant below. Falls back to the point of minimum level difference.
    public static func detectCrossover(main hm: TransferFunction, sub hs: TransferFunction,
                                       settings s: AlignmentSettings) -> Double {
        let f = hm.frequencies
        let w = zip(hm.coherence, hs.coherence).map { min($0, $1) >= s.coherenceThreshold ? 1.0 : 0.0 }
        let pm = Smoothing.smoothPower(hm.response.map(\.magnitudeSquared), frequencies: f, octaves: 1.0 / 6, weights: w)
        let ps = Smoothing.smoothPower(hs.response.map(\.magnitudeSquared), frequencies: f, octaves: 1.0 / 6, weights: w)
        let idx = f.indices.filter { f[$0] >= 50 && f[$0] <= 200 && pm[$0].isFinite && ps[$0].isFinite && pm[$0] > 0 && ps[$0] > 0 }
        guard !idx.isEmpty else { return 100 }
        let diff = idx.map { Decibel.fromPower(ps[$0]) - Decibel.fromPower(pm[$0]) }
        for k in 1..<max(diff.count, 1) where diff[k - 1] > 0 && diff[k] <= 0 {
            // Linear interpolation of the zero crossing in log frequency.
            let t = diff[k - 1] / (diff[k - 1] - diff[k])
            return f[idx[k - 1]] * pow(f[idx[k]] / f[idx[k - 1]], t)
        }
        let k = diff.indices.min { abs(diff[$0]) < abs(diff[$1]) }!
        return f[idx[k]]
    }

    static func usablePoints(main hm: TransferFunction, sub hs: TransferFunction, band: ClosedRange<Double>,
                             settings s: AlignmentSettings) -> [Int] {
        hm.frequencies.indices.filter { i in
            guard band.contains(hm.frequencies[i]), hm.isValid(i), hs.isValid(i),
                  hm.coherence[i] >= s.coherenceThreshold, hs.coherence[i] >= s.coherenceThreshold else { return false }
            let dm = Decibel.fromAmplitude(hm.response[i].magnitude)
            let ds = Decibel.fromAmplitude(hs.response[i].magnitude)
            return abs(dm - ds) <= s.maxLevelDifferenceDB
        }
    }

    /// J(τ, p) = Σ w·|H_m + p·H_s·e^(−j2πfτ)|² / (|H_m|² + |H_s|²) / Σ w, w = γ² (the grid is already
    /// uniform in log frequency, so each point carries equal log-frequency weight).
    static func quality(main hm: TransferFunction, sub hs: TransferFunction, indices: [Int],
                        delay tau: Double, invert: Bool) -> Double {
        var num = 0.0, wsum = 0.0
        let p = invert ? -1.0 : 1.0
        for i in indices {
            let w = min(hm.coherence[i], hs.coherence[i])
            let m = hm.response[i], sv = hs.response[i]
            let sum = m + sv * Complex.expj(-2 * .pi * hm.frequencies[i] * tau) * p
            let den = m.magnitudeSquared + sv.magnitudeSquared
            guard den > 0 else { continue }
            num += w * sum.magnitudeSquared / den
            wsum += w
        }
        return wsum > 0 ? num / wsum : 0
    }

    /// Coarse sub delay from the envelope peaks of band-limited impulse responses
    /// (non-uniform inverse DFT over the grid points of the overlap band; positive
    /// frequencies only → the result is the analytic signal, its magnitude the envelope).
    static func coarseDelay(main hm: TransferFunction, sub hs: TransferFunction, indices: [Int],
                            band: ClosedRange<Double>) -> Double? {
        guard indices.count >= 4 else { return nil }
        let f = hm.frequencies
        let lo = log2(band.lowerBound), hi = log2(band.upperBound)
        var taps: [(f: Double, df: Double, w: Double)] = []
        for (k, i) in indices.enumerated() {
            let fPrev = k > 0 ? f[indices[k - 1]] : f[i] / pow(2, 1.0 / 24)
            let x = (log2(f[i]) - lo) / (hi - lo)
            taps.append((f[i], f[i] - fPrev, 0.5 - 0.5 * cos(2 * .pi * min(max(x, 0), 1))))
        }
        func arrival(_ h: TransferFunction) -> Double {
            var bestT = 0.0, bestE = -1.0
            let dt = 0.0002
            var t = -0.08
            while t <= 0.08 {
                var acc = Complex.zero
                for (n, i) in indices.enumerated() {
                    acc += h.response[i] * Complex.expj(2 * .pi * taps[n].f * t) * (taps[n].w * taps[n].df)
                }
                let e = acc.magnitude
                if e > bestE { bestE = e; bestT = t }
                t += dt
            }
            return bestT
        }
        return arrival(hm) - arrival(hs)
    }

    static func passbandLevel(_ h: TransferFunction, band: ClosedRange<Double>, settings s: AlignmentSettings) -> Double {
        let v = h.frequencies.indices.filter { band.contains(h.frequencies[$0]) && h.isValid($0) && h.coherence[$0] >= s.coherenceThreshold }
            .map { Decibel.fromAmplitude(h.response[$0].magnitude) }
        return median(v)
    }

    static func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : 0.5 * (s[s.count / 2 - 1] + s[s.count / 2])
    }
}
