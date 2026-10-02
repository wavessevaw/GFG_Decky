import Foundation

/// One analysis window of the multi-time-window FFT and the frequency range it serves.
public struct AnalysisWindowBand: Equatable, Codable, Sendable {
    public var fftSize: Int
    /// Lower edge of the range served by this window (Hz). The upper edge is the next band's lower edge.
    public var lowerEdge: Double

    public init(fftSize: Int, lowerEdge: Double) {
        self.fftSize = fftSize
        self.lowerEdge = lowerEdge
    }
}

public struct MultiWindowConfig: Equatable, Codable, Sendable {
    public var sampleRate: Double
    /// Bands sorted by ascending lower edge (largest FFT first).
    public var bands: [AnalysisWindowBand]
    public var overlap: Double
    public var window: WindowFunction
    public var pointsPerOctave: Int
    public var minFrequency: Double
    public var maxFrequency: Double
    /// Width of the raised-cosine crossfade between adjacent windows, in octaves.
    public var crossfadeOctaves: Double
    public var averaging: SpectralAveraging

    public init(sampleRate: Double, bands: [AnalysisWindowBand], overlap: Double = 0.75,
                window: WindowFunction = .hann, pointsPerOctave: Int = 24,
                minFrequency: Double = 20, maxFrequency: Double = 20000,
                crossfadeOctaves: Double = 1.0 / 3.0, averaging: SpectralAveraging = .cumulative) {
        self.sampleRate = sampleRate
        self.bands = bands.sorted { $0.lowerEdge < $1.lowerEdge }
        self.overlap = overlap
        self.window = window
        self.pointsPerOctave = pointsPerOctave
        self.minFrequency = minFrequency
        self.maxFrequency = min(maxFrequency, sampleRate / 2 * 0.95)
        self.crossfadeOctaves = crossfadeOctaves
        self.averaging = averaging
    }

    /// Default multi-window layout from the spec, scaled to the sample rate
    /// so that window durations stay constant (48 kHz reference).
    public static func standard(sampleRate: Double = 48000,
                                averaging: SpectralAveraging = .cumulative) -> MultiWindowConfig {
        let scale = max(1, Int((sampleRate / 48000).rounded()))
        return MultiWindowConfig(
            sampleRate: sampleRate,
            bands: [
                AnalysisWindowBand(fftSize: 65536 * scale, lowerEdge: 0),
                AnalysisWindowBand(fftSize: 16384 * scale, lowerEdge: 100),
                AnalysisWindowBand(fftSize: 4096 * scale, lowerEdge: 500),
                AnalysisWindowBand(fftSize: 1024 * scale, lowerEdge: 2000),
            ],
            averaging: averaging)
    }

    /// Single-window configuration (used for the periodic-noise fast mode and for tests).
    public static func single(fftSize: Int, sampleRate: Double = 48000) -> MultiWindowConfig {
        MultiWindowConfig(sampleRate: sampleRate, bands: [AnalysisWindowBand(fftSize: fftSize, lowerEdge: 0)])
    }
}

/// Multi-time-window dual-channel FFT analyzer.
///
/// Each window runs its own Welch estimator. The spectra (not H) are mapped to a
/// fractional-octave grid by averaging the bins inside each grid band, then blended
/// across windows with a raised-cosine crossfade in log frequency. Because Gxx, Gyy
/// and Gxy are blended before forming H and γ², the result is continuous at the seams.
public final class MultiWindowAnalyzer {
    public let config: MultiWindowConfig
    public let grid: FrequencyGrid
    public private(set) var referenceDelaySamples: Int = 0

    private let accumulators: [WelchAccumulator]
    /// For each window: per grid point list of (bin, weight).
    private let binMaps: [[[(Int, Double)]]]
    /// For each window: blend weight per grid point.
    private let blendWeights: [[Double]]
    private var delayLine: [Double] = []

    public init(config: MultiWindowConfig, backend: FFTBackend = FFT.defaultBackend) {
        self.config = config
        let grid = FrequencyGrid(pointsPerOctave: config.pointsPerOctave,
                                 minFrequency: config.minFrequency, maxFrequency: config.maxFrequency)
        self.grid = grid
        accumulators = config.bands.map {
            WelchAccumulator(fftSize: $0.fftSize, overlap: config.overlap, window: config.window,
                             sampleRate: config.sampleRate, averaging: config.averaging, backend: backend)
        }
        binMaps = config.bands.map {
            MultiWindowAnalyzer.makeBinMap(grid: grid, fftSize: $0.fftSize, sampleRate: config.sampleRate)
        }
        blendWeights = MultiWindowAnalyzer.makeBlendWeights(grid: grid, bands: config.bands,
                                                            crossfadeOctaves: config.crossfadeOctaves)
    }

    /// Delays the reference by n samples so that it lines up with the measurement.
    /// Changing the delay resets the averages.
    public func setReferenceDelay(samples n: Int) {
        precondition(n >= 0)
        referenceDelaySamples = n
        reset()
    }

    public func reset() {
        accumulators.forEach { $0.reset() }
        delayLine = [Double](repeating: 0, count: referenceDelaySamples)
    }

    /// Minimum number of averages across windows that have produced at least one frame.
    public var averages: Int { accumulators.map(\.frameCount).min() ?? 0 }

