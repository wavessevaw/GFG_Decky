import Foundation

public enum LoudspeakerGroup: String, Codable, Sendable { case sub, mains }

/// One parametric EQ band as entered on the processor.
public struct PEQFilter: Equatable, Codable, Sendable, Identifiable {
    public var id: Int
    public var frequency: Double
    public var gainDB: Double
    public var q: Double
    public var group: LoudspeakerGroup
    /// True if neither group clearly dominates at this frequency (warning: assigned to mains).
    public var groupAmbiguous: Bool

    public func biquad(sampleRate: Double) -> Biquad {
        Biquad.design(.peaking, frequency: frequency, q: q, gainDB: gainDB, sampleRate: sampleRate)
    }

    /// Magnitude response (dB) at f.
    public func responseDB(at f: Double, sampleRate: Double = 48000) -> Double {
        Decibel.fromAmplitude(biquad(sampleRate: sampleRate).response(at: f, sampleRate: sampleRate).magnitude)
    }
}

public struct EQSettings: Equatable, Codable, Sendable {
    public var maxBands = 8
    public var maxBoostDB = 3.0
    public var maxCutDB = 12.0
    public var minQ = 0.5
    public var maxQ = 8.0
    /// Boosts are kept broad.
    public var maxBoostQ = 2.0
    /// Stop when the remaining (broad) error is within ± this (dB).
    public var residualThresholdDB = 1.5
    /// Stop when a new band improves the weighted RMS error by less than this (dB).
    public var minImprovementDB = 0.3
    public var coherenceThreshold = 0.6
    /// Areas where the spread between points exceeds this are not corrected (room/interference).
    public var maxSpreadDB = 4.0
    public var upperLimit = 16000.0
    public var sampleRate = 48000.0
    public init() {}
}

/// Why a frequency is excluded from correction.
public enum UncorrectableReason: String, Codable, Sendable {
    case narrowDip, lowCoherence, highSpread, crossoverZone, outOfRange
}

public struct EQResult: Equatable, Codable, Sendable {
    public var frequencies: [Double]
    /// Measured (spatial average, 1/6-oct smoothed) and target (aligned to the measured level), dB.
    public var measuredDB: [Double]
    public var targetDB: [Double]
    public var filters: [PEQFilter]
    /// Measured + filters.
    public var predictedDB: [Double]
    public var workingRange: ClosedRange<Double>
    public var uncorrectable: [UncorrectableReason?]
    /// RMS deviation from target in the working range (correctable points), before / after.
    public var rmsBeforeDB: Double
    public var rmsAfterDB: Double

    public var filterResponseDB: [Double] {
        frequencies.map { f in filters.reduce(0) { $0 + $1.responseDB(at: f) } }
    }
}

