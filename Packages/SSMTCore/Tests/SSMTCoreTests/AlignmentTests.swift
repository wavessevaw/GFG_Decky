import XCTest
@testable import SSMTCore

final class AlignmentTests: XCTestCase {
    let fs = 48000.0

    /// Sub and mains with only LR24 filters: the ideal sub delay is exactly d_main − d_sub.
    func pureLRSystem(subDelay: Int, mainDelay: Int, crossover: Double = 100, subInverted: Bool = false,
                      subGainDB: Double = 0) -> VirtualSystem {
        let sub = VirtualSource(filters: CrossoverFilter.linkwitzRiley24(.lowPass, frequency: crossover, sampleRate: fs),
                                delaySamples: subDelay, gainDB: subGainDB, invertPolarity: subInverted)
        let main = VirtualSource(filters: CrossoverFilter.linkwitzRiley24(.highPass, frequency: crossover, sampleRate: fs),
                                 delaySamples: mainDelay)
        return VirtualSystem(sampleRate: fs, sub: sub, main: main, micNoiseDBFS: -80)
    }

    /// Measures (mains only, sub only, all) with one locked reference delay — like the wizard.
    func measureGroups(_ system: VirtualSystem, lockDelay: Int, seconds: Double = 12)
        -> (main: TransferFunction, sub: TransferFunction, total: TransferFunction) {
        var m = system; m.sub.enabled = false
        var s = system; s.main.enabled = false
        return (TestSignals.measure(system: m, seconds: seconds, referenceDelay: lockDelay, seed: 2),
                TestSignals.measure(system: s, seconds: seconds, referenceDelay: lockDelay, seed: 3),
                TestSignals.measure(system: system, seconds: seconds, referenceDelay: lockDelay, seed: 4))
    }

    func testFindsKnownDelayWithinOneSampleBothSigns() throws {
        for (subDelay, mainDelay) in [(400, 610), (700, 520), (1000, 1000)] {
            let sys = pureLRSystem(subDelay: subDelay, mainDelay: mainDelay)
            let g = measureGroups(sys, lockDelay: 128 + mainDelay)
            var settings = AlignmentSettings(crossover: 100)
            settings.delayStep = 1 / fs
            let r = try SubAlignment.align(main: g.main, sub: g.sub, settings: settings)
            XCTAssertEqual(r.best.delay * fs, Double(mainDelay - subDelay), accuracy: 1.0, "sub \(subDelay) main \(mainDelay)")
            XCTAssertFalse(r.best.invertPolarity)
            XCTAssertEqual(r.delayTarget, mainDelay > subDelay ? .sub : (mainDelay < subDelay ? .mains : .none))
        }
    }

    func testDetectsInvertedSubPolarity() throws {
        let sys = pureLRSystem(subDelay: 450, mainDelay: 600, subInverted: true)
        let g = measureGroups(sys, lockDelay: 728)
        var settings = AlignmentSettings(crossover: 100)
        settings.delayStep = 1 / fs
        let r = try SubAlignment.align(main: g.main, sub: g.sub, settings: settings)
        XCTAssertTrue(r.best.invertPolarity)
        XCTAssertEqual(r.best.delay * fs, 150, accuracy: 1.0)
    }

    func testDetectsCrossoverAndLevel() throws {
        let sys = pureLRSystem(subDelay: 500, mainDelay: 560, crossover: 90, subGainDB: 4)
        let g = measureGroups(sys, lockDelay: 688)
        let r = try SubAlignment.align(main: g.main, sub: g.sub, settings: AlignmentSettings())
        XCTAssertTrue(r.crossoverWasDetected)
        // With a hot sub the crossing moves up; it must still be found in the right region.
        XCTAssertEqual(log2(r.crossover / 90), 0, accuracy: 0.5)
        XCTAssertEqual(r.subGainDB, -4, accuracy: 0.6)
        XCTAssertEqual(r.best.delay * fs, 60, accuracy: 1.5)
    }

    func testRoundingToProcessorStep() throws {
        let sys = pureLRSystem(subDelay: 400, mainDelay: 611)
        let g = measureGroups(sys, lockDelay: 739)
        var settings = AlignmentSettings(crossover: 100)
        settings.delayStep = 0.0001 // 0.1 ms processor
        let r = try SubAlignment.align(main: g.main, sub: g.sub, settings: settings)
        XCTAssertEqual(r.roundedDelay * 10000, (r.roundedDelay * 10000).rounded(), accuracy: 1e-6)
        XCTAssertEqual(r.roundedDelay, 211 / fs, accuracy: 0.00005 + 1 / fs)
    }

    /// Acceptance criterion 2 (alignment part): in the simulated realistic PA (extra driver
    /// filters, reflections, room modes, sub misaligned), applying the recommendation removes
    /// the crossover dip (< 3 dB) and the verification confirms it.
    func testRecommendationRemovesCrossoverDipInRealisticRoom() throws {
        let room = VirtualRoom(reflections: [VirtualReflection(delaySamples: 168, gain: 0.3)],
                               modes: [Biquad.design(.peaking, frequency: 63, q: 6, gainDB: 6, sampleRate: fs)])
        // Sub 3 m closer than the mains and inverted by mistake → deep cancellation at crossover.
        var sys = VirtualSystem.typicalPA(sampleRate: fs, crossover: 90, subDistance: 6.5, mainDistance: 9.5,
                                          subInverted: true, room: room, micNoiseDBFS: -80)
        let lock = 128 + sys.main.delaySamples
        let g = measureGroups(sys, lockDelay: lock)
        let r = try SubAlignment.align(main: g.main, sub: g.sub, settings: AlignmentSettings(crossover: 90))
        XCTAssertTrue(r.best.invertPolarity)
        XCTAssertFalse(r.isAmbiguous, "alternatives: \(r.alternatives)")

        let before = try XCTUnwrap(SummationMetrics.evaluate(total: g.total, main: g.main, sub: g.sub, band: r.overlapBand))
        XCTAssertGreaterThan(before.dipDepthDB, 6)

        // Apply on the "processor".
        let delaySamples = Int((r.roundedDelay * fs).rounded())
        if delaySamples >= 0 { sys.sub.delaySamples += delaySamples } else { sys.main.delaySamples -= delaySamples }
        sys.sub.invertPolarity.toggle()
        sys.sub.gainDB += r.subGainDB
        let verification = TestSignals.measure(system: sys, seconds: 12, referenceDelay: lock + max(0, -delaySamples), seed: 9)

        let report = VerificationReport.evaluate(baseline: g.total, verification: verification,
                                                 main: g.main, sub: g.sub, alignment: r)
        XCTAssertLessThan(report.after?.dipDepthDB ?? 99, 3)
        XCTAssertEqual(report.verdict, .excellent, "\(report)")
    }

