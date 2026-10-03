import Foundation

/// Two microphones (or a mic and a DI) on the same source whose polarity must agree.
public struct PolarityPair: Equatable, Codable, Sendable {
    /// Channel kept as it is.
    public var reference: Int
    /// Channel whose polarity is flipped and judged.
    public var test: Int
    public init(reference: Int, test: Int) { self.reference = reference; self.test = test }
}

public enum PolarityPairs {
    /// Words that tell two mics of one source apart ("Kick In" / "Kick Out", "SN Top" / "SN Bottom", "Bass DI" / "Bass Mic").
    static let positions: Set<String> = ["in", "out", "inside", "outside", "top", "bottom", "btm", "bot", "up", "down", "dn",
                                         "sub", "di", "mic", "amp", "cab", "l", "r", "left", "right", "front", "back",
                                         "вн", "внутр", "внутри", "нар", "наруж", "снаружи", "верх", "низ", "лев", "прав",
                                         "ди", "мик", "комбо", "кабинет"]

    /// Name without the position word and numbers: "Kick In" and "Kick Out" both give "kick".
    static func source(_ name: String) -> String {
        let words = name.lowercased().split { !$0.isLetter }.map(String.init)
        return words.filter { !positions.contains($0) }.joined(separator: " ")
    }

    /// Pairs found from the console names: channels of one source and kind; the first is the reference.
    /// Drums, bass, guitars, keys and acoustic instruments; never vocals of different singers.
    public static func find(in strips: [ChannelStrip]) -> [PolarityPair] {
        var groups: [String: [ChannelStrip]] = [:]
        for s in strips.sorted(by: { $0.id < $1.id }) where !s.name.isEmpty {
            let base = source(s.name)
            guard !base.isEmpty, let kind = SourceClassifier.kind(forName: s.name),
                  kind.family != .vocals, kind != .choir, kind != .playback else { continue }
            groups["\(kind.family.rawValue)|\(base)", default: []].append(s)
        }
        var pairs: [PolarityPair] = []
        for (_, g) in groups where g.count >= 2 {
            for s in g.dropFirst() { pairs.append(PolarityPair(reference: g[0].id, test: s.id)) }
        }
        // Overheads against the snare: the classic check for the whole kit.
        let snare = strips.first { SourceClassifier.kind(forName: $0.name) == .snare }
        for oh in strips where SourceClassifier.kind(forName: oh.name) == .overhead {
            if let sn = snare, !pairs.contains(where: { $0.test == oh.id || $0.reference == oh.id }) { pairs.append(PolarityPair(reference: sn.id, test: oh.id)) }
        }
        return pairs.sorted { ($0.reference, $0.test) < ($1.reference, $1.test) }
    }
}

/// Automatic polarity check by ear, the way an engineer does it: while the source plays, flip the polarity of the
/// second mic back and forth and listen to the sum; keep the position where the sum is fuller (more low and low-mid
/// energy — the two mics add instead of cancelling).
///
/// The "ear" is the measurement mic in the hall (low/low-mid band, 40–800 Hz) or, without it, the console's main
/// meter. Each window is compared with the reference channel's own level, so the musician playing louder or softer
/// does not count. At least four windows in each position are needed; the decision needs a median difference of
/// 1 dB and two thirds of the alternations agreeing. Otherwise the pair is reported as unclear and left as it was.
public struct PolarityCheck: Sendable {
    public enum Verdict: Equatable, Sendable {
        case keep(differenceDB: Double)
        case invert(differenceDB: Double)
        case unclear(differenceDB: Double)
    }

    public let pairs: [PolarityPair]
    public private(set) var index = 0
    public private(set) var results: [PolarityPair: Verdict] = [:]
    /// Windows needed in each position.
    public var windowsPerState = 4
    public var maxWindows = 30
    public var thresholdDB = 1.0

    var originalInverted: Bool?
    var originalFaders: [Int: Double] = [:]
    var measured: [(inverted: Bool, value: Double)] = []
    var windows = 0
    var currentInverted = false

    public init(pairs: [PolarityPair]) { self.pairs = pairs }

    public var done: Bool { index >= pairs.count }
    public var current: PolarityPair? { done ? nil : pairs[index] }

    /// Energy of the sum in the band where two mics of one source overlap most (dB).
    public static func sumEnergy(_ f: SignalFeatures) -> Double? {
        let idx = ThirdOctave.centers.indices.filter { (40...800).contains(ThirdOctave.centers[$0]) }
        let p = idx.map { f.bandsDB[$0] }.filter { $0 > -119 }
        guard !p.isEmpty else { return nil }
        return Decibel.fromPower(p.reduce(0) { $0 + pow(10, $1 / 10) })
    }

