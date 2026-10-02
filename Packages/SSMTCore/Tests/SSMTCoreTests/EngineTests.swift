import XCTest
@testable import SSMTCore

final class EngineTests: XCTestCase {
    func makeBackend(sub: Bool = true, main: Bool = true) -> SimulatedAudioBackend {
        var system = VirtualSystem.typicalPA(subDistance: 9.5, mainDistance: 9.5)
        system.sub.enabled = sub
        system.main.enabled = main
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 0.01
        safety.startLevelDBFS = -20
        return SimulatedAudioBackend(system: system, deviceLatency: 512, bank: GeneratorBankSpec(), safety: safety, seed: 3)
    }

    func testCaptureThroughEngineMatchesSystem() {
        let backend = makeBackend()
        let engine = MeasurementEngine(backend: backend)
        backend.generatorControl.targetLevelDBFS.value = -20
        backend.generatorControl.run.value = true
        engine.setReferenceDelay(samples: 512 + backend.system.main.delaySamples)
        // Pre-roll so the virtual system's delay lines are filled.
        for _ in 0..<40 { backend.pump(frames: 1200) }
        engine.drainNow()
        let done = expectation(description: "capture")
        var result: Capture?
        engine.capture(label: "all", duration: 6) { c in
            result = c
            done.fulfill()
        }
        for _ in 0..<(6 * 40 + 4) {
            backend.pump(frames: 1200)
            engine.drainNow()
        }
        wait(for: [done], timeout: 5)
        let c = try! XCTUnwrap(result)
        XCTAssertEqual(c.assessment.quality, .good)
        XCTAssertFalse(c.assessment.clipped)
        let tau = Double(backend.system.main.delaySamples) / 48000
        let i = c.transfer.frequencies.firstIndex { $0 >= 1000 }!
        let truth = backend.system.response(at: c.transfer.frequencies[i]) * Complex.expj(2 * .pi * c.transfer.frequencies[i] * tau)
        XCTAssertEqual(c.transfer.response[i].magnitude, truth.magnitude, accuracy: 0.03)
    }

    func testClippedCaptureIsRejected() {
        let backend = makeBackend()
        backend.micPreampDB = 40
        let engine = MeasurementEngine(backend: backend)
        backend.generatorControl.targetLevelDBFS.value = -12
        backend.generatorControl.run.value = true
        let done = expectation(description: "capture")
        var result: Capture?
        engine.capture(label: "clip", duration: 2) { c in
            result = c
            done.fulfill()
        }
        for _ in 0..<(2 * 40 + 4) {
            backend.pump(frames: 1200)
            engine.drainNow()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(result?.assessment.quality, .repeatRequired)
        XCTAssertTrue(result?.assessment.reasons.contains(.clipping) ?? false)
    }

    func testEmergencyStopSilencesNextBuffer() {
        let backend = makeBackend()
        backend.generatorControl.targetLevelDBFS.value = -20
        backend.generatorControl.run.value = true
        backend.pump(frames: 4800)
        _ = backend.outputRing.read(maxFrames: 4800)
        backend.generatorControl.emergencyStop()
        backend.pump(frames: 256)
        let out = backend.outputRing.read(maxFrames: 256)[0]
        XCTAssertEqual(out.map(abs).max(), 0)
        // And it stays silent while run is off.
        backend.pump(frames: 4800)
        XCTAssertEqual(backend.outputRing.read(maxFrames: 4800)[0].map(abs).max(), 0)
    }

    func testRealtimeSimulationThreadProducesSnapshots() throws {
        let backend = makeBackend()
        let engine = MeasurementEngine(backend: backend)
        let got = expectation(description: "snapshot with transfer")
        got.assertForOverFulfill = false
        engine.setSnapshotHandler { s in
            if s.transfer != nil && s.microphone.rmsDBFS > -60 { got.fulfill() }
        }
        backend.generatorControl.targetLevelDBFS.value = -20
        backend.generatorControl.run.value = true
        try engine.start()
        wait(for: [got], timeout: 6)
        engine.stop()
    }
}

final class EngineDelayTests: XCTestCase {
    func testEngineFindsAndLocksDelay() {
        var system = VirtualSystem.typicalPA(subDistance: 9.5, mainDistance: 9.5)
        system.sub.enabled = false
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 0.01
        safety.startLevelDBFS = -20
        let backend = SimulatedAudioBackend(system: system, deviceLatency: 777, safety: safety, seed: 5)
        let engine = MeasurementEngine(backend: backend)
        backend.generatorControl.targetLevelDBFS.value = -20
        backend.generatorControl.run.value = true
        for _ in 0..<10 { backend.pump(frames: 1200) }
        engine.drainNow()
        let done = expectation(description: "delay")
        var estimate: DelayEstimate?
        engine.findDelay(seconds: 2) { e in
            estimate = e
            done.fulfill()
        }
        for _ in 0..<90 {
            backend.pump(frames: 1200)
            engine.drainNow()
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(estimate?.samples ?? 0, Double(777 + system.main.delaySamples), accuracy: 1)
    }
}

final class AutoLevelTests: XCTestCase {
    func makeBackend(micNoise: Double, preamp: Double = 0) -> SimulatedAudioBackend {
        var system = VirtualSystem.typicalPA(subDistance: 9.5, mainDistance: 9.5)
        system.micNoiseDBFS = micNoise
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 0.2
        safety.startLevelDBFS = -60
        safety.maximumLevelDBFS = -6
        let b = SimulatedAudioBackend(system: system, deviceLatency: 512, safety: safety, seed: 11)
        b.micPreampDB = preamp
        return b
    }