    func testVerificationDetectsForgottenPolarity() throws {
        var sys = pureLRSystem(subDelay: 400, mainDelay: 600, subInverted: true)
        let lock = 728
        let g = measureGroups(sys, lockDelay: lock)
        let r = try SubAlignment.align(main: g.main, sub: g.sub, settings: AlignmentSettings(crossover: 100))
        // User applies the delay but forgets the polarity.
        sys.sub.delaySamples += Int((r.roundedDelay * fs).rounded())
        let v = TestSignals.measure(system: sys, seconds: 12, referenceDelay: lock, seed: 5)
        let report = VerificationReport.evaluate(baseline: g.total, verification: v, main: g.main, sub: g.sub, alignment: r)
        XCTAssertEqual(report.verdict, .checkSettings)
        XCTAssertEqual(report.advice, .polarityNotApplied)
    }

    func testPredictionMatchesMeasuredSum() throws {
        let sys = pureLRSystem(subDelay: 400, mainDelay: 600)
        let g = measureGroups(sys, lockDelay: 728)
        let p = SubAlignment.predictSum(main: g.main, sub: g.sub, delay: 0, invertPolarity: false, subGainDB: 0)
        for i in g.total.frequencies.indices where g.total.frequencies[i] > 40 && g.total.frequencies[i] < 300 {
            XCTAssertEqual(Decibel.fromAmplitude(p.response[i].magnitude),
                           Decibel.fromAmplitude(g.total.response[i].magnitude), accuracy: 0.5)
        }
    }

    func testFastModeSubtractionRecoversMains() {
        let sys = pureLRSystem(subDelay: 400, mainDelay: 600)
        let g = measureGroups(sys, lockDelay: 728)
        let derived = g.total.subtracting(g.sub)
        for i in g.main.frequencies.indices where g.main.frequencies[i] > 70 && g.main.frequencies[i] < 2000 {
            XCTAssertEqual(Decibel.fromAmplitude(derived.response[i].magnitude),
                           Decibel.fromAmplitude(g.main.response[i].magnitude), accuracy: 0.5)
        }
    }
}

final class AlignmentAmbiguityTests: XCTestCase {
    /// Sub with a 90° phase offset relative to the mains: "normal at τ+¼T" and "inverted at τ−¼T"
    /// sum equally well and the IR timing sits right between them → must be reported as ambiguous.
    func testQuadratureSubIsReportedAmbiguous() throws {
        let grid = FrequencyGrid()
        let f = grid.frequencies
        let d = 0.004
        let ones = [Double](repeating: 1, count: f.count)
        let hm = TransferFunction(frequencies: f, response: f.map { _ in Complex.one }, coherence: ones,
                                  measurementPower: ones, referencePower: ones, averages: 50)
        let hs = TransferFunction(frequencies: f, response: f.map { Complex.expj(-2 * .pi * $0 * d - .pi / 2) },
                                  coherence: ones, measurementPower: ones, referencePower: ones, averages: 50)
        let r = try SubAlignment.align(main: hm, sub: hs, settings: AlignmentSettings(crossover: 100))
        XCTAssertTrue(r.isAmbiguous, "best \(r.best) alt \(r.alternatives)")
        XCTAssertTrue(r.alternatives.contains { $0.invertPolarity != r.best.invertPolarity })
    }

    func testClearCaseIsNotAmbiguous() throws {
        let grid = FrequencyGrid()
        let f = grid.frequencies
        let ones = [Double](repeating: 1, count: f.count)
        let fs = 48000.0
        let lp = CrossoverFilter.linkwitzRiley24(.lowPass, frequency: 100, sampleRate: fs)
        let hp = CrossoverFilter.linkwitzRiley24(.highPass, frequency: 100, sampleRate: fs)
        let hm = TransferFunction(frequencies: f, response: f.map { x in hp.reduce(Complex.one) { $0 * $1.response(at: x, sampleRate: fs) } },
                                  coherence: ones, measurementPower: ones, referencePower: ones, averages: 50)
        let hs = TransferFunction(frequencies: f, response: f.map { x in
            lp.reduce(Complex.one) { $0 * $1.response(at: x, sampleRate: fs) } * Complex.expj(-2 * .pi * x * 0.003)
        }, coherence: ones, measurementPower: ones, referencePower: ones, averages: 50)
        let r = try SubAlignment.align(main: hm, sub: hs, settings: AlignmentSettings(crossover: 100))
        XCTAssertFalse(r.isAmbiguous)
        XCTAssertEqual(r.best.delay, -0.003, accuracy: 1 / fs)
        XCTAssertEqual(r.delayTarget, .mains)
    }
}
