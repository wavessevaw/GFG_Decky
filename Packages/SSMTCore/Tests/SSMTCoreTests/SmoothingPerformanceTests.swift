import XCTest
@testable import SSMTCore

final class SmoothingPerformanceTests: XCTestCase {
    /// Straightforward O(n²) reference implementation of the complex smoothing.
    private func reference(_ values: [Complex], _ f: [Double], octaves: Double) -> [Complex] {
        let power = Smoothing.smoothPower(values.map { $0.magnitudeSquared }, frequencies: f, octaves: octaves)
        return f.indices.map { i in
            let lo = f[i] * pow(2, -octaves / 2), hi = f[i] * pow(2, octaves / 2)
            var acc = Complex.zero
            for j in f.indices where f[j] >= lo && f[j] <= hi {
                let m = values[j].magnitude
                guard m > 0, m.isFinite else { continue }
                acc += values[j] / m
            }
            guard power[i].isFinite, acc.magnitude > 0 else { return Complex(.nan, .nan) }
            return Complex.polar(magnitude: power[i].squareRoot(), phase: acc.phase)
        }
    }

    func testWindowedSmoothingMatchesReference() {
        var rng = RandomSource(seed: 3)
        let f = (0..<480).map { 20 * pow(1000, Double($0) / 479) }
        let v = f.map { _ in Complex.polar(magnitude: 0.5 + abs(rng.nextGaussian()), phase: rng.nextGaussian() * 2) }
        for res in [SmoothingResolution.oct48, .oct12, .oct3] {
            let fast = Smoothing.smoothComplex(v, frequencies: f, octaves: res.octaves)
            let slow = reference(v, f, octaves: res.octaves)
            for i in f.indices {
                XCTAssertEqual(fast[i].re, slow[i].re, accuracy: 1e-9)
                XCTAssertEqual(fast[i].im, slow[i].im, accuracy: 1e-9)
            }
        }
    }

    /// The live display path (snapshot → 1/3-oct smoothing) must stay far below one frame.
    func testDisplaySmoothingIsCheap() {
        let f = (0..<480).map { 20 * pow(1000, Double($0) / 479) }
        let ones = [Double](repeating: 1, count: f.count)
        let tf = TransferFunction(frequencies: f, response: f.map { Complex.polar(magnitude: 1, phase: $0 / 1000) },
                                  coherence: ones, measurementPower: ones, referencePower: ones, averages: 1)
        let start = Date()
        for _ in 0..<100 { _ = Smoothing.smooth(tf, resolution: .oct3) }
        let perCall = Date().timeIntervalSince(start) / 100
        XCTAssertLessThan(perCall, 0.002, "1/3-oct smoothing took \(perCall * 1000) ms")
    }
}
