import Foundation

/// Finds acoustic feedback in the measurement microphone (or any channel) signal.
///
/// Feedback is a narrow spectral peak that stands far above its one-third-octave neighbourhood, keeps its
/// frequency, and either grows or holds for longer than a played note. During a ring-out the assistant also
/// knows when it raised the faders: a peak that grows by more than the fader step is a loop with gain ≥ 1.
public final class FeedbackDetector {
    public struct Event: Equatable, Sendable {
        public var frequency: Double
        /// Peak above its neighbourhood (dB).
        public var prominenceDB: Double
        /// Growth over the tracked time (dB).
        public var growthDB: Double
        public var levelDB: Double
    }

    public let sampleRate: Double
    let size = 8192
    let fft: FFTEngine
    let window: [Double]
    var buffer: [Float] = []
    struct Track { var bin: Int; var frames: Int; var firstDB: Double; var lastDB: Double; var maxProm: Double; var rising: Int }
    var tracks: [Track] = []
    /// Spectrum of the last frame (dB per bin), used to compare before/after a fader step.
    public private(set) var lastSpectrum: [Double] = []

    /// Peak must stand this far above the median of its ±1/3-octave neighbourhood.
    public var prominenceDB = 15.0
    /// Frames (≈ 85 ms each at 48 kHz, hop 4096) a steady peak must hold to count without growing.
    public var steadyFrames = 14
    public var minLevelDB = -70.0

    public init(sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        fft = FFT.make(size: size)
        window = WindowFunction.hann.coefficients(count: size)
    }

    public func reset() { buffer.removeAll(); tracks.removeAll() }

    /// Feeds samples; returns the feedback found in the frames completed by this call.
    public func process(_ x: [Float]) -> [Event] {
        buffer += x
        var events: [Event] = []
        while buffer.count >= size {
            events += analyzeFrame(Array(buffer[0..<size]))
            buffer.removeFirst(size / 2)
        }
        // One event per frequency.
        var seen: [Event] = []
        for e in events where !seen.contains(where: { abs(log2($0.frequency / e.frequency)) < 1.0 / 12 }) { seen.append(e) }
        return seen
    }

    func spectrumDB(_ frame: [Float]) -> [Double] {
        let seg = (0..<size).map { Double(frame[$0]) * window[$0] }
        let (re, im) = FFT.realForward(seg, engine: fft)
        let norm = 2.0 / pow(window.reduce(0, +), 2)
        return (0..<re.count).map { Decibel.fromPower((re[$0] * re[$0] + im[$0] * im[$0]) * norm + 1e-20) }
    }

    func analyzeFrame(_ frame: [Float]) -> [Event] {
        let db = spectrumDB(frame)
        lastSpectrum = db
        let df = sampleRate / Double(size)
        let kmin = Int(60 / df), kmax = min(db.count - 2, Int(16000 / df))
        var peaks: [(Int, Double, Double)] = []
        var k = kmin
        while k <= kmax {
            if db[k] > db[k - 1] && db[k] >= db[k + 1] && db[k] > minLevelDB {
                let f = Double(k) * df
                let lo = max(1, Int(f / pow(2, 1.0 / 6) / df)), hi = min(db.count - 1, Int(f * pow(2, 1.0 / 6) / df))
                if hi - lo >= 4 {
                    let neighbourhood = db[lo...hi].sorted()
                    let median = neighbourhood[neighbourhood.count / 2]
                    let prom = db[k] - median
                    if prom >= prominenceDB { peaks.append((k, db[k], prom)) }
                }
            }
            k += 1
        }
        var next: [Track] = []
        var events: [Event] = []
        for (bin, level, prom) in peaks {
            if var t = tracks.first(where: { abs($0.bin - bin) <= 1 }) {
                t.frames += 1
                if level > t.lastDB + 0.3 { t.rising += 1 }
                t.lastDB = level
                t.bin = bin
                t.maxProm = max(t.maxProm, prom)
                next.append(t)
                let growth = t.lastDB - t.firstDB
                // Feedback climbs fast (tens of dB per second); a crescendo is slower.
                let seconds = Double(t.frames) * Double(size / 2) / sampleRate
                let growing = t.frames >= 5 && growth >= 6 && growth / seconds >= 9 && t.rising * 2 >= t.frames
                // Holding: long, prominent and not dying away (a fading note is not feedback).
                let holding = t.frames >= steadyFrames && t.maxProm >= prominenceDB + 5 && growth > -2
                // Feedback is one pure tone; a played note comes with its harmonics (a crescendo grows too).
                // Feedback is caught while it is still pure, before the system clips and adds harmonics.
                let note = hasHarmonics(db, bin)
                if (growing || holding) && !note {
                    events.append(Event(frequency: refine(db, bin) , prominenceDB: t.maxProm, growthDB: growth, levelDB: level))
                }
            } else {
                next.append(Track(bin: bin, frames: 1, firstDB: level, lastDB: level, maxProm: prom, rising: 0))
            }
        }
        tracks = next
        return events
    }

    /// True when the peak at `k` has a harmonic partner (f/2, 2f or 3f) standing out of its own neighbourhood.
    func hasHarmonics(_ db: [Double], _ k: Int) -> Bool {
        for m in [0.5, 2.0, 3.0] {
            let c = Int((Double(k) * m).rounded())
            guard c > 4, c < db.count - 4 else { continue }
            let lo = max(1, c - 2), hi = min(db.count - 2, c + 2)
            guard let peak = (lo...hi).max(by: { db[$0] < db[$1] }) else { continue }
            let f = Double(peak) * sampleRate / Double(size)
            let a = max(1, Int(f / pow(2, 1.0 / 6) * Double(size) / sampleRate)), b = min(db.count - 1, Int(f * pow(2, 1.0 / 6) * Double(size) / sampleRate))
            guard b - a >= 4 else { continue }
            let med = db[a...b].sorted()[(b - a + 1) / 2]
            if db[peak] - med >= 6 && db[peak] > db[k] - 30 { return true }
        }
        return false
    }

    /// Parabolic interpolation of the peak frequency.
    func refine(_ db: [Double], _ k: Int) -> Double {
        let a = db[k - 1], b = db[k], c = db[k + 1]
        let d = a - 2 * b + c
        let off = abs(d) > 1e-9 ? 0.5 * (a - c) / d : 0
        return (Double(k) + off) * sampleRate / Double(size)
    }

    /// Ring-out test: peaks that grew by more than `faderStepDB + margin` between two spectra.
    public static func runaway(before: [Double], after: [Double], faderStepDB: Double, sampleRate: Double,
                               margin: Double = 3) -> [Double] {
        guard before.count == after.count, before.count > 4 else { return [] }
        let df = sampleRate / Double((before.count - 1) * 2)
        var out: [Double] = []
        for k in 2..<(after.count - 2) where after[k] > -70 && after[k] > after[k - 1] && after[k] >= after[k + 1] {
            if after[k] - before[k] > faderStepDB + margin {
                let f = Double(k) * df
                if !out.contains(where: { abs(log2($0 / f)) < 1.0 / 6 }) { out.append(f) }
            }
        }
        return out
    }
}
