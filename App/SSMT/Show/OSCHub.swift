import Darwin
import Foundation
import Network
import SSMTCore

/// UDP side of OSC: one connection per device address. Thread-safe; `send` may be called from
/// the playback queue.
final class OSCTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ssmt.osc")
    private var connections: [String: NWConnection] = [:]
    /// Messages received on a device connection (answers such as X32 `/info`).
    var onReply: ((String, OSCMessage) -> Void)?

    func send(_ message: OSCMessage, to device: OSCDevice) {
        let data = message.encoded()
        queue.async {
            let c = self.connection(host: device.host, port: device.port)
            c.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func connection(host: String, port: UInt16) -> NWConnection {
        let key = "\(host):\(port)"
        if let c = connections[key], c.state != .cancelled { return c }
        let c = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 8000, using: .udp)
        c.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.queue.async { self?.connections[key] = nil } }
        }
        c.start(queue: queue)
        receive(on: c, from: host)
        connections[key] = c
        return c
    }

    private func receive(on c: NWConnection, from host: String) {
        c.receiveMessage { [weak self] data, _, _, error in
            if let data, let msgs = OSCMessage.decode(data) { msgs.forEach { self?.onReply?(host, $0) } }
            if error == nil { self?.receive(on: c, from: host) }
        }
    }

    func reset() {
        queue.async {
            self.connections.values.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }
}

/// One received OSC message (monitor and connection tests).
struct OSCLogEntry: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let from: String
    let message: OSCMessage
}

/// OSC for the UI: sending, the incoming monitor, connection tests and network hints.
@MainActor
final class OSCHub: ObservableObject {
    let transport = OSCTransport()
    @Published private(set) var log: [OSCLogEntry] = []
    @Published private(set) var listening: UInt16?
    @Published private(set) var listenError: String?
    private var listener: NWListener?
    private var waiters: [(String, (OSCMessage) -> Bool, CheckedContinuation<Bool, Never>)] = []

    init() {
        transport.onReply = { [weak self] host, msg in
            Task { @MainActor in self?.received(msg, from: host) }
        }
    }

    func send(_ message: OSCMessage, to device: OSCDevice) { transport.send(message, to: device) }

    // MARK: Listening (monitor, Eos answers)

    func listen(on port: UInt16) {
        stopListening()
        do {
            let l = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: port) ?? 53535)
            l.newConnectionHandler = { [weak self] c in
                c.start(queue: .global(qos: .utility))
                self?.receive(c)
            }
            l.stateUpdateHandler = { [weak self] state in
                if case let .failed(e) = state {
                    Task { @MainActor in self?.listenError = "\(e)"; self?.listening = nil }
                }
            }
            l.start(queue: .global(qos: .utility))
            listener = l
            listening = port
            listenError = nil
        } catch {
            listenError = "\(error)"
            listening = nil
        }
    }

    func stopListening() {
        listener?.cancel()
        listener = nil
        listening = nil
    }

    nonisolated private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            var host = "?"
            if case let .hostPort(h, _) = c.endpoint { host = "\(h)".components(separatedBy: "%").first ?? "\(h)" }
            if let data, let msgs = OSCMessage.decode(data) {
                Task { @MainActor in msgs.forEach { self?.received($0, from: host) } }
            }
            if error == nil { self?.receive(c) }
        }
    }

    private func received(_ m: OSCMessage, from host: String) {
        log.append(OSCLogEntry(time: Date(), from: host, message: m))
        if log.count > 300 { log.removeFirst(log.count - 300) }
        for (i, w) in waiters.enumerated().reversed() where w.1(m) {
            w.2.resume(returning: true)
            waiters.remove(at: i)
        }
    }

    func clearLog() { log.removeAll() }

    // MARK: Connection test

    enum TestResult: Equatable { case answered, noAnswer, cannotTell }

    /// Sends the device's probe and waits up to 2 s for its answer.
    func test(_ device: OSCDevice) async -> TestResult {
        guard let probe = device.kind.probe else { return .cannotTell }
        if let reply = device.kind.replyPort, listening != reply { listen(on: reply) }
        let match: (OSCMessage) -> Bool
        switch device.kind {
        case .eos: match = { $0.address.hasPrefix("/eos/out/ping") }
        case .x32: match = { $0.address.hasPrefix("/info") }
        default: match = { _ in true }
        }
        send(probe, to: device)
        let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let key = UUID().uuidString
            waiters.append((key, match, cont))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, let i = self.waiters.firstIndex(where: { $0.0 == key }) else { return }
                self.waiters[i].2.resume(returning: false)
                self.waiters.remove(at: i)
            }
        }
        return ok ? .answered : .noAnswer
    }

    // MARK: This Mac's network

    struct Interface: Hashable { let name: String; let address: String; let mask: String }

    /// IPv4 addresses of this Mac (without loopback).
    static func interfaces() -> [Interface] {
        var out: [Interface] = []
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let first = ptr else { return [] }
        defer { freeifaddrs(ptr) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            defer { p = i.pointee.ifa_next }
            guard let a = i.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET), let m = i.pointee.ifa_netmask else { continue }
            let name = String(cString: i.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            func text(_ sa: UnsafeMutablePointer<sockaddr>) -> String {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                return String(cString: host)
            }
            out.append(Interface(name: name, address: text(a), mask: text(m)))
        }
        return out
    }
}
