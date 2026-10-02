import Foundation

public struct WizardConfiguration: Equatable, Codable, Sendable {
    public var hasSubwoofer = true
    /// Known crossover frequency; nil = detect automatically.
    public var crossover: Double?
    /// Fast mode: skip the "mains only" capture and derive it as H_total − H_sub (lower accuracy).
    public var fastMode = false
    public var captureSeconds: Double = 12
    public var delayStep: Double = 0.00001
    public var levelStep: Double = 0.5
    public var temperatureCelsius: Double = 20
    public var coherenceThreshold: Double = 0.6
    public var sampleRate: Double = 48000

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

public enum WizardStep: Int, Codable, Sendable, CaseIterable, Comparable {
    case preparation = 0
    case baseline
    case subOnly
    case mainsOnly
    case results
    case verification
    case finished

    public static func < (a: WizardStep, b: WizardStep) -> Bool { a.rawValue < b.rawValue }

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
        case .baseline, .verification: return (true, true)
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

    public mutating func start() {
        guard isPrepared else { return }
        step = .baseline
    }

    public mutating func goBack() {
        switch step {
        case .preparation: break
        case .baseline: step = .preparation
        case .subOnly: step = .baseline
        case .mainsOnly: step = .subOnly
        case .results: step = configuration.fastMode ? .subOnly : .mainsOnly
        case .verification: step = .results
        case .finished: step = .verification
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
        case .baseline:
            baseline = capture
            step = configuration.hasSubwoofer ? .subOnly : .finished
        case .subOnly:
            subOnly = capture
            if configuration.fastMode {
                computeResults()
            } else {
                step = .mainsOnly
            }
        case .mainsOnly:
            mainsOnly = capture
            computeResults()
        case .verification:
            verification = capture
            evaluateVerification()
            step = .finished
        default:
            return .rejected([])
        }
        return .accepted(capture.assessment.quality)
    }

    /// Mains response used for the alignment (measured, or derived in fast mode).
    public var mainsResponse: TransferFunction? {
        if let m = mainsOnly { return m.transfer }
        if configuration.fastMode, let b = baseline, let s = subOnly { return b.transfer.subtracting(s.transfer) }
        return nil
    }

    public mutating func beginVerification() {
        guard alignment != nil else { return }
        step = .verification
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
    public var actionCards: [ActionCard] {
        guard let a = alignment else { return [] }
        let c = Acoustics.speedOfSound(celsius: configuration.temperatureCelsius)
        var cards: [ActionCard] = []
        switch a.delayTarget {
        case .sub: cards.append(.delaySub(seconds: a.roundedDelay, meters: a.roundedDelay * c))
        case .mains: cards.append(.delayMains(seconds: -a.roundedDelay, meters: -a.roundedDelay * c))
        case .none: cards.append(.noDelayChange)
        }
        cards.append(.polarity(invert: a.best.invertPolarity))
        cards.append(.subLevel(dB: a.subGainDB))
        return cards
    }

    private mutating func invalidateCaptures() {
        baseline = nil
        subOnly = nil
        mainsOnly = nil
        verification = nil
        alignment = nil
        prediction = nil
        report = nil
        if step > .preparation { step = .preparation }
    }
}
