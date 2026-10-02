import Foundation

extension Cue {
    /// Deep copy with fresh identifiers (targets inside the copy are remapped to the copies).
    public func duplicated() -> Cue {
        var map: [UUID: UUID] = [:]
        func assign(_ c: Cue) {
            map[c.id] = UUID()
            c.children.forEach(assign)
        }
        assign(self)
        func copy(_ c: Cue) -> Cue {
            var n = c
            n.id = map[c.id]!
            if let t = c.target, let m = map[t] { n.target = m }
            n.children = c.children.map(copy)
            return n
        }
        return copy(self)
    }

    /// Audio cue for a file, named after it.
    public static func audio(file: String, number: String = "") -> Cue {
        var c = Cue(kind: .audio, number: number)
        c.audio = AudioCueParams(file: file)
        let base = (file as NSString).lastPathComponent
        c.name = (base as NSString).deletingPathExtension
        return c
    }

    /// Every cue id in this subtree.
    public var subtreeIDs: Set<UUID> {
        var s: Set<UUID> = [id]
        for c in children { s.formUnion(c.subtreeIDs) }
        return s
    }
}

extension ShowDocument {
    private func listIndex(_ id: UUID) -> Int? { lists.firstIndex { $0.id == id } }

    /// Inserts cues after `after` (as its siblings) or at the end of the list. Returns their ids.
    @discardableResult
    public mutating func insert(_ new: [Cue], after: UUID?, list: UUID) -> [UUID] {
        guard let li = listIndex(list), !new.isEmpty else { return [] }
        if let after, let path = lists[li].cues.path(of: after) {
            Self.insert(new, into: &lists[li].cues, path: path)
        } else {
            lists[li].cues += new
        }
        return new.map(\.id)
    }

    private static func insert(_ new: [Cue], into cues: inout [Cue], path: [Int]) {
        if path.count == 1 {
            cues.insert(contentsOf: new, at: min(cues.count, path[0] + 1))
        } else {
            insert(new, into: &cues[path[0]].children, path: Array(path.dropFirst()))
        }
    }

    /// Appends cues inside a group.
    public mutating func append(_ new: [Cue], toGroup group: UUID) {
        updateCue(group) { $0.children += new }
    }

    /// Deletes cues (with their children) and clears targets that pointed at them.
    public mutating func delete(_ ids: Set<UUID>) {
        var gone = Set<UUID>()
        for li in lists.indices {
            gone.formUnion(lists[li].cues.removeCues(ids).reduce(into: Set<UUID>()) { $0.formUnion($1.subtreeIDs) })
        }
        guard !gone.isEmpty else { return }
        for li in lists.indices { Self.clearTargets(&lists[li].cues, gone) }
    }

    private static func clearTargets(_ cues: inout [Cue], _ gone: Set<UUID>) {
        for i in cues.indices {
            if let t = cues[i].target, gone.contains(t) { cues[i].target = nil }
            if let t = cues[i].newTarget, gone.contains(t) { cues[i].newTarget = nil }
            clearTargets(&cues[i].children, gone)
        }
    }

    /// Duplicates cues, each copy right after its original. Returns the copies' ids.
    @discardableResult
    public mutating func duplicate(_ ids: [UUID], list: UUID) -> [UUID] {
        var out: [UUID] = []
        for id in ids {
            guard let c = cue(id) else { continue }
            let copy = c.duplicated()
            insert([copy], after: id, list: list)
            out.append(copy.id)
        }
        return out
    }

    /// Wraps sibling cues into a new group placed where the first of them was. Returns the group id.
    @discardableResult
    public mutating func group(_ ids: [UUID], list: UUID, mode: GroupMode = .simultaneous, name: String = "") -> UUID? {
        guard let li = listIndex(list), !ids.isEmpty else { return nil }
        // Keep the show order of the selection.
        let order = lists[li].cues.flattened().map(\.cue.id)
        let sorted = ids.sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
        guard let firstPath = lists[li].cues.path(of: sorted[0]) else { return nil }
        var g = Cue(kind: .group, name: name)
        g.groupMode = mode
        let removed = lists[li].cues.removeCues(Set(sorted))
        g.children = sorted.compactMap { id in removed.first { $0.id == id } }
        Self.insertAt(g, into: &lists[li].cues, path: firstPath)
        return g.id
    }

    private static func insertAt(_ c: Cue, into cues: inout [Cue], path: [Int]) {
        if path.count == 1 {
            cues.insert(c, at: min(cues.count, path[0]))
        } else if path[0] < cues.count {
            insertAt(c, into: &cues[path[0]].children, path: Array(path.dropFirst()))
        } else {
            cues.append(c)
        }
    }

