import Foundation

public struct WizardConfiguration: Equatable, Codable, Sendable {
    public var hasSubwoofer = true
    /// Known crossover frequency; nil = detect automatically.
    public var crossover: Double?
    /// Legacy option from earlier versions (derive the mains as "whole system − subs"); the
    /// phase-match flow always measures the satellites and the subs separately.
    public var fastMode = false
    public var captureSeconds: Double = 12
    public var delayStep: Double = 0.00001
    public var levelStep: Double = 0.5
    public var temperatureCelsius: Double = 20
    public var coherenceThreshold: Double = 0.6
    public var sampleRate: Double = 48000
    /// Zone-averaged EQ (spec 5, steps 6–7).
    public var eqPointCount = 5
    public var target = TargetCurve.preset(.livePA)
    public var eq = EQSettings()
    /// Consecutive EQ iterations allowed before suggesting to stop (spec 7).
    public var maxEQIterations = 2

    public init() {}

    public var alignmentSettings: AlignmentSettings {
        var s = AlignmentSettings(crossover: crossover)
        s.coherenceThreshold = coherenceThreshold
        s.delayStep = delayStep
        s.levelStep = levelStep
        s.sampleRate = sampleRate
        return s
    }
}

/// Wizard steps. Raw values are stored in session files and stay fixed; the order in which the
/// alignment captures are taken is defined by `SetupWizard` (mains → subs → whole system), not by
/// the raw values.
public enum WizardStep: Int, Codable, Sendable, CaseIterable, Comparable {
    case preparation = 0
    case baseline
    case subOnly
    case mainsOnly
    case results
    case verification
    case eqPoints
    case eqTuning
    case eqVerification
    case finished

    public static func < (a: WizardStep, b: WizardStep) -> Bool { a.rawValue < b.rawValue }

    /// One of the three captures for the sub ↔ mains alignment.
    public var isAlignmentCapture: Bool { self == .mainsOnly || self == .subOnly || self == .baseline }

    /// Band in which the capture quality (coherence) is judged for this step.
    public func qualityBand(crossover: Double?) -> ClosedRange<Double> {
        let fc = crossover ?? 100
        switch self {
        case .subOnly: return 30...(fc * 1.5)
        case .mainsOnly: return (fc / 1.5)...16000
        default: return 40...16000
        }
    }

    /// Which loudspeaker groups must be on during this step's capture.
    public var requiredGroups: (sub: Bool, mains: Bool)? {
        switch self {
        case .baseline, .verification, .eqPoints, .eqVerification: return (true, true)
        case .subOnly: return (true, false)
        case .mainsOnly: return (false, true)
        default: return nil
        }
    }
}

/// Plain-language action derived from the alignment (what the user enters on the processor).
public enum ActionCard: Equatable, Codable, Sendable {
    /// Delay for the subwoofer group (s) and its equivalent distance (m).
    case delaySub(seconds: Double, meters: Double)
    /// The subs arrive late: delay the mains instead.
    case delayMains(seconds: Double, meters: Double)
    case noDelayChange
    case polarity(invert: Bool)
    /// Level change for the subwoofer group (dB).
    case subLevel(dB: Double)
}

public enum CaptureAcceptance: Equatable, Sendable {
    case accepted(CaptureQuality)
    case rejected([CaptureAssessment.Reason])
    /// The audio stream restarted since the delay was locked: lock again and repeat captures.
    case streamRestarted
}

/// State of the automatic setup wizard (steps 0–5). Pure value type: the UI layer performs the
/// captures with `MeasurementEngine` and feeds them here; all decisions are made and tested here.
public struct SetupWizard: Codable, Sendable {
    public var configuration: WizardConfiguration
    public private(set) var step: WizardStep = .preparation

    public private(set) var delayLock: DelayEstimate?
    public private(set) var lockEpoch: UInt64?
    public private(set) var baseline: Capture?
    public private(set) var subOnly: Capture?
    public private(set) var mainsOnly: Capture?
    public private(set) var verification: Capture?
    public private(set) var alignment: AlignmentResult?
    public private(set) var alignmentError: String?
    public private(set) var prediction: TransferFunction?
    public private(set) var report: VerificationReport?

