import Foundation
import Network
import SSMTAudio
import SSMTCore
import SwiftUI

/// UDP link to a Behringer X32 / Midas M32 or X Air console (the same OSC dialect remote apps use).
/// Reads channel names and strips, keeps the subscription alive, and sends the assistant's changes.
final class X32Link: @unchecked Sendable {
    let family: MixerFamily
    let host: String
    private let queue = DispatchQueue(label: "ssmt.assist.x32")
    private var connection: NWConnection?
    private var keepAlive: DispatchSourceTimer?
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
        send([X32Codec.info, X32Codec.subscribe(family: family)])
        // The console forgets a remote after 10 s without /xremote.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 8, repeating: 8)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.send([X32Codec.subscribe(family: self.family)])
        }
        t.resume()
        keepAlive = t
    }

    /// Asks for the whole strip of every channel (spaced out so the console does not drop requests).
    func queryAll(channels: Int) {
        var delay = 0.0
        for ch in 1...channels {
            let msgs = X32Codec.queryAddresses(ch, family: family).map { OSCMessage($0) }
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

/// Function #4: FOH Assist. Connects to the console, listens to its channels through the audio interface,
/// and tunes gain, filters, EQ, dynamics and group levels by itself.
@MainActor
final class AssistStore: ObservableObject {
    enum Connection: Equatable {
        case disconnected
        case connecting
        case connected(String)
        case failed(String)
    }

    @Published var family: MixerFamily = .simulator
    @Published var host = UserDefaults.standard.string(forKey: "assist.host") ?? "192.168.1.64" {
        didSet { UserDefaults.standard.set(host, forKey: "assist.host") }
    }
    @Published private(set) var connection: Connection = .disconnected
    @Published private(set) var strips: [ChannelStrip] = []
    @Published var character: MixCharacter = .musical { didSet { session?.character = character } }
    @Published var tap: TapPoint = .preEQ { didSet { session?.tap = tap } }
    /// Interface carrying the console channels and the measurement mic.
    @Published var inputDeviceUID: String?
    /// Interface input that carries console channel 1 (the others follow in order).
    @Published var firstInput = 1
    /// Interface input of the measurement microphone (0 = none).
    @Published var micInput = 0
    @Published var rangeFrom = 1
    @Published var rangeTo = 8
    @Published private(set) var log: [AssistSession.LogEntry] = []
    @Published private(set) var features: [Int: SignalFeatures] = [:]
    @Published private(set) var job: AssistSession.Job = .none
    @Published private(set) var running = false
    @Published private(set) var groupPhase: GroupPhase?
    @Published var message: String?

    private var session: AssistSession?
    private var sim: SimulatedConsole?
    private var link: X32Link?
    private var capture: AssistCapture?
    private var timer: Timer?
    private var stripMap: [Int: ChannelStrip] = [:]

    var isConnected: Bool { if case .connected = connection { return true } else { return false } }

    // MARK: connection

    func connect() {
        disconnect()
        switch family {
        case .simulator:
            let c = SimulatedConsole.demo()
            sim = c
            setStrips(c.strips)
            connection = .connected("SSMT simulator · \(c.strips.count) ch")
        case .x32, .xAir:
            connection = .connecting
            let blank = Dictionary(uniqueKeysWithValues: (1...family.channelCount).map { ($0, ChannelStrip(id: $0)) })
            setStrips(blank)
            let l = X32Link(family: family, host: host)
            l.onMessage = { [weak self] m in Task { @MainActor in self?.received(m) } }
            link = l
            l.start()
            l.queryAll(channels: family.channelCount)
            // No answer to /info within 3 s: wrong address or another network.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.connection == .connecting else { return }
                self.connection = .failed("no answer from \(self.host):\(self.family.defaultPort)")
            }
            startCapture()
        case .wing, .yamaha, .allenHeath:
            connection = .failed("not supported yet")
        }
        session = AssistSession(strips: strips, character: character, tap: tap)
    }

    func disconnect() {
        stopJob()
        link?.stop()
        link = nil
        capture?.stop()
        capture = nil
        sim = nil
        session = nil
        connection = .disconnected
    }

    private func startCapture() {
        do { capture = try AssistCapture(deviceUID: inputDeviceUID) } catch { message = "\(error)" }
    }

    func restartCapture() {
        guard family != .simulator, isConnected || connection == .connecting else { return }
        capture?.stop()
        startCapture()
    }

    private func received(_ m: OSCMessage) {
        if m.address == "/info" {
            let parts = m.arguments.compactMap { if case let .string(s) = $0 { return s } else { return nil } }
            connection = .connected(parts.dropFirst().joined(separator: " · "))
            return
        }
        if X32Codec.apply(m, to: &stripMap, family: family) != nil {
            if connection == .connecting { connection = .connected(host) }
            strips = stripMap.values.sorted { $0.id < $1.id }
            for s in strips { session?.updateFromConsole(s) }
        }
    }

    private func setStrips(_ map: [Int: ChannelStrip]) {
        stripMap = map
        strips = map.values.sorted { $0.id < $1.id }
    }

    // MARK: jobs

    func tune(channel: Int) {
        guard let session else { return }
        session.startChannel(channel)
        begin()
    }

    func tune(_ selection: AssistGroupSelection) {
        guard let session else { return }
        let members = session.startGroup(selection)
        if members.isEmpty {
            message = "nothing found"
            return
        }
        begin()
    }

    private func begin() {
        message = nil
        job = session?.job ?? .none
        running = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
    }

    func stopJob() {
        timer?.invalidate()
        timer = nil
        session?.stop()
        running = false
        job = .none
        groupPhase = nil
    }

    func undoAll() {
        guard let session else { return }
        let back = session.undo()
        apply(back)
        stopJob()
    }

    /// Runs steps immediately instead of every 2 s (demo in the simulator, snapshot tests).
    func runNow(steps: Int) {
        timer?.invalidate()
        timer = nil
        for _ in 0..<steps { step() }
    }

    private func step() {
        guard let session, session.isRunning else {
            if running { running = false; timer?.invalidate(); timer = nil }
            return
        }
        let chans = session.listening
        var taps: [Int: [Float]] = [:]
        var mic: [Float]?
        if let sim {
            let r = sim.render(seconds: 2, channels: chans, tap: tap)
            taps = r.taps
            mic = r.mic
        } else if let capture {
            for ch in chans { taps[ch] = capture.latest(input: firstInput + ch - 1) }
            if micInput > 0 { mic = capture.latest(input: micInput) }
        }
        let changed = session.tick(taps: taps, mic: mic)
        apply(changed)
        log = Array(session.log.suffix(200))
        features = session.features
        groupPhase = session.group?.phase
        if !session.isRunning { running = false; timer?.invalidate(); timer = nil }
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
        let name = stripMap[ch]?.name ?? ""
        return SourceClassifier.classify(name: name, features: features[ch]).kind
    }

    var inputDevices: [AudioDeviceInfo] { DeviceCatalog.allDevices().filter { $0.inputChannels > 0 } }
}
