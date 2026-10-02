import Foundation

/// One loudspeaker group of the virtual system (subwoofers or mains).
public struct VirtualSource: Equatable, Codable, Sendable {
    /// Crossover and driver response as biquads.
    public var filters: [Biquad]
    /// Acoustic + processing delay in whole samples.
    public var delaySamples: Int
    public var gainDB: Double
    public var invertPolarity: Bool
    /// Group is powered/unmuted.
    public var enabled: Bool

    public init(filters: [Biquad], delaySamples: Int, gainDB: Double = 0, invertPolarity: Bool = false,
                enabled: Bool = true) {
        self.filters = filters
        self.delaySamples = delaySamples
        self.gainDB = gainDB
        self.invertPolarity = invertPolarity
        self.enabled = enabled
    }

    var linearGain: Double { Decibel.toAmplitude(gainDB) * (invertPolarity ? -1 : 1) }

    public func response(at f: Double, sampleRate fs: Double) -> Complex {
        guard enabled else { return .zero }
        let h = filters.reduce(Complex.one) { $0 * $1.response(at: f, sampleRate: fs) }
        return h * linearGain * Complex.expj(-2 * .pi * f * Double(delaySamples) / fs)
    }
}

public struct VirtualReflection: Equatable, Codable, Sendable {
    /// Extra delay relative to the direct sound, in samples.
    public var delaySamples: Int
    public var gain: Double

    public init(delaySamples: Int, gain: Double) {
        self.delaySamples = delaySamples
        self.gain = gain
    }
}

/// Room seen by the measurement microphone: discrete reflections (comb filtering) and
/// low-frequency modes (peaking resonances).
public struct VirtualRoom: Equatable, Codable, Sendable {
    public var reflections: [VirtualReflection]
    public var modes: [Biquad]

    public init(reflections: [VirtualReflection] = [], modes: [Biquad] = []) {
        self.reflections = reflections
        self.modes = modes
    }

    public static let anechoic = VirtualRoom()

    public func response(at f: Double, sampleRate fs: Double) -> Complex {
        var h = Complex.one
        for r in reflections {
            h += Complex.expj(-2 * .pi * f * Double(r.delaySamples) / fs) * r.gain
        }
        return modes.reduce(h) { $0 * $1.response(at: f, sampleRate: fs) }
    }
}

/// Complete virtual sound system: signal → (subs + mains) → room → microphone.
public struct VirtualSystem: Equatable, Codable, Sendable {
    public var sampleRate: Double
    public var sub: VirtualSource
    public var main: VirtualSource
    public var room: VirtualRoom
    /// RMS of white noise added at the microphone (dBFS). Use −200 for none.
    public var micNoiseDBFS: Double
    /// Overall acoustic gain to the microphone (dB).
    public var acousticGainDB: Double

    public init(sampleRate: Double, sub: VirtualSource, main: VirtualSource, room: VirtualRoom = .anechoic,
                micNoiseDBFS: Double = -200, acousticGainDB: Double = 0) {
        self.sampleRate = sampleRate
        self.sub = sub
        self.main = main
        self.room = room
        self.micNoiseDBFS = micNoiseDBFS
        self.acousticGainDB = acousticGainDB
    }

    /// Analytic transfer function from the system input to the microphone (excluding device latency).
    public func response(at f: Double) -> Complex {
        (sub.response(at: f, sampleRate: sampleRate) + main.response(at: f, sampleRate: sampleRate))
            * room.response(at: f, sampleRate: sampleRate) * Decibel.toAmplitude(acousticGainDB)
    }

    public func response(on frequencies: [Double]) -> [Complex] { frequencies.map { response(at: $0) } }

    public var maximumDelaySamples: Int {
        max(sub.delaySamples, main.delaySamples) + (room.reflections.map(\.delaySamples).max() ?? 0)
    }

