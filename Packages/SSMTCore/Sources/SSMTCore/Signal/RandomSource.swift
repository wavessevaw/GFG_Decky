import Foundation

/// xoshiro256** PRNG: fast, allocation-free, deterministic for a given seed (needed for tests
/// and for the real-time generator).
public struct RandomSource: Sendable {
    private var s0: UInt64, s1: UInt64, s2: UInt64, s3: UInt64
    private var spareGaussian: Double?

    public init(seed: UInt64) {
        // SplitMix64 seeding.
        var z = seed
        func next() -> UInt64 {
            z &+= 0x9E37_79B9_7F4A_7C15
            var x = z
            x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
            x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
            return x ^ (x >> 31)
        }
        s0 = next(); s1 = next(); s2 = next(); s3 = next()
    }

    @inline(__always)
    public mutating func nextUInt64() -> UInt64 {
        let result = ((s1 &* 5) << 7 | (s1 &* 5) >> 57) &* 9
        let t = s1 << 17
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = (s3 << 45) | (s3 >> 19)
        return result
    }

    /// Uniform in [0, 1).
    @inline(__always)
    public mutating func nextUniform() -> Double {
        Double(nextUInt64() >> 11) * 0x1.0p-53
    }

    /// Standard normal (Box–Muller, polar-free form).
    @inline(__always)
    public mutating func nextGaussian() -> Double {
        if let g = spareGaussian {
            spareGaussian = nil
            return g
        }
        var u1 = nextUniform()
        if u1 < 1e-300 { u1 = 1e-300 }
        let u2 = nextUniform()
        let r = (-2 * log(u1)).squareRoot()
        let a = 2 * Double.pi * u2
        spareGaussian = r * sin(a)
        return r * cos(a)
    }
}
