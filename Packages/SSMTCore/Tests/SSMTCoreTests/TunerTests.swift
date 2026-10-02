import XCTest
@testable import SSMTCore

final class TunerTests: XCTestCase {
    let fs = 48000.0

    func system(subDistance: Double) -> VirtualSystem {
        let room = VirtualRoom(reflections: [VirtualReflection(delaySamples: 168, gain: 0.3)],
                               modes: [Biquad.design(.peaking, frequency: 63, q: 6, gainDB: 6, sampleRate: fs)])
        return VirtualSystem.typicalPA(sampleRate: fs, crossover: 90, subDistance: subDistance, mainDistance: 9.5,
                                       subGainDB: 3, subInverted: true, room: room, micNoiseDBFS: -75)
    }

    func captures(_ sys: VirtualSystem, lock: Int) -> (main: TransferFunction, sub: TransferFunction) {
        var m = sys; m.sub.enabled = false
        var s = sys; s.main.enabled = false
        return (TestSignals.measure(system: m, seconds: 10, referenceDelay: lock, seed: 2),
                TestSignals.measure(system: s, seconds: 10, referenceDelay: lock, seed: 3))
    }

    /// Turning the "knobs" step by step: the needle tracks the remaining error and ends in tune.
    func testNeedleTracksSubAdjustment() throws {
        var sys = system(subDistance: 7)
        let lock = 128 + sys.main.delaySamples
        let g = captures(sys, lock: lock)
        let rec = try SubAlignment.align(main: g.main, sub: g.sub, settings: AlignmentSettings(crossover: 90))
        let tuner = AlignmentTuner(stage: .adjustSub, fixed: g.main, alignment: rec, settings: AlignmentSettings(crossover: 90))
        let target = Int((rec.best.delay * fs).rounded())

        // 1. Nothing changed yet: polarity wrong, full delay and level error.
        var r = try XCTUnwrap(tuner.read(live: TestSignals.measure(system: sys, seconds: 6, referenceDelay: lock, seed: 5)))
        XCTAssertTrue(r.polarityWrong)
        XCTAssertFalse(r.allInTune)
        XCTAssertTrue(r.isReliable)

        // 2. Polarity switched, half the delay entered: needle shows the remaining half.
        sys.sub.invertPolarity = false
        sys.sub.delaySamples += target / 2
        r = try XCTUnwrap(tuner.read(live: TestSignals.measure(system: sys, seconds: 6, referenceDelay: lock, seed: 6)))
        XCTAssertFalse(r.polarityWrong)
        XCTAssertEqual(r.delayError * fs, Double(target - target / 2), accuracy: 3)
        XCTAssertFalse(r.delayInTune)

        // 3. Too much delay: the needle swings to the other side.
        sys.sub.delaySamples += target
        r = try XCTUnwrap(tuner.read(live: TestSignals.measure(system: sys, seconds: 6, referenceDelay: lock, seed: 7)))
        XCTAssertLessThan(r.delayError, 0)

        // 4. Exact setting and level: in tune.
        sys.sub.delaySamples = system(subDistance: 7).sub.delaySamples + target
        sys.sub.gainDB += rec.subGainDB
        r = try XCTUnwrap(tuner.read(live: TestSignals.measure(system: sys, seconds: 6, referenceDelay: lock, seed: 8)))
        XCTAssertTrue(r.delayInTune, "phase error \(r.delayPhaseError)°")
        XCTAssertEqual(r.levelError, 0, accuracy: 0.6)
        XCTAssertTrue(r.allInTune, "\(r)")
    }

    /// Sub arrives late: polarity/level on the sub, then the mains delay against the adjusted sub.
    func testMainsDelayStage() throws {
        var sys = system(subDistance: 11)
        let lock = 128 + sys.main.delaySamples
        let g = captures(sys, lock: lock)
        let rec = try SubAlignment.align(main: g.main, sub: g.sub, settings: AlignmentSettings(crossover: 90))
        XCTAssertEqual(rec.delayTarget, .mains)

        // Stage 1 done by the user: polarity and level on the sub.
        sys.sub.invertPolarity = false
        sys.sub.gainDB += rec.subGainDB
        let live1 = TestSignals.measure(system: sys, seconds: 8, referenceDelay: lock, seed: 4)
        let stage1 = AlignmentTuner(stage: .adjustSub, fixed: g.main, alignment: rec, settings: AlignmentSettings(crossover: 90))
        // The adjusted sub becomes the fixed reference for stage 2.
        let newSub = stage1.changingResponse(live: live1)
        let stage2 = AlignmentTuner(stage: .adjustMainsDelay, fixed: newSub, alignment: rec, settings: AlignmentSettings(crossover: 90))
        var r = try XCTUnwrap(stage2.read(live: live1))
        XCTAssertEqual(r.delayError, -rec.best.delay, accuracy: 3 / fs)
        XCTAssertGreaterThan(r.delayError, 0)

        sys.main.delaySamples += Int((r.delayError * fs).rounded())
        r = try XCTUnwrap(stage2.read(live: TestSignals.measure(system: sys, seconds: 8, referenceDelay: lock, seed: 9)))
        XCTAssertTrue(r.delayInTune, "phase error \(r.delayPhaseError)°")
    }

    func testVirtualProcessorKnobs() {
        let b = SimulatedAudioBackend(system: system(subDistance: 7), seed: 1)
        var p = VirtualProcessorSettings()
        p.subDelayMs = 2
        p.subPolarityInverted = true
        b.setProcessor(p)
        b.pump(frames: 16)
        XCTAssertEqual(b.system.sub.delaySamples, system(subDistance: 7).sub.delaySamples + 96)
        XCTAssertFalse(b.system.sub.invertPolarity) // base was inverted, knob inverts back
        b.applyAlignment(delaySeconds: -0.001, invertPolarity: false, subGainDB: -1)
        b.pump(frames: 16)
        XCTAssertEqual(b.processorSettings.mainsDelayMs, 1, accuracy: 1e-9)
        XCTAssertEqual(b.system.sub.gainDB, 2, accuracy: 1e-9)
    }
}
