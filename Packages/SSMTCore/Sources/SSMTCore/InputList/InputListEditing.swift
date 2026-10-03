import Foundation

// MARK: - Channel editing

extension InputListDocument {
    /// Next free channel number after the highest one in use.
    public var nextChannelNumber: Int { (channels.map(\.number).max() ?? 0) + 1 }

    /// Adds an empty channel after `id` (or at the end) and renumbers what follows. Returns its id.
    @discardableResult
    public mutating func addChannel(after id: InputChannel.ID? = nil, group: ChannelGroup = .other) -> InputChannel.ID {
        let index = id.flatMap { i in channels.firstIndex { $0.id == i } }.map { $0 + 1 } ?? channels.count
        let number = index < channels.count ? channels[index].number : nextChannelNumber
        let ch = InputChannel(number: number, group: group)
        channels.insert(ch, at: index)
        shiftNumbers(from: index + 1, startingAt: number + 1)
        return ch.id
    }

    /// Inserts channels from a template after `id` (or at the end), numbered consecutively.
    @discardableResult
    public mutating func insert(_ template: ChannelTemplate, after id: InputChannel.ID? = nil) -> [InputChannel.ID] {
        let index = id.flatMap { i in channels.firstIndex { $0.id == i } }.map { $0 + 1 } ?? channels.count
        let first = index < channels.count ? channels[index].number : nextChannelNumber
        let new = template.channels.enumerated().map { k, t -> InputChannel in
            var c = t
            c.id = UUID()
            c.number = first + k
            return c
        }
        channels.insert(contentsOf: new, at: index)
        shiftNumbers(from: index + new.count, startingAt: first + new.count)
        return new.map(\.id)
    }

    /// Duplicates channels as a stereo pair: "Keys" → "Keys L" / "Keys R".
    @discardableResult
    public mutating func makeStereo(_ id: InputChannel.ID) -> InputChannel.ID? {
        guard let i = channels.firstIndex(where: { $0.id == id }) else { return nil }
        let base = channels[i].source.isEmpty ? "" : channels[i].source + " "
        channels[i].source = base + "L"
        var right = channels[i]
        right.id = UUID()
        right.source = base + "R"
        right.number = channels[i].number + 1
        right.stagebox = Self.nextStagebox(after: channels[i].stagebox)
        channels.insert(right, at: i + 1)
        shiftNumbers(from: i + 2, startingAt: right.number + 1)
        return right.id
    }

    public mutating func duplicate(_ ids: Set<InputChannel.ID>) {
        for id in channels.filter({ ids.contains($0.id) }).map(\.id).reversed() {
            guard let i = channels.firstIndex(where: { $0.id == id }) else { continue }
            var copy = channels[i]
            copy.id = UUID()
            copy.number = channels[i].number + 1
            channels.insert(copy, at: i + 1)
            shiftNumbers(from: i + 2, startingAt: copy.number + 1)
        }
    }

    public mutating func delete(_ ids: Set<InputChannel.ID>) {
        channels.removeAll { ids.contains($0.id) }
    }

    /// Moves the selected channels one row up or down; numbers follow the rows.
    public mutating func move(_ ids: Set<InputChannel.ID>, by offset: Int) {
        guard offset != 0, !ids.isEmpty else { return }
        let numbers = channels.map(\.number)
        var indices = channels.indices.filter { ids.contains(channels[$0].id) }
        if offset > 0 { indices.reverse() }
        for i in indices {
            let j = i + (offset > 0 ? 1 : -1)
            guard channels.indices.contains(j), !ids.contains(channels[j].id) else { continue }
            channels.swapAt(i, j)
        }
        for k in channels.indices { channels[k].number = numbers[k] }
    }

    /// Moves rows (drag and drop in the table); numbers follow the rows.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let numbers = channels.map(\.number)
        let moving = source.map { channels[$0] }
        let before = source.filter { $0 < destination }.count
        for i in source.sorted(by: >) { channels.remove(at: i) }
        channels.insert(contentsOf: moving, at: destination - before)
        for k in channels.indices { channels[k].number = numbers[k] }
    }

    /// Numbers all channels 1…N in their current order.
    public mutating func renumber(startingAt first: Int = 1) {
        for k in channels.indices { channels[k].number = first + k }
    }

    /// Renumbers rows from `index` on so they continue from `number`, only where that keeps the
    /// order (gaps that the user made on purpose further down are kept).
    private mutating func shiftNumbers(from index: Int, startingAt number: Int) {
        var n = number
        for k in index..<channels.count {
            guard channels[k].number < n else { break }
            channels[k].number = n
            n += 1
        }
    }

    /// "SB1-05" → "SB1-06"; anything without a trailing number stays empty.
    static func nextStagebox(after s: String) -> String {
        guard let r = s.range(of: #"\d+$"#, options: .regularExpression), let n = Int(s[r]) else { return "" }
        let digits = s[r].count
        return s[s.startIndex..<r.lowerBound] + String(format: "%0\(digits)d", n + 1)
    }

    /// Fills empty stage box fields in order: "SB1-01", "SB1-02", … (prefix and start chosen by the user).
    public mutating func assignStagebox(prefix: String, start: Int = 1, onlyEmpty: Bool = true) {
        var n = start
        for k in channels.indices {
            if !onlyEmpty || channels[k].stagebox.isEmpty {
                channels[k].stagebox = prefix + String(format: "%02d", n)
            }
            n += 1
        }
    }
}

