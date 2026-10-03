import Foundation
import Network
import SSMTCore

/// The console test's own UDP connection to a real X32 / M32 / X Air: sends, queries and waits for replies.
final class UDPConsoleTransport: ConsoleTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ssmt.assist.consoletest")
    private let connection: NWConnection
    private var inbox: [OSCMessage] = []
    private let lock = NSLock()

    init(host: String, port: UInt16) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 10023, using: .udp)
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data, let msgs = OSCMessage.decode(data), let self {
                self.lock.lock()
                self.inbox += msgs
                if self.inbox.count > 5000 { self.inbox.removeFirst(self.inbox.count - 5000) }
                self.lock.unlock()
            }
            if error == nil { self?.receive() }
        }
    }

    func send(_ messages: [OSCMessage]) {
        for m in messages { connection.send(content: m.encoded(), completion: .contentProcessed { _ in }) }
    }

    private func take(_ match: (OSCMessage) -> Bool) -> [OSCMessage] {
        lock.lock()
        defer { lock.unlock() }
        let hit = inbox.filter(match)
        inbox.removeAll(where: match)
        return hit
    }

    func query(_ addresses: [String], timeout: Double) async -> [OSCMessage] {
        let wanted = Set(addresses)
        _ = take { wanted.contains($0.address) }
        // Spaced out a little: the console answers every request, but drops bursts.
        for (i, a) in addresses.enumerated() {
            send([OSCMessage(a)])
            if i % 20 == 19 { try? await Task.sleep(nanoseconds: 10_000_000) }
        }
        var got: [OSCMessage] = []
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            got += take { wanted.contains($0.address) }
            if Set(got.map(\.address)).count >= wanted.count { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return got
    }

    func waitFor(prefix: String, timeout: Double) async -> OSCMessage? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if let m = take({ $0.address.hasPrefix(prefix) }).first { return m }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    func close() { connection.cancel() }
}