    /// Replaces a group by its children.
    public mutating func ungroup(_ id: UUID, list: UUID) {
        guard let li = listIndex(list), let g = cue(id), g.kind == .group, let path = lists[li].cues.path(of: id) else { return }
        lists[li].cues.removeCues([id])
        for (k, child) in g.children.enumerated() {
            var p = path
            p[p.count - 1] += k
            Self.insertAt(child, into: &lists[li].cues, path: p)
        }
    }

    /// Moves a cue one place up or down among its siblings.
    public mutating func move(_ id: UUID, by delta: Int, list: UUID) {
        guard let li = listIndex(list), let path = lists[li].cues.path(of: id) else { return }
        Self.moveSibling(&lists[li].cues, path: path, delta: delta)
    }

    private static func moveSibling(_ cues: inout [Cue], path: [Int], delta: Int) {
        if path.count == 1 {
            let i = path[0], j = i + delta
            guard cues.indices.contains(i), cues.indices.contains(j) else { return }
            cues.swapAt(i, j)
        } else {
            moveSibling(&cues[path[0]].children, path: Array(path.dropFirst()), delta: delta)
        }
    }

    /// Moves cues (from anywhere) to a position: before `before`, or at the end of the list / group.
    public mutating func move(_ ids: [UUID], before: UUID?, intoGroup: UUID? = nil, list: UUID) {
        guard let li = listIndex(list) else { return }
        // Never move a group into itself.
        if let target = intoGroup ?? before, ids.contains(where: { cue($0)?.subtreeIDs.contains(target) == true }) { return }
        let order = lists[li].cues.flattened().map(\.cue.id)
        let sorted = ids.sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
        let removed = lists[li].cues.removeCues(Set(sorted))
        let moving = sorted.compactMap { id in removed.first { $0.id == id } }
        if let before, let path = lists[li].cues.path(of: before) {
            for (k, c) in moving.enumerated() {
                var p = path
                p[p.count - 1] += k
                Self.insertAt(c, into: &lists[li].cues, path: p)
            }
        } else if let intoGroup {
            updateCue(intoGroup) { $0.children += moving }
        } else {
            lists[li].cues += moving
        }
    }

    /// Numbers cues in show order: start, start + step… (only the given ids, or every non-group cue).
    public mutating func renumber(_ ids: [UUID]? = nil, list: UUID, start: Double = 1, step: Double = 1) {
        guard let li = listIndex(list) else { return }
        let all = lists[li].cues.flattened().map(\.cue)
        let targets = ids.map(Set.init) ?? Set(all.filter { $0.kind != .group }.map(\.id))
        var n = start
        for c in all where targets.contains(c.id) {
            let text = n.rounded() == n ? String(Int(n)) : String(format: "%g", n)
            updateCue(c.id) { $0.number = text }
            n += step
        }
    }

    /// Valid targets for a cue kind (cues of the right type anywhere in the show).
    public func targetCandidates(for kind: CueKind, excluding id: UUID) -> [Cue] {
        allCues.filter { c in
            guard c.id != id else { return false }
            switch kind {
            case .fade: return c.kind == .audio || c.kind == .group
            case .devamp: return c.kind == .audio
            case .load: return c.kind == .audio || c.kind == .group
            case .goTo: return lists.contains { l in l.cues.contains { $0.id == c.id } }
            default: return true
            }
        }
    }
}

/// Problems found before a show.
public enum ShowIssue: Equatable, Sendable {
    case missingTarget(UUID)
    case missingFile(UUID)
    case duplicateNumber(String)
    case duplicateHotkey(String)
    case emptyGroup(UUID)
    case invalidRegion(UUID)
}

extension ShowDocument {
    /// Pre-show check. `fileExists` resolves an audio cue's file.
    public func issues(fileExists: (Cue) -> Bool) -> [ShowIssue] {
        var out: [ShowIssue] = []
        var numbers: [String: Int] = [:]
        var keys: [String: Int] = [:]
        for c in allCues {
            if c.kind.needsTarget && c.target == nil { out.append(.missingTarget(c.id)) }
            if let t = c.target, cue(t) == nil { out.append(.missingTarget(c.id)) }
            if c.kind == .audio {
                if c.audio?.file.isEmpty != false || !fileExists(c) { out.append(.missingFile(c.id)) }
                if let a = c.audio, let e = a.end, e <= a.start { out.append(.invalidRegion(c.id)) }
            }
            if c.kind == .group && c.children.isEmpty { out.append(.emptyGroup(c.id)) }
            if !c.number.isEmpty { numbers[c.number, default: 0] += 1 }
            if let k = c.hotkey, !k.isEmpty { keys[k.lowercased(), default: 0] += 1 }
        }
        out += numbers.filter { $0.value > 1 }.keys.sorted().map { .duplicateNumber($0) }
        out += keys.filter { $0.value > 1 }.keys.sorted().map { .duplicateHotkey($0) }
        return out
    }
}
