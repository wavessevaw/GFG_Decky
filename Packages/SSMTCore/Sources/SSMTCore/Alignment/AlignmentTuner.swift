import Foundation

/// Live "guitar tuner" for sub ↔ mains alignment.
///
/// While the user turns knobs on the processor, only one group changes. The other (fixed) group's
/// response was captured before, so the changing group's current response is recovered from the
/// live whole-system measurement by complex subtraction: H_changing = H_total − H_fixed. Running the
/// alignment on (fixed, changing) gives the remaining error in processor terms, several times a second.
public struct AlignmentTuner: Sendable {
    public enum Stage: String, Codable, Sendable {
        /// Mains fixed; the user adjusts the subwoofer (polarity, level and — if needed — delay).
        case adjustSub
        /// Sub fixed (already adjusted); the user adjusts the mains delay.
        case adjustMainsDelay
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
    }

    public let stage: Stage
    public let fixed: TransferFunction
    public let crossover: Double
    public let settings: AlignmentSettings
    public var tolerance: Tolerance

    /// - Parameters:
    ///   - fixed: captured response of the group that is NOT being adjusted in this stage.
    ///   - alignment: the recommendation (for the crossover / overlap band).
    public init(stage: Stage, fixed: TransferFunction, alignment: AlignmentResult, settings: AlignmentSettings,
                tolerance: Tolerance = Tolerance()) {
        self.stage = stage
        self.fixed = fixed
        crossover = alignment.crossover
        var s = settings
        // Use the same overlap band as the recommendation for consistent readings, and fine
        // resolution so the needle shows residuals smaller than the processor step.
        s.crossover = alignment.crossover
        s.levelStep = 0.1
        s.delayStep = 1 / s.sampleRate
        self.settings = s
        self.tolerance = tolerance
    }

    /// Changing group's current response recovered from a live whole-system measurement.
    public func changingResponse(live total: TransferFunction) -> TransferFunction {
        total.subtracting(fixed)
    }

    public func read(live total: TransferFunction) -> Reading? {
        guard total.frequencies == fixed.frequencies else { return nil }
        let changing = changingResponse(live: total)
        let main = stage == .adjustSub ? fixed : changing
        let sub = stage == .adjustSub ? changing : fixed
        guard let a = try? SubAlignment.align(main: main, sub: sub, settings: settings) else { return nil }

        // `a.best.delay` is the delay to add to the SUB. For the mains stage the sign flips.
        let delayError = stage == .adjustSub ? a.best.delay : -a.best.delay
        let phase = delayError * crossover * 360
        let band = (crossover / 1.5)...(crossover * 1.5)
        let coh = total.frequencies.indices
            .filter { band.contains(total.frequencies[$0]) && total.coherence[$0].isFinite }
            .map { total.coherence[$0] }.sorted()
        let confidence = coh.isEmpty ? 0 : coh[coh.count / 2]
        let levelError = stage == .adjustSub ? a.subGainDB : 0
        return Reading(delayError: delayError, delayPhaseError: phase,
                       polarityWrong: stage == .adjustSub && a.best.invertPolarity,
                       levelError: levelError,
                       delayInTune: abs(phase) <= tolerance.phaseDegrees,
                       levelInTune: abs(levelError) <= tolerance.levelDB,
                       confidence: confidence)
    }
}
