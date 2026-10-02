import Foundation

/// Minimal double-precision complex number used throughout the DSP core.
public struct Complex: Equatable, Hashable, Codable, Sendable {
    public var re: Double
    public var im: Double

    @inlinable public init(_ re: Double, _ im: Double = 0) {
        self.re = re
        self.im = im
    }

    public static let zero = Complex(0, 0)
    public static let one = Complex(1, 0)

    /// e^(j·phase)
    @inlinable public static func expj(_ phase: Double) -> Complex {
        Complex(cos(phase), sin(phase))
    }

    @inlinable public static func polar(magnitude: Double, phase: Double) -> Complex {
        Complex(magnitude * cos(phase), magnitude * sin(phase))
    }

    @inlinable public var magnitudeSquared: Double { re * re + im * im }
    @inlinable public var magnitude: Double { (re * re + im * im).squareRoot() }
    @inlinable public var phase: Double { atan2(im, re) }
    @inlinable public var conjugate: Complex { Complex(re, -im) }

    @inlinable public static func + (a: Complex, b: Complex) -> Complex { Complex(a.re + b.re, a.im + b.im) }
    @inlinable public static func - (a: Complex, b: Complex) -> Complex { Complex(a.re - b.re, a.im - b.im) }
    @inlinable public static prefix func - (a: Complex) -> Complex { Complex(-a.re, -a.im) }
    @inlinable public static func * (a: Complex, b: Complex) -> Complex {
        Complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re)
    }
    @inlinable public static func * (a: Complex, s: Double) -> Complex { Complex(a.re * s, a.im * s) }
    @inlinable public static func * (s: Double, a: Complex) -> Complex { Complex(a.re * s, a.im * s) }
    @inlinable public static func / (a: Complex, s: Double) -> Complex { Complex(a.re / s, a.im / s) }
    @inlinable public static func / (a: Complex, b: Complex) -> Complex {
        let d = b.re * b.re + b.im * b.im
        return Complex((a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d)
    }
    @inlinable public static func += (a: inout Complex, b: Complex) { a = a + b }
    @inlinable public static func -= (a: inout Complex, b: Complex) { a = a - b }
    @inlinable public static func *= (a: inout Complex, b: Complex) { a = a * b }
    @inlinable public static func *= (a: inout Complex, s: Double) { a = a * s }
}

public enum Decibel {
    /// Floor used to avoid -inf when converting zero power.
    public static let floor: Double = -300

    @inlinable public static func fromPower(_ p: Double) -> Double {
        p > 0 ? 10 * log10(p) : floor
    }

    @inlinable public static func fromAmplitude(_ a: Double) -> Double {
        a > 0 ? 20 * log10(a) : floor
    }

    @inlinable public static func toAmplitude(_ db: Double) -> Double { pow(10, db / 20) }
    @inlinable public static func toPower(_ db: Double) -> Double { pow(10, db / 10) }
}

public enum Acoustics {
    /// Speed of sound in air, m/s: c = 331.3 + 0.606·T (T in °C).
    @inlinable public static func speedOfSound(celsius: Double) -> Double { 331.3 + 0.606 * celsius }

    @inlinable public static func meters(forDelaySeconds seconds: Double, celsius: Double) -> Double {
        seconds * speedOfSound(celsius: celsius)
    }
}
