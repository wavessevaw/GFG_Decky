import Foundation
import Network
import SSMTCore

/// Talks to a running QLab over its OSC interface (TCP port 53000, SLIP-framed OSC) and reads
/// a workspace's cue lists for import.
final class QLabClient: @unchecked Sendable {
    struct Workspace: Identifiable, Hashable { let id: String; let name: String }

    enum ClientError: LocalizedError {
        case connect(String), timeout, refused(String)
        var errorDescription: String? {
            switch self {
            case let .connect(s): return s
            case .timeout: return "QLab did not answer"
            case let .refused(s): return s
            }
        }
    }

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ssmt.qlab")
    private var buffer = Data()
    private var waiting: [String: CheckedContinuation<String, Error>] = [:]

    init(host: String, port: UInt16 = 53000) {
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 53000, using: .tcp)
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready: resumed = true; cont.resume()
                case let .failed(e): resumed = true; cont.resume(throwing: ClientError.connect(e.localizedDescription))
                case let .waiting(e): resumed = true; cont.resume(throwing: ClientError.connect(e.localizedDescription))
                default: break
                }
            }
            connection.start(queue: queue)
        }
        receive()
    }

    func close() { connection.cancel() }

    // MARK: Requests

    func workspaces() async throws -> [Workspace] {
        let data = try await request(OSCMessage("/workspaces"))
        return (data as? [[String: Any]] ?? []).compactMap { d in
            guard let id = d["uniqueID"] as? String else { return nil }
            return Workspace(id: id, name: d["displayName"] as? String ?? id)
        }
    }

    /// Reads every cue list with every cue's properties. `progress(done, total)` is called as cues are read.
    func readWorkspace(_ ws: Workspace, passcode: String, progress: @escaping (Int, Int) -> Void) async throws -> [QLabImport.Item] {
        let base = "/workspace/\(ws.id)"
        _ = try? await request(OSCMessage(base + "/connect", passcode.isEmpty ? [] : [.string(passcode)]))
        guard let raw = try await request(OSCMessage(base + "/cueLists")) as? [[String: Any]] else {
            throw ClientError.refused("cueLists")
        }
        var lists = raw.map(QLabImport.item(fromJSON:))
        let total = lists.reduce(0) { $0 + Self.count($1.children) }
        var done = 0
        let keys = String(data: try JSONSerialization.data(withJSONObject: QLabImport.valueKeys), encoding: .utf8) ?? "[]"
        func fill(_ q: inout QLabImport.Item) async {
            if let v = try? await request(OSCMessage(base + "/cue_id/\(q.uniqueID)/valuesForKeys", [.string(keys)])) as? [String: Any] {
                QLabImport.merge(values: v, into: &q)
            }
            done += 1
            progress(done, total)
            for i in q.children.indices { await fill(&q.children[i]) }
        }
        for l in lists.indices {
            for i in lists[l].children.indices { await fill(&lists[l].children[i]) }
        }
        return lists
    }

    private static func count(_ items: [QLabImport.Item]) -> Int { items.reduce(0) { $0 + 1 + count($1.children) } }

    /// Sends a message and waits for QLab's `/reply…` with the same address; returns its `data`.
    private func request(_ m: OSCMessage, timeout: Double = 6) async throws -> Any? {
        let replyAddress = "/reply" + m.address
        let json: String = try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.waiting[replyAddress]?.resume(throwing: ClientError.timeout)
                self.waiting[replyAddress] = cont
                self.connection.send(content: Self.slip(m.encoded()), completion: .contentProcessed { _ in })
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if let c = self.waiting.removeValue(forKey: replyAddress) { c.resume(throwing: ClientError.timeout) }
                }
            }
        }
        guard let d = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        if let status = obj["status"] as? String, status != "ok" { throw ClientError.refused(status) }
        return obj["data"]
    }

    // MARK: SLIP framing

    private static let end: UInt8 = 0xC0, esc: UInt8 = 0xDB, escEnd: UInt8 = 0xDC, escEsc: UInt8 = 0xDD

    static func slip(_ d: Data) -> Data {
        var out = Data([end])
        for b in d {
            switch b {
            case end: out.append(contentsOf: [esc, escEnd])
            case esc: out.append(contentsOf: [esc, escEsc])
            default: out.append(b)
            }
        }
        out.append(end)
        return out
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.consume(data) }
            if error == nil && !complete { self.receive() }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let endIndex = buffer.dropFirst().firstIndex(of: Self.end) {
            let frame = buffer[buffer.startIndex..<endIndex]
            buffer = Data(buffer[endIndex...])
            var packet = Data()
            var escaped = false
            for b in frame where b != Self.end {
                if escaped { packet.append(b == Self.escEnd ? Self.end : (b == Self.escEsc ? Self.esc : b)); escaped = false }
                else if b == Self.esc { escaped = true }
                else { packet.append(b) }
            }
            guard !packet.isEmpty, let msgs = OSCMessage.decode(packet) else { continue }
            for m in msgs {
                guard let c = waiting.removeValue(forKey: m.address) else { continue }
                if case let .string(s)? = m.arguments.first { c.resume(returning: s) } else { c.resume(returning: "{}") }
            }
        }
        if buffer.count == 1 && buffer.first == Self.end { buffer.removeAll() }
    }
}
