import XCTest
@testable import SSMTCore

/// End-to-end wizard run in simulation, driven exactly like the app does it.
final class WizardTests: XCTestCase {
    final class Rig {
        let backend: SimulatedAudioBackend
        let engine: MeasurementEngine
        init(system: VirtualSystem) {
            var safety = GeneratorSafety()
            safety.fadeInSeconds = 0.05
            safety.startLevelDBFS = -20
            backend = SimulatedAudioBackend(system: system, deviceLatency: 512, safety: safety, seed: 21)
            engine = MeasurementEngine(backend: backend)
            backend.generatorControl.targetLevelDBFS.value = -20
            backend.generatorControl.run.value = true
            run(seconds: 1)
        }
        func run(seconds: Double) {
            for _ in 0..<Int(seconds * 40) {
                backend.pump(frames: 1200)
                engine.drainNow()
            }
        }
        func findDelay() -> DelayEstimate? {
            var result: DelayEstimate?
            engine.findDelay(seconds: 3) { result = $0 }
            run(seconds: 3.5)
            return result
        }
        func capture(_ label: String, seconds: Double, band: ClosedRange<Double>? = nil) -> Capture? {
            var result: Capture?
            engine.capture(label: label, duration: seconds, qualityBand: band) { result = $0 }
            run(seconds: seconds + 0.5)
            return result
        }
    }

    static func demoSystem() -> VirtualSystem {
        let fs = 48000.0
        let room = VirtualRoom(reflections: [VirtualReflection(delaySamples: 168, gain: 0.3)],
                               modes: [Biquad.design(.peaking, frequency: 63, q: 6, gainDB: 6, sampleRate: fs)])
        // Sub 2.5 m closer, polarity inverted by mistake, 3 dB hot; mains with a honky mid and bright top.
        var sys = VirtualSystem.typicalPA(sampleRate: fs, crossover: 90, subDistance: 7, mainDistance: 9.5,
                                          subGainDB: 3, subInverted: true, room: room, micNoiseDBFS: -75)
        sys.main.filters += [Biquad.design(.peaking, frequency: 1800, q: 1.2, gainDB: 5, sampleRate: fs),
                             Biquad.design(.peaking, frequency: 9000, q: 0.8, gainDB: 3, sampleRate: fs)]
        return sys
    }

    func runWizard(fastMode: Bool) throws -> SetupWizard {
        let rig = Rig(system: Self.demoSystem())
        var config = WizardConfiguration()
        config.crossover = 90
        config.fastMode = fastMode
        config.captureSeconds = 10
        var wizard = SetupWizard(configuration: config)

        // Step 0: delay lock on the full system.
        let delay = try XCTUnwrap(rig.findDelay())
        XCTAssertTrue(delay.isReliable)
        wizard.lockDelay(delay, epoch: rig.backend.discontinuities.value)
        wizard.start()
        XCTAssertEqual(wizard.step, .mainsOnly)

        // Satellites alone, then subs alone, then the whole system as it is ("before"; not in fast mode).
        for step in [WizardStep.mainsOnly, .subOnly, .baseline] {
            if fastMode && step == .baseline { break }
            XCTAssertEqual(wizard.step, step)
            let g = step.requiredGroups!
            rig.backend.setActiveGroups(sub: g.sub, main: g.mains)
            rig.run(seconds: 0.5)
            let c = try XCTUnwrap(rig.capture("\(step)", seconds: config.captureSeconds,
                                              band: step.qualityBand(crossover: config.crossover)))
            XCTAssertEqual(wizard.submit(c), .accepted(c.assessment.quality), "\(step): \(c.assessment)")
        }
        XCTAssertEqual(wizard.step, .results)
        let a = try XCTUnwrap(wizard.alignment, wizard.alignmentError ?? "")
        XCTAssertTrue(a.best.invertPolarity, "polarity must be corrected")
        XCTAssertEqual(wizard.actionCards.count, 3)

        // Step 5: user applies the settings, verification capture.
        rig.backend.applyAlignment(delaySeconds: a.roundedDelay, invertPolarity: a.best.invertPolarity, subGainDB: a.subGainDB)
        rig.backend.setActiveGroups(sub: true, main: true)
        wizard.beginVerification()
        rig.run(seconds: 0.5)
        let v = try XCTUnwrap(rig.capture("verify", seconds: config.captureSeconds))
        _ = wizard.submit(v)
        XCTAssertEqual(wizard.step, .verification)
        XCTAssertNotNil(wizard.report)
        return wizard
    }