    /// Seconds of signal required before every window has at least one frame.
    public var warmUpDuration: Double {
        Double(config.bands.map(\.fftSize).max() ?? 0) / config.sampleRate
    }

    public func ingest(reference x: [Float], measurement y: [Float]) {
        ingest(reference: x.map(Double.init), measurement: y.map(Double.init))
    }

    public func ingest(reference x: [Double], measurement y: [Double]) {
        precondition(x.count == y.count)
        var xd: [Double]
        if referenceDelaySamples > 0 {
            delayLine.append(contentsOf: x)
            xd = Array(delayLine[0..<x.count])
            delayLine.removeFirst(x.count)
        } else {
            xd = x
        }
        for acc in accumulators {
            acc.ingest(reference: xd, measurement: y)
        }
    }

    /// Builds the current transfer function on the grid. Points that no window
    /// can serve yet are NaN.
    public func snapshot() -> TransferFunction {
        let n = grid.count
        var response = [Complex](repeating: Complex(.nan, .nan), count: n)
        var coherence = [Double](repeating: .nan, count: n)
        var pyy = [Double](repeating: .nan, count: n)
        var pxx = [Double](repeating: .nan, count: n)
        for i in 0..<n {
            var sxx = 0.0, syy = 0.0, sxy = Complex.zero, wsum = 0.0
            for (w, acc) in accumulators.enumerated() {
                let bw = blendWeights[w][i]
                guard bw > 0, acc.frameCount > 0 else { continue }
                var bxx = 0.0, byy = 0.0, bxy = Complex.zero, bwt = 0.0
                for (k, weight) in binMaps[w][i] {
                    bxx += weight * acc.gxx[k]
                    byy += weight * acc.gyy[k]
                    bxy += Complex(acc.gxyRe[k], acc.gxyIm[k]) * weight
                    bwt += weight
                }
                guard bwt > 0 else { continue }
                sxx += bw * bxx / bwt
                syy += bw * byy / bwt
                sxy += bxy * (bw / bwt)
                wsum += bw
            }
            guard wsum > 0, sxx > 0 else { continue }
            sxx /= wsum
            syy /= wsum
            sxy = sxy / wsum
            response[i] = sxy / sxx
            coherence[i] = syy > 0 ? min(1, sxy.magnitudeSquared / (sxx * syy)) : 0
            pyy[i] = syy
            pxx[i] = sxx
        }
        let used = accumulators.map(\.frameCount).filter { $0 > 0 }
        return TransferFunction(frequencies: grid.frequencies, response: response, coherence: coherence,
                                measurementPower: pyy, referencePower: pxx, averages: used.min() ?? 0,
                                compensatedDelay: Double(referenceDelaySamples) / config.sampleRate)
    }

    // MARK: - Precomputation

    static func makeBinMap(grid: FrequencyGrid, fftSize: Int, sampleRate: Double) -> [[(Int, Double)]] {
        let df = sampleRate / Double(fftSize)
        let maxBin = fftSize / 2
        return grid.frequencies.indices.map { i in
            let (lo, hi) = grid.bandEdges(i)
            if hi - lo >= 2 * df {
                // Each bin covers [k−½, k+½]·df; weight = fraction of that interval inside the band.
                // Partial edge weights keep the band centroid on the grid frequency, which avoids
                // bin-count quantization ripple on steep slopes.
                let kLo = max(1, Int((lo / df - 0.5).rounded(.down)))
                let kHi = min(maxBin, Int((hi / df + 0.5).rounded(.up)))
                var map: [(Int, Double)] = []
                for k in kLo...kHi {
                    let b0 = (Double(k) - 0.5) * df, b1 = (Double(k) + 0.5) * df
                    let overlap = min(b1, hi) - max(b0, lo)
                    if overlap > 0 { map.append((k, overlap / df)) }
                }
                return map
            }
            // Band narrower than two bins: linear interpolation between the two neighbours.
            let pos = grid.frequencies[i] / df
            let k0 = max(1, min(maxBin - 1, Int(pos.rounded(.down))))
            let t = min(max(pos - Double(k0), 0), 1)
            return [(k0, 1 - t), (k0 + 1, t)]
        }
    }

    static func makeBlendWeights(grid: FrequencyGrid, bands: [AnalysisWindowBand],
                                 crossfadeOctaves: Double) -> [[Double]] {
        let half = crossfadeOctaves / 2
        func ramp(_ f: Double, edge: Double) -> Double {
            // 0 below edge·2^(−half), 1 above edge·2^(+half), raised cosine in between.
            guard edge > 0 else { return 1 }
            let x = log2(f / edge)
            if half <= 0 { return x >= 0 ? 1 : 0 }
            if x <= -half { return 0 }
            if x >= half { return 1 }
            return 0.5 - 0.5 * cos(Double.pi * (x + half) / (2 * half))
        }
        return bands.indices.map { b in
            grid.frequencies.map { f in
                let rise = ramp(f, edge: bands[b].lowerEdge)
                let fall = b + 1 < bands.count ? 1 - ramp(f, edge: bands[b + 1].lowerEdge) : 1
                return rise * fall
            }
        }
    }
}
