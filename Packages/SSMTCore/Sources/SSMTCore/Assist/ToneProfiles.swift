import Foundation

/// The assistant's knowledge of how each source usually sounds well in a live mix.
///
/// These are engineering starting points collected from common live-sound practice (high-pass points,
/// long-term tonal balance, compression), not measurements of a reference library. The tonal target is a
/// long-term one-third-octave balance: the assistant only corrects the *shape* of the spectrum, never its
/// absolute level, and only by a share of the deviation set by the mix character.
public struct ToneProfile: Equatable, Sendable {
    /// High-pass (Hz); 0 = off.
    public var highPassHz: Double
    /// (frequency, relative dB) anchors of the target balance, interpolated on a log-frequency axis.
    public var target: [(Double, Double)]
    /// Upper limit of the band the EQ works in (Hz).
    public var upperHz: Double
    /// Compressor starting point.
    public var ratio: Double
    public var attackMS: Double
    public var releaseMS: Double
    /// Gain reduction on loud passages (95th percentile, dB) for the musical character.
    public var gainReductionDB: Double
    /// Level in the mix relative to the lead (dB), used when several channels are balanced together.
    public var mixLevelDB: Double

    public static func == (a: ToneProfile, b: ToneProfile) -> Bool {
        a.highPassHz == b.highPassHz && a.upperHz == b.upperHz && a.ratio == b.ratio && a.attackMS == b.attackMS
            && a.releaseMS == b.releaseMS && a.gainReductionDB == b.gainReductionDB && a.mixLevelDB == b.mixLevelDB
            && a.target.map(\.0) == b.target.map(\.0) && a.target.map(\.1) == b.target.map(\.1)
    }

    /// Target (dB) at frequency f.
    public func targetDB(at f: Double) -> Double {
        guard let first = target.first, let last = target.last else { return 0 }
        if f <= first.0 { return first.1 - 6 * log2(first.0 / f) * (first.0 > 60 ? 1 : 0) }
        if f >= last.0 { return last.1 - 9 * log2(f / last.0) }
        for k in 1..<target.count where f <= target[k].0 {
            let (f0, d0) = target[k - 1], (f1, d1) = target[k]
            let t = log(f / f0) / log(f1 / f0)
            return d0 + (d1 - d0) * t
        }
        return last.1
    }

    /// Lowest frequency the EQ works on.
    public var lowerHz: Double { max(30, highPassHz * 1.25) }

    public static func profile(for kind: SourceKind, character: MixCharacter) -> ToneProfile {
        var p = base(kind)
        switch character {
        case .musical:
            // Headset and lavalier vocals: higher low cut, more presence.
            if kind.family == .vocals || kind == .choir { p.highPassHz *= 1.15 }
        case .rock:
            if kind.family == .drums || kind == .bassGuitar { p.gainReductionDB += 1 }
            if kind == .electricGuitar { p.highPassHz = max(p.highPassHz, 100) }
        case .classical:
            p.highPassHz *= 0.75
            p.mixLevelDB += kind.family == .brass ? -3 : 0
        case .speech:
            if kind.family == .vocals { p.highPassHz = max(p.highPassHz, 110) }
        }
        p.gainReductionDB *= character.compressionScale
        return p
    }