    func testFullWizardInSimulation() throws {
        let w = try runWizard(fastMode: false)
        let a = w.alignment!
        // Truth: sub 2.5 m closer → ≈ 7.3 ms, refined by the filter phase in the overlap.
        XCTAssertEqual(a.roundedDelay * 1000, 2.5 / Acoustics.speedOfSound(celsius: 20) * 1000, accuracy: 0.6)
        // Level (spec 6.5): after the change the median levels in the overlap band match.
        let hm = try XCTUnwrap(w.mainsResponse), hs = try XCTUnwrap(w.subOnly?.transfer)
        let medM = SubAlignment.passbandLevel(hm, band: a.overlapBand, settings: w.configuration.alignmentSettings)
        let medS = SubAlignment.passbandLevel(hs, band: a.overlapBand, settings: w.configuration.alignmentSettings) + a.subGainDB
        XCTAssertEqual(medM, medS, accuracy: 0.3)
        XCTAssertLessThan(a.subGainDB, -1.5, "the +3 dB hot sub must be turned down")
        let r = try XCTUnwrap(w.report)
        XCTAssertGreaterThan(r.before?.dipDepthDB ?? 0, 3, "baseline must show the cancellation")
        XCTAssertGreaterThan((r.after?.summationGainDB ?? 0) - (r.before?.summationGainDB ?? 0), 1)
        XCTAssertLessThan(r.after?.dipDepthDB ?? 99, 3, "acceptance: crossover dip < 3 dB")
        XCTAssertEqual(r.verdict, .excellent, "\(r)")
        if case .delaySub(let s, let m) = w.actionCards[0] {
            XCTAssertEqual(m, s * Acoustics.speedOfSound(celsius: 20), accuracy: 1e-9)
        } else {
            XCTFail("expected sub delay card, got \(w.actionCards[0])")
        }
    }

    /// Steps 6–8: zone points → EQ → enter filters (virtual processor) → verification points.
    func testEQStepsInSimulation() throws {
        var w = try Self.runWizardKeepingRig()
        let rig = w.rig
        w.wizard.beginEQ()
        XCTAssertEqual(w.wizard.step, .eqPoints)
        for p in 0..<w.wizard.configuration.eqPointCount {
            rig.backend.moveMicrophone(toPoint: p)
            rig.run(seconds: 0.5)
            let c = try XCTUnwrap(rig.capture("eq\(p)", seconds: 8))
            XCTAssertEqual(w.wizard.submit(c), .accepted(c.assessment.quality), "point \(p): \(c.assessment)")
        }
        let r = try XCTUnwrap(w.wizard.computeEQ())
        XCTAssertEqual(w.wizard.step, .eqTuning)
        XCTAssertFalse(r.filters.isEmpty)
        // Enter the filters on the virtual processor.
        var knobs = rig.backend.processorSettings
        knobs.subEQ = r.filters.filter { $0.group == .sub }
        knobs.mainsEQ = r.filters.filter { $0.group == .mains }
        rig.backend.setProcessor(knobs)
        w.wizard.beginEQVerification()
        XCTAssertEqual(w.wizard.step, .eqVerification)
        for p in 0..<w.wizard.configuration.eqPointCount {
            rig.backend.moveMicrophone(toPoint: p)
            rig.run(seconds: 0.5)
            let c = try XCTUnwrap(rig.capture("v\(p)", seconds: 8))
            _ = w.wizard.submit(c)
        }
        let scores = try XCTUnwrap(w.wizard.eqScores())
        let after = try XCTUnwrap(scores.after)
        XCTAssertLessThan(after.rmsDeviationDB, scores.before.rmsDeviationDB * 0.75,
                          "EQ must reduce the deviation (before \(scores.before.rmsDeviationDB), after \(after.rmsDeviationDB))")
        XCTAssertGreaterThanOrEqual(after.score, scores.before.score)
        XCTAssertTrue(w.wizard.canIterateEQ)
        w.wizard.iterateEQ()
        XCTAssertEqual(w.wizard.step, .eqTuning)
        w.wizard.beginEQVerification()
        XCTAssertEqual(w.wizard.eqIteration, 2)
        XCTAssertFalse(w.wizard.canIterateEQ, "max 2 consecutive EQ iterations")
    }

