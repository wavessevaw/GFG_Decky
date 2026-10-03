import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// In-place complex FFT of a power-of-two size.
/// Convention: forward = Σ x[n]·e^(−j2πkn/N) (unnormalized), inverse includes the 1/N factor.
public protocol FFTEngine: AnyObject {
    var size: Int { get }
    func forward(re: inout [Double], im: inout [Double])
    func inverse(re: inout [Double], im: inout [Double])
}

public enum FFTBackend: String, Sendable {
    case accelerate
    case portable
}

public enum FFT {
    /// Default backend: Accelerate where available, portable radix-2 elsewhere (Linux CI).
    public static var defaultBackend: FFTBackend {
        #if canImport(Accelerate)
        return .accelerate
        #else
        return .portable
        #endif
    }

    public static func make(size: Int, backend: FFTBackend = defaultBackend) -> FFTEngine {
        precondition(size >= 2 && size & (size - 1) == 0, "FFT size must be a power of two")
        switch backend {
        case .accelerate:
            #if canImport(Accelerate)
            return AccelerateFFT(size: size)
            #else
            return PortableFFT(size: size)
            #endif
        case .portable:
            return PortableFFT(size: size)
        }
    }

    /// Forward FFT of a real signal. Returns the N/2+1 non-negative-frequency bins.
    public static func realForward(_ x: [Double], engine: FFTEngine) -> (re: [Double], im: [Double]) {
        let n = engine.size
        var re = [Double](repeating: 0, count: n)
        var im = [Double](repeating: 0, count: n)
        for i in 0..<min(n, x.count) { re[i] = x[i] }
        engine.forward(re: &re, im: &im)
        return (Array(re[0...(n / 2)]), Array(im[0...(n / 2)]))
    }

    /// Inverse FFT of a Hermitian spectrum given by its N/2+1 bins. Returns N real samples.
    public static func realInverse(re halfRe: [Double], im halfIm: [Double], engine: FFTEngine) -> [Double] {
        let n = engine.size
        precondition(halfRe.count == n / 2 + 1 && halfIm.count == n / 2 + 1)
        var re = [Double](repeating: 0, count: n)
        var im = [Double](repeating: 0, count: n)
        for k in 0...(n / 2) {
            re[k] = halfRe[k]
            im[k] = halfIm[k]
        }
        im[0] = 0
        im[n / 2] = 0
        for k in 1..<(n / 2) {
            re[n - k] = halfRe[k]
            im[n - k] = -halfIm[k]
        }
        engine.inverse(re: &re, im: &im)
        return re
    }
}

/// Iterative radix-2 Cooley–Tukey FFT. Used on platforms without Accelerate and as a cross-check.
public final class PortableFFT: FFTEngine {
    public let size: Int
    private let log2n: Int
    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReverse: [Int]

    public init(size: Int) {
        precondition(size >= 2 && size & (size - 1) == 0)
        self.size = size
        var l = 0
        while (1 << l) < size { l += 1 }
        log2n = l
        var c = [Double](repeating: 0, count: size / 2)
        var s = [Double](repeating: 0, count: size / 2)
        for i in 0..<(size / 2) {
            let a = -2.0 * Double.pi * Double(i) / Double(size)
            c[i] = cos(a)
            s[i] = sin(a)
        }
        cosTable = c
        sinTable = s
        var br = [Int](repeating: 0, count: size)
        for i in 0..<size {
            var x = i
            var r = 0
            for _ in 0..<l {
                r = (r << 1) | (x & 1)
                x >>= 1
            }
            br[i] = r
        }
        bitReverse = br
    }

    public func forward(re: inout [Double], im: inout [Double]) {
        transform(re: &re, im: &im, inverse: false)
    }

    public func inverse(re: inout [Double], im: inout [Double]) {
        transform(re: &re, im: &im, inverse: true)
        let scale = 1.0 / Double(size)
        for i in 0..<size {
            re[i] *= scale
            im[i] *= scale
        }
    }

    private func transform(re: inout [Double], im: inout [Double], inverse: Bool) {
        precondition(re.count == size && im.count == size)
        let n = size
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                bitReverse.withUnsafeBufferPointer { br in
                    for i in 0..<n {
                        let j = br[i]
                        if j > i {
                            rp.swapAt(i, j)
                            ip.swapAt(i, j)
                        }
                    }
                }
                cosTable.withUnsafeBufferPointer { ct in
                    sinTable.withUnsafeBufferPointer { st in
                        let sign: Double = inverse ? -1 : 1
                        var half = 1
                        while half < n {
                            let step = n / (half * 2)
                            var start = 0
                            while start < n {
                                var t = 0
                                for k in 0..<half {
                                    let wr = ct[t]
                                    let wi = sign * st[t]
                                    let a = start + k
                                    let b = a + half
                                    let xr = rp[b] * wr - ip[b] * wi
                                    let xi = rp[b] * wi + ip[b] * wr
                                    rp[b] = rp[a] - xr
                                    ip[b] = ip[a] - xi
                                    rp[a] += xr
                                    ip[a] += xi
                                    t += step
                                }
                                start += half * 2
                            }
                            half *= 2
                        }
                    }
                }
            }
        }
    }
}

#if canImport(Accelerate)
/// vDSP-backed complex FFT (double precision).
public final class AccelerateFFT: FFTEngine {
    public let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetupD

    public init(size: Int) {
        precondition(size >= 2 && size & (size - 1) == 0)
        self.size = size
        var l: vDSP_Length = 0
        while (1 << l) < size { l += 1 }
        log2n = l
        guard let s = vDSP_create_fftsetupD(l, FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetupD failed for size \(size)")
        }
        setup = s
    }

    deinit { vDSP_destroy_fftsetupD(setup) }

    public func forward(re: inout [Double], im: inout [Double]) {
        run(re: &re, im: &im, direction: FFTDirection(kFFTDirection_Forward))
    }

    public func inverse(re: inout [Double], im: inout [Double]) {
        run(re: &re, im: &im, direction: FFTDirection(kFFTDirection_Inverse))
        var scale = 1.0 / Double(size)
        let n = vDSP_Length(size)
        re.withUnsafeMutableBufferPointer { vDSP_vsmulD($0.baseAddress!, 1, &scale, $0.baseAddress!, 1, n) }
        im.withUnsafeMutableBufferPointer { vDSP_vsmulD($0.baseAddress!, 1, &scale, $0.baseAddress!, 1, n) }
    }

    private func run(re: inout [Double], im: inout [Double], direction: FFTDirection) {
        precondition(re.count == size && im.count == size)
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPDoubleSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zipD(setup, &split, 1, log2n, direction)
            }
        }
    }
}
#endif