/// Greedy PEQ fitting with the protective rules of spec section 7.
public enum EQFitter {
    public static func fit(average: SpatialAverage, target: TargetCurve, settings s: EQSettings = EQSettings(),
                           main: TransferFunction? = nil, sub: TransferFunction? = nil,
                           crossoverBand: ClosedRange<Double>? = nil) -> EQResult {
        let f = average.frequencies
        let n = f.count
        // 1. 1/6-octave smoothing for the calculation (energy domain, coherent points only).
        let w0 = average.coherence.map { $0.isFinite && $0 >= s.coherenceThreshold ? 1.0 : 0.0 }
        let measured = Smoothing.smoothPower(average.levelDB.map { $0.isFinite ? Decibel.toPower($0) : .nan },
                                             frequencies: f, octaves: 1.0 / 6, weights: w0).map { Decibel.fromPower($0) }
        let raw = average.levelDB

        // 2. Working range: from the low limit of the system to the HF limit (≤ 16 kHz), by level and coherence.
        let range = workingRange(f: f, measured: measured, coherenceOK: w0, target: target, settings: s)

        // 3. Target aligned to the measured level (EQ must not change the overall gain).
        let refIdx = f.indices.filter { f[$0] >= max(range.lowerBound, 200) && f[$0] <= min(range.upperBound, 4000) && measured[$0].isFinite }
        let offsets = refIdx.map { measured[$0] - target.value(at: f[$0]) }.sorted()
        let offset = offsets.isEmpty ? 0 : offsets[offsets.count / 2]
        let targetDB = f.map { target.value(at: $0) + offset }

        // 4. Uncorrectable mask.
        let broad = Smoothing.smoothPower(raw.map { $0.isFinite ? Decibel.toPower($0) : .nan }, frequencies: f,
                                          octaves: 1.0 / 3, weights: w0).map { Decibel.fromPower($0) }
        var reason = [UncorrectableReason?](repeating: nil, count: n)
        var dipCandidate = [Bool](repeating: false, count: n)
        for i in 0..<n where raw[i].isFinite && broad[i].isFinite {
            dipCandidate[i] = raw[i] < broad[i] - 3
        }
        // Dips narrower than 1/6 octave → narrowDip (not correctable by EQ).
        var i = 0
        while i < n {
            guard dipCandidate[i] else { i += 1; continue }
            let start = i
            while i < n && dipCandidate[i] { i += 1 }
            let widthOct = log2(f[i - 1] / f[start]) + 1.0 / Double(24)
            if widthOct < 1.0 / 6 {
                // Mark the dip plus a guard of one point on each side.
                for k in max(0, start - 1)...min(n - 1, i) { reason[k] = .narrowDip }
            }
        }
        for k in 0..<n {
            if !range.contains(f[k]) { reason[k] = reason[k] ?? .outOfRange; continue }
            if w0[k] == 0 { reason[k] = .lowCoherence }
            else if let sp = average.spreadDB[k] as Double?, sp.isFinite, sp > s.maxSpreadDB, reason[k] == nil { reason[k] = .highSpread }
        }

        // Group dominance per frequency (sub vs mains, > 6 dB rule).
        var dominance = [LoudspeakerGroup?](repeating: .mains, count: n)
        if let hm = main, let hs = sub, hm.frequencies == f {
            for k in 0..<n where hm.isValid(k) && hs.isValid(k) {
                let d = Decibel.fromAmplitude(hs.response[k].magnitude) - Decibel.fromAmplitude(hm.response[k].magnitude)
                dominance[k] = d > 6 ? .sub : (d < -6 ? .mains : nil)
                if dominance[k] == nil, let xb = crossoverBand, xb.contains(f[k]), reason[k] == nil {
                    reason[k] = .crossoverZone
                }
            }
        }

        // Importance weight: full weight 100 Hz–8 kHz, half outside; zero where uncorrectable.
        let weight: [Double] = (0..<n).map { k in
            guard reason[k] == nil, measured[k].isFinite else { return 0 }
            return (f[k] >= 100 && f[k] <= 8000) ? 1 : 0.5
        }
        let allowed = (0..<n).map { reason[$0] == nil }
        let dipZone = (0..<n).map { reason[$0] == .narrowDip }
        let xoZone = (0..<n).map { reason[$0] == .crossoverZone }

        var error = (0..<n).map { k in measured[k].isFinite ? targetDB[k] - measured[k] : 0 }
        func rms(_ e: [Double]) -> Double {
            var num = 0.0, den = 0.0
            for k in 0..<n where weight[k] > 0 { num += weight[k] * e[k] * e[k]; den += weight[k] }
            return den > 0 ? (num / den).squareRoot() : 0
        }
        let rmsBefore = rms(error)

        // 5. Greedy band placement.
        var filters: [PEQFilter] = []
        let logLo = log(range.lowerBound), logHi = log(range.upperBound)
        // No boosts in the half octave above the low limit (subwoofer excursion / roll-off region).
        let boostFloor = range.lowerBound * pow(2, 0.5)
        while filters.count < s.maxBands {
            let currentRMS = rms(error)
            // Broad error first (1/3 octave), so wide gentle bands are placed before narrow ones.
            let broadErr = Smoothing.smoothPower(error.map { $0 }, frequencies: f, octaves: 1.0 / 3, weights: weight)
            var bestK = -1, bestV = 0.0
            for k in 0..<n where weight[k] > 0 && broadErr[k].isFinite {
                let v = abs(broadErr[k]) * weight[k]
                if v > bestV { bestV = v; bestK = k }
            }
            // Narrow peaks (cuts) are allowed when a single point stands out much more than the broad error.
            var narrowK = -1, narrowV = 0.0
            for k in 0..<n where weight[k] > 0 && error[k] < 0 {
                let v = -error[k] * weight[k]
                if v > narrowV { narrowV = v; narrowK = k }
            }
            if narrowK >= 0 && narrowV > bestV + 3 { bestK = narrowK; bestV = narrowV }
            guard bestK >= 0, bestV >= s.residualThresholdDB else { break }

            let g0 = min(max(error[bestK], -s.maxCutDB), s.maxBoostDB)
            let q0 = bestK == narrowK && narrowV > bestV - 0.01 ? 4.0 : 1.4
            let cost: ([Double]) -> Double = { x in
                let fc = exp(x[0]), q = exp(x[1]), g = x[2]
                var penalty = 0.0
                if x[0] < logLo || x[0] > logHi { penalty += 1e3 }
                if q < s.minQ || q > s.maxQ { penalty += 1e3 }
                if g > s.maxBoostDB || g < -s.maxCutDB { penalty += 1e3 }
                if g > 0 && q > s.maxBoostQ { penalty += 1e3 }
                if g > 0 && fc < boostFloor { penalty += 1e3 }
                let b = Biquad.design(.peaking, frequency: fc, q: q, gainDB: g, sampleRate: s.sampleRate)
                var num = 0.0, den = 0.0
                for k in 0..<n {
                    let resp = Decibel.fromAmplitude(b.response(at: f[k], sampleRate: s.sampleRate).magnitude)
                    // No boost into dips or the crossover zone; no action where nothing may be corrected.
                    if resp > 0.5 && dipZone[k] { penalty += resp * 2 }
                    if abs(resp) > 1 && xoZone[k] { penalty += abs(resp) }
                    if !allowed[k] && abs(resp) > 1 && !dipZone[k] && !xoZone[k] { penalty += 0.2 * abs(resp) }
                    guard weight[k] > 0 else { continue }
                    let e = error[k] - resp
                    num += weight[k] * e * e
                    den += weight[k]
                }
                let fit = den > 0 ? num / den : 0
                // Regularization: prefer small gains and low Q ("broad and gentle").
                return fit + 0.004 * g * g + 0.02 * max(0, q - 2) * max(0, q - 2) + penalty
            }
            let start = [log(f[bestK]), log(q0), g0]
            let result = NelderMead.minimize(cost, start: start, step: [0.15, 0.4, g0 >= 0 ? 1 : -2], maxIterations: 400)
            let fc = exp(result.x[0]), q = min(max(exp(result.x[1]), s.minQ), s.maxQ)
            let g = min(max(result.x[2], -s.maxCutDB), s.maxBoostDB)
            guard result.value < 1e3 else { break }
            let b = Biquad.design(.peaking, frequency: fc, q: q, gainDB: g, sampleRate: s.sampleRate)
            let resp = f.map { Decibel.fromAmplitude(b.response(at: $0, sampleRate: s.sampleRate).magnitude) }
            let newError = (0..<n).map { error[$0] - resp[$0] }
            // Improvement is judged both globally and where the band acts (± its bandwidth), so a
            // narrow but large correction (e.g. a room mode) is not rejected for moving the
            // overall RMS only a little.
            let halfWidth = max(1 / (2 * q), 1.0 / 6)
            let local = (0..<n).filter { weight[$0] > 0 && abs(log2(f[$0] / fc)) <= halfWidth }
            func localRMS(_ e: [Double]) -> Double {
                guard !local.isEmpty else { return 0 }
                return (local.map { e[$0] * e[$0] }.reduce(0, +) / Double(local.count)).squareRoot()
            }
            let improvement = max(currentRMS - rms(newError), localRMS(error) - localRMS(newError))
            guard improvement >= s.minImprovementDB, rms(newError) <= currentRMS + 0.05 else { break }
            error = newError
            let k = f.indices.min { abs(log(f[$0] / fc)) < abs(log(f[$1] / fc)) }!
            let group: LoudspeakerGroup = dominance[k] ?? .mains
            filters.append(PEQFilter(id: filters.count + 1, frequency: fc, gainDB: g, q: q, group: group,
                                     groupAmbiguous: dominance[k] == nil))
        }

        // Rounding to sensible processor resolution.
        filters = filters.map { var x = $0
            x.frequency = x.frequency < 1000 ? x.frequency.rounded() : (x.frequency / 10).rounded() * 10
            x.gainDB = (x.gainDB * 10).rounded() / 10
            x.q = (x.q * 100).rounded() / 100
            return x
        }
        let filterDB = f.map { fr in filters.reduce(0) { $0 + $1.responseDB(at: fr, sampleRate: s.sampleRate) } }
        let predicted = (0..<n).map { measured[$0] + filterDB[$0] }
        let finalError = (0..<n).map { k in measured[k].isFinite ? targetDB[k] - predicted[k] : 0 }
        return EQResult(frequencies: f, measuredDB: measured, targetDB: targetDB, filters: filters,
                        predictedDB: predicted, workingRange: range, uncorrectable: reason,
                        rmsBeforeDB: rmsBefore, rmsAfterDB: rms(finalError))
    }

