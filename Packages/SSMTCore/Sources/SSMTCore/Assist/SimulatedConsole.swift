import Foundation

/// A console with simulated musicians, for learning the assistant without hardware and for tests.
///
/// Each channel plays a synthetic source of its kind through a "microphone" with its own colouring
/// (boominess, a resonance, a dull or harsh top). The console applies preamp gain, high-pass and EQ;
/// the room adds a couple of resonances where feedback can build up when channels are pushed.
public final class SimulatedConsole {
    public struct Source: Sendable {
        public var kind: SourceKind
        /// Fundamental (Hz) for pitched sources.
        public var pitch: Double
        /// Microphone colouring the assistant is expected to correct.
        public var coloring: [StripEQBand]
        /// Source level at 0 dB preamp gain (dBFS, loud passages).
        public var levelDB: Double
        /// How much of this channel the measurement mic / other mics pick up back (dB); higher = feedback sooner.
        public var couplingDB: Double
    }

    public let sampleRate: Double
    public private(set) var strips: [Int: ChannelStrip]
    public var sources: [Int: Source]
    /// Room resonances (frequency, extra loop gain dB) where feedback appears first.
    public var roomModes: [(Double, Double)] = [(2500, 10), (630, 6)]
    /// Stage monitor mixes. A bus starts to ring when its fader goes above `loopAtDB`.
    public private(set) var buses: [Int: BusStrip] = [:]
    public var loopAtDB: [Int: Double] = [:]
    var busHowl: [Int: Double] = [:]
    var rng: UInt64
    var time = 0.0
    /// Running feedback tones in the room (frequency → amplitude).
    var howl: [Double: Double] = [:]

    public init(sampleRate: Double = 48000, seed: UInt64 = 7) {
        self.sampleRate = sampleRate
        rng = seed
        strips = [:]
        sources = [:]
    }

    /// A typical stage: lead vocals, a band, a small string section and a four-mic choir.
    public static func demo(sampleRate: Double = 48000) -> SimulatedConsole {
        let c = SimulatedConsole(sampleRate: sampleRate)
        let mud = StripEQBand(type: .peaking, frequency: 315, gainDB: 6, q: 1.2)
        let harsh = StripEQBand(type: .peaking, frequency: 3150, gainDB: 5, q: 2)
        let dull = StripEQBand(type: .highShelf, frequency: 5000, gainDB: -6)
        let boom = StripEQBand(type: .lowShelf, frequency: 150, gainDB: 6)
        let list: [(String, SourceKind, Double, [StripEQBand], Double)] = [
            ("Kick In", .kick, 55, [boom], -30), ("Snare Top", .snare, 190, [harsh], -26), ("OH L", .overhead, 0, [dull], -38),
            ("Bass DI", .bassGuitar, 55, [mud], -24), ("Gtr", .electricGuitar, 196, [harsh], -30), ("Keys", .keys, 262, [], -28),
            ("Vox Lead", .maleVocal, 130, [mud, harsh], -40), ("BV 1", .femaleVocal, 260, [boom], -42),
            ("Violin 1", .violin, 440, [harsh], -42), ("Violin 2", .violin, 392, [mud], -44), ("Viola", .viola, 262, [dull], -44),
            ("Cello", .cello, 98, [boom], -40),
            ("Choir S", .choir, 330, [mud], -46), ("Choir A", .choir, 262, [dull], -46), ("Choir T", .choir, 196, [harsh], -45),
            ("Choir B", .choir, 130, [boom], -45),
        ]
        for (i, e) in list.enumerated() {
            let ch = i + 1
            c.strips[ch] = ChannelStrip(id: ch, name: e.0, gainDB: 20, faderDB: -10)
            c.sources[ch] = Source(kind: e.1, pitch: e.2, coloring: e.3, levelDB: e.4, couplingDB: e.1.family == .choir || e.1.family == .vocals ? -18 : -30)
        }
        for b in 1...4 { c.buses[b] = BusStrip(id: b, name: "Mon \(b)", faderDB: -3) }
        c.loopAtDB = [2: 0]   // Mon 2 (choir wedges) rings when pushed to unity
        return c
    }

