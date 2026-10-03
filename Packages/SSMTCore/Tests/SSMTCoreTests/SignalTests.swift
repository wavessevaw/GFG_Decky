import XCTest
@testable import SSMTCore
import SSMTRealtime

final class SignalTests: XCTestCase {
    /// Pink noise must fall at −3 dB/octave across the audio band.
    func testPinkNoiseSlope() {
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 0.001
        safety.startLevelDBFS = -20
        safety.peakCeilingDBFS = 0
        let gen = SignalGenerator(kind: .pink, sampleRate: 48000, seed: 9, safety: safety)
        let x = gen.render(count: 48000 * 20, targetLevelDBFS: -20).map(Double.init)
        let acc = WelchAccumulator(fftSize: 16384, overlap: 0.5, window: .hann, sampleRate: 48000)
        acc.ingest(reference: x, measurement: x)
        func bandPower(_ f: Double) -> Double {
            let lo = Int(f / pow(2, 1.0 / 6) / acc.binSpacing), hi = Int(f * pow(2, 1.0 / 6) / acc.binSpacing)
            return (lo...hi).reduce(0) { $0 + acc.gxx[$1] } / Double(hi - lo + 1)
        }
        let ref = Decibel.fromPower(bandPower(1000))
        for f in [31.5, 63, 125, 250, 500, 2000, 4000, 8000, 16000] {
            let expected = -3 * log2(f / 1000)
            XCTAssertEqual(Decibel.fromPower(bandPower(f)) - ref, expected, accuracy: 0.75, "at \(f) Hz")
        }
    }

    func testGeneratorLevelAndCeiling() {
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 0.001
        safety.startLevelDBFS = -6
        safety.maximumLevelDBFS = 0
        safety.peakCeilingDBFS = -3
        let gen = SignalGenerator(kind: .white, sampleRate: 48000, seed: 1, safety: safety)
        let x = gen.render(count: 48000 * 2, targetLevelDBFS: -6)
        let ceiling = Float(Decibel.toAmplitude(-3))
        XCTAssertLessThanOrEqual(x.map(abs).max()!, ceiling + 1e-6)
    }

    func testFadeInIsSmoothAndStartsSilent() {
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 1
        safety.startLevelDBFS = -20
        let gen = SignalGenerator(kind: .periodicPink(periodLength: 4096), sampleRate: 48000, seed: 1, safety: safety)
        let x = gen.render(count: 48000, targetLevelDBFS: -20)
        XCTAssertLessThan(TestSignals.rms(Array(x[0..<480])), Decibel.toAmplitude(-60))
        XCTAssertGreaterThan(TestSignals.rms(Array(x[47000..<48000])), Decibel.toAmplitude(-23))
    }

    func testLevelRiseIsSlewLimitedAndTargetClamped() {
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 0.001
        safety.startLevelDBFS = -60
        safety.maximumLevelDBFS = -30
        let gen = SignalGenerator(kind: .pink, sampleRate: 48000, seed: 1, safety: safety)
        _ = gen.render(count: 48000, targetLevelDBFS: 0)
        XCTAssertEqual(gen.currentLevelDBFS, -57, accuracy: 0.01) // 3 dB/s
        for _ in 0..<20 { _ = gen.render(count: 48000, targetLevelDBFS: 0) }
        XCTAssertEqual(gen.currentLevelDBFS, -30, accuracy: 1e-9) // clamped to user maximum
    }

    func testHardMuteSilencesImmediately() {
        var safety = GeneratorSafety()
        safety.fadeInSeconds = 0.001
        let gen = SignalGenerator(kind: .pink, sampleRate: 48000, seed: 1, safety: safety)
        _ = gen.render(count: 4800, targetLevelDBFS: -20)
        gen.hardMute()
        // After a hard mute the next sample must already be silent even if run is requested on
        // the following block (fade restarts from zero).
        let x = gen.render(count: 1, run: false, targetLevelDBFS: -20)
        XCTAssertEqual(x[0], 0)
    }