    // EQ
    public private(set) var eqPoints: [Capture] = []
    public private(set) var eqVerificationPoints: [Capture] = []
    public private(set) var eqAverage: SpatialAverage?
    public private(set) var eqResult: EQResult?
    public private(set) var eqAfterAverage: SpatialAverage?
    public private(set) var eqIteration = 0
    /// All filters entered so far (cumulative over iterations).
    public private(set) var enteredFilters: [PEQFilter] = []

    public init(configuration: WizardConfiguration = WizardConfiguration()) {
        self.configuration = configuration
    }

    // MARK: Step 0

    /// Records a reliable delay lock. Invalidates earlier captures if the lock changed.
    public mutating func lockDelay(_ estimate: DelayEstimate, epoch: UInt64) {
        if let old = delayLock, abs(old.samples.rounded() - estimate.samples.rounded()) >= 1 || lockEpoch != epoch {
            invalidateCaptures()
        }
        delayLock = estimate
        lockEpoch = epoch
    }

    public var isPrepared: Bool { delayLock?.isReliable == true }

    // MARK: Navigation

    /// Phase-match flow: 1) satellites alone are captured and become the fixed reference;
    /// 2) only the subwoofers play and the user turns the sub delay / polarity / level live until the
    /// sub is in phase with the stored satellites, then that state is captured; 3) everything on for
    /// the verification. Without subwoofers only the whole system is measured.
    public mutating func start() {
        guard isPrepared else { return }
        step = configuration.hasSubwoofer ? .mainsOnly : .baseline
    }

    public mutating func goBack() {
        switch step {
        case .preparation: break
        case .mainsOnly: step = .preparation
        case .subOnly: step = .mainsOnly
        case .baseline: step = .preparation
        case .results: step = .subOnly
        case .verification: step = .results
        case .eqPoints: step = configuration.hasSubwoofer ? .verification : .baseline
        case .eqTuning: step = .eqPoints
        case .eqVerification: step = .eqTuning
        case .finished: step = .eqVerification
        }
    }

    public mutating func restart() {
        let c = configuration
        self = SetupWizard(configuration: c)
    }

    // MARK: Captures

    /// Feeds a finished capture for the current step. Accepted captures advance the wizard.
    @discardableResult
    public mutating func submit(_ capture: Capture) -> CaptureAcceptance {
        if let epoch = lockEpoch, capture.streamEpoch != epoch {
            invalidateCaptures()
            delayLock = nil
            lockEpoch = nil
            step = .preparation
            return .streamRestarted
        }
        guard capture.assessment.quality != .repeatRequired else {
            return .rejected(capture.assessment.reasons)
        }
        switch step {
        case .mainsOnly:
            mainsOnly = capture
            mainsDelayAddedStorage = nil
            phaseMatchStartStorage = nil
            step = .subOnly
        case .subOnly:
            subOnly = capture
            computeResults()
            // Glued already (the user matched the phase live): go straight to the verification.
            if isAlignedWithinTolerance { beginVerification() }
        case .baseline:
            baseline = capture
            step = .eqPoints
        case .verification:
            verification = capture
            evaluateVerification()
        case .eqPoints:
            guard eqPoints.count < configuration.eqPointCount else { return .rejected([]) }
            eqPoints.append(capture)
        case .eqVerification:
            guard eqVerificationPoints.count < eqPoints.count else { return .rejected([]) }
            eqVerificationPoints.append(capture)
            if eqVerificationPoints.count == eqPoints.count { evaluateEQ() }
        default:
            return .rejected([])
        }
        return .accepted(capture.assessment.quality)
    }

    /// Delay the user added to the satellites during the phase match because the subwoofers arrive
    /// later (s). The stored satellite response is shifted by it.
    public var mainsDelayAdded: Double { mainsDelayAddedStorage ?? 0 }
    /// Optional so that sessions saved before this field existed still decode.
    private var mainsDelayAddedStorage: Double?

    /// The subs arrive later than the satellites: the user enters `seconds` of delay on the
    /// satellites (muted at that moment) and the stored reference is shifted accordingly.
    public mutating func addMainsDelay(_ seconds: Double) {
        guard seconds > 0, step == .subOnly else { return }
        mainsDelayAddedStorage = mainsDelayAdded + seconds
    }