    public func setBus(_ b: BusStrip) { buses[b.id] = b }

    /// Monitor bus meters for a window, from the channel levels (dBFS) and the bus faders; a ringing bus
    /// climbs to a steady howl within a couple of seconds.
    public func busLevels(channelRMS: [Int: Double], seconds: Double = 1) -> [Int: Double] {
        let sum = Decibel.fromPower(channelRMS.values.reduce(0) { $0 + pow(10, $1 / 10) } + 1e-12)
        var out: [Int: Double] = [:]
        for (id, b) in buses {
            var level = b.muted ? -120 : sum + b.faderDB - 6
            var howl = busHowl[id] ?? -60
            if let at = loopAtDB[id], !b.muted, b.faderDB > at {
                howl = min(-6, howl + 12 * seconds)
            } else {
                howl = max(-90, howl - 30 * seconds)
            }
            busHowl[id] = howl
            level = Decibel.fromPower(pow(10, level / 10) + pow(10, howl / 10))
            out[id] = level
        }
        return out
    }

    public func setStrip(_ s: ChannelStrip) { strips[s.id] = s }

    func noise() -> Double {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Double(Int64(bitPattern: rng >> 1) % 2_000_000) / 1_000_000 - 1
    }

    /// Renders `seconds` of every requested channel at the console's tap (after gain; pre-EQ or post-EQ),
    /// and the measurement microphone (all channels after EQ and fader, plus feedback).
    public func render(seconds: Double = 2, channels: [Int], tap: TapPoint = .preEQ) -> (taps: [Int: [Float]], mic: [Float]) {
        let n = Int(seconds * sampleRate)
        var taps: [Int: [Float]] = [:]
        var mic = [Double](repeating: 0, count: n)
        let active = Set(channels)
        for (ch, src) in sources {
            guard let strip = strips[ch] else { continue }
            let audible = !strip.muted && strip.faderDB > -90
            guard active.contains(ch) || audible else { continue }
            var x = synth(src, count: n, seed: UInt64(ch))
            // Microphone colouring, then preamp gain.
            x = filter(x, src.coloring.map { $0.biquad(sampleRate: sampleRate) })
            let g = pow(10, (strip.gainDB + src.levelDB) / 20)
            for i in 0..<n { x[i] *= g }
            var post = x
            var chain: [Biquad] = []
            if strip.highPassOn { chain.append(Biquad.design(.highPass, frequency: strip.highPassHz, q: 0.7071, sampleRate: sampleRate)) }
            if strip.eqOn { chain += strip.eq.filter { abs($0.gainDB) > 0.01 }.map { $0.biquad(sampleRate: sampleRate) } }
            post = filter(post, chain)
            if active.contains(ch) { taps[ch] = (tap == .preEQ ? x : post).map { Float(max(-1, min(1, $0))) } }
            if !strip.muted && strip.faderDB > -90 {
                let f = pow(10, (strip.faderDB - 20) / 20)
                for i in 0..<n { mic[i] += post[i] * f }
            }
        }
        // Feedback: a room mode howls when any channel's loop gain there exceeds 0 dB.
        for (fr, modeDB) in roomModes {
            var loop = -200.0
            for (ch, src) in sources {
                guard let s = strips[ch], !s.muted, s.faderDB > -90 else { continue }
                loop = max(loop, s.faderDB + s.gainDB - 20 + src.couplingDB + modeDB + s.filterResponseDB(at: fr, sampleRate: sampleRate))
            }
            var a = howl[fr] ?? 0
            if loop > 0 { a = max(a, 0.002) * pow(10, min(loop, 6) / 20 * 4) } else { a *= 0.05 }
            a = min(a, 0.5)
            howl[fr] = a < 1e-6 ? nil : a
            if a > 0 {
                for i in 0..<n {
                    let ramp = loop > 0 ? Double(i) / Double(n) : 1 - Double(i) / Double(n)
                    mic[i] += a * (0.3 + 0.7 * ramp) * sin(2 * .pi * fr * (time + Double(i) / sampleRate))
                }
            }
        }
        time += seconds
        let micF = mic.map { Float(max(-1, min(1, $0 + 0.0003 * noise()))) }
        return (taps, micF)
    }

