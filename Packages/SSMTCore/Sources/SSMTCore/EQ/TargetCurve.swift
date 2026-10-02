import Foundation

public struct TargetPoint: Equatable, Codable, Sendable {
    public var frequency: Double
    public var gainDB: Double
    public init(_ frequency: Double, _ gainDB: Double) {
        self.frequency = frequency
        self.gainDB = gainDB
    }
}

/// Editable target curve: points interpolated linearly in log frequency, flat beyond the ends.
/// The presets are starting points (spec 7), not dogma — all values are in ASSUMPTIONS.md (A14).
public struct TargetCurve: Equatable, Codable, Sendable, Identifiable {
    public enum Preset: String, Codable, Sendable, CaseIterable {
        case flat, livePA, speech, club, custom
    }

    public var id: String { preset.rawValue + name }
    public var preset: Preset
    public var name: String
    public var points: [TargetPoint]

    public init(preset: Preset, name: String, points: [TargetPoint]) {
        self.preset = preset
        self.name = name
        self.points = points.sorted { $0.frequency < $1.frequency }
    }

    public static func preset(_ p: Preset) -> TargetCurve {
        switch p {
        case .flat, .custom:
            return TargetCurve(preset: p, name: p.rawValue, points: [TargetPoint(20, 0), TargetPoint(20000, 0)])
        case .livePA:
            return TargetCurve(preset: p, name: p.rawValue, points: [
                TargetPoint(20, 3), TargetPoint(60, 3), TargetPoint(150, 0), TargetPoint(1000, 0),
                TargetPoint(2000, -1), TargetPoint(4000, -2), TargetPoint(8000, -3), TargetPoint(16000, -4),
                TargetPoint(20000, -4.3)])
        case .speech:
            return TargetCurve(preset: p, name: p.rawValue, points: [
                TargetPoint(30, -12), TargetPoint(60, -6), TargetPoint(120, 0), TargetPoint(2000, 0),
                TargetPoint(3000, 1.5), TargetPoint(4000, 1.5), TargetPoint(6000, 0), TargetPoint(12000, -1),
                TargetPoint(20000, -1.7)])
        case .club:
            return TargetCurve(preset: p, name: p.rawValue, points: [
                TargetPoint(20, 6), TargetPoint(60, 6), TargetPoint(120, 0), TargetPoint(1000, 0),
                TargetPoint(2000, -1.5), TargetPoint(4000, -3), TargetPoint(8000, -4.5), TargetPoint(16000, -6),
                TargetPoint(20000, -6.5)])
        }
    }

    public func value(at f: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if f <= first.frequency { return first.gainDB }
        if f >= last.frequency { return last.gainDB }
        for i in 1..<points.count where f <= points[i].frequency {
            let a = points[i - 1], b = points[i]
            let t = log(f / a.frequency) / log(b.frequency / a.frequency)
            return a.gainDB + t * (b.gainDB - a.gainDB)
        }
        return last.gainDB
    }
}
