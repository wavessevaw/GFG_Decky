import XCTest
@testable import SSMTCore

/// Guards against performance regressions on the paths that run continuously while measuring.
/// Limits are generous (×5–10 above a typical run with the portable FFT) so they only fail on a
/// real slowdown, not on a busy CI machine.
final class PerformanceTests: XCTestCase {
    private func seconds(_ n: Int = 1, _ body: () -> Void) -> Double {
        let t = Date()
        for _ in 0..<n { body() }
        return Date().timeIntervalSince(t) / Double(n)
    }

    /// Live analysis must be a small fraction of real time (typical ≈ 17 ms per second of audio).
    func testAnalyzerIsFarFasterThanRealTime() {
        var rng = RandomSource(seed: 1)
        let x = (0..<48000).map { _ in Float(rng.nextGaussian() * 0.1) }
        let an = MultiWindowAnalyzer(config: .standard(sampleRate: 48000))
        an.setReferenceDelay(samples: 900)
        let t = seconds {
            for b in stride(from: 0, to: 48000, by: 1200) {
                an.ingest(reference: Array(x[b..<b + 1200]), measurement: Array(x[b..<b + 1200]))
            }
        }
        XCTAssertLessThan(t, 0.2, "analysis of 1 s of audio took \(t * 1000) ms")
    }

    /// The tuner runs the full alignment several times a second (typical ≈ 4 ms per reading).
    func testTunerReadingIsCheap() throws {
        let sys = WizardTests.demoSystem()
        var m = sys; m.sub.enabled = false
        var s = sys; s.main.enabled = false
        let lock = 128 + sys.main.delaySamples
        let hm = TestSignals.measure(system: m, seconds: 6, referenceDelay: lock, seed: 2)
        let hs = TestSignals.measure(system: s, seconds: 6, referenceDelay: lock, seed: 3)
        let rec = try SubAlignment.align(main: hm, sub: hs, settings: AlignmentSettings(crossover: 90))
        let tuner = AlignmentTuner(stage: .adjustSub, fixed: hm, alignment: rec, settings: AlignmentSettings(crossover: 90))
        let live = TestSignals.measure(system: sys, seconds: 6, referenceDelay: lock, seed: 4)
        let t = seconds(5) { _ = tuner.read(live: live) }
        XCTAssertLessThan(t, 0.05, "tuner reading took \(t * 1000) ms")
    }
}