    static func base(_ kind: SourceKind) -> ToneProfile {
        func P(_ hp: Double, _ t: [(Double, Double)], up: Double = 16000, ratio: Double, att: Double, rel: Double, gr: Double, mix: Double) -> ToneProfile {
            ToneProfile(highPassHz: hp, target: t, upperHz: up, ratio: ratio, attackMS: att, releaseMS: rel, gainReductionDB: gr, mixLevelDB: mix)
        }
        switch kind {
        case .kick:
            return P(30, [(50, 0), (63, 0), (80, -1), (125, -5), (250, -12), (400, -16), (630, -17), (1000, -17), (2500, -15), (4000, -16), (8000, -24)],
                     up: 10000, ratio: 4, att: 15, rel: 100, gr: 4, mix: -2)
        case .snare:
            return P(80, [(160, -4), (200, -2), (250, -3), (400, -6), (630, -8), (1000, -8), (2000, -8), (4000, -8), (6300, -10), (10000, -16)],
                     ratio: 4, att: 8, rel: 120, gr: 4, mix: -3)
        case .tom:
            return P(50, [(80, -2), (125, 0), (200, -2), (400, -10), (630, -12), (1000, -13), (3150, -14), (6300, -20)],
                     up: 10000, ratio: 3, att: 15, rel: 150, gr: 3, mix: -6)
        case .hiHat:
            return P(250, [(2000, -8), (4000, -4), (6300, -2), (8000, -1), (10000, -2), (16000, -8)], ratio: 2, att: 5, rel: 80, gr: 0, mix: -12)
        case .overhead:
            return P(120, [(200, -6), (400, -7), (1000, -7), (3000, -6), (6300, -6), (10000, -7), (16000, -12)], ratio: 2, att: 25, rel: 200, gr: 1.5, mix: -10)
        case .percussion:
            return P(80, [(125, -4), (400, -6), (1000, -6), (4000, -7), (10000, -12)], ratio: 2.5, att: 10, rel: 120, gr: 3, mix: -8)
        case .bassGuitar:
            return P(35, [(40, -2), (63, 0), (100, 0), (160, -3), (250, -6), (500, -10), (800, -11), (1600, -14), (3150, -20), (6300, -30)],
                     up: 8000, ratio: 4, att: 20, rel: 200, gr: 5, mix: -3)
        case .electricGuitar:
            return P(90, [(125, -8), (200, -4), (400, -3), (800, -2), (1600, -1), (2500, -2), (4000, -5), (6300, -11), (10000, -20)],
                     up: 10000, ratio: 2.5, att: 15, rel: 150, gr: 2, mix: -6)
        case .acousticGuitar:
            return P(80, [(100, -10), (160, -6), (250, -5), (500, -6), (1000, -6), (2500, -6), (5000, -7), (10000, -10)], ratio: 3, att: 10, rel: 150, gr: 4, mix: -6)
        case .keys:
            return P(40, [(63, -6), (125, -3), (250, -3), (500, -4), (1000, -5), (2000, -6), (4000, -8), (8000, -11), (16000, -17)], ratio: 2, att: 20, rel: 200, gr: 2, mix: -7)
        case .piano:
            return P(40, [(63, -6), (125, -3), (250, -4), (500, -4), (1000, -5), (2000, -6), (4000, -8), (8000, -11), (16000, -17)], ratio: 2, att: 20, rel: 250, gr: 3, mix: -6)
        case .maleVocal:
            return P(90, [(100, -10), (160, -4), (250, -3), (400, -5), (800, -6), (1600, -7), (3150, -7), (5000, -9), (8000, -13), (12500, -18)],
                     ratio: 3, att: 6, rel: 150, gr: 6, mix: 0)
        case .femaleVocal:
            return P(120, [(160, -10), (250, -5), (400, -4), (800, -5), (1600, -6), (3150, -6), (5000, -8), (8000, -12), (12500, -16)],
                     ratio: 3, att: 6, rel: 150, gr: 6, mix: 0)
        case .backingVocal:
            return P(140, [(200, -10), (315, -5), (500, -5), (1000, -6), (2000, -6), (3150, -6), (5000, -8), (8000, -12), (12500, -17)],
                     ratio: 4, att: 6, rel: 150, gr: 6, mix: -6)
        case .choir:
            return P(100, [(125, -12), (200, -6), (315, -4), (500, -4), (1000, -5), (2000, -6), (4000, -8), (8000, -12), (12500, -17)],
                     ratio: 2, att: 15, rel: 250, gr: 3, mix: -3)
        case .speech:
            return P(110, [(125, -12), (200, -5), (400, -4), (1000, -5), (2500, -5), (4000, -7), (8000, -14), (12500, -22)],
                     up: 12500, ratio: 3, att: 5, rel: 150, gr: 6, mix: 0)
        case .violin:
            return P(160, [(200, -6), (400, -4), (630, -4), (1000, -4), (2000, -4), (3150, -6), (5000, -9), (8000, -13), (12500, -19)],
                     ratio: 2, att: 15, rel: 200, gr: 2, mix: -6)
        case .viola:
            return P(110, [(125, -7), (250, -3), (500, -3), (1000, -4), (2000, -6), (4000, -9), (8000, -14)], up: 12500, ratio: 2, att: 15, rel: 200, gr: 2, mix: -7)
        case .cello:
            return P(55, [(63, -8), (100, -3), (200, -2), (400, -3), (800, -5), (1600, -7), (3150, -10), (6300, -16)], up: 12500, ratio: 2, att: 20, rel: 250, gr: 2, mix: -6)
        case .doubleBass:
            return P(35, [(40, -3), (63, 0), (125, -1), (250, -4), (500, -8), (1000, -12), (2500, -18)], up: 8000, ratio: 3, att: 25, rel: 250, gr: 3, mix: -6)
        case .harp:
            return P(45, [(63, -6), (200, -3), (500, -4), (1000, -5), (2500, -6), (5000, -9), (10000, -14)], ratio: 2, att: 15, rel: 250, gr: 2, mix: -8)
        case .flute:
            return P(200, [(250, -8), (500, -3), (1000, -2), (2000, -4), (4000, -8), (8000, -14)], up: 12500, ratio: 2, att: 15, rel: 200, gr: 2, mix: -8)
        case .clarinet:
            return P(120, [(160, -6), (250, -3), (500, -3), (1000, -4), (2000, -6), (4000, -9), (8000, -15)], up: 12500, ratio: 2, att: 15, rel: 200, gr: 2, mix: -8)
        case .oboe:
            return P(200, [(250, -6), (500, -3), (1000, -3), (2000, -4), (4000, -7), (8000, -14)], up: 12500, ratio: 2, att: 15, rel: 200, gr: 2, mix: -8)
        case .bassoon:
            return P(50, [(63, -8), (100, -3), (200, -2), (400, -3), (800, -6), (1600, -9), (3150, -13)], up: 10000, ratio: 2, att: 15, rel: 200, gr: 2, mix: -8)
        case .saxophone:
            return P(80, [(125, -8), (250, -3), (500, -3), (1000, -4), (2000, -5), (4000, -8), (8000, -14)], ratio: 3, att: 10, rel: 150, gr: 4, mix: -6)
        case .trumpet:
            return P(150, [(200, -10), (400, -5), (800, -3), (1600, -3), (3150, -5), (6300, -10), (10000, -16)], ratio: 3, att: 10, rel: 150, gr: 4, mix: -6)
        case .trombone:
            return P(70, [(80, -8), (160, -3), (315, -2), (630, -3), (1250, -5), (2500, -8), (5000, -13)], up: 12500, ratio: 3, att: 12, rel: 150, gr: 3, mix: -7)
        case .frenchHorn:
            return P(60, [(63, -8), (125, -3), (250, -2), (500, -3), (1000, -6), (2000, -10), (4000, -15)], up: 10000, ratio: 2, att: 15, rel: 200, gr: 2, mix: -7)
        case .tuba:
            return P(30, [(31.5, -6), (50, -2), (80, 0), (160, -2), (315, -6), (630, -11), (1250, -17)], up: 6300, ratio: 3, att: 20, rel: 200, gr: 3, mix: -8)
        case .playback, .unknown:
            return P(0, [], ratio: 2, att: 10, rel: 150, gr: 0, mix: -6)
        }
    }
}
