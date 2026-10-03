import Foundation

/// Live "tuner" while the user enters EQ bands on the processor.
///
/// Before entering anything a reference is captured at the current microphone position. Since
/// the room and the position do not change, |H_live / H_reference| is exactly the EQ that has been
/// entered so far — independent of the room. The needle compares it with the planned filters.
public struct EQTuner: Sendable {
    public let reference: TransferFunction
    public let filters: [PEQFilter]
    public let workingRange: ClosedRange<Double>
    public var sampleRate = 48000.0

    public init(reference: TransferFunction, filters: [PEQFilter], workingRange: ClosedRange<Double>) {
        self.reference = reference
        self.filters = filters
        self.workingRange = workingRange
    }

    public struct BandReading: Equatable, Sendable {
        public var bandIndex: Int
        /// Gain still to add at the band centre (dB): negative = cut more.
        public var remainingGainDB: Double
        /// RMS mismatch of the band's shape (dB) — high with a correct centre gain means wrong Fc or Q.
        public var shapeErrorDB: Double
        public var inTune: Bool { abs(remainingGainDB) <= 0.5 && shapeErrorDB <= 1.0 }
    }

    public struct Reading: Equatable, Sendable {
        public var bands: [BandReading]
        /// RMS difference between entered and planned EQ over the working range (dB).
        public var overallErrorDB: Double
        /// Entered EQ (dB) on the grid, for drawing.
        public var appliedDB: [Double]
        public var plannedDB: [Double]
        public var confidence: Double
        public var allInTune: Bool { overallErrorDB <= 0.75 && bands.allSatisfy(\.inTune) }
    }

    /// Entered EQ curve: 20·log|live/ref|, 1/6-octave smoothed over coherent points.
    public func appliedDB(live: TransferFunction) -> [Double] {
        let f = reference.frequencies
        let ratio: [Double] = f.indices.map { i in
            guard live.isValid(i), reference.isValid(i), reference.response[i].magnitudeSquared > 0 else { return .nan }
            return live.response[i].magnitudeSquared / reference.response[i].magnitudeSquared
        }
        let w = f.indices.map { min(live.coherence[$0], reference.coherence[$0]) >= 0.6 ? 1.0 : 0.0 }
        return Smoothing.smoothPower(ratio, frequencies: f, octaves: 1.0 / 6, weights: w).map { Decibel.fromPower($0) }
    }

    public func plannedDB(upTo count: Int? = nil) -> [Double] {
        let fs = Array(filters.prefix(count ?? filters.count))
        return reference.frequencies.map { f in fs.reduce(0) { $0 + $1.responseDB(at: f, sampleRate: sampleRate) } }
    }

    public func read(live: TransferFunction) -> Reading? {
        guard live.frequencies == reference.frequencies else { return nil }
        let f = reference.frequencies
        let applied = appliedDB(live: live)
        let planned = plannedDB()
        let inRange = f.indices.filter { workingRange.contains(f[$0]) && applied[$0].isFinite }
        guard !inRange.isEmpty else { return nil }
        let d = inRange.map { planned[$0] - applied[$0] }
        let overall = (d.map { $0 * $0 }.reduce(0, +) / Double(d.count)).squareRoot()

        var bands: [BandReading] = []
        for (k, x) in filters.enumerated() {
            // Bands are entered in order: compare with the plan up to and including this band.
            let plan = plannedDB(upTo: k + 1)
            let center = f.indices.min { abs(log(f[$0] / x.frequency)) < abs(log(f[$1] / x.frequency)) }!
            let halfWidth = max(1.0 / (2 * x.q), 1.0 / 6)
            let region = f.indices.filter {
                abs(log2(f[$0] / x.frequency)) <= halfWidth && applied[$0].isFinite
            }
            guard applied[center].isFinite, !region.isEmpty else { continue }
            let remaining = plan[center] - applied[center]
            let shape = (region.map { r -> Double in
                let e = (plan[r] - applied[r]) - remaining
                return e * e
            }.reduce(0, +) / Double(region.count)).squareRoot()
            bands.append(BandReading(bandIndex: k, remainingGainDB: remaining, shapeErrorDB: shape))
        }
        let coh = inRange.map { live.coherence[$0] }.sorted()
        return Reading(bands: bands, overallErrorDB: overall, appliedDB: applied, plannedDB: planned,
                       confidence: coh.isEmpty ? 0 : coh[coh.count / 2])
    }
}
