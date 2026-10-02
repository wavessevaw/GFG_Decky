import Foundation

public struct ChannelMeter: Equatable, Codable, Sendable {
    public var peakDBFS: Double
    public var rmsDBFS: Double
    /// Clipping seen since the last `resetClip`.
    public var clipped: Bool
    public var clipCount: Int

    public static let silent = ChannelMeter(peakDBFS: -120, rmsDBFS: -120, clipped: false, clipCount: 0)
}

/// Block-based peak/RMS meter with clip latch (consumer side, not real-time).
public struct MeterAccumulator: Sendable {
    public var clipThreshold: Float
    private var peak: Float = 0
    private var sumSq: Double = 0
    private var count = 0
    private var clipCount = 0
    private var peakHold: Float = 0
    private var rmsSmoothed: Double = 0
    private let rmsCoefficient: Double

    public init(clipThresholdDBFS: Double = -0.1, sampleRate: Double, rmsTimeConstant: Double = 0.3) {
        clipThreshold = Float(Decibel.toAmplitude(clipThresholdDBFS))
        rmsCoefficient = 1 / (rmsTimeConstant * sampleRate)
    }

    public mutating func process(_ x: [Float]) {
        for v in x {
            let a = abs(v)
            if a > peak { peak = a }
            if a >= clipThreshold { clipCount += 1 }
            sumSq += Double(v) * Double(v)
        }
        count += x.count
        if !x.isEmpty {
            let blockMS = sumSq / Double(max(count, 1))
            let alpha = min(1, rmsCoefficient * Double(x.count))
            rmsSmoothed += alpha * (blockMS - rmsSmoothed)
            sumSq = 0
            count = 0
        }
    }

    /// Returns the meter and starts a new peak interval (clip latch persists).
    public mutating func read() -> ChannelMeter {
        let m = ChannelMeter(peakDBFS: Decibel.fromAmplitude(Double(peak)), rmsDBFS: Decibel.fromPower(rmsSmoothed),
                             clipped: clipCount > 0, clipCount: clipCount)
        peak = 0
        return m
    }

    public mutating func resetClip() { clipCount = 0 }

    public var isClipped: Bool { clipCount > 0 }
}
