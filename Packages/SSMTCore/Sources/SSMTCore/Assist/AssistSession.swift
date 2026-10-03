import Foundation

/// One FOH Assist session: the console mirror, what is being tuned, and the undo snapshot.
/// The app feeds it every ≈ 2 s with the audio of the channels being tuned (and the measurement mic)
/// and sends the strips it returns to the console.
public final class AssistSession {
    public struct LogEntry: Equatable, Sendable {
        public var step: Int
        public var channel: Int
        public var note: AssistNote
    }

    public enum Job: Equatable, Sendable {
        case none
        case channel(Int)
        case group(AssistGroupSelection, [Int])
        case polarity([PolarityPair])
    }

    public let sampleRate: Double
    public var character: MixCharacter
    public var tap: TapPoint
    /// Console state as last read or written.
    public private(set) var strips: [Int: ChannelStrip]
    /// Strips before the assistant first touched them (for undo).
    public private(set) var snapshot: [Int: ChannelStrip] = [:]
    public private(set) var job: Job = .none
    public private(set) var single: ChannelTuning?
    public private(set) var group: GroupTuning?
    public private(set) var polarity: PolarityCheck?
    public private(set) var log: [LogEntry] = []
    public private(set) var steps = 0
    /// Last analysis per channel (for the UI meters and the classifier column).
    public private(set) var features: [Int: SignalFeatures] = [:]
    /// Calibrated measurement mic level, if the user calibrated it in function #1 (dB SPL A).
    public var micSPL: Double?
    /// Last A-weighted mic level (dB SPL if calibrated, else dBFS).
    public private(set) var micLevel: Double?
    /// The measurement microphone chosen from the function #1 library.
    public var measurementMic = MeasurementMic()
    let extractor: FeatureExtractor
    let detector: FeedbackDetector

    public init(strips: [ChannelStrip], character: MixCharacter = .musical, tap: TapPoint = .preEQ, sampleRate: Double = 48000) {
        self.sampleRate = sampleRate
        self.character = character
        self.tap = tap
        self.strips = Dictionary(uniqueKeysWithValues: strips.map { ($0.id, $0) })
        extractor = FeatureExtractor(sampleRate: sampleRate)
        detector = FeedbackDetector(sampleRate: sampleRate)
    }

    public var isRunning: Bool {
        switch job {
        case .none: return false
        case .channel: return single?.state != .done
        case .group: return group?.phase != .done
        case .polarity: return polarity?.done == false
        }
    }

    /// Channels the current job listens to.
    public var listening: [Int] {
        switch job {
        case .none: return []
        case let .channel(c): return [c]
        case let .group(_, m): return m
        case .polarity: return polarity?.current.map { [$0.reference, $0.test] } ?? []
        }
    }

    /// The console changed a strip (pushed update or the engineer moved something).
    public func updateFromConsole(_ s: ChannelStrip) { strips[s.id] = s }

    public func startChannel(_ ch: Int, kind: SourceKind? = nil) {
        guard let s = strips[ch] else { return }
        if snapshot[ch] == nil { snapshot[ch] = s }
        single = ChannelTuning(channel: ch, name: s.name, kind: kind, character: character, tap: tap)
        group = nil
        job = .channel(ch)
        detector.reset()
    }

    /// Starts a group. Returns the channels found (empty: nothing matched, nothing started).
    @discardableResult
    public func startGroup(_ selection: AssistGroupSelection) -> [Int] {
        let members = selection.channels(in: strips.values.sorted { $0.id < $1.id })
        guard !members.isEmpty else { return [] }
        for ch in members where snapshot[ch] == nil { snapshot[ch] = strips[ch] }
        group = GroupTuning(members: members, names: strips.mapValues(\.name), character: character, tap: tap)
        single = nil
        job = .group(selection, members)
        detector.reset()
        return members
    }