    /// One window (≈ 1–2 s). `channels`: features of the two channels; `sum`: the measured sum (hall mic band energy
    /// via `sumEnergy`, or the main meter). Returns strips to send and notes.
    public mutating func step(strips: [Int: ChannelStrip], channels: [Int: SignalFeatures], sum: Double?)
        -> (strips: [ChannelStrip], notes: [(Int, AssistNote)]) {
        guard let pair = current, var test = strips[pair.test], var ref = strips[pair.reference] else {
            if !done { index += 1 }
            return ([], [])
        }
        var out: [ChannelStrip] = []
        var notes: [(Int, AssistNote)] = []

        if originalInverted == nil {
            // Start: remember, make both audible at a similar level, begin in the current position.
            originalInverted = test.polarityInverted
            currentInverted = test.polarityInverted
            originalFaders = [ref.id: ref.faderDB, test.id: test.faderDB]
            let level = max(ref.faderDB, test.faderDB, -20)
            if ref.faderDB < level - 10 || ref.muted { ref.faderDB = level; ref.muted = false; out.append(ref) }
            if test.faderDB < level - 10 || test.muted { test.faderDB = level; test.muted = false; out.append(test) }
            notes.append((test.id, .polarityChecking(against: ref.id)))
            measured = []
            windows = 0
            return (out, notes)
        }

        windows += 1
        let both = (channels[ref.id]?.hasSignal ?? false) && (channels[test.id]?.hasSignal ?? false)
        if both, let s = sum {
            // Relative to the power sum of both channels: how the playing goes louder or softer cancels out, and
            // two unrelated signals give the same value in either position.
            let a = channels[ref.id]?.rmsDB ?? 0, b = channels[test.id]?.rmsDB ?? 0
            let rel = s - Decibel.fromPower(pow(10, a / 10) + pow(10, b / 10))
            measured.append((currentInverted, rel))
        }
        let nNorm = measured.filter { !$0.inverted }.count, nInv = measured.filter(\.inverted).count
        if (nNorm >= windowsPerState && nInv >= windowsPerState) || windows >= maxWindows {
            let verdict = decide()
            results[pair] = verdict
            var final = test
            final.polarityInverted = {
                switch verdict {
                case .keep: return false
                case .invert: return true
                case .unclear: return originalInverted ?? false
                }
            }()
            // Faders back as they were.
            if let f = originalFaders[test.id] { final.faderDB = f }
            final.muted = strips[test.id]?.muted ?? final.muted
            out.append(final)
            if let f = originalFaders[ref.id], ref.faderDB != f { ref.faderDB = f; out.append(ref) }
            switch verdict {
            case let .keep(d): notes.append((test.id, .polarity(inverted: false, differenceDB: d)))
            case let .invert(d): notes.append((test.id, .polarity(inverted: true, differenceDB: d)))
            case let .unclear(d): notes.append((test.id, .polarityUnclear(differenceDB: d)))
            }
            index += 1
            originalInverted = nil
            return (out, notes)
        }
        // Click: an irregular pattern (N I I N I N N I …) so a musical rhythm cannot line up with the clicks.
        let pattern = [true, false, true, true, false, true, false, false]
        if pattern[windows % pattern.count] { currentInverted.toggle() }
        test.polarityInverted = currentInverted
        out.append(test)
        return (out, notes)
    }

    /// Inverted minus normal (dB): the median over neighbouring windows, and how many of them agree.
    func decide() -> Verdict {
        // Every inverted window against every normal one.
        let inv = measured.filter(\.inverted).map(\.value), nor = measured.filter { !$0.inverted }.map(\.value)
        var diffs: [Double] = []
        for a in inv { for b in nor { diffs.append(a - b) } }
        guard diffs.count >= 3 else { return .unclear(differenceDB: diffs.first ?? 0) }
        let med = diffs.sorted()[diffs.count / 2]
        let agree = Double(diffs.filter { ($0 > 0) == (med > 0) && abs($0) > thresholdDB / 2 }.count) / Double(diffs.count)
        if abs(med) >= thresholdDB && agree >= 2.0 / 3 { return med > 0 ? .invert(differenceDB: med) : .keep(differenceDB: -med) }
        return .unclear(differenceDB: med)
    }
}

extension PolarityPair: Hashable {}
