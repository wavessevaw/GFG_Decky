import Foundation

/// Traffic-light quality of a capture.
public enum CaptureQuality: String, Codable, Sendable {
    case good
    case weak
    case repeatRequired
}

public struct CaptureAssessment: Equatable, Codable, Sendable {
    public var quality: CaptureQuality
    public var medianCoherence: Double
    public var averages: Int
    public var clipped: Bool
    public var reasons: [Reason]

    public enum Reason: String, Codable, Sendable {
        case clipping, lowCoherence, tooFewAverages, streamDiscontinuity
    }

    /// Thresholds per ASSUMPTIONS.md A6: ≥0.8 good, 0.6–0.8 weak, <0.6 repeat.
    public static func assess(_ tf: TransferFunction, band: ClosedRange<Double>, clipped: Bool,
                              discontinuity: Bool = false, minimumAverages: Int = 8,
                              goodCoherence: Double = 0.8, minimumCoherence: Double = 0.6) -> CaptureAssessment {
        let values = tf.frequencies.indices
            .filter { band.contains(tf.frequencies[$0]) && tf.coherence[$0].isFinite }
            .map { tf.coherence[$0] }
            .sorted()
        let median = values.isEmpty ? 0 : values[values.count / 2]
        var reasons: [Reason] = []
        if clipped { reasons.append(.clipping) }
        if discontinuity { reasons.append(.streamDiscontinuity) }
        if tf.averages < minimumAverages { reasons.append(.tooFewAverages) }
        if median < minimumCoherence { reasons.append(.lowCoherence) }
        let quality: CaptureQuality
        if !reasons.isEmpty {
            quality = .repeatRequired
        } else if median < goodCoherence {
            quality = .weak
        } else {
            quality = .good
        }
        return CaptureAssessment(quality: quality, medianCoherence: median, averages: tf.averages,
                                 clipped: clipped, reasons: reasons)
    }
}
