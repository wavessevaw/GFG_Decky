import XCTest
@testable import SSMTCore

final class AnalyzerTests: XCTestCase {
    let fs = 48000.0

    /// Noise-free system with known filters: measured H must match the analytic response.
    func testTransferFunctionMatchesAnalyticResponse() {
        let system = VirtualSystem.typicalPA(sampleRate: fs, subDistance: 9.5, mainDistance: 9.5)
        let tf = TestSignals.measure(system: system, seconds: 16)
        let tau = Double(system.main.delaySamples) / fs
        var checked = 0
        for i in tf.frequencies.indices where tf.frequencies[i] >= 25 && tf.frequencies[i] <= 16000 {
            let f = tf.frequencies[i]
            let truth = system.response(at: f) * Complex.expj(2 * .pi * f * tau)
            let m = tf.response[i]
            XCTAssertEqual(Decibel.fromAmplitude(m.magnitude), Decibel.fromAmplitude(truth.magnitude),
                           accuracy: 0.25, "magnitude at \(f) Hz")
            let dphi = PhaseTools.wrap(m.phase - truth.phase) * 180 / .pi
            XCTAssertEqual(dphi, 0, accuracy: 3, "phase at \(f) Hz")
            XCTAssertGreaterThan(tf.coherence[i], 0.98, "coherence at \(f) Hz")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 200)
    }

    /// Multi-window seams (100/500/2000 Hz) must not create jumps: the error against the
    /// analytic response must be the same just below and just above each seam.
    func testMultiWindowStitchingIsContinuous() {
        var system = VirtualSystem.typicalPA(sampleRate: fs, subDistance: 9.5, mainDistance: 9.5)
        system.sub.enabled = false
        let tf = TestSignals.measure(system: system, seconds: 30)
        let tau = Double(system.main.delaySamples) / fs
        func errors(_ idx: [Int]) -> (mag: Double, phase: Double) {
            var m = 0.0, p = 0.0
            for i in idx {
                let f = tf.frequencies[i]
                let truth = system.response(at: f) * Complex.expj(2 * .pi * f * tau)
                m += Decibel.fromAmplitude(tf.response[i].magnitude) - Decibel.fromAmplitude(truth.magnitude)
                p += PhaseTools.wrap(tf.response[i].phase - truth.phase) * 180 / .pi
            }
            return (m / Double(idx.count), p / Double(idx.count))
        }
        for seam in [100.0, 500, 2000] {
            let below = tf.frequencies.indices.filter { tf.frequencies[$0] < seam && tf.frequencies[$0] > seam / pow(2, 1.0 / 3) }
            let above = tf.frequencies.indices.filter { tf.frequencies[$0] >= seam && tf.frequencies[$0] < seam * pow(2, 1.0 / 3) }
            let eb = errors(below), ea = errors(above)
            XCTAssertEqual(eb.mag, ea.mag, accuracy: 0.05, "magnitude seam \(seam) Hz")
            XCTAssertEqual(eb.phase, ea.phase, accuracy: 0.5, "phase seam \(seam) Hz")
            for i in below + above {
                let f = tf.frequencies[i]
                let truth = system.response(at: f) * Complex.expj(2 * .pi * f * tau)
                XCTAssertEqual(Decibel.fromAmplitude(tf.response[i].magnitude),
                               Decibel.fromAmplitude(truth.magnitude), accuracy: 0.15, "at \(f)")
            }
        }
    }

    /// With uncorrelated noise at the microphone the coherence must follow γ² = S/(S+N).
    func testCoherenceFollowsSignalToNoiseRatio() {
        var system = VirtualSystem.typicalPA(sampleRate: fs, subDistance: 9.5, mainDistance: 9.5)
        system.sub.enabled = false
        // White noise at the mic: per-octave noise power grows toward HF while pink stays
        // constant per octave, so the SNR (and coherence) must fall with frequency.
        system.micNoiseDBFS = -30
        let tf = TestSignals.measure(system: system, seconds: 20, level: -20)
        let lowIdx = tf.frequencies.indices.filter { tf.frequencies[$0] > 300 && tf.frequencies[$0] < 1000 }
        let highIdx = tf.frequencies.indices.filter { tf.frequencies[$0] > 10000 && tf.frequencies[$0] < 16000 }
        let lowMean = lowIdx.map { tf.coherence[$0] }.reduce(0, +) / Double(lowIdx.count)
        let highMean = highIdx.map { tf.coherence[$0] }.reduce(0, +) / Double(highIdx.count)
        XCTAssertGreaterThan(lowMean, 0.9)
        XCTAssertLessThan(highMean, lowMean - 0.1)

        // Quantitative check against theory using the measured auto-spectra:
        // noise PSD (white, density-scaled) is known: σ² / (fs/2) per Hz → per-bin density σ².
        let sigma2 = Decibel.toPower(-30)
        for i in highIdx {
            let s = tf.measurementPower[i] - sigma2
            let expected = max(s, 0) / tf.measurementPower[i]
            XCTAssertEqual(tf.coherence[i], expected, accuracy: 0.08, "at \(tf.frequencies[i])")
        }
    }

    /// The transfer-function magnitude must stay accurate (bias-free) at moderate SNR.
    func testTransferFunctionAccuracyAtModerateSNR() {
        var system = VirtualSystem.typicalPA(sampleRate: fs, subDistance: 9.5, mainDistance: 9.5)
        system.micNoiseDBFS = -45
        let tf = TestSignals.measure(system: system, seconds: 20, level: -20)
        let tau = Double(system.main.delaySamples) / fs
        for i in tf.frequencies.indices where tf.frequencies[i] >= 40 && tf.frequencies[i] <= 8000 {
            guard tf.coherence[i] > 0.8 else { continue }
            let truth = system.response(at: tf.frequencies[i]) * Complex.expj(2 * .pi * tf.frequencies[i] * tau)
            XCTAssertEqual(Decibel.fromAmplitude(tf.response[i].magnitude),
                           Decibel.fromAmplitude(truth.magnitude), accuracy: 0.6, "at \(tf.frequencies[i])")
        }
    }

    func testUncompensatedDelayLowersHighFrequencyCoherence() {
        var system = VirtualSystem.typicalPA(sampleRate: fs, subDistance: 9.5, mainDistance: 9.5)
        system.sub.enabled = false
        // Reference not delayed: 1024-sample window cannot see the arrival at 9.5 m (≈1330 samples).
        let tf = TestSignals.measure(system: system, seconds: 8, referenceDelay: 0)
        let hf = tf.frequencies.indices.filter { tf.frequencies[$0] > 4000 }
        XCTAssertLessThan(hf.map { tf.coherence[$0] }.reduce(0, +) / Double(hf.count), 0.3)
    }

    func testPhaseSlopeDelayEstimate() {
        var system = VirtualSystem.typicalPA(sampleRate: fs, subDistance: 9.5, mainDistance: 9.5)
        system.sub.enabled = false
        // Compensate 20 samples less than the true delay; the slope must reveal them.
        let tf = TestSignals.measure(system: system, seconds: 8, referenceDelay: 128 + system.main.delaySamples - 20)
        let d = PhaseTools.phaseSlopeDelay(tf, from: 2000, to: 12000)
        XCTAssertNotNil(d)
        XCTAssertEqual(d! * fs, 20, accuracy: 1.0)
    }
}

extension TransferFunction {
    /// Grid indices i (with i+1 valid) within ±octaves of a frequency.
    func grid(around f: Double, octaves: Double) -> [Int] {
        frequencies.indices.filter {
            $0 + 1 < frequencies.count && abs(log2(frequencies[$0] / f)) <= octaves
        }
    }
}
