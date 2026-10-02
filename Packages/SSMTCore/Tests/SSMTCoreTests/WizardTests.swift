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

    func demoSystem() -> VirtualSystem {
        let fs = 48000.0
        let room = VirtualRoom(reflections: [VirtualReflection(delaySamples: 168, gain: 0.3)],
                               modes: [Biquad.design(.peaking, frequency: 63, q: 6, gainDB: 6, sampleRate: fs)])
        // Sub 2.5 m closer, polarity inverted by mistake, 3 dB hot.
        return VirtualSystem.typicalPA(sampleRate: fs, crossover: 90, subDistance: 7, mainDistance: 9.5,
                                       subGainDB: 3, subInverted: true, room: room, micNoiseDBFS: -75)
    }

    func runWizard(fastMode: Bool) throws -> SetupWizard {
        let rig = Rig(system: demoSystem())
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
        XCTAssertEqual(wizard.step, .baseline)

        for step in [WizardStep.baseline, .subOnly, .mainsOnly] {
            if fastMode && step == .mainsOnly { break }
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
        XCTAssertEqual(wizard.step, .finished)
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

    func testFastModeWizard() throws {
        let w = try runWizard(fastMode: true)
        XCTAssertNil(w.mainsOnly)
        XCTAssertLessThan(w.report?.after?.dipDepthDB ?? 99, 3)
    }

    func testStreamRestartInvalidatesWizard() throws {
        let rig = Rig(system: demoSystem())
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
        let rig = Rig(system: demoSystem())
        var wizard = SetupWizard()
        let d = try XCTUnwrap(rig.findDelay())
        wizard.lockDelay(d, epoch: rig.backend.discontinuities.value)
        wizard.start()
        rig.backend.micPreampDB = 40
        let c = try XCTUnwrap(rig.capture("baseline", seconds: 3))
        guard case .rejected(let reasons) = wizard.submit(c) else { return XCTFail() }
        XCTAssertTrue(reasons.contains(.clipping))
        XCTAssertEqual(wizard.step, .baseline)
    }
}
