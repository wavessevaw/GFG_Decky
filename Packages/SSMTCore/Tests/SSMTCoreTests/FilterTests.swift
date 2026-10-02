import XCTest
@testable import SSMTCore

final class FilterTests: XCTestCase {
    let fs = 48000.0

    func testPeakingGainAtCenter() {
        let b = Biquad.design(.peaking, frequency: 1000, q: 2, gainDB: -6, sampleRate: fs)
        XCTAssertEqual(Decibel.fromAmplitude(b.response(at: 1000, sampleRate: fs).magnitude), -6, accuracy: 1e-9)
        XCTAssertEqual(Decibel.fromAmplitude(b.response(at: 20, sampleRate: fs).magnitude), 0, accuracy: 0.01)
    }

    func testLinkwitzRileySumIsAllPass() {
        let lp = CrossoverFilter.linkwitzRiley24(.lowPass, frequency: 100, sampleRate: fs)
        let hp = CrossoverFilter.linkwitzRiley24(.highPass, frequency: 100, sampleRate: fs)
        for f in [20.0, 50, 100, 200, 1000, 10000] {
            let l = lp.reduce(Complex.one) { $0 * $1.response(at: f, sampleRate: fs) }
            let h = hp.reduce(Complex.one) { $0 * $1.response(at: f, sampleRate: fs) }
            XCTAssertEqual((l + h).magnitude, 1, accuracy: 1e-6, "at \(f)")
        }
        let l = lp.reduce(Complex.one) { $0 * $1.response(at: 100, sampleRate: fs) }
        XCTAssertEqual(Decibel.fromAmplitude(l.magnitude), -6.02, accuracy: 0.01)
    }

    func testCascadeTimeDomainMatchesResponse() {
        var c = BiquadCascade(CrossoverFilter.butterworth(.highPass, order: 4, frequency: 200, sampleRate: fs))
        let f = 300.0
        var peak = 0.0
        for n in 0..<48000 {
            let y = c.process(sin(2 * .pi * f * Double(n) / fs))
            if n > 24000 { peak = max(peak, abs(y)) }
        }
        XCTAssertEqual(peak, c.response(at: f, sampleRate: fs).magnitude, accuracy: 1e-3)
    }

    func testSmoothingOfConstantIsConstantAndUnwrap() {
        let grid = FrequencyGrid()
        let flat = [Double](repeating: 2, count: grid.count)
        let s = Smoothing.smoothPower(flat, frequencies: grid.frequencies, octaves: 1.0 / 3)
        XCTAssertTrue(s.allSatisfy { abs($0 - 2) < 1e-12 })
        let wrapped = (0..<100).map { PhaseTools.wrap(Double($0) * 0.5) }
        let un = PhaseTools.unwrap(wrapped)
        for i in 0..<100 { XCTAssertEqual(un[i] - un[0], Double(i) * 0.5, accuracy: 1e-9) }
    }

    func testFrequencyGrid() {
        let g = FrequencyGrid(pointsPerOctave: 24)
        XCTAssertTrue(g.frequencies.contains { abs($0 - 1000) < 1e-9 })
        XCTAssertGreaterThanOrEqual(g.frequencies.first!, 20)
        XCTAssertLessThanOrEqual(g.frequencies.last!, 20000)
        XCTAssertEqual(g.count, 239) // k = −135…103 around 1 kHz
        XCTAssertEqual(g.frequencies[g.nearestIndex(to: 1000)], 1000, accuracy: 1e-9)
    }
}
