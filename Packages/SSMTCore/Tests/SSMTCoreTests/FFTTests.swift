import XCTest
@testable import SSMTCore

final class FFTTests: XCTestCase {
    func naiveDFT(_ re: [Double], _ im: [Double]) -> ([Double], [Double]) {
        let n = re.count
        var outR = [Double](repeating: 0, count: n), outI = outR
        for k in 0..<n {
            for t in 0..<n {
                let a = -2 * Double.pi * Double(k * t) / Double(n)
                outR[k] += re[t] * cos(a) - im[t] * sin(a)
                outI[k] += re[t] * sin(a) + im[t] * cos(a)
            }
        }
        return (outR, outI)
    }

    func testPortableMatchesNaiveDFT() {
        var rng = RandomSource(seed: 3)
        let n = 64
        let re = (0..<n).map { _ in rng.nextGaussian() }
        let im = (0..<n).map { _ in rng.nextGaussian() }
        let (er, ei) = naiveDFT(re, im)
        var r = re, i = im
        PortableFFT(size: n).forward(re: &r, im: &i)
        for k in 0..<n {
            XCTAssertEqual(r[k], er[k], accuracy: 1e-9)
            XCTAssertEqual(i[k], ei[k], accuracy: 1e-9)
        }
    }

    func testRoundTripAllBackends() {
        var rng = RandomSource(seed: 4)
        let n = 4096
        let x = (0..<n).map { _ in rng.nextGaussian() }
        for backend in [FFTBackend.portable, FFT.defaultBackend] {
            let e = FFT.make(size: n, backend: backend)
            let spec = FFT.realForward(x, engine: e)
            let y = FFT.realInverse(re: spec.re, im: spec.im, engine: e)
            for t in 0..<n { XCTAssertEqual(y[t], x[t], accuracy: 1e-9) }
        }
    }

    func testBackendsAgree() {
        var rng = RandomSource(seed: 5)
        let n = 1 << 14
        let x = (0..<n).map { _ in rng.nextGaussian() }
        let a = FFT.realForward(x, engine: FFT.make(size: n, backend: .portable))
        let b = FFT.realForward(x, engine: FFT.make(size: n, backend: FFT.defaultBackend))
        for k in stride(from: 0, to: n / 2 + 1, by: 97) {
            XCTAssertEqual(a.re[k], b.re[k], accuracy: 1e-7)
            XCTAssertEqual(a.im[k], b.im[k], accuracy: 1e-7)
        }
    }

    func testHilbertEnvelopeOfModulatedTone() {
        let n = 4096
        let x = (0..<n).map { t -> Double in
            let env = exp(-pow(Double(t - 2000) / 200, 2))
            return env * cos(2 * .pi * 0.1 * Double(t))
        }
        let env = Hilbert.envelope(x)
        let peak = env.enumerated().max { $0.element < $1.element }!.offset
        XCTAssertEqual(peak, 2000, accuracy: 2)
        XCTAssertEqual(env[2000], 1, accuracy: 0.02)
    }
}
