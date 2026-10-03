import Foundation

/// Kinds of stage items drawn as simple vector symbols.
public enum StageItemKind: String, Codable, Sendable, CaseIterable {
    case drumKit, percussion, guitarAmp, bassAmp, keyboard, piano, vocalMic, micStand, diBox
    case wedge, iem, sideFill, speaker, riser, person, chair, musicStand, powerDrop, text

    /// Default footprint on stage (metres, width × depth).
    public var defaultSize: (w: Double, d: Double) {
        switch self {
        case .drumKit: return (2.0, 1.8)
        case .percussion: return (1.4, 1.0)
        case .guitarAmp: return (0.7, 0.35)
        case .bassAmp: return (0.8, 0.5)
        case .keyboard: return (1.4, 0.45)
        case .piano: return (1.5, 1.9)
        case .vocalMic, .micStand: return (0.4, 0.4)
        case .diBox: return (0.25, 0.2)
        case .wedge: return (0.7, 0.5)
        case .iem: return (0.4, 0.3)
        case .sideFill: return (0.8, 0.7)
        case .speaker: return (0.7, 0.6)
        case .riser: return (2.4, 2.0)
        case .person: return (0.6, 0.6)
        case .chair: return (0.5, 0.5)
        case .musicStand: return (0.5, 0.3)
        case .powerDrop: return (0.3, 0.3)
        case .text: return (1.6, 0.4)
        }
    }
}

public struct StageItem: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: StageItemKind
    /// Centre on stage in metres: x from the left edge as seen from the audience (house left), y from the front edge.
    public var x: Double
    public var y: Double
    /// Size in metres.
    public var width: Double
    public var depth: Double
    /// Rotation in degrees, clockwise.
    public var rotation: Double = 0
    /// Caption (performer, instrument) or the text itself for `.text`.
    public var label: String = ""
    /// Channels / mixes it uses ("1–10", "Mix 3"), printed under the symbol.
    public var info: String = ""
    /// Text size in points for `.text`.
    public var fontSize: Double = 14

    public init(kind: StageItemKind, x: Double, y: Double, label: String = "") {
        self.kind = kind
        self.x = x
        self.y = y
        let s = kind.defaultSize
        width = s.w
        depth = s.d
        self.label = label
    }
}

/// Stage plan: a rectangle (audience at the front) with items on it.
public struct StagePlan: Codable, Equatable, Sendable {
    /// Stage size in metres.
    public var width: Double = 10
    public var depth: Double = 6
    /// Items in drawing order (last on top).
    public var items: [StageItem] = []
    /// Grid step for snapping (m); 0 = free.
    public var grid: Double = 0.25

    public init() {}

    @discardableResult
    public mutating func add(_ kind: StageItemKind, at point: (x: Double, y: Double)? = nil, label: String = "") -> StageItem.ID {
        let p = point ?? (width / 2, depth / 2)
        var item = StageItem(kind: kind, x: p.x, y: p.y, label: label)
        if kind == .text && label.isEmpty { item.label = "Text" }
        clamp(&item)
        items.append(item)
        return item.id
    }

    /// Moves an item to a point (snapped to the grid, kept on stage).
    public mutating func move(_ id: StageItem.ID, to point: (x: Double, y: Double)) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].x = snap(point.x)
        items[i].y = snap(point.y)
        clamp(&items[i])
    }

    public mutating func rotate(_ id: StageItem.ID, by degrees: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var r = (items[i].rotation + degrees).truncatingRemainder(dividingBy: 360)
        if r < 0 { r += 360 }
        items[i].rotation = r
    }

    public mutating func remove(_ ids: Set<StageItem.ID>) {
        items.removeAll { ids.contains($0.id) }
    }

    @discardableResult
    public mutating func duplicate(_ id: StageItem.ID) -> StageItem.ID? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = items[i]
        copy.id = UUID()
        copy.x += 0.5
        copy.y += 0.3
        clamp(&copy)
        items.append(copy)
        return copy.id
    }

    public mutating func bringToFront(_ id: StageItem.ID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items.append(items.remove(at: i))
    }

    public mutating func sendToBack(_ id: StageItem.ID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items.insert(items.remove(at: i), at: 0)
    }

    /// Keeps all items on stage after the stage was resized.
    public mutating func clampAll() {
        for i in items.indices { clamp(&items[i]) }
    }

    func snap(_ v: Double) -> Double {
        grid > 0 ? (v / grid).rounded() * grid : v
    }

    func clamp(_ item: inout StageItem) {
        item.x = min(max(item.x, 0), width)
        item.y = min(max(item.y, 0), depth)
    }
}