    func filter(_ x: [Double], _ chain: [Biquad]) -> [Double] {
        var y = x
        for b in chain {
            var z1 = 0.0, z2 = 0.0
            for i in 0..<y.count {
                let v = y[i]
                let o = b.b0 * v + z1
                z1 = b.b1 * v - b.a1 * o + z2
                z2 = b.b2 * v - b.a2 * o
                y[i] = o
            }
        }
        return y
    }

    var tables: [String: [Double]] = [:]

    /// One period of a harmonic tone with partials falling as 1/h^tilt (band-limited to 9 kHz).
    func wavetable(pitch: Double, tilt: Double) -> [Double] {
        let key = "\(pitch)-\(tilt)"
        if let t = tables[key] { return t }
        let size = 2048
        let harmonics = max(1, min(60, Int(9000 / max(pitch, 30))))
        var t = [Double](repeating: 0, count: size)
        for h in 1...harmonics {
            let a = 1 / pow(Double(h), tilt)
            for i in 0..<size { t[i] += a * sin(2 * .pi * Double(h * i) / Double(size)) }
        }
        tables[key] = t
        return t
    }

    func synth(_ s: Source, count n: Int, seed: UInt64) -> [Double] {
        var out = [Double](repeating: 0, count: n)
        let fs = sampleRate
        let t0 = time
        switch s.kind.family {
        case .drums where s.kind != .overhead:
            // Hits twice a second: decaying tone plus a noise burst.
            let period = Int(fs * (s.kind == .hiHat ? 0.25 : 0.5))
            var lp = 0.0
            for i in 0..<n {
                let k = i % period
                let env = exp(-Double(k) / (fs * (s.kind == .kick ? 0.12 : 0.08)))
                let tone = s.pitch > 0 ? sin(2 * .pi * s.pitch * Double(k) / fs * (1 + 0.5 * env)) : 0
                let nz = noise()
                lp += 0.3 * (nz - lp)
                let noisePart = s.kind == .kick ? lp * 0.3 : (s.kind == .hiHat ? nz - lp : nz) * 0.6
                out[i] = env * (tone * (s.kind == .hiHat ? 0 : s.kind == .snare ? 0.25 : 1) + noisePart * exp(-Double(k) / (fs * 0.03)) * (s.kind == .snare ? 3 : 2))
            }
        case .drums:
            var lp = 0.0
            for i in 0..<n { let nz = noise(); lp += 0.5 * (nz - lp); out[i] = (nz - lp * 0.5) * 0.3 * (1 + 0.8 * exp(-Double(i % 24000) / 6000)) }
        default:
            // Harmonic source: vibrato, a phrase rhythm with breaths, spectral tilt by family.
            let tilt: Double = {
                switch s.kind.family {
                case .vocals, .choir: return 1.3
                case .strings: return 0.9
                case .woodwinds: return 1.6
                case .brass: return 0.8
                default: return s.kind == .bassGuitar ? 1.8 : 1.1
                }
            }()
            let vib = s.kind.family == .vocals || s.kind.family == .choir || s.kind.family == .strings ? 0.012 : 0.002
            let table = wavetable(pitch: s.pitch, tilt: tilt)
            let size = Double(table.count)
            var ph = Double(seed % 7) / 7 * size
            let phrase = s.kind.family == .vocals || s.kind == .choir ? 0.9 : 1.6
            for i in 0..<n {
                let t = t0 + Double(i) / fs
                let f0 = s.pitch * (1 + vib * sin(2 * .pi * 5.2 * t))
                ph += f0 / fs * size
                if ph >= size { ph -= size }
                let k = Int(ph), fr = ph - Double(k)
                let v = table[k] + (table[(k + 1) % table.count] - table[k]) * fr
                // Phrases with short gaps (breaths, bow changes) and some dynamics.
                let pos = (t / phrase).truncatingRemainder(dividingBy: 1)
                let gate = pos < 0.85 ? 1.0 : 0.0
                let dyn = 0.6 + 0.4 * sin(2 * .pi * t / 3.7 + Double(seed))
                out[i] = v * 0.4 * gate * dyn + 0.02 * noise() * gate
            }
        }
        return out
    }
}