    static func workingRange(f: [Double], measured: [Double], coherenceOK: [Double], target: TargetCurve,
                             settings s: EQSettings) -> ClosedRange<Double> {
        let mid = f.indices.filter { f[$0] >= 200 && f[$0] <= 4000 && measured[$0].isFinite }
        let ref = mid.map { measured[$0] - target.value(at: f[$0]) }.sorted()
        let r = ref.isEmpty ? 0 : ref[ref.count / 2]
        func ok(_ k: Int) -> Bool {
            // The system's natural roll-offs (−6 dB below the aligned target) bound the range:
            // EQ must not try to extend the loudspeakers' bandwidth.
            measured[k].isFinite && coherenceOK[k] > 0 && measured[k] > r + target.value(at: f[k]) - 6
        }
        let start = f.indices.min { abs(f[$0] - 1000) < abs(f[$1] - 1000) } ?? 0
        var lo = start
        while lo > 0 && (ok(lo - 1) || (lo > 1 && ok(lo - 2))) && f[lo - 1] >= 20 { lo -= 1 }
        var hi = start
        while hi + 1 < f.count && f[hi + 1] <= s.upperLimit && (ok(hi + 1) || (hi + 2 < f.count && ok(hi + 2))) { hi += 1 }
        return f[lo]...f[hi]
    }
}

