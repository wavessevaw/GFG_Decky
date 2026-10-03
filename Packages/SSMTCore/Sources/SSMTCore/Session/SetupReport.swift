import Foundation

/// Everything the PDF/PNG report shows, derived from a finished (or partial) wizard.
public struct SetupReport: Equatable, Sendable {
    public struct Alignment: Equatable, Sendable {
        public var delayMs: Double
        public var delayMeters: Double
        public var delayTarget: AlignmentResult.DelayTarget
        public var invertPolarity: Bool
        public var subLevelDB: Double
        public var crossover: Double
        public var crossoverDetected: Bool
        public var ambiguous: Bool
    }

    public struct Verification: Equatable, Sendable {
        public var dipBeforeDB: Double?
        public var dipAfterDB: Double?
        public var summationBeforeDB: Double?
        public var summationAfterDB: Double?
        public var predictionErrorDB: Double
        public var verdict: VerificationVerdict
    }

    public struct EQ: Equatable, Sendable {
        public var filters: [PEQFilter]
        public var targetName: String
        public var points: Int
        public var iterations: Int
        public var deviationBeforeDB: Double
        public var deviationAfterDB: Double?
        public var scoreBefore: Int
        public var scoreAfter: Int?
    }

    public var date: Date
    public var interfaceName: String
    public var sampleRate: Double
    public var temperatureCelsius: Double
    public var microphoneCalibrationName: String?
    public var referenceDelayMs: Double?
    public var alignment: Alignment?
    public var verification: Verification?
    public var eq: EQ?

    public init(wizard w: SetupWizard, interfaceName: String, sampleRate: Double,
                microphone: MicrophoneCalibration?, date: Date = Date()) {
        self.date = date
        self.interfaceName = interfaceName
        self.sampleRate = sampleRate
        temperatureCelsius = w.configuration.temperatureCelsius
        microphoneCalibrationName = microphone?.name
        referenceDelayMs = w.delayLock.map { $0.milliseconds }
        if let a = w.alignment {
            let c = Acoustics.speedOfSound(celsius: w.configuration.temperatureCelsius)
            alignment = Alignment(delayMs: abs(a.roundedDelay) * 1000, delayMeters: abs(a.roundedDelay) * c,
                                  delayTarget: a.delayTarget, invertPolarity: a.best.invertPolarity,
                                  subLevelDB: a.subGainDB, crossover: a.crossover,
                                  crossoverDetected: a.crossoverWasDetected, ambiguous: a.isAmbiguous)
        }
        if let r = w.report {
            verification = Verification(dipBeforeDB: r.before?.dipDepthDB, dipAfterDB: r.after?.dipDepthDB,
                                        summationBeforeDB: r.before?.summationGainDB,
                                        summationAfterDB: r.after?.summationGainDB,
                                        predictionErrorDB: r.predictionErrorDB, verdict: r.verdict)
        }
        if let r = w.eqResult, let scores = w.eqScores(microphone: microphone) {
            eq = EQ(filters: w.enteredFilters.isEmpty ? r.filters : w.enteredFilters,
                    targetName: w.configuration.target.preset.rawValue,
                    points: w.eqPoints.count, iterations: w.eqIteration,
                    deviationBeforeDB: scores.before.rmsDeviationDB, deviationAfterDB: scores.after?.rmsDeviationDB,
                    scoreBefore: scores.before.score, scoreAfter: scores.after?.score)
        }
    }

    /// Plain-text version (clipboard / e-mail), always in English technical notation.
    public var plainText: String {
        let df = ISO8601DateFormatter()
        var l = ["SSMT — System setup report", "Date: \(df.string(from: date))",
                 "Interface: \(interfaceName) @ \(Int(sampleRate)) Hz",
                 String(format: "Air temperature: %.0f °C", temperatureCelsius),
                 "Microphone calibration: \(microphoneCalibrationName ?? "none (not calibrated)")"]
        if let d = referenceDelayMs { l.append(String(format: "System delay (locked): %.2f ms", d)) }
        if let a = alignment {
            l.append("")
            l.append("Subwoofer alignment")
            switch a.delayTarget {
            case .sub: l.append(String(format: "  Delay subwoofers: +%.2f ms (%.2f m)", a.delayMs, a.delayMeters))
            case .mains: l.append(String(format: "  Delay mains: +%.2f ms (%.2f m)", a.delayMs, a.delayMeters))
            case .none: l.append("  Delay: no change")
            }
            l.append("  Subwoofer polarity: \(a.invertPolarity ? "INVERT" : "normal")")
            l.append(String(format: "  Subwoofer level: %+.1f dB", a.subLevelDB))
            l.append(String(format: "  Crossover: %.0f Hz%@", a.crossover, a.crossoverDetected ? " (detected)" : ""))
            if a.ambiguous { l.append("  WARNING: ambiguous solution") }
        }
        if let v = verification {
            l.append("")
            l.append("Verification: \(v.verdict.rawValue)")
            if let b = v.dipBeforeDB, let a = v.dipAfterDB { l.append(String(format: "  Crossover dip: %.1f → %.1f dB", b, a)) }
            if let b = v.summationBeforeDB, let a = v.summationAfterDB { l.append(String(format: "  Summation: %+.1f → %+.1f dB", b, a)) }
            l.append(String(format: "  Deviation from prediction: %.1f dB", v.predictionErrorDB))
        }
        if let e = eq {
            l.append("")
            l.append("EQ (target: \(e.targetName), \(e.points) points, \(e.iterations) round(s))")
            let after = e.deviationAfterDB.map { String(format: " → ±%.1f", $0) } ?? ""
            l.append(String(format: "  Deviation from target: ±%.1f%@ dB", e.deviationBeforeDB, after))
            l.append("  Quality score: \(e.scoreBefore)\(e.scoreAfter.map { " → \($0)" } ?? "") (a guide, not a guarantee)")
            l.append("")
            l.append(PEQExport.filterSettingsText(e.filters, title: "Filters"))
        }
        return l.joined(separator: "\n")
    }
}