    /// The correction the live phase match asked for at its start, i.e. the total change from the
    /// original processor state (the user enters it while watching the needle).
    public struct PhaseMatchCorrection: Codable, Equatable, Sendable {
        /// Delay for the subwoofers (s); negative = the satellites get the delay.
        public var delay: Double
        public var invertPolarity: Bool
        public var subGainDB: Double
        public var crossover: Double
        public init(delay: Double, invertPolarity: Bool, subGainDB: Double, crossover: Double) {
            self.delay = delay
            self.invertPolarity = invertPolarity
            self.subGainDB = subGainDB
            self.crossover = crossover
        }
    }

    public var phaseMatchStart: PhaseMatchCorrection? { phaseMatchStartStorage }
    private var phaseMatchStartStorage: PhaseMatchCorrection?

    /// Records the first reliable live reading of the phase match (once per subwoofer step).
    public mutating func recordPhaseMatchStart(_ c: PhaseMatchCorrection) {
        guard step == .subOnly, phaseMatchStartStorage == nil else { return }
        phaseMatchStartStorage = c
    }

    /// Total change from the original state: what the phase match asked for, plus anything the
    /// results step still asks for; without a phase match, the alignment recommendation itself.
    public var totalCorrection: PhaseMatchCorrection? {
        guard let a = alignment else { return phaseMatchStart }
        guard let s = phaseMatchStart else {
            return PhaseMatchCorrection(delay: a.roundedDelay, invertPolarity: a.best.invertPolarity,
                                        subGainDB: a.subGainDB, crossover: a.crossover)
        }
        let step = configuration.delayStep
        return PhaseMatchCorrection(delay: ((s.delay + a.roundedDelay) / step).rounded() * step,
                                    invertPolarity: s.invertPolarity != a.best.invertPolarity,
                                    subGainDB: ((s.subGainDB + a.subGainDB) / configuration.levelStep).rounded() * configuration.levelStep,
                                    crossover: a.crossover)
    }

    /// True when the alignment result needs no further change on the processor.
    public var isAlignedWithinTolerance: Bool {
        guard let a = alignment else { return false }
        return abs(a.roundedDelay * a.crossover * 360) <= 10 && !a.best.invertPolarity && abs(a.subGainDB) <= 1
    }

    /// Mains response used for the alignment (measured, or derived in fast mode), including any
    /// delay added to the satellites during the phase match.
    public var mainsResponse: TransferFunction? {
        if let m = mainsOnly { return mainsDelayAdded > 0 ? m.transfer.delayed(by: mainsDelayAdded) : m.transfer }
        if configuration.fastMode, let b = baseline, let s = subOnly { return b.transfer.subtracting(s.transfer) }
        return nil
    }

    public mutating func beginVerification() {
        guard alignment != nil else { return }
        verification = nil
        report = nil
        step = .verification
    }

    // MARK: EQ

    /// From the alignment verification (or the baseline without subs) to the zone measurement.
    public mutating func beginEQ() {
        eqPoints = []
        eqVerificationPoints = []
        eqAverage = nil
        eqResult = nil
        eqAfterAverage = nil
        step = .eqPoints
    }

    public var canComputeEQ: Bool { eqPoints.count >= min(3, configuration.eqPointCount) }

    /// Averages the points, fits the EQ and moves to the EQ tuner.
    @discardableResult
    public mutating func computeEQ(microphone: MicrophoneCalibration? = nil) -> EQResult? {
        guard canComputeEQ,
              let avg = SpatialAverage.compute(eqPoints.map(\.transfer), coherenceThreshold: configuration.coherenceThreshold)
        else { return nil }
        let a = avg.removingMicrophone(microphone)
        eqAverage = a
        var eqs = configuration.eq
        eqs.coherenceThreshold = configuration.coherenceThreshold
        eqs.sampleRate = configuration.sampleRate
        let r = EQFitter.fit(average: a, target: configuration.target, settings: eqs,
                             main: mainsResponse, sub: subOnly?.transfer, crossoverBand: alignment?.overlapBand)
        eqResult = r
        step = .eqTuning
        return r
    }

    /// The user entered the bands; measure the same points again.
    public mutating func beginEQVerification() {
        guard let r = eqResult else { return }
        enteredFilters += r.filters.map { var f = $0; f.id = enteredFilters.count + $0.id; return f }
        eqIteration += 1
        eqVerificationPoints = []
        eqAfterAverage = nil
        step = .eqVerification
    }

