import Foundation

/// One-third-octave bands (ISO nominal 25 Hz … 20 kHz) used by the assistant's analysis.
public enum ThirdOctave {
    public static let centers: [Double] = [25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
                                           1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000]

    public static func index(of f: Double) -> Int {
        centers.indices.min { abs(log(centers[$0] / f)) < abs(log(centers[$1] / f)) } ?? 0
    }
}

/// What the assistant knows about a channel's signal after one analysis window (≈ 2 s).
public struct SignalFeatures: Equatable, Codable, Sendable {
    /// Power per one-third-octave band (dBFS), smoothed over the active part of the window.
    public var bandsDB: [Double]
    /// RMS over the active part (dBFS).
    public var rmsDB: Double
    /// Highest sample peak (dBFS).
    public var peakDB: Double
    /// Short-term (50 ms) levels, 50th and 95th percentile (dBFS), active frames only.
    public var level50DB: Double
    public var level95DB: Double
    /// Peak minus RMS (dB): high for drums, low for sustained sources.
    public var crestDB: Double
    /// Share of 50 ms frames with signal (0…1).
    public var activity: Double
    /// Spectral centroid (Hz).
    public var centroidHz: Double
    /// Median fundamental of voiced frames (Hz, 0 when not pitched).
    public var pitchHz: Double
    /// Share of frames with a clear periodic component (0…1).
    public var harmonicity: Double
    /// Detected onsets per second.
    public var onsetRate: Double

    public var hasSignal: Bool { activity > 0.15 && rmsDB > -60 }

    public init(bandsDB: [Double] = Array(repeating: -120, count: ThirdOctave.centers.count), rmsDB: Double = -120,
                peakDB: Double = -120, level50DB: Double = -120, level95DB: Double = -120, crestDB: Double = 0,
                activity: Double = 0, centroidHz: Double = 0, pitchHz: Double = 0, harmonicity: Double = 0, onsetRate: Double = 0) {
        self.bandsDB = bandsDB; self.rmsDB = rmsDB; self.peakDB = peakDB; self.level50DB = level50DB; self.level95DB = level95DB
        self.crestDB = crestDB; self.activity = activity; self.centroidHz = centroidHz; self.pitchHz = pitchHz
        self.harmonicity = harmonicity; self.onsetRate = onsetRate
    }
}