// MARK: - Monitor mixes

extension InputListDocument {
    @discardableResult
    public mutating func addMix(type: MixType = .wedge) -> MonitorMix.ID {
        let m = MonitorMix(number: (mixes.map(\.number).max() ?? 0) + 1, type: type)
        mixes.append(m)
        return m.id
    }

    public mutating func deleteMixes(_ ids: Set<MonitorMix.ID>) {
        mixes.removeAll { ids.contains($0.id) }
    }

    public mutating func renumberMixes() {
        for k in mixes.indices { mixes[k].number = k + 1 }
    }
}

// MARK: - Summary and checks

public struct EquipmentSummary: Equatable, Sendable {
    public var channelCount: Int
    /// Microphones / DIs by model, most used first.
    public var models: [(name: String, count: Int)]
    public var stands: [(type: StandType, count: Int)]
    public var phantomCount: Int
    public var mixCount: Int
    public var stereoMixCount: Int

    public static func == (a: EquipmentSummary, b: EquipmentSummary) -> Bool {
        a.channelCount == b.channelCount && a.phantomCount == b.phantomCount && a.mixCount == b.mixCount
            && a.stereoMixCount == b.stereoMixCount
            && a.models.map(\.name) == b.models.map(\.name) && a.models.map(\.count) == b.models.map(\.count)
            && a.stands.map(\.type) == b.stands.map(\.type) && a.stands.map(\.count) == b.stands.map(\.count)
    }
}

public enum InputListIssue: Equatable, Sendable {
    case duplicateNumber(Int)
    case duplicateStagebox(String)
    case emptySource(channel: Int)
}

extension InputListDocument {
    /// Pull list for the stage crew: microphones / DIs by model, stands by type, phantom count.
    public var summary: EquipmentSummary {
        var models: [String: Int] = [:]
        var order: [String] = []
        for c in channels {
            let m = c.mic.trimmingCharacters(in: .whitespaces)
            guard !m.isEmpty else { continue }
            if models[m] == nil { order.append(m) }
            models[m, default: 0] += 1
        }
        let sortedModels = order.map { ($0, models[$0]!) }.sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
        let stands = StandType.allCases.filter { $0 != .none }.compactMap { t -> (StandType, Int)? in
            let n = channels.filter { $0.stand == t }.count
            return n > 0 ? (t, n) : nil
        }
        return EquipmentSummary(channelCount: channels.count, models: sortedModels.map { (name: $0.0, count: $0.1) },
                                stands: stands.map { (type: $0.0, count: $0.1) },
                                phantomCount: channels.filter(\.phantom).count,
                                mixCount: mixes.count, stereoMixCount: mixes.filter(\.stereo).count)
    }

    /// Problems worth fixing before the list goes out.
    public var issues: [InputListIssue] {
        var out: [InputListIssue] = []
        var seen = Set<Int>(), reported = Set<Int>()
        for c in channels {
            if seen.contains(c.number), !reported.contains(c.number) {
                out.append(.duplicateNumber(c.number))
                reported.insert(c.number)
            }
            seen.insert(c.number)
        }
        var boxes = Set<String>(), reportedBoxes = Set<String>()
        for c in channels where !c.stagebox.isEmpty {
            let b = c.stagebox.uppercased()
            if boxes.contains(b), !reportedBoxes.contains(b) {
                out.append(.duplicateStagebox(c.stagebox))
                reportedBoxes.insert(b)
            }
            boxes.insert(b)
        }
        out += channels.filter { $0.source.trimmingCharacters(in: .whitespaces).isEmpty }.map { .emptySource(channel: $0.number) }
        return out
    }
}

// MARK: - CSV

extension InputListDocument {
    /// Channels as CSV (RFC 4180), header in English for spreadsheets and console software.
    public var channelsCSV: String {
        var lines = ["Ch,Source,Mic/DI,Stand,48V,Stagebox,Insert,Group,Notes"]
        for c in channels.sorted(by: { $0.number < $1.number }) {
            lines.append([String(c.number), c.source, c.mic, c.stand.rawValue, c.phantom ? "48V" : "",
                          c.stagebox, c.insert, c.group.rawValue, c.notes].map(Self.csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    public var mixesCSV: String {
        var lines = ["Mix,Name,Type,Stereo,Notes"]
        for m in mixes.sorted(by: { $0.number < $1.number }) {
            lines.append([String(m.number), m.name, m.type.rawValue, m.stereo ? "stereo" : "mono", m.notes]
                .map(Self.csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func csvField(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Rows split into printable pages.
    public func channelPages(rowsPerPage: Int) -> [[InputChannel]] {
        let sorted = channels.sorted { $0.number < $1.number }
        guard rowsPerPage > 0, !sorted.isEmpty else { return [sorted] }
        return stride(from: 0, to: sorted.count, by: rowsPerPage).map { Array(sorted[$0..<min($0 + rowsPerPage, sorted.count)]) }
    }
}