    /// Checks the polarity of the given pairs (default: pairs found from the console names). Returns the pairs.
    @discardableResult
    public func startPolarity(_ pairs: [PolarityPair]? = nil) -> [PolarityPair] {
        let p = pairs ?? PolarityPairs.find(in: strips.values.sorted { $0.id < $1.id })
        guard !p.isEmpty else { return [] }
        for pair in p { for ch in [pair.reference, pair.test] where snapshot[ch] == nil { snapshot[ch] = strips[ch] } }
        polarity = PolarityCheck(pairs: p)
        single = nil
        group = nil
        job = .polarity(p)
        return p
    }

    public func stop() { job = .none; single = nil; group = nil; polarity = nil }

    /// Strips to send to put channels back as they were before the assistant (all touched channels if nil).
    public func undo(_ channel: Int? = nil) -> [ChannelStrip] {
        let chans = channel.map { [$0] } ?? Array(snapshot.keys)
        var out: [ChannelStrip] = []
        for ch in chans.sorted() {
            guard let s = snapshot[ch] else { continue }
            strips[ch] = s
            snapshot[ch] = nil
            out.append(s)
        }
        if channel == nil || listening.contains(channel!) { stop() }
        return out
    }

    /// One step: audio of the listened channels (at the tap) and of the measurement mic for the last window.
    /// Returns the strips that changed (send them to the console).
    public func tick(taps: [Int: [Float]], mic: [Float]?) -> [ChannelStrip] {
        var feats: [Int: SignalFeatures] = [:]
        for (ch, x) in taps { feats[ch] = extractor.analyze(x) }
        return tick(features: feats, mic: mic)
    }

    /// Same, with channel features already measured (console meters and RTA over the network).
    public func tick(features feats: [Int: SignalFeatures], mic: [Float]?, mainLevelDB: Double? = nil) -> [ChannelStrip] {
        guard isRunning else { return [] }
        steps += 1
        for (ch, f) in feats { features[ch] = f }
        if let mic {
            let l = measurementMic.levelA(mic, sampleRate: sampleRate)
            micLevel = l.value
            if l.calibrated { micSPL = l.value }
        }
        let events = mic.map { detector.process($0) } ?? []
        var changed: [ChannelStrip] = []
        func commit(_ s: ChannelStrip) {
            if strips[s.id] != s { strips[s.id] = s; changed.append(s) }
        }
        switch job {
        case .none:
            break
        case let .channel(ch):
            guard var t = single, var s = strips[ch], let f = feats[ch] else { break }
            // Feedback while tuning one channel: notch that channel.
            for e in events {
                while s.eq.count <= 2 { s.eq.append(StripEQBand(frequency: 1000)) }
                let depth = min(12, abs(s.eq[2].gainDB) + (t.reservedBands.contains(2) ? 3 : 4))
                s.eq[2] = StripEQBand(type: .peaking, frequency: (e.frequency * 10).rounded() / 10, gainDB: -depth, q: 8)
                t.reservedBands.insert(2)
                log.append(LogEntry(step: steps, channel: ch, note: .feedback(frequency: e.frequency, notchDB: -depth)))
            }
            let (ns, notes) = t.step(features: f, strip: s)
            single = t
            for n in notes { log.append(LogEntry(step: steps, channel: ch, note: n)) }
            commit(ns)
        case .polarity:
            guard var p = polarity else { break }
            // The "ear": the hall mic's low / low-mid energy, else the console's main meter.
            var sum = mainLevelDB
            if let mic, mic.count >= 4096 {
                let mf = measurementMic.corrected(extractor.analyze(mic, gateDB: -90))
                if let e = PolarityCheck.sumEnergy(mf) { sum = e }
            }
            let (ns, notes) = p.step(strips: strips, channels: feats, sum: sum)
            polarity = p
            for s in ns { commit(s) }
            for (ch, n) in notes { log.append(LogEntry(step: steps, channel: ch, note: n)) }
        case .group:
            guard var g = group else { break }
            let (ns, notes) = g.step(strips: strips, features: feats, feedback: events, splA: micSPL)
            group = g
            for ch in ns.keys.sorted() { commit(ns[ch]!) }
            for ch in notes.keys.sorted() { for n in notes[ch]! { log.append(LogEntry(step: steps, channel: ch, note: n)) } }
        }
        return changed
    }
}
