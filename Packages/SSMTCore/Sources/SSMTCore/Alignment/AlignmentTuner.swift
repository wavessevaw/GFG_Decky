import Foundation

/// Live "guitar tuner" for sub ↔ mains alignment.
///
/// While the user turns knobs on the processor, only one group changes; the other (fixed) group's
/// response was captured before. The changing group's current response is either measured directly
/// (`.changingGroupOnly`: only that group plays — the main phase-match step, most accurate) or
/// recovered from the live whole-system measurement by complex subtraction, H_changing = H_total −
/// H_fixed (`.wholeSystem`). Every reading runs the full alignment (phase match in the overlap band,
/// cycle-slip rejection by the impulse-response arrival, polarity, level) on (fixed, changing), so
/// the needle shows the real remaining error in processor terms, several times a second.
public struct AlignmentTuner: Sendable {
    public enum Stage: String, Codable, Sendable {
        /// Mains fixed; the user adjusts the subwoofer (polarity, level and — if needed — delay).
        case adjustSub
        /// Sub fixed (already adjusted); the user adjusts the mains delay.
        case adjustMainsDelay
    }

    /// What the live measurement contains.
    public enum LiveInput: String, Codable, Sendable {
        case wholeSystem, changingGroupOnly
    }

    public struct Tolerance: Equatable, Codable, Sendable {
        /// Delay is "in tune" when the phase error at the crossover is within this many degrees.
        public var phaseDegrees: Double = 10
        public var levelDB: Double = 0.5
        public init() {}
    }

    public struct Reading: Equatable, Sendable {
        /// Delay still to ADD to the adjusted group (s); negative = remove delay.
        public var delayError: Double
        /// Same error as a phase angle at the crossover (degrees), the needle position.
        public var delayPhaseError: Double
        /// True if the adjusted group's polarity must still be switched (sub only).
        public var polarityWrong: Bool
        /// Level still to ADD to the subwoofer (dB).
        public var levelError: Double
        public var delayInTune: Bool
        public var levelInTune: Bool
        public var allInTune: Bool { delayInTune && levelInTune && !polarityWrong }
        /// Median coherence of the live data in the overlap band; low → reading not trustworthy.
        public var confidence: Double
        public var isReliable: Bool { confidence >= 0.6 }
        /// Crossover used for this reading (Hz).
        public var crossover: Double = 100
        /// Mean absolute phase difference between the groups in the overlap band (degrees),
        /// before any correction — 0 when they are glued.
        public var phaseGapDegrees: Double = 0
    }

    public let stage: Stage
    public let fixed: TransferFunction
    /// Known crossover; nil = detected from the data on each reading.
    public let crossover: Double?
    public let settings: AlignmentSettings
    public let input: LiveInput
    public var tolerance: Tolerance

    /// - Parameters:
    ///   - fixed: captured response of the group that is NOT being adjusted in this stage.
    ///   - alignment: the recommendation (for the crossover / overlap band).
    public init(stage: Stage, fixed: TransferFunction, crossover: Double?, settings: AlignmentSettings,
                input: LiveInput = .wholeSystem, tolerance: Tolerance = Tolerance()) {
        self.stage = stage
        self.fixed = fixed
        self.crossover = crossover
        self.input = input
        var s = settings
        // Same overlap band on every reading, and fine resolution so the needle shows residuals
        // smaller than the processor step.
        s.crossover = crossover
        s.levelStep = 0.1
        s.delayStep = 1 / s.sampleRate
        self.settings = s
        self.tolerance = tolerance
    }

    /// - Parameters:
    ///   - fixed: captured response of the group that is NOT being adjusted in this stage.
    ///   - alignment: the recommendation (for the crossover / overlap band).
    public init(stage: Stage, fixed: TransferFunction, alignment: AlignmentResult, settings: AlignmentSettings,
                input: LiveInput = .wholeSystem, tolerance: Tolerance = Tolerance()) {
        self.init(stage: stage, fixed: fixed, crossover: alignment.crossover, settings: settings,
                  input: input, tolerance: tolerance)
    }

    /// Changing group's current response from the live measurement.
    public func changingResponse(live: TransferFunction) -> TransferFunction {
        input == .changingGroupOnly ? live : live.subtracting(fixed)
    }

    public func read(live: TransferFunction) -> Reading? {
        guard live.frequencies == fixed.frequencies else { return nil }
        let changing = changingResponse(live: live)
        let main = stage == .adjustSub ? fixed : changing
        let sub = stage == .adjustSub ? changing : fixed
        guard let a = try? SubAlignment.align(main: main, sub: sub, settings: settings) else { return nil }

        // `a.best.delay` is the delay to add to the SUB. For the mains stage the sign flips.
        let fc = a.crossover
        let delayError = stage == .adjustSub ? a.best.delay : -a.best.delay
        let phase = delayError * fc * 360
        let band = (fc / 1.5)...(fc * 1.5)
        let coh = live.frequencies.indices
            .filter { band.contains(live.frequencies[$0]) && live.coherence[$0].isFinite }
            .map { live.coherence[$0] }.sorted()
        let confidence = coh.isEmpty ? 0 : coh[coh.count / 2]
        let levelError = stage == .adjustSub ? a.subGainDB : 0
        var gaps: [Double] = []
        for i in live.frequencies.indices where a.overlapBand.contains(live.frequencies[i]) {
            let m = main.response[i], sb = sub.response[i]
            guard m.magnitude > 0, sb.magnitude > 0, m.magnitude.isFinite, sb.magnitude.isFinite else { continue }
            gaps.append(abs((sb / m).phase) * 180 / .pi)
        }
        return Reading(delayError: delayError, delayPhaseError: phase,
                       polarityWrong: stage == .adjustSub && a.best.invertPolarity,
                       levelError: levelError,
                       delayInTune: abs(phase) <= tolerance.phaseDegrees,
                       levelInTune: abs(levelError) <= tolerance.levelDB,
                       confidence: confidence, crossover: fc,
                       phaseGapDegrees: gaps.isEmpty ? 0 : gaps.reduce(0, +) / Double(gaps.count))
    }
}
