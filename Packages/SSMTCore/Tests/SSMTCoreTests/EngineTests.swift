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
