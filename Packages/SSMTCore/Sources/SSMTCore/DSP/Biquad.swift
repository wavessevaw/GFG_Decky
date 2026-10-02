import Foundation

/// Second-order IIR section. Coefficients follow the RBJ Audio EQ Cookbook, normalized so a0 = 1.
public struct Biquad: Equatable, Codable, Sendable {
    public var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    public init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
    }

    public static let identity = Biquad(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    public enum Kind: String, Codable, Sendable, CaseIterable {
        case lowPass, highPass, peaking, lowShelf, highShelf, allPass, bandPass, notch
    }

    /// Design per RBJ cookbook. `gainDB` is used by peaking and shelving filters.
    /// For shelves, `q` is the shelf Q (0.7071 ≈ Butterworth-like transition).
    public static func design(_ kind: Kind, frequency f0: Double, q: Double, gainDB: Double = 0,
                              sampleRate fs: Double) -> Biquad {
        let w0 = 2 * Double.pi * f0 / fs
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * q)
        let A = pow(10, gainDB / 40)
        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0
        switch kind {
        case .lowPass:
            b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .highPass:
            b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .bandPass:
            b0 = alpha; b1 = 0; b2 = -alpha
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .notch:
            b0 = 1; b1 = -2 * cw; b2 = 1
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .allPass:
            b0 = 1 - alpha; b1 = -2 * cw; b2 = 1 + alpha
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .peaking:
            b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
            a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
        case .lowShelf:
            let s = 2 * A.squareRoot() * alpha
            b0 = A * ((A + 1) - (A - 1) * cw + s)
            b1 = 2 * A * ((A - 1) - (A + 1) * cw)
            b2 = A * ((A + 1) - (A - 1) * cw - s)
            a0 = (A + 1) + (A - 1) * cw + s
            a1 = -2 * ((A - 1) + (A + 1) * cw)
            a2 = (A + 1) + (A - 1) * cw - s
        case .highShelf:
            let s = 2 * A.squareRoot() * alpha
            b0 = A * ((A + 1) + (A - 1) * cw + s)
            b1 = -2 * A * ((A - 1) + (A + 1) * cw)
            b2 = A * ((A + 1) + (A - 1) * cw - s)
            a0 = (A + 1) - (A - 1) * cw + s
            a1 = 2 * ((A - 1) - (A + 1) * cw)
            a2 = (A + 1) - (A - 1) * cw - s
        }
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Complex frequency response at f (Hz).
    public func response(at f: Double, sampleRate fs: Double) -> Complex {
        let w = 2 * Double.pi * f / fs
        let z1 = Complex.expj(-w)
        let z2 = Complex.expj(-2 * w)
        let num = Complex(b0) + z1 * b1 + z2 * b2
        let den = Complex(1) + z1 * a1 + z2 * a2
        return num / den
    }
}

/// Stateful transposed direct form II processor for a cascade of biquads.
public struct BiquadCascade: Sendable {
    public private(set) var sections: [Biquad]
    private var z1: [Double]
    private var z2: [Double]

    public init(_ sections: [Biquad]) {
        self.sections = sections
        z1 = [Double](repeating: 0, count: sections.count)
        z2 = [Double](repeating: 0, count: sections.count)
    }

    public mutating func reset() {
        for i in sections.indices { z1[i] = 0; z2[i] = 0 }
    }

    @inline(__always)
    public mutating func process(_ input: Double) -> Double {
        var x = input
        for i in sections.indices {
            let s = sections[i]
            let y = s.b0 * x + z1[i]
            z1[i] = s.b1 * x - s.a1 * y + z2[i]
            z2[i] = s.b2 * x - s.a2 * y
            x = y
        }
        return x
    }

    public func response(at f: Double, sampleRate fs: Double) -> Complex {
        sections.reduce(Complex.one) { $0 * $1.response(at: f, sampleRate: fs) }
    }
}

public enum CrossoverFilter {
    /// Linkwitz–Riley 24 dB/oct = two cascaded 2nd-order Butterworth sections.
    public static func linkwitzRiley24(_ kind: Biquad.Kind, frequency: Double, sampleRate: Double) -> [Biquad] {
        precondition(kind == .lowPass || kind == .highPass)
        let s = Biquad.design(kind, frequency: frequency, q: 1 / 2.0.squareRoot(), sampleRate: sampleRate)
        return [s, s]
    }

    /// Butterworth of even order (as cascaded biquads).
    public static func butterworth(_ kind: Biquad.Kind, order: Int, frequency: Double, sampleRate: Double) -> [Biquad] {
        precondition(order >= 2 && order % 2 == 0)
        return (0..<(order / 2)).map { k in
            let theta = Double.pi * Double(2 * k + 1) / Double(2 * order)
            let q = 1 / (2 * sin(theta))
            return Biquad.design(kind, frequency: frequency, q: q, sampleRate: sampleRate)
        }
    }
}
