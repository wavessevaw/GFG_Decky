import Foundation
import Network
import SSMTAudio
import SSMTCore
import SwiftUI

/// UDP link to a Behringer X32 / Midas M32 or X Air console over the venue network (Wi-Fi router or cable),
/// the same way Mixing Station and X32-Edit connect: OSC parameters, /xremote updates and meter streams.
final class X32Link: @unchecked Sendable {
    let family: MixerFamily
    let host: String
    private let queue = DispatchQueue(label: "ssmt.assist.x32")
    private var connection: NWConnection?
    private var keepAlive: DispatchSourceTimer?
    /// Meter banks to keep streaming.
    var meterBanks: [ConsoleMeters.Bank] = [.channels, .buses, .rta]
    /// Every message received from the console (called on the link's queue).
    var onMessage: ((OSCMessage) -> Void)?

    init(family: MixerFamily, host: String) {
        self.family = family
        self.host = host
    }

    func start() {
        let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: family.defaultPort) ?? 10023, using: .udp)
        connection = c
        c.start(queue: queue)
        receive(c)
        send([X32Codec.info] + subscriptions())
        // The console forgets a remote and stops meters after 10 s without renewal.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 8, repeating: 8)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.sendNow(self.subscriptions())
        }
        t.resume()
        keepAlive = t
    }

    private func subscriptions() -> [OSCMessage] {
        [X32Codec.subscribe(family: family)] + meterBanks.map { ConsoleMeters.request($0, family: family) }
    }

    /// Asks for every channel strip and every mix bus (spaced out so the console does not drop requests).
    func queryAll(channels: Int) {
        var delay = 0.0
        for ch in 1...channels {
            let msgs = X32Codec.queryAddresses(ch, family: family).map { OSCMessage($0) }
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.sendNow(msgs) }
            delay += 0.02
        }
        for b in 1...X32Codec.busCount(family) {
            let msgs = X32Codec.busQueryAddresses(b, family: family).map { OSCMessage($0) }
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.sendNow(msgs) }
            delay += 0.02
        }
    }

    func send(_ messages: [OSCMessage]) { queue.async { [weak self] in self?.sendNow(messages) } }

    private func sendNow(_ messages: [OSCMessage]) {
        for m in messages { connection?.send(content: m.encoded(), completion: .contentProcessed { _ in }) }
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            if let data, let msgs = OSCMessage.decode(data) { msgs.forEach { self?.onMessage?($0) } }
            if error == nil { self?.receive(c) }
        }
    }

    func stop() {
        keepAlive?.cancel()
        keepAlive = nil
        connection?.cancel()
        connection = nil
    }
}

