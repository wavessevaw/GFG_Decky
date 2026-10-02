import Foundation

public enum WindowFunction: String, Codable, Sendable, CaseIterable {
    case hann
    case blackmanHarris

    /// Periodic (DFT-even) window of length n, the correct form for Welch averaging.
    public func coefficients(count n: Int) -> [Double] {
        var w = [Double](repeating: 0, count: n)
        let N = Double(n)
        for i in 0..<n {
            let x = 2 * Double.pi * Double(i) / N
            switch self {
            case .hann:
                w[i] = 0.5 - 0.5 * cos(x)
            case .blackmanHarris:
                w[i] = 0.35875 - 0.48829 * cos(x) + 0.14128 * cos(2 * x) - 0.01168 * cos(3 * x)
            }
        }
        return w
    }
}
