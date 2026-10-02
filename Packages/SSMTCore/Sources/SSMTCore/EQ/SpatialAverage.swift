import Foundation

/// Spatially averaged response over several microphone positions (spec 7, "Вход и подготовка").
public struct SpatialAverage: Equatable, Codable, Sendable {
    public var frequencies: [Double]
    /// Energy average of |H|² over the coherent points, in dB.
    public var levelDB: [Double]
    /// Standard deviation of the per-point levels (dB) — high values mean interference/room modes.
    public var spreadDB: [Double]
    /// Mean coherence of the points used at each frequency.
    public var coherence: [Double]
    /// Number of points used at each frequency.
    public var pointsUsed: [Int]
    public var pointCount: Int

    /// - Parameter coherenceThreshold: a point is excluded at frequencies where its γ² is below this.
    public static func compute(_ points: [TransferFunction], coherenceThreshold: Double = 0.6) -> SpatialAverage? {
        guard let first = points.first, points.allSatisfy({ $0.frequencies == first.frequencies }) else { return nil }
        let f = first.frequencies
        var level = [Double](repeating: .nan, count: f.count)
        var spread = [Double](repeating: .nan, count: f.count)
        var coh = [Double](repeating: .nan, count: f.count)
        var used = [Int](repeating: 0, count: f.count)
        for i in f.indices {
            var wsum = 0.0, psum = 0.0, csum = 0.0
            var dbs: [Double] = []
            for p in points where p.isValid(i) && p.coherence[i] >= coherenceThreshold {
                let w = p.coherence[i]
                psum += w * p.response[i].magnitudeSquared
                wsum += w
                csum += p.coherence[i]
                dbs.append(Decibel.fromAmplitude(p.response[i].magnitude))
            }
            guard wsum > 0 else { continue }
            level[i] = Decibel.fromPower(psum / wsum)
            coh[i] = csum / Double(dbs.count)
            used[i] = dbs.count
            if dbs.count >= 2 {
                let m = dbs.reduce(0, +) / Double(dbs.count)
                spread[i] = (dbs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(dbs.count - 1)).squareRoot()
            } else {
                spread[i] = 0
            }
        }
        return SpatialAverage(frequencies: f, levelDB: level, spreadDB: spread, coherence: coh,
                              pointsUsed: used, pointCount: points.count)
    }

    /// As a transfer function (zero phase) for plotting.
    public var asTransferFunction: TransferFunction {
        TransferFunction(frequencies: frequencies,
                         response: levelDB.map { $0.isFinite ? Complex(Decibel.toAmplitude($0)) : Complex(.nan, .nan) },
                         coherence: coherence.map { $0.isFinite ? $0 : 0 },
                         measurementPower: levelDB.map { Decibel.toPower($0) },
                         referencePower: levelDB.map { _ in 1 }, averages: pointCount)
    }

    /// Applies a microphone calibration (magnitude only).
    public func removingMicrophone(_ mic: MicrophoneCalibration?) -> SpatialAverage {
        guard let mic else { return self }
        var out = self
        for i in frequencies.indices { out.levelDB[i] -= mic.deviation(at: frequencies[i]) }
        return out
    }
}