    /// A typical small PA: LR24 crossover at `crossover` Hz, mains with a 2nd-order HPF at 45 Hz
    /// (cabinet), subs with an 8th-order-ish 30 Hz roll-off, given distances to the microphone.
    public static func typicalPA(sampleRate: Double = 48000, crossover: Double = 90,
                                 subDistance: Double = 8, mainDistance: Double = 9.5,
                                 celsius: Double = 20, subGainDB: Double = 0,
                                 subInverted: Bool = false, room: VirtualRoom = .anechoic,
                                 micNoiseDBFS: Double = -200) -> VirtualSystem {
        let c = Acoustics.speedOfSound(celsius: celsius)
        func samples(_ meters: Double) -> Int { Int((meters / c * sampleRate).rounded()) }
        let sub = VirtualSource(
            filters: CrossoverFilter.linkwitzRiley24(.lowPass, frequency: crossover, sampleRate: sampleRate)
                + CrossoverFilter.butterworth(.highPass, order: 4, frequency: 30, sampleRate: sampleRate),
            delaySamples: samples(subDistance), gainDB: subGainDB, invertPolarity: subInverted)
        let main = VirtualSource(
            filters: CrossoverFilter.linkwitzRiley24(.highPass, frequency: crossover, sampleRate: sampleRate)
                + [Biquad.design(.highPass, frequency: 45, q: 0.707, sampleRate: sampleRate),
                   Biquad.design(.lowPass, frequency: 18000, q: 0.707, sampleRate: sampleRate)],
            delaySamples: samples(mainDistance))
        return VirtualSystem(sampleRate: sampleRate, sub: sub, main: main, room: room, micNoiseDBFS: micNoiseDBFS)
    }
}

/// Time-domain renderer of a `VirtualSystem` (sample-accurate, matches `response(at:)`).
public final class VirtualSystemProcessor {
    public private(set) var system: VirtualSystem

    private var subFilter: BiquadCascade
    private var mainFilter: BiquadCascade
    private var modeFilter: BiquadCascade
    private var inputHistory: [Double]
    private var sumHistory: [Double]
    private let mask: Int
    private var position = 0
    private var rng: RandomSource

    public init(system: VirtualSystem, seed: UInt64 = 7) {
        self.system = system
        subFilter = BiquadCascade(system.sub.filters)
        mainFilter = BiquadCascade(system.main.filters)
        modeFilter = BiquadCascade(system.room.modes)
        var size = 1
        while size < system.maximumDelaySamples + 2 { size <<= 1 }
        size = max(size, 1 << 12)
        inputHistory = [Double](repeating: 0, count: size)
        sumHistory = [Double](repeating: 0, count: size)
        mask = size - 1
        rng = RandomSource(seed: seed)
    }

    /// Changes which groups are on (e.g. "only the subwoofer") without resetting filter state.
    public func setEnabled(sub: Bool, main: Bool) {
        system.sub.enabled = sub
        system.main.enabled = main
    }

    public func process(_ input: [Float]) -> [Float] {
        let s = system
        let gSub = s.sub.enabled ? s.sub.linearGain : 0
        let gMain = s.main.enabled ? s.main.linearGain : 0
        let acoustic = Decibel.toAmplitude(s.acousticGainDB)
        let noise = s.micNoiseDBFS > -199 ? Decibel.toAmplitude(s.micNoiseDBFS) : 0
        var out = [Float](repeating: 0, count: input.count)
        for n in input.indices {
            inputHistory[position] = Double(input[n])
            let xs = inputHistory[(position - s.sub.delaySamples) & mask]
            let xm = inputHistory[(position - s.main.delaySamples) & mask]
            // Filters always run so that toggling groups behaves like muting an amplifier.
            let ys = subFilter.process(xs) * gSub
            let ym = mainFilter.process(xm) * gMain
            let direct = ys + ym
            sumHistory[position] = direct
            var y = direct
            for r in s.room.reflections {
                y += sumHistory[(position - r.delaySamples) & mask] * r.gain
            }
            y = modeFilter.process(y) * acoustic
            if noise > 0 { y += rng.nextGaussian() * noise }
            out[n] = Float(y)
            position = (position + 1) & mask
        }
        return out
    }
}