    static func runWizardKeepingRig() throws -> (wizard: SetupWizard, rig: Rig) {
        let rig = Rig(system: Self.demoSystem())
        var config = WizardConfiguration()
        config.crossover = 90
        config.captureSeconds = 8
        config.target = .preset(.flat)
        var wizard = SetupWizard(configuration: config)
        let delay = try XCTUnwrap(rig.findDelay())
        wizard.lockDelay(delay, epoch: rig.backend.discontinuities.value)
        wizard.start()
        for step in [WizardStep.mainsOnly, .subOnly, .baseline] {
            let g = step.requiredGroups!
            rig.backend.setActiveGroups(sub: g.sub, main: g.mains)
            rig.run(seconds: 0.5)
            let c = try XCTUnwrap(rig.capture("\(step)", seconds: config.captureSeconds,
                                              band: step.qualityBand(crossover: config.crossover)))
            wizard.submit(c)
        }
        let a = try XCTUnwrap(wizard.alignment)
        rig.backend.applyAlignment(delaySeconds: a.roundedDelay, invertPolarity: a.best.invertPolarity, subGainDB: a.subGainDB)
        rig.backend.setActiveGroups(sub: true, main: true)
        wizard.beginVerification()
        rig.run(seconds: 0.5)
        wizard.submit(try XCTUnwrap(rig.capture("verify", seconds: config.captureSeconds)))
        return (wizard, rig)
    }

    func testFastModeWizard() throws {
        let w = try runWizard(fastMode: true)
        XCTAssertNil(w.baseline)
        XCTAssertNotNil(w.mainsOnly)
        XCTAssertLessThan(w.report?.after?.dipDepthDB ?? 99, 3)
    }

    func testStreamRestartInvalidatesWizard() throws {
        let rig = Rig(system: Self.demoSystem())
        var wizard = SetupWizard()
        let d = try XCTUnwrap(rig.findDelay())
        wizard.lockDelay(d, epoch: rig.backend.discontinuities.value)
        wizard.start()
        rig.backend.discontinuities.increment() // device glitch
        let c = try XCTUnwrap(rig.capture("baseline", seconds: 3))
        XCTAssertEqual(wizard.submit(c), .streamRestarted)
        XCTAssertEqual(wizard.step, .preparation)
        XCTAssertNil(wizard.delayLock)
    }

    func testClippedCaptureIsNotAccepted() throws {
        let rig = Rig(system: Self.demoSystem())
        var wizard = SetupWizard()
        let d = try XCTUnwrap(rig.findDelay())
        wizard.lockDelay(d, epoch: rig.backend.discontinuities.value)
        wizard.start()
        rig.backend.micPreampDB = 40
        let c = try XCTUnwrap(rig.capture("baseline", seconds: 3))
        guard case .rejected(let reasons) = wizard.submit(c) else { return XCTFail() }
        XCTAssertTrue(reasons.contains(.clipping))
        XCTAssertEqual(wizard.step, .mainsOnly)
    }
}
