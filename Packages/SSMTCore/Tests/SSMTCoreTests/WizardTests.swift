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

    /// The live phase match as the user does it: only the subs play, the tuner compares the live sub
    /// with the stored satellites, the user enters what the needle asks for (here in one go).
    /// Returns the first reading (the full correction that was needed).
    static func liveMatch(_ rig: Rig, _ wizard: inout SetupWizard) throws -> AlignmentTuner.Reading {
        rig.backend.setActiveGroups(sub: true, main: false)
        rig.run(seconds: 0.5)
        let mains = try XCTUnwrap(wizard.mainsResponse)
        let tuner = AlignmentTuner(stage: .adjustSub, fixed: mains, crossover: wizard.configuration.crossover,
                                   settings: wizard.configuration.alignmentSettings, input: .changingGroupOnly)
        let live = try XCTUnwrap(rig.capture("live", seconds: 6)).transfer
        let r = try XCTUnwrap(tuner.read(live: live))
        wizard.recordPhaseMatchStart(.init(delay: r.delayError, invertPolarity: r.polarityWrong,
                                           subGainDB: r.levelError, crossover: r.crossover))
        let step = wizard.configuration.delayStep
        let delay = (r.delayError / step).rounded() * step
        // Subs late → the delay goes to the satellites (muted now); the stored reference follows.
        if delay < 0 { wizard.addMainsDelay(-delay) }
        rig.backend.applyAlignment(delaySeconds: delay, invertPolarity: r.polarityWrong,
                                   subGainDB: (r.levelError / 0.5).rounded() * 0.5)
        rig.run(seconds: 0.5)
        return r
    }

    @discardableResult
    func runWizard(system: VirtualSystem = WizardTests.demoSystem()) throws -> (wizard: SetupWizard, reading: AlignmentTuner.Reading) {
        let rig = Rig(system: system)
        var config = WizardConfiguration()
        config.crossover = 90
        config.captureSeconds = 10
        var wizard = SetupWizard(configuration: config)

        // Step 0: delay lock on the full system.
        let delay = try XCTUnwrap(rig.findDelay())
        XCTAssertTrue(delay.isReliable)
        wizard.lockDelay(delay, epoch: rig.backend.discontinuities.value)
        wizard.start()

        // 1. Satellites only → fixed reference.
        XCTAssertEqual(wizard.step, .mainsOnly)
        rig.backend.setActiveGroups(sub: false, main: true)
        rig.run(seconds: 0.5)
        let m = try XCTUnwrap(rig.capture("mains", seconds: config.captureSeconds,
                                          band: WizardStep.mainsOnly.qualityBand(crossover: 90)))
        XCTAssertEqual(wizard.submit(m), .accepted(m.assessment.quality), "\(m.assessment)")
        XCTAssertEqual(wizard.step, .subOnly)

        // 2. Only the subs play: live phase match, then the matched state is captured.
        let reading = try Self.liveMatch(rig, &wizard)
        let sub = try XCTUnwrap(rig.capture("sub", seconds: config.captureSeconds,
                                            band: WizardStep.subOnly.qualityBand(crossover: 90)))
        XCTAssertEqual(wizard.submit(sub), .accepted(sub.assessment.quality), "\(sub.assessment)")
        XCTAssertTrue(wizard.isAlignedWithinTolerance, "\(String(describing: wizard.alignment))")
        XCTAssertEqual(wizard.step, .verification, "glued → straight to the verification")

        // 3. Everything on: verification.
        rig.backend.setActiveGroups(sub: true, main: true)
        rig.run(seconds: 0.5)
        let v = try XCTUnwrap(rig.capture("verify", seconds: config.captureSeconds))
        _ = wizard.submit(v)
        XCTAssertNotNil(wizard.report)
        return (wizard, reading)
    }

    func testFullWizardInSimulation() throws {
        let (w, r) = try runWizard()
        // The live reading found the real correction: sub 2.5 m closer → ≈ 7.3 ms, wrong polarity, 3 dB hot.
        XCTAssertEqual(r.delayError * 1000, 2.5 / Acoustics.speedOfSound(celsius: 20) * 1000, accuracy: 0.6)
        XCTAssertTrue(r.polarityWrong, "polarity must be corrected")
        XCTAssertLessThan(r.levelError, -1.5, "the +3 dB hot sub must be turned down")
        XCTAssertGreaterThan(r.phaseGapDegrees, 45, "before matching the groups are far apart in phase")
        XCTAssertTrue(r.isReliable)
        // After entering it the groups are glued: residual alignment ≈ 0 and the sum has no dip.
        let a = try XCTUnwrap(w.alignment)
        XCTAssertLessThan(abs(a.roundedDelay * a.crossover * 360), 10)
        XCTAssertFalse(a.best.invertPolarity)
        let rep = try XCTUnwrap(w.report)
        XCTAssertLessThan(rep.after?.dipDepthDB ?? 99, 3, "acceptance: crossover dip < 3 dB")
        XCTAssertNotEqual(rep.verdict, .checkSettings, "\(rep)")
        // The summary shows the total change from the original state.
        if case .delaySub(let sec, let m) = w.actionCards[0] {
            XCTAssertEqual(sec * 1000, r.delayError * 1000, accuracy: 0.3)
            XCTAssertEqual(m, sec * Acoustics.speedOfSound(celsius: 20), accuracy: 1e-9)
        } else {
            XCTFail("expected sub delay card, got \(w.actionCards[0])")
        }
        XCTAssertEqual(w.actionCards[1], .polarity(invert: true))
    }

    /// Subs farther than the satellites: the needle asks for negative sub delay; the delay goes to the
    /// satellites and the stored reference is shifted, then the sub is glued.
    func testLateSubsGetMainsDelay() throws {
        let fs = 48000.0
        let room = VirtualRoom(reflections: [VirtualReflection(delaySamples: 168, gain: 0.3)],
                               modes: [Biquad.design(.peaking, frequency: 63, q: 6, gainDB: 6, sampleRate: fs)])
        let sys = VirtualSystem.typicalPA(sampleRate: fs, crossover: 90, subDistance: 11, mainDistance: 9.5,
                                          subGainDB: 0, subInverted: false, room: room, micNoiseDBFS: -75)
        let (w, r) = try runWizard(system: sys)
        XCTAssertLessThan(r.delayError, 0, "the subs arrive late")
        XCTAssertGreaterThan(w.mainsDelayAdded, 0)
        XCTAssertLessThan(w.report?.after?.dipDepthDB ?? 99, 3)
    }

    /// Steps 6–8: zone points → EQ → enter filters (virtual processor) → verification points.
    func testEQStepsInSimulation() throws {
        var w = try Self.runWizardKeepingRig()
        let rig = w.rig
        XCTAssertEqual(w.wizard.step, .verification)
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

    static func runWizardKeepingRig() throws -> (wizard: SetupWizard, rig: Rig, reading: AlignmentTuner.Reading) {
        let rig = Rig(system: Self.demoSystem())
        var config = WizardConfiguration()
        config.crossover = 90
        config.captureSeconds = 8
        config.target = .preset(.flat)
        var wizard = SetupWizard(configuration: config)
        let delay = try XCTUnwrap(rig.findDelay())
        wizard.lockDelay(delay, epoch: rig.backend.discontinuities.value)
        wizard.start()
        rig.backend.setActiveGroups(sub: false, main: true)
        rig.run(seconds: 0.5)
        wizard.submit(try XCTUnwrap(rig.capture("mains", seconds: config.captureSeconds,
                                                band: WizardStep.mainsOnly.qualityBand(crossover: 90))))
        let reading = try liveMatch(rig, &wizard)
        wizard.submit(try XCTUnwrap(rig.capture("sub", seconds: config.captureSeconds,
                                                band: WizardStep.subOnly.qualityBand(crossover: 90))))
        rig.backend.setActiveGroups(sub: true, main: true)
        if wizard.step == .results { wizard.beginVerification() }
        rig.run(seconds: 0.5)
        wizard.submit(try XCTUnwrap(rig.capture("verify", seconds: config.captureSeconds)))
        return (wizard, rig, reading)
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
        let c = try XCTUnwrap(rig.capture("mains", seconds: 3))
        guard case .rejected(let reasons) = wizard.submit(c) else { return XCTFail() }
        XCTAssertTrue(reasons.contains(.clipping))
        XCTAssertEqual(wizard.step, .mainsOnly)
    }
}
