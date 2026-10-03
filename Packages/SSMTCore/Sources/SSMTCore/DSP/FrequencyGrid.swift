import Foundation

/// Log-spaced frequency grid with a fixed number of points per octave, anchored at 1 kHz.
public struct FrequencyGrid: Equatable, Codable, Sendable {
    public let pointsPerOctave: Int
    public let frequencies: [Double]

    public init(pointsPerOctave: Int = 24, minFrequency: Double = 20, maxFrequency: Double = 20000) {
        precondition(pointsPerOctave > 0 && minFrequency > 0 && maxFrequency > minFrequency)
        self.pointsPerOctave = pointsPerOctave
        let ppo = Double(pointsPerOctave)
        let kMin = Int((ppo * log2(minFrequency / 1000)).rounded(.up))
        let kMax = Int((ppo * log2(maxFrequency / 1000)).rounded(.down))
        frequencies = (kMin...kMax).map { 1000 * pow(2, Double($0) / ppo) }
    }

    public var count: Int { frequencies.count }

    /// Lower and upper band edges of point i (±1/(2·ppo) octave).
    public func bandEdges(_ i: Int) -> (lower: Double, upper: Double) {
        let f = frequencies[i]
        let h = pow(2, 0.5 / Double(pointsPerOctave))
        return (f / h, f * h)
    }

    /// Index of the grid point closest (in log frequency) to f.
    public func nearestIndex(to f: Double) -> Int {
        guard f > 0 else { return 0 }
        let k = Double(pointsPerOctave) * log2(f / frequencies[0])
        return min(max(Int(k.rounded()), 0), count - 1)
    }

    /// Indices whose frequency lies within [low, high].
    public func indices(from low: Double, to high: Double) -> [Int] {
        frequencies.indices.filter { frequencies[$0] >= low && frequencies[$0] <= high }
    }
}
