import XCTest
@testable import SSMTCore

final class DelayFinderTests: XCTestCase {
    func run(system: VirtualSystem, latency: Int, seconds: Double = 3, seed: UInt64 = 1) -> DelayEstimate? {
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 0.001
        safety.startLevelDBFS = -20
        let rig = SimulatedRig(system: system, deviceLatency: latency, seed: seed, safety: safety)
        _ = rig.render(count: 4800)
        let b = rig.render(count: Int(seconds * system.sampleRate))
        return DelayFinder.estimate(reference: b.generated, measurement: b.microphone, sampleRate: system.sampleRate)
    }

    func testFindsKnownDelaysWithinOneSample() {
        for (distance, latency) in [(3.0, 128), (17.0, 512), (60.0, 7000), (120.0, 6000)] {
            var system = VirtualSystem.typicalPA(mainDistance: distance)
            system.sub.enabled = false
            let truth = Double(latency + system.main.delaySamples)
            let e = try! XCTUnwrap(run(system: system, latency: latency))
            // Mains include a 2nd-order HPF etc.; the arrival peak sits at the bulk delay.
            XCTAssertEqual(e.samples, truth, accuracy: 1.0, "distance \(distance) m")
            XCTAssertTrue(e.isReliable)
        }
    }

    func testFindsDelayUpTo500msWithNoise() {
        var system = VirtualSystem.typicalPA(mainDistance: 160) // ≈ 466 ms
        system.sub.enabled = false
        system.micNoiseDBFS = -32 // poor SNR
        let truth = Double(256 + system.main.delaySamples)
        XCTAssertGreaterThan(truth / 48000, 0.45)
        let e = try! XCTUnwrap(run(system: system, latency: 256, seconds: 5.5))
        XCTAssertEqual(e.samples, truth, accuracy: 1.0)
        XCTAssertTrue(e.isReliable)
    }

    func testReportsUnreliableOnPureNoise() {
        var rng = RandomSource(seed: 1)
        let x = (0..<144000).map { _ in Float(rng.nextGaussian()) }
        let y = (0..<144000).map { _ in Float(rng.nextGaussian()) }
        let e = DelayFinder.estimate(reference: x, measurement: y, sampleRate: 48000)
        XCTAssertFalse(e?.isReliable ?? false)
    }

    func testMetersFromTemperature() {
        let e = DelayEstimate(samples: 480, sampleRate: 48000, confidence: 10, peakToNoiseDB: 30)
        XCTAssertEqual(e.meters(celsius: 20), 0.01 * (331.3 + 0.606 * 20), accuracy: 1e-9)
    }
}