/// Turns a window of samples into `SignalFeatures`. Not real-time: runs on a worker every ~2 s.
public final class FeatureExtractor {
    public let sampleRate: Double
    let fftSize = 4096
    let fft: FFTEngine
    let window: [Double]
    /// Bin ranges of each one-third-octave band.
    let bandBins: [Range<Int>]

    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        fft = FFT.make(size: fftSize)
        window = WindowFunction.hann.coefficients(count: fftSize)
        let df = sampleRate / Double(fftSize)
        bandBins = ThirdOctave.centers.map { c in
            let lo = max(1, Int((c / pow(2, 1.0 / 6) / df).rounded(.down)))
            let hi = min(4096 / 2, max(lo + 1, Int((c * pow(2, 1.0 / 6) / df).rounded(.up))))
            return lo..<hi
        }
    }

    public func analyze(_ x: [Float], gateDB: Double = -65) -> SignalFeatures {
        var out = SignalFeatures()
        guard x.count >= fftSize else { return out }
        let frame = Int(sampleRate * 0.05)
        var levels: [Double] = []
        var peak: Float = 0
        var energy = 0.0, activeSamples = 0
        var activeFrames: [Bool] = []
        var i = 0
        while i + frame <= x.count {
            var e = 0.0
            for k in i..<i + frame { let v = Double(x[k]); e += v * v; peak = max(peak, abs(x[k])) }
            let l = Decibel.fromPower(e / Double(frame))
            let on = l > gateDB
            activeFrames.append(on)
            if on { levels.append(l); energy += e; activeSamples += frame }
            i += frame
        }
        out.activity = activeFrames.isEmpty ? 0 : Double(levels.count) / Double(activeFrames.count)
        out.peakDB = Decibel.fromAmplitude(Double(peak))
        guard activeSamples > 0 else { return out }
        out.rmsDB = Decibel.fromPower(energy / Double(activeSamples))
        out.crestDB = out.peakDB - out.rmsDB
        let sorted = levels.sorted()
        out.level50DB = sorted[sorted.count / 2]
        out.level95DB = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]

        // Onsets: a 50 ms frame at least 6 dB above the previous one and above the gate.
        var onsets = 0, prev = -200.0, li = 0
        for on in activeFrames {
            let l = on ? levels[li] : -200
            if on { li += 1 }
            if on && l - prev > 6 { onsets += 1 }
            prev = l
        }
        out.onsetRate = Double(onsets) / (Double(x.count) / sampleRate)

        // Averaged spectrum over active segments (Welch, 50 % overlap).
        var power = [Double](repeating: 0, count: fftSize / 2 + 1)
        var segments = 0
        var s = 0
        while s + fftSize <= x.count {
            let f0 = s / frame, f1 = min(activeFrames.count - 1, (s + fftSize) / frame)
            if f0 <= f1, activeFrames[f0...f1].contains(true) {
                let seg = (0..<fftSize).map { Double(x[s + $0]) * window[$0] }
                let (re, im) = FFT.realForward(seg, engine: fft)
                for k in 0..<re.count { power[k] += re[k] * re[k] + im[k] * im[k] }
                segments += 1
            }
            s += fftSize / 2
        }
        guard segments > 0 else { return out }
        // Hann power gain and one-sided scaling so a full-scale sine reads about 0 dBFS in its band.
        let norm = 2.0 / (Double(segments) * pow(window.reduce(0, +), 2))
        var num = 0.0, den = 0.0
        for k in 1..<power.count {
            let p = power[k] * norm
            let f = Double(k) * sampleRate / Double(fftSize)
            num += f * p; den += p
        }
        out.centroidHz = den > 0 ? num / den : 0
        out.bandsDB = bandBins.map { r in Decibel.fromPower(r.reduce(0.0) { $0 + power[$1] * norm } + 1e-15) }

        // Pitch: autocorrelation via FFT on active 2048-sample frames (40 Hz … 1.5 kHz).
        let n = 4096 / 2
        let minLag = Int(sampleRate / 1500), maxLag = Int(sampleRate / 40)
        var pitches: [Double] = []
        var voiced = 0, tested = 0
        let hop = max(n, x.count / 24)
        var p0 = 0
        while p0 + n <= x.count && tested < 24 {
            let fi = min(activeFrames.count - 1, (p0 + n / 2) / frame)
            if activeFrames[fi] {
                tested += 1
                let seg = (0..<n).map { Double(x[p0 + $0]) }   // rectangular, zero-padded to 4096: no circular wrap
                let (re, im) = FFT.realForward(seg, engine: fft)
                let pw = (0..<re.count).map { re[$0] * re[$0] + im[$0] * im[$0] }
                let r = FFT.realInverse(re: pw, im: [Double](repeating: 0, count: pw.count), engine: fft)
                if r[0] > 1e-12 {
                    // Unbiased and normalized to lag 0.
                    func rn(_ l: Int) -> Double { r[l] / r[0] * Double(n) / Double(n - l) }
                    var best = 0.0
                    for l in minLag...min(maxLag, n / 2) { best = max(best, rn(l)) }
                    // The period is the first autocorrelation peak nearly as high as the best one
                    // (multiples of the period are just as high and would read an octave or more low).
                    var chosen = 0
                    if best > 0.6 {
                        for l in (minLag + 1)...min(maxLag, n / 2) where rn(l) >= rn(l - 1) && rn(l) >= rn(l + 1) && rn(l) > best - 0.1 {
                            chosen = l
                            break
                        }
                    }
                    if chosen > 0 {
                        // Parabolic refinement of the lag.
                        let a = rn(chosen - 1), b = rn(chosen), c = rn(chosen + 1)
                        let d = a - 2 * b + c
                        let lag = Double(chosen) + (abs(d) > 1e-9 ? 0.5 * (a - c) / d : 0)
                        voiced += 1
                        pitches.append(sampleRate / lag)
                    }
                }
            }
            p0 += hop
        }
        out.harmonicity = tested > 0 ? Double(voiced) / Double(tested) : 0
        if !pitches.isEmpty { out.pitchHz = pitches.sorted()[pitches.count / 2] }
        return out
    }
}

/// Averages features over several windows so slow loops see a stable picture.
public struct FeatureAverager: Sendable {
    public private(set) var windows = 0
    var bandPower: [Double] = Array(repeating: 0, count: ThirdOctave.centers.count)
    var last: SignalFeatures?
    var pitchSum = 0.0, pitchN = 0.0, harm = 0.0, onset = 0.0, centroid = 0.0, crest = 0.0, l50 = 0.0, l95 = 0.0, rms = 0.0
    var peak = -200.0

    public init() {}

    public mutating func add(_ f: SignalFeatures) {
        guard f.hasSignal else { return }
        windows += 1
        for k in bandPower.indices { bandPower[k] += pow(10, f.bandsDB[k] / 10) }
        if f.pitchHz > 0 { pitchSum += log(f.pitchHz); pitchN += 1 }
        harm += f.harmonicity; onset += f.onsetRate; centroid += f.centroidHz; crest += f.crestDB
        l50 += f.level50DB; l95 += f.level95DB; rms += pow(10, f.rmsDB / 10); peak = max(peak, f.peakDB)
        last = f
    }

    public var average: SignalFeatures? {
        guard windows > 0 else { return nil }
        let n = Double(windows)
        return SignalFeatures(bandsDB: bandPower.map { Decibel.fromPower($0 / n + 1e-15) }, rmsDB: Decibel.fromPower(rms / n),
                              peakDB: peak, level50DB: l50 / n, level95DB: l95 / n, crestDB: crest / n, activity: 1,
                              centroidHz: centroid / n, pitchHz: pitchN > 0 ? exp(pitchSum / pitchN) : 0,
                              harmonicity: harm / n, onsetRate: onset / n)
    }
}
