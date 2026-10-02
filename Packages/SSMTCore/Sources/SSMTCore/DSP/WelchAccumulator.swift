import Foundation

public enum SpectralAveraging: Equatable, Codable, Sendable {
    /// Plain mean over all frames since the last reset (for captures).
    case cumulative
    /// Exponential averaging with an equivalent time constant in seconds (for live display).
    case exponential(timeConstant: Double)
}

/// Welch estimator of the auto-spectra Gxx, Gyy and the cross-spectrum Gxy
/// for one FFT window size. Spectra are scaled to a density (1/Σw²), so that
/// different window sizes can be blended directly.
public final class WelchAccumulator {
    public let fftSize: Int
    public let hop: Int
    public let sampleRate: Double
    public let averaging: SpectralAveraging

    public private(set) var gxx: [Double]
    public private(set) var gyy: [Double]
    public private(set) var gxyRe: [Double]
    public private(set) var gxyIm: [Double]
    public private(set) var frameCount: Int = 0

    private let window: [Double]
    private let densityScale: Double
    private let engine: FFTEngine
    private var pendingX: [Double] = []
    private var pendingY: [Double] = []
    private var pendingStart = 0
    private var reX: [Double]
    private var imX: [Double]
    private var reY: [Double]
    private var imY: [Double]

    public init(fftSize: Int, overlap: Double, window: WindowFunction, sampleRate: Double,
                averaging: SpectralAveraging = .cumulative, backend: FFTBackend = FFT.defaultBackend) {
        precondition(overlap >= 0 && overlap < 1)
        self.fftSize = fftSize
        self.hop = max(1, Int((Double(fftSize) * (1 - overlap)).rounded()))
        self.sampleRate = sampleRate
        self.averaging = averaging
        self.window = window.coefficients(count: fftSize)
        self.densityScale = 1.0 / self.window.reduce(0) { $0 + $1 * $1 }
        self.engine = FFT.make(size: fftSize, backend: backend)
        let bins = fftSize / 2 + 1
        gxx = [Double](repeating: 0, count: bins)
        gyy = [Double](repeating: 0, count: bins)
        gxyRe = [Double](repeating: 0, count: bins)
        gxyIm = [Double](repeating: 0, count: bins)
        reX = [Double](repeating: 0, count: fftSize)
        imX = [Double](repeating: 0, count: fftSize)
        reY = [Double](repeating: 0, count: fftSize)
        imY = [Double](repeating: 0, count: fftSize)
    }

    public var binCount: Int { fftSize / 2 + 1 }
    public var binSpacing: Double { sampleRate / Double(fftSize) }

    public func reset() {
        for i in 0..<binCount {
            gxx[i] = 0
            gyy[i] = 0
            gxyRe[i] = 0
            gxyIm[i] = 0
        }
        frameCount = 0
        pendingX.removeAll(keepingCapacity: true)
        pendingY.removeAll(keepingCapacity: true)
        pendingStart = 0
    }

    /// Feeds equal-length blocks of reference (x) and measurement (y).
    public func ingest(reference x: [Double], measurement y: [Double]) {
        precondition(x.count == y.count)
        pendingX.append(contentsOf: x)
        pendingY.append(contentsOf: y)
        while pendingX.count - pendingStart >= fftSize {
            processFrame(at: pendingStart)
            pendingStart += hop
        }
        // Compact occasionally to keep memory bounded without per-frame copies.
        if pendingStart >= fftSize * 4 || pendingStart == pendingX.count {
            pendingX.removeFirst(pendingStart)
            pendingY.removeFirst(pendingStart)
            pendingStart = 0
        }
    }

    private func processFrame(at start: Int) {
        for i in 0..<fftSize {
            let w = window[i]
            reX[i] = pendingX[start + i] * w
            imX[i] = 0
            reY[i] = pendingY[start + i] * w
            imY[i] = 0
        }
        engine.forward(re: &reX, im: &imX)
        engine.forward(re: &reY, im: &imY)

        let alpha: Double
        switch averaging {
        case .cumulative:
            alpha = 1.0 / Double(frameCount + 1)
        case .exponential(let tau):
            let framesPerSecond = sampleRate / Double(hop)
            let a = 1.0 - exp(-1.0 / max(tau * framesPerSecond, 1e-9))
            // Start as a cumulative mean so the first frames are not biased toward zero.
            alpha = max(a, 1.0 / Double(frameCount + 1))
        }
        let s = densityScale
        for k in 0..<binCount {
            let xr = reX[k], xi = imX[k], yr = reY[k], yi = imY[k]
            let pxx = (xr * xr + xi * xi) * s
            let pyy = (yr * yr + yi * yi) * s
            // conj(X)·Y
            let cr = (xr * yr + xi * yi) * s
            let ci = (xr * yi - xi * yr) * s
            gxx[k] += alpha * (pxx - gxx[k])
            gyy[k] += alpha * (pyy - gyy[k])
            gxyRe[k] += alpha * (cr - gxyRe[k])
            gxyIm[k] += alpha * (ci - gxyIm[k])
        }
        frameCount += 1
    }
}
