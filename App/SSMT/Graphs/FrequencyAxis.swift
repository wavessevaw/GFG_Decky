import CoreGraphics
import Foundation

/// Logarithmic frequency axis 20 Hz – 20 kHz.
struct FrequencyAxis {
    var minFrequency: Double = 20
    var maxFrequency: Double = 20000

    func x(_ f: Double, width: CGFloat) -> CGFloat {
        let t = log10(f / minFrequency) / log10(maxFrequency / minFrequency)
        return CGFloat(t) * width
    }

    static let majorTicks: [Double] = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
    static let minorTicks: [Double] = [30, 40, 60, 70, 80, 90, 300, 400, 600, 700, 800, 900,
                                       3000, 4000, 6000, 7000, 8000, 9000]

    static func label(_ f: Double) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }
}