/// Function #4: FOH Assist. Soundcheck: tunes channels and groups by itself. Show: backs up the engineer.
@MainActor
final class AssistStore: ObservableObject {
    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected(String)
        case failed(String)
    }

    /// Where the assistant hears each channel.
    enum SignalSource: String, CaseIterable {
        /// Console meters and RTA over the network (Wi-Fi), like Mixing Station. Nothing else to connect.
        case network
        /// Every console channel as an input of the Mac (USB / Dante card): full audio analysis.
        case interface
    }

    enum Mode: String, CaseIterable { case soundcheck, show }

    @Published var family: MixerFamily = .simulator
    @Published var host = UserDefaults.standard.string(forKey: "assist.host") ?? "192.168.1.64" {
        didSet { UserDefaults.standard.set(host, forKey: "assist.host") }
    }
    @Published private(set) var connection: Connection = .disconnected
    @Published private(set) var strips: [ChannelStrip] = []
    @Published private(set) var buses: [BusStrip] = []
    @Published var mode: Mode = .soundcheck
    @Published var character: MixCharacter = .musical {
        didSet { session?.character = character; guardian?.character = character }
    }
    @Published var tap: TapPoint = .preEQ { didSet { session?.tap = tap } }
    @Published var signalSource: SignalSource = .network
    /// Audio interface with the measurement mic (and, for `.interface`, the console channels).
    @Published var inputDeviceUID: String?
    /// Interface input that carries console channel 1 (the others follow in order).
    @Published var firstInput = 1
    /// Interface input of the hall measurement microphone (0 = none) and of an optional stage mic.
    @Published var micInput = 0
    @Published var stageMicInput = 0
    /// Measurement microphone from the function #1 library (nil = the one selected there).
    @Published var micID: UUID?
    @Published var rangeFrom = 1
    @Published var rangeTo = 8
    @Published private(set) var log: [AssistSession.LogEntry] = []
    @Published private(set) var guardLog: [(time: Double, action: GuardAction)] = []
    @Published private(set) var features: [Int: SignalFeatures] = [:]
    @Published private(set) var busLevels: [Int: Double] = [:]
    @Published private(set) var job: AssistSession.Job = .none
    @Published private(set) var running = false
    @Published private(set) var guarding = false
    @Published private(set) var groupPhase: GroupPhase?
    @Published private(set) var micLevel: Double?
    @Published private(set) var micCalibrated = false
    @Published var message: String?

    /// Microphones of the function #1 library, the selected one and the SPL calibration (set by AppModel).
    var micLibrary: () -> (mics: [MicrophoneCalibration], selected: UUID?, spl: SPLCalibration?) = { ([], nil, nil) }

    private var session: AssistSession?
    private(set) var guardian: ShowGuard?
    private var sim: SimulatedConsole?
    private var link: X32Link?
    private var capture: AssistCapture?
    private var timer: Timer?
    private var stripMap: [Int: ChannelStrip] = [:]
    private var busMap: [Int: BusStrip] = [:]
    private var meters = ConsoleMeterAccumulator()
    /// Main L+R meter frames of the current window (the polarity check's "ear" without a hall mic).
    private var mainFrames: [Double] = []
    private var rtaCursor = 0
    private var references: [Int: [Double]] = [:]
    private var guardStart = Date()
    private let hallDetector = FeedbackDetector()
    private let stageDetector = FeedbackDetector()

    var isConnected: Bool { if case .connected = connection { return true } else { return false } }

    // MARK: measurement microphone (any microphone of the function #1 library)

    struct MicChoice: Identifiable, Hashable {
        let id: UUID
        let name: String
        let typical: Bool
    }

    var micChoices: [MicChoice] {
        let lib = micLibrary()
        return lib.mics.map { MicChoice(id: $0.id, name: $0.name, typical: false) }
            + MicrophoneProfiles.all.map { MicChoice(id: $0.uuid, name: $0.displayName, typical: true) }
    }

    var measurementMic: MeasurementMic {
        let lib = micLibrary()
        let id = micID ?? lib.selected
        let cal = id.flatMap { i in lib.mics.first { $0.id == i } ?? MicrophoneProfiles.profile(id: i)?.calibration }
        return MeasurementMic(calibration: cal, spl: lib.spl)
    }

    // MARK: connection

    func connect() {
        disconnect()
        switch family {
        case .simulator:
            let c = SimulatedConsole.demo()
            sim = c
            setStrips(c.strips)
            busMap = c.buses
            buses = busMap.values.sorted { $0.id < $1.id }
            connection = .connected("SSMT simulator · \(c.strips.count) ch")
        case .x32, .xAir:
            connection = .connecting
            setStrips(Dictionary(uniqueKeysWithValues: (1...family.channelCount).map { ($0, ChannelStrip(id: $0)) }))
            busMap = Dictionary(uniqueKeysWithValues: (1...X32Codec.busCount(family)).map { ($0, BusStrip(id: $0)) })
            buses = busMap.values.sorted { $0.id < $1.id }
            let l = X32Link(family: family, host: host)
            l.onMessage = { [weak self] m in Task { @MainActor in self?.received(m) } }
            link = l
            l.start()
            l.queryAll(channels: family.channelCount)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.connection == .connecting else { return }
                self.connection = .failed("no answer from \(self.host):\(self.family.defaultPort)")
            }
            startCapture()
        case .wing, .yamaha, .allenHeath:
            connection = .failed("not supported yet")
        }
        session = AssistSession(strips: strips, character: character, tap: tap)
        session?.measurementMic = measurementMic
    }

    func disconnect() {
        stopJob()
        stopGuard()
        link?.stop()
        link = nil
        capture?.stop()
        capture = nil
        sim = nil
        session = nil
        connection = .disconnected
    }

    private func startCapture() {
        // Audio is needed for the measurement mic, and for the channels when they come over USB / Dante.
        guard micInput > 0 || stageMicInput > 0 || signalSource == .interface else { return }
        do { capture = try AssistCapture(deviceUID: inputDeviceUID) } catch { message = "\(error)" }
    }

    func restartCapture() {
        guard family != .simulator, isConnected || connection == .connecting else { return }
        capture?.stop()
        capture = nil
        startCapture()
    }

    private func received(_ m: OSCMessage) {
        if m.address == "/info" {
            let parts = m.arguments.compactMap { if case let .string(s) = $0 { return s } else { return nil } }
            connection = .connected(parts.dropFirst().joined(separator: " · "))
            return
        }
        if let (bank, values) = ConsoleMeters.decode(m, family: family) {
            switch bank {
            case .channels: if running || guarding { meters.add(channelLevels: values) }
            case .rta: if running || guarding { meters.add(rtaBands: values) }
            case .buses:
                for (i, v) in values.prefix(X32Codec.busCount(family)).enumerated() { busLevels[i + 1] = v }
                if values.count >= 24, running { mainFrames.append(Decibel.fromPower(pow(10, values[22] / 10) + pow(10, values[23] / 10))) }
            }
            return
        }
        let t = Date().timeIntervalSince(guardStart)
        if let ch = X32Codec.apply(m, to: &stripMap, family: family) {
            if connection == .connecting { connection = .connected(host) }
            strips = stripMap.values.sorted { $0.id < $1.id }
            if let s = stripMap[ch] { session?.updateFromConsole(s); guardian?.consoleChanged(s, time: t) }
        } else if let id = X32Codec.apply(m, toBuses: &busMap) {
            buses = busMap.values.sorted { $0.id < $1.id }
            if let b = busMap[id] { guardian?.consoleChanged(bus: b, time: t) }
        }
    }

    private func setStrips(_ map: [Int: ChannelStrip]) {
        stripMap = map
        strips = map.values.sorted { $0.id < $1.id }
    }

    // MARK: soundcheck jobs

    func tune(channel: Int) {
        guard let session else { return }
        session.measurementMic = measurementMic
        session.startChannel(channel)
        begin()
    }

    func tune(_ selection: AssistGroupSelection) {
        guard let session else { return }
        session.measurementMic = measurementMic
        if session.startGroup(selection).isEmpty {
            message = "nothing found"
            return
        }
        begin()
    }

    /// Automatic polarity check of the mic pairs found from the console names (kick in/out, snare top/bottom,
    /// bass DI/mic, guitar L/R, overheads against the snare).
    func checkPolarity() {
        guard let session else { return }
        session.measurementMic = measurementMic
        if session.startPolarity().isEmpty {
            message = "nothing found"
            return
        }
        begin()
    }

    private func begin() {
        message = nil
        job = session?.job ?? .none
        running = true
        followRTA()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
    }

    func stopJob() {
        if !guarding { timer?.invalidate(); timer = nil }
        session?.stop()
        running = false
        job = .none
        groupPhase = nil
    }

    func undoAll() {
        guard let session else { return }
        apply(session.undo())
        stopJob()
    }

    /// Runs steps immediately instead of every 2 s (demo in the simulator, snapshot tests).
    func runNow(steps: Int) {
        timer?.invalidate()
        timer = nil
        for _ in 0..<steps { step() }
    }

    /// The console RTA follows the channel being tuned; in a group it visits the members in turn.
    private func followRTA() {
        guard let link, let session else { return }
        let chans = session.listening
        guard !chans.isEmpty else { return }
        let ch = chans[rtaCursor % chans.count]
        rtaCursor += 1
        meters.rtaChannel = ch
        link.send(ConsoleMeters.rtaFollow(channel: ch, family: family))
    }

    /// Features of the listened channels for the last window, and the hall mic audio.
    private func window(channels chans: [Int], seconds: Double) -> ([Int: SignalFeatures], [Float]?, [Float]?) {
        var feats: [Int: SignalFeatures] = [:]
        var mic: [Float]?
        var stage: [Float]?
        let ex = FeatureExtractor()
        if let sim {
            let r = sim.render(seconds: seconds, channels: chans, tap: tap)
            for (ch, x) in r.taps { feats[ch] = ex.analyze(x) }
            mic = r.mic
        } else {
            if signalSource == .interface, let capture {
                for ch in chans { if let x = capture.latest(input: firstInput + ch - 1, seconds: seconds) { feats[ch] = ex.analyze(x) } }
            } else {
                let w = meters.takeWindow(seconds: seconds)
                for ch in chans { if let f = w[ch] { feats[ch] = f } }
            }
            if micInput > 0 { mic = capture?.latest(input: micInput, seconds: seconds) }
            if stageMicInput > 0 { stage = capture?.latest(input: stageMicInput, seconds: seconds) }
        }
        if let mic {
            let l = measurementMic.levelA(mic, sampleRate: capture?.sampleRate ?? 48000)
            micLevel = l.value
            micCalibrated = l.calibrated
        }
        return (feats, mic, stage)
    }

    private func step() {
        guard let session, session.isRunning else {
            if running { running = false; if !guarding { timer?.invalidate(); timer = nil } }
            return
        }
        let (feats, mic, _) = window(channels: session.listening, seconds: 2)
        let main = mainFrames.isEmpty ? nil : Decibel.fromPower(mainFrames.reduce(0) { $0 + pow(10, $1 / 10) } / Double(mainFrames.count))
        mainFrames.removeAll()
        let changed = session.tick(features: feats, mic: mic, mainLevelDB: main)
        apply(changed)
        log = Array(session.log.suffix(200))
        features.merge(session.features) { $1 }
        groupPhase = session.group?.phase
        // A channel that is ready becomes the show guard's tonal reference.
        for ch in session.listening where references[ch] == nil {
            let done = session.single?.channel == ch ? session.single?.state == .done : session.group?.tunings[ch]?.state == .done
            if done, let f = session.features[ch], f.bandsDB.contains(where: { $0 > -119 }) { references[ch] = f.bandsDB }
        }
        if !session.isRunning { running = false; timer?.invalidate(); timer = nil } else { followRTA() }
    }

    private func apply(_ changed: [ChannelStrip]) {
        for s in changed {
            let old = stripMap[s.id]
            stripMap[s.id] = s
            sim?.setStrip(s)
            link?.send(X32Codec.messages(from: old, to: s, family: family))
        }
        if !changed.isEmpty { strips = stripMap.values.sorted { $0.id < $1.id } }
    }

    private func apply(buses changed: [BusStrip]) {
        for b in changed {
            let old = busMap[b.id]
            busMap[b.id] = b
            sim?.setBus(b)
            link?.send(X32Codec.busMessages(from: old, to: b, family: family))
        }
        if !changed.isEmpty { buses = busMap.values.sorted { $0.id < $1.id } }
    }

    // MARK: per-channel state for the table

    func state(of ch: Int) -> TuningState? {
        guard let session else { return nil }
        if let t = session.single, t.channel == ch { return t.state }
        return session.group?.tunings[ch]?.state
    }

    func kind(of ch: Int) -> SourceKind? {
        guard let session else { return nil }
        if let t = session.single, t.channel == ch { return t.kind }
        if let t = session.group?.tunings[ch] { return t.kind }
        return SourceClassifier.classify(name: stripMap[ch]?.name ?? "", features: features[ch]).kind
    }

    var inputDevices: [AudioDeviceInfo] { DeviceCatalog.allDevices().filter { $0.inputChannels > 0 } }

    // MARK: show guard

    func startGuard() {
        guard isConnected else { return }
        stopJob()
        let g = ShowGuard(strips: strips, buses: buses, character: character)
        g.references = references
        guardian = g
        guardStart = Date()
        guarding = true
        hallDetector.reset()
        stageDetector.reset()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.guardStep() }
        }
    }

    func stopGuard() {
        guard let g = guardian else { return }
        let (s, b) = g.releaseAll()
        apply(s)
        apply(buses: b)
        guardian = nil
        guarding = false
        timer?.invalidate()
        timer = nil
    }

    func setMonitor(_ bus: Int, _ on: Bool) {
        if on { guardian?.monitorBuses.insert(bus) } else { guardian?.monitorBuses.remove(bus) }
        objectWillChange.send()
    }

    func setLead(_ ch: Int, _ on: Bool) {
        if on { guardian?.leads.insert(ch) } else { guardian?.leads.remove(ch) }
        objectWillChange.send()
    }

    /// Runs guard steps immediately (simulator demo, tests).
    func runGuardNow(steps: Int) {
        timer?.invalidate()
        timer = nil
        for _ in 0..<steps { guardStep() }
    }

    private var guardTime: Double = 0

    private func guardStep() {
        guard let g = guardian else { return }
        let t = sim != nil ? guardTime : Date().timeIntervalSince(guardStart)
        guardTime += 1
        // Spectra visit the channels that are playing, loudest first, one per second.
        let playing = stripMap.values.filter { !$0.muted && $0.faderDB > -60 }.map(\.id).sorted()
        if !playing.isEmpty, let link {
            let ch = playing[rtaCursor % playing.count]
            rtaCursor += 1
            meters.rtaChannel = ch
            link.send(ConsoleMeters.rtaFollow(channel: ch, family: family))
        }
        let (feats, mic, stage) = window(channels: sim != nil ? playing : Array(stripMap.keys), seconds: 1)
        if let sim {
            busLevels = sim.busLevels(channelRMS: feats.filter { $0.value.hasSignal }.mapValues(\.rmsDB))
        }
        let hall = mic.map { hallDetector.process($0) } ?? []
        let onStage = stage.map { stageDetector.process($0) } ?? []
        let r = g.step(time: t, channels: feats, busLevels: busLevels, hallFeedback: hall, stageFeedback: onStage)
        apply(r.strips)
        apply(buses: r.buses)
        features.merge(feats) { $1 }
        guardLog = Array(g.log.suffix(200))
    }
}