    func testPeriodicPinkIsExactlyPeriodicAndFlatPerOctave() {
        let n = 8192
        let p = PeriodicNoise.pinkPeriod(length: n, sampleRate: 48000, seed: 3)
        XCTAssertEqual(TestSignals.rms(p.map(Float.init)), 1, accuracy: 1e-6)
        let spec = FFT.realForward(p, engine: FFT.make(size: n))
        // Every bin above the low cut has |X|² ∝ 1/f.
        let k1 = 100, k2 = 1600
        let r = (spec.re[k1] * spec.re[k1] + spec.im[k1] * spec.im[k1]) /
            (spec.re[k2] * spec.re[k2] + spec.im[k2] * spec.im[k2])
        XCTAssertEqual(r, 16, accuracy: 1e-6)
    }

    func testRingBufferRoundTripAndOverflow() {
        let ring = ssmt_ring_create(1000, 2)!
        defer { ssmt_ring_destroy(ring) }
        XCTAssertEqual(ssmt_ring_capacity(ring), 1024)
        let a: [Float] = (0..<700).map(Float.init)
        let b: [Float] = (0..<700).map { -Float($0) }
        a.withUnsafeBufferPointer { pa in
            b.withUnsafeBufferPointer { pb in
                var ptrs: [UnsafePointer<Float>?] = [pa.baseAddress, pb.baseAddress]
                XCTAssertEqual(ssmt_ring_write_planar(ring, &ptrs, 700), 700)
                XCTAssertEqual(ssmt_ring_write_planar(ring, &ptrs, 700), 324)
            }
        }
        XCTAssertEqual(ssmt_ring_overflow_count(ring), 376)
        var outA = [Float](repeating: 0, count: 1024), outB = outA
        outA.withUnsafeMutableBufferPointer { pa in
            outB.withUnsafeMutableBufferPointer { pb in
                var ptrs: [UnsafeMutablePointer<Float>?] = [pa.baseAddress, pb.baseAddress]
                XCTAssertEqual(ssmt_ring_read_planar(ring, &ptrs, 1024), 1024)
            }
        }
        XCTAssertEqual(outA[699], 699)
        XCTAssertEqual(outB[699], -699)
        XCTAssertEqual(outA[700], 0)
        XCTAssertEqual(outA[1023], 323)
    }

    func testRingBufferConcurrentProducerConsumer() {
        let ring = ssmt_ring_create(4096, 1)!
        defer { ssmt_ring_destroy(ring) }
        let total = 2_000_000
        let producer = Thread {
            var next = 0
            var block = [Float](repeating: 0, count: 256)
            while next < total {
                let n = min(256, total - next)
                for i in 0..<n { block[i] = Float(next + i) }
                block.withUnsafeBufferPointer { p in
                    var ptrs: [UnsafePointer<Float>?] = [p.baseAddress]
                    var written: UInt64 = 0
                    while written == 0 {
                        // Write only when there is room so nothing is dropped in this test.
                        if ssmt_ring_capacity(ring) - ssmt_ring_readable(ring) >= UInt64(n) {
                            written = ssmt_ring_write_planar(ring, &ptrs, UInt64(n))
                        }
                    }
                }
                next += n
            }
        }
        producer.start()
        var expected = 0
        var out = [Float](repeating: 0, count: 512)
        let deadline = Date().addingTimeInterval(30)
        while expected < total && Date() < deadline {
            let got = out.withUnsafeMutableBufferPointer { p -> Int in
                var ptrs: [UnsafeMutablePointer<Float>?] = [p.baseAddress]
                return Int(ssmt_ring_read_planar(ring, &ptrs, 512))
            }
            for i in 0..<got where out[i] != Float(expected + i) {
                XCTFail("Mismatch at \(expected + i)")
                return
            }
            expected += got
        }
        XCTAssertEqual(expected, total)
        XCTAssertEqual(ssmt_ring_overflow_count(ring), 0)
    }
}
