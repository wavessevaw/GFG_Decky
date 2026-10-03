import XCTest
@testable import SSMTCore

final class CalibrationTests: XCTestCase {
    func testParsesHeaderStyleFile() throws {
        let text = """
        "Sens Factor =-1.378dB, SERNO: 7023270"
        10.054\t-3.1\t0.0
        20.000\t-1.0\t0.0
        1000.0\t0.0\t0.0
        10000.0\t2.0\t0.0
        20000.0\t-4.0\t0.0
        """
        let c = try MicrophoneCalibration.parse(text, name: "test")
        XCTAssertEqual(c.frequencies.count, 5)
        XCTAssertEqual(c.sensitivityDB ?? 0, -1.378, accuracy: 1e-9)
        XCTAssertEqual(c.serialNumber, "7023270")
        XCTAssertEqual(c.deviation(at: 1000), 0, accuracy: 1e-12)
        // Log interpolation: midpoint in log frequency between 1 k and 10 k → 1 dB.
        XCTAssertEqual(c.deviation(at: 1000 * pow(10, 0.5)), 1, accuracy: 1e-9)
        XCTAssertEqual(c.deviation(at: 5), -3.1)      // clamped below
        XCTAssertEqual(c.deviation(at: 30000), -4.0)  // clamped above
    }

    func testParsesCommentsCsvAndEuropeanDecimals() throws {
        let csv = "* REW style comment\n20,-1.5\n100,0.25\n1000,0\n"
        XCTAssertEqual(try MicrophoneCalibration.parse(csv, name: "csv").deviationDB, [-1.5, 0.25, 0])
        let eu = "Sensitivity: -37,5 dBFS\n20;-1,5\n100;0,25\n1000;0\n"
        let c = try MicrophoneCalibration.parse(eu, name: "eu")
        XCTAssertEqual(c.deviationDB, [-1.5, 0.25, 0])
        XCTAssertEqual(c.sensitivityDB ?? 0, -37.5, accuracy: 1e-9)
    }

    func testRejectsBadFiles() {
        XCTAssertThrowsError(try MicrophoneCalibration.parse("hello", name: "x"))
        XCTAssertThrowsError(try MicrophoneCalibration.parse("100 1\n50 2\n200 3", name: "x"))
    }

    func testApplyRemovesMicResponse() throws {
        let c = try MicrophoneCalibration.parse("20 6\n1000 6\n20000 6", name: "flat+6")
        let tf = TransferFunction(frequencies: [100, 1000], response: [Complex(2), Complex(2)],
                                  coherence: [1, 1], measurementPower: [1, 1], referencePower: [1, 1], averages: 1)
        let out = c.apply(to: tf)
        XCTAssertEqual(Decibel.fromAmplitude(out.response[0].magnitude), Decibel.fromAmplitude(2) - 6, accuracy: 1e-9)
    }
}

final class SoundLevelTests: XCTestCase {
    let fs = 48000.0

    func testDigitalWeightingMatchesIEC() {
        for w in [FrequencyWeighting.a, .c] {
            let bq = w.biquads(sampleRate: fs)
            for (f, tol) in [(31.5, 0.3), (63.0, 0.2), (125.0, 0.2), (250.0, 0.2), (500.0, 0.2), (1000.0, 0.05),
                             (2000.0, 0.2), (4000.0, 0.4), (8000.0, 1.2)] {
                let digital = Decibel.fromAmplitude(bq.reduce(Complex.one) { $0 * $1.response(at: f, sampleRate: fs) }.magnitude)
                XCTAssertEqual(digital, w.analyticDB(at: f), accuracy: tol, "\(w.rawValue) at \(f)")
            }
        }
        XCTAssertEqual(FrequencyWeighting.a.analyticDB(at: 1000), 0, accuracy: 0.01)
        XCTAssertEqual(FrequencyWeighting.a.analyticDB(at: 100), -19.1, accuracy: 0.1)
    }

    func testCalibratedSineReads94() {
        // Calibrator: 1 kHz sine whose RMS is −20 dBFS (sine-referenced) at 94 dB SPL.
        let amp = Decibel.toAmplitude(-20)
        let x = (0..<Int(fs * 2)).map { Float(amp * sin(2 * .pi * 1000 * Double($0) / fs)) }
        var meter = SoundLevelMeter(sampleRate: fs)
        meter.process(x)
        let raw = meter.reading()
        XCTAssertEqual(raw.laeq, -20, accuracy: 0.05)
        let cal = SPLCalibration.fromCalibrator(measuredDBFS: raw.laeq, calibratorSPL: 94)
        var m2 = SoundLevelMeter(sampleRate: fs, calibration: cal)
        // Let the weighting filters settle (an abrupt sine start overshoots like on a real meter).
        m2.process(Array(x[0..<24000]))
        m2.reset()
        m2.process(Array(x[24000...]))
        let r = m2.reading()
        XCTAssertEqual(r.laeq, 94, accuracy: 0.05)
        XCTAssertEqual(r.lceq, 94, accuracy: 0.05)
        XCTAssertEqual(r.lmax, 94, accuracy: 0.1)
        XCTAssertEqual(r.lpeak, 97.0, accuracy: 0.1) // sine peak = RMS + 3 dB
        XCTAssertTrue(r.isCalibrated)
    }

    func testSensitivityCalibration() {
        // 10 mV/Pa into an interface where 0 dBFS = +4 dBV → 94 dB SPL reads −44 dBFS.
        let c = SPLCalibration.fromSensitivity(millivoltsPerPascal: 10, fullScaleDBV: 4)
        XCTAssertEqual(c.dBFSAt94dBSPL, -44, accuracy: 1e-9)
        XCTAssertEqual(c.spl(fromDBFS: -24), 114, accuracy: 1e-9)
    }
}