    /// Drives a full noise-floor + auto-level sequence synchronously.
    func runSequence(_ backend: SimulatedAudioBackend, settings: AutoLevelController.Settings)
        -> (Double, AutoLevelController.Outcome)? {
        let engine = MeasurementEngine(backend: backend)
        engine.setReferenceDelay(samples: 512 + backend.system.main.delaySamples)
        var floor: [Double]?
        engine.measureNoiseFloor(seconds: 3) { floor = $0 }
        for _ in 0..<(4 * 40) where floor == nil {
            backend.pump(frames: 1200)
            engine.drainNow()
        }
        guard let nf = floor else { XCTFail("no noise floor"); return nil }
        XCTAssertTrue(nf.filter { $0.isFinite && $0 > 0 }.count > 200)
        var result: (Double, AutoLevelController.Outcome)?
        engine.runAutoLevel(settings: settings, noiseFloor: nf) { result = ($0, $1) }
        for _ in 0..<(120 * 40) where result == nil {
            backend.pump(frames: 1200)
            engine.drainNow()
        }
        return result
    }

    func testReachesTargetSNR() {
        var s = AutoLevelController.Settings()
        s.maximumLevelDBFS = -6
        let r = runSequence(makeBackend(micNoise: -70), settings: s)
        guard case .targetReached(let snr)? = r?.1 else { return XCTFail("unexpected \(String(describing: r))") }
        XCTAssertGreaterThanOrEqual(snr, 20)
        XCTAssertLessThanOrEqual(r!.0, -6)
        XCTAssertGreaterThan(r!.0, -60)
    }

    func testStopsAtUserMaximum() {
        var s = AutoLevelController.Settings()
        s.maximumLevelDBFS = -50
        let r = runSequence(makeBackend(micNoise: -45), settings: s)
        guard case .maximumReached? = r?.1 else { return XCTFail("unexpected \(String(describing: r))") }
        XCTAssertEqual(r!.0, -50, accuracy: 1e-9)
    }

    func testBacksOffOnClipping() {
        var s = AutoLevelController.Settings()
        s.maximumLevelDBFS = 0
        s.targetSNRDB = 200 // unreachable: forces raising until clipping
        let r = runSequence(makeBackend(micNoise: -90, preamp: 30), settings: s)
        XCTAssertEqual(r?.1, .clipped)
    }
}

final class SPLEngineTests: XCTestCase {
    func testSnapshotCarriesSoundLevel() {
        let backend = SimulatedAudioBackend(system: .typicalPA(), seed: 1)
        let engine = MeasurementEngine(backend: backend)
        engine.setSPLCalibration(SPLCalibration(dBFSAt94dBSPL: -30))
        let got = expectation(description: "snapshot")
        got.assertForOverFulfill = false
        var reading: SoundLevelReading?
        engine.setSnapshotHandler { s in
            reading = s.soundLevel
            got.fulfill()
        }
        backend.generatorControl.targetLevelDBFS.value = -20
        backend.generatorControl.run.value = true
        for _ in 0..<40 { backend.pump(frames: 1200) }
        engine.drainNow()
        wait(for: [got], timeout: 2)
        XCTAssertTrue(reading?.isCalibrated ?? false)
        // Generator is still fading in after 1 s (safe start); only check a sensible calibrated value.
        XCTAssertGreaterThan(reading?.laeq ?? 0, 30)
    }
}