/// Indicative quality score 0–100 (spec 7): RMS deviation from target 63 Hz–12.5 kHz,
/// crossover dip depth, spread between points and mean coherence. A guide, not a guarantee.
public struct QualityScore: Equatable, Codable, Sendable {
    public var score: Int
    public var rmsDeviationDB: Double
    public var crossoverDipDB: Double?
    public var meanSpreadDB: Double
    public var meanCoherence: Double

    public static func compute(levelDB: [Double], targetDB: [Double], average: SpatialAverage,
                               crossoverDipDB: Double?) -> QualityScore {
        let f = average.frequencies
        let idx = f.indices.filter { f[$0] >= 63 && f[$0] <= 12500 && levelDB[$0].isFinite && targetDB[$0].isFinite }
        let dev = idx.map { levelDB[$0] - targetDB[$0] }
        let mean = dev.isEmpty ? 0 : dev.reduce(0, +) / Double(dev.count)
        let rms = dev.isEmpty ? 99 : (dev.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(dev.count)).squareRoot()
        let sp = idx.compactMap { average.spreadDB[$0].isFinite ? average.spreadDB[$0] : nil }
        let spread = sp.isEmpty ? 0 : sp.reduce(0, +) / Double(sp.count)
        let ch = idx.compactMap { average.coherence[$0].isFinite ? average.coherence[$0] : nil }
        let coh = ch.isEmpty ? 0 : ch.reduce(0, +) / Double(ch.count)
        func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
        let s1 = clamp(1 - rms / 6)
        let s2 = crossoverDipDB.map { clamp(1 - $0 / 9) } ?? 1
        let s3 = clamp(1 - (spread - 1) / 5)
        let s4 = clamp((coh - 0.5) / 0.45)
        let score = Int((100 * (0.5 * s1 + 0.2 * s2 + 0.15 * s3 + 0.15 * s4)).rounded())
        return QualityScore(score: score, rmsDeviationDB: rms, crossoverDipDB: crossoverDipDB,
                            meanSpreadDB: spread, meanCoherence: coh)
    }
}

/// Text exports of the filter list.
public enum PEQExport {
    /// "Filter Settings" style text for manual entry.
    public static func filterSettingsText(_ filters: [PEQFilter], title: String = "SSMT Filter Settings") -> String {
        var lines = [title, "Date: \(ISO8601DateFormatter().string(from: Date()))", ""]
        for group in [LoudspeakerGroup.mains, .sub] {
            let fs = filters.filter { $0.group == group }
            guard !fs.isEmpty else { continue }
            lines.append("Group: \(group == .sub ? "Subwoofers" : "Mains")")
            for (i, x) in fs.enumerated() {
                lines.append(String(format: "Filter %2d: ON  PK  Fc %7.1f Hz  Gain %+5.1f dB  Q %5.2f%@",
                                    i + 1, x.frequency, x.gainDB, x.q, x.groupAmbiguous ? "  (check group)" : ""))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public static func csv(_ filters: [PEQFilter]) -> String {
        var lines = ["group,index,type,frequency_hz,gain_db,q"]
        for group in [LoudspeakerGroup.mains, .sub] {
            for (i, x) in filters.filter({ $0.group == group }).enumerated() {
                lines.append(String(format: "%@,%d,PK,%.1f,%.1f,%.2f", group.rawValue, i + 1, x.frequency, x.gainDB, x.q))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