    /// Another correction round on top of the entered filters (limited to `maxEQIterations`).
    public var canIterateEQ: Bool { eqIteration < configuration.maxEQIterations && eqAfterAverage != nil }

    public mutating func iterateEQ(microphone: MicrophoneCalibration? = nil) {
        guard canIterateEQ else { return }
        eqPoints = eqVerificationPoints
        eqVerificationPoints = []
        computeEQ(microphone: microphone)
    }

    public mutating func finish() { step = .finished }

    private mutating func evaluateEQ() {
        eqAfterAverage = SpatialAverage.compute(eqVerificationPoints.map(\.transfer),
                                                coherenceThreshold: configuration.coherenceThreshold)
    }

    /// Deviation from the target and quality score, before and after the EQ round.
    public func eqScores(microphone: MicrophoneCalibration? = nil) -> (before: QualityScore, after: QualityScore?)? {
        guard let r = eqResult, let before = eqAverage else { return nil }
        let dip = report?.after?.dipDepthDB ?? report?.before?.dipDepthDB
        let qb = QualityScore.compute(levelDB: r.measuredDB, targetDB: r.targetDB, average: before, crossoverDipDB: dip)
        guard let after = eqAfterAverage?.removingMicrophone(microphone) else { return (qb, nil) }
        let f = after.frequencies
        let smoothed = Smoothing.smoothPower(after.levelDB.map { $0.isFinite ? Decibel.toPower($0) : .nan },
                                             frequencies: f, octaves: 1.0 / 6).map { Decibel.fromPower($0) }
        // Same target alignment as the fit, re-based on the new level.
        let offset = median(f.indices.filter { f[$0] >= 200 && f[$0] <= 4000 && smoothed[$0].isFinite }
            .map { smoothed[$0] - configuration.target.value(at: f[$0]) })
        let target = f.map { configuration.target.value(at: $0) + offset }
        let qa = QualityScore.compute(levelDB: smoothed, targetDB: target, average: after, crossoverDipDB: dip)
        return (qb, qa)
    }

    private func median(_ v: [Double]) -> Double {
        let s = v.sorted()
        return s.isEmpty ? 0 : s[s.count / 2]
    }

    // MARK: Results

    private mutating func computeResults() {
        guard let hm = mainsResponse, let hs = subOnly?.transfer else { return }
        do {
            let a = try SubAlignment.align(main: hm, sub: hs, settings: configuration.alignmentSettings)
            alignment = a
            alignmentError = nil
            prediction = SubAlignment.predictSum(main: hm, sub: hs, delay: a.roundedDelay,
                                                 invertPolarity: a.best.invertPolarity, subGainDB: a.subGainDB)
        } catch {
            alignment = nil
            prediction = nil
            alignmentError = String(describing: error)
        }
        step = .results
    }

    private mutating func evaluateVerification() {
        guard let a = alignment, let hm = mainsResponse, let hs = subOnly?.transfer, let v = verification else { return }
        report = VerificationReport.evaluate(baseline: baseline?.transfer, verification: v.transfer,
                                             main: hm, sub: hs, alignment: a)
    }

    /// Action cards for the results screen, in processor terms.
    /// The total processor settings (change from the original state) for the summary and report.
    public var actionCards: [ActionCard] {
        guard let t = totalCorrection else { return [] }
        let c = Acoustics.speedOfSound(celsius: configuration.temperatureCelsius)
        var cards: [ActionCard] = []
        if abs(t.delay) < 1e-9 {
            cards.append(.noDelayChange)
        } else if t.delay > 0 {
            cards.append(.delaySub(seconds: t.delay, meters: t.delay * c))
        } else {
            cards.append(.delayMains(seconds: -t.delay, meters: -t.delay * c))
        }
        cards.append(.polarity(invert: t.invertPolarity))
        cards.append(.subLevel(dB: t.subGainDB))
        return cards
    }

    private mutating func invalidateCaptures() {
        mainsDelayAddedStorage = nil
        phaseMatchStartStorage = nil
        baseline = nil
        subOnly = nil
        mainsOnly = nil
        verification = nil
        alignment = nil
        prediction = nil
        report = nil
        eqPoints = []
        eqVerificationPoints = []
        eqAverage = nil
        eqResult = nil
        eqAfterAverage = nil
        if step > .preparation { step = .preparation }
    }
}
