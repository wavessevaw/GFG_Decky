import Foundation

/// Built-in typical (nominal) frequency responses of popular microphones.
///
/// These are approximations of the manufacturers' published on-axis free-field response charts
/// (cardioid pattern where switchable, no pad, no low-cut, far field without proximity effect).
/// They are not measurements of an individual microphone: sample-to-sample spread and reading the
/// charts give an uncertainty of about ±2–3 dB, mostly above 5 kHz. An individual calibration file
/// always takes precedence. Values are deviations from flat in dB; the correction subtracts them.
public struct MicrophoneProfile: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case measurement, smallDiaphragm, largeDiaphragm, dynamic
    }

    public enum Pattern: String, Sendable {
        case omni, cardioid
    }

    public let id: String
    public let brand: String
    public let model: String
    public let kind: Kind
    public let pattern: Pattern
    /// (frequency Hz, deviation dB) in ascending frequency.
    public let points: [(Double, Double)]

    public var displayName: String { "\(brand) \(model)" }

    /// The response is nominally flat (±1 dB): selecting it changes almost nothing; an individual
    /// calibration file supplied with the microphone should be used instead when available.
    public var isNominallyFlat: Bool { points.allSatisfy { abs($0.1) <= 1 } }

    /// Stable identifier for persistence (same UUID on every launch and machine).
    public var uuid: UUID { Self.stableUUID(id) }

    /// Calibration usable by the measurement pipeline; the name marks it as a typical curve.
    public var calibration: MicrophoneCalibration {
        MicrophoneCalibration(id: uuid, name: "\(displayName) (typical)", frequencies: points.map(\.0),
                              deviationDB: points.map(\.1), source: .typical)
    }

    public static func == (a: MicrophoneProfile, b: MicrophoneProfile) -> Bool { a.id == b.id }

    /// Deterministic UUID from a string (two FNV-1a 64-bit hashes, RFC 4122 variant bits set).
    static func stableUUID(_ s: String) -> UUID {
        func fnv(_ seed: UInt64) -> UInt64 {
            var h = seed
            for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01B3 }
            return h
        }
        let a = fnv(0xCBF2_9CE4_8422_2325), b = fnv(0x84222325_CBF29CE4)
        var bytes = (0..<8).map { UInt8(truncatingIfNeeded: a >> (8 * $0)) } + (0..<8).map { UInt8(truncatingIfNeeded: b >> (8 * $0)) }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

public enum MicrophoneProfiles {
    public static let all: [MicrophoneProfile] = measurement + smallDiaphragm + largeDiaphragm + dynamic

    public static func profile(id: UUID) -> MicrophoneProfile? { all.first { $0.uuid == id } }

    // MARK: Measurement microphones (omni)

    static let measurement: [MicrophoneProfile] = [
        .init(id: "behringer-ecm8000", brand: "Behringer", model: "ECM8000", kind: .measurement, pattern: .omni,
              points: [(20, -1.5), (50, 0), (1000, 0), (3000, 0.5), (5000, 1), (8000, 2), (10000, 3),
                       (12000, 3.5), (15000, 3), (18000, 1), (20000, -1)]),
        .init(id: "superlux-ecm999", brand: "Superlux", model: "ECM999", kind: .measurement, pattern: .omni,
              points: [(20, -1), (50, 0), (1000, 0), (5000, 0.5), (8000, 1.5), (10000, 2.5), (13000, 3),
                       (16000, 2), (20000, 0)]),
        .init(id: "dayton-emm6", brand: "Dayton Audio", model: "EMM-6", kind: .measurement, pattern: .omni,
              points: [(20, 0), (1000, 0), (10000, 0.5), (16000, 1), (20000, 0)]),
        .init(id: "beyerdynamic-mm1", brand: "beyerdynamic", model: "MM 1", kind: .measurement, pattern: .omni,
              points: [(20, -0.5), (50, 0), (1000, 0), (10000, 0.5), (16000, 1), (20000, 0)]),
        .init(id: "earthworks-m23", brand: "Earthworks", model: "M23 / M30", kind: .measurement, pattern: .omni,
              points: [(20, 0), (1000, 0), (20000, 0)]),
        .init(id: "audix-tm1", brand: "Audix", model: "TM1", kind: .measurement, pattern: .omni,
              points: [(20, -0.5), (50, 0), (1000, 0), (15000, 0.5), (20000, -0.5)]),
        .init(id: "isemcon-emx7150", brand: "iSEMcon", model: "EMX-7150", kind: .measurement, pattern: .omni,
              points: [(20, 0), (1000, 0), (20000, 0)]),
    ]

    // MARK: Small-diaphragm condensers (cardioid)

    static let smallDiaphragm: [MicrophoneProfile] = [
        .init(id: "shure-sm81", brand: "Shure", model: "SM81", kind: .smallDiaphragm, pattern: .cardioid,
              points: [(20, -4), (30, -2), (50, -0.5), (100, 0), (1000, 0), (3000, 0.5), (6000, 1.5),
                       (9000, 2), (12000, 1.5), (15000, 0.5), (18000, -1), (20000, -2)]),
        .init(id: "soyuz-011-fet", brand: "Soyuz", model: "011 FET", kind: .smallDiaphragm, pattern: .cardioid,
              points: [(20, -3), (40, -1), (100, 0), (1000, 0), (5000, 0.5), (8000, 1.5), (12000, 2),
                       (16000, 1), (20000, -2)]),
        .init(id: "soyuz-013-fet", brand: "Soyuz", model: "013 FET", kind: .smallDiaphragm, pattern: .cardioid,
              points: [(20, -2.5), (40, -1), (100, 0), (1000, 0), (4000, 0.5), (7000, 1.5), (10000, 1.5),
                       (14000, 1), (18000, -1), (20000, -2)]),
        .init(id: "neumann-km184", brand: "Neumann", model: "KM 184", kind: .smallDiaphragm, pattern: .cardioid,
              points: [(20, -1.5), (40, -0.5), (100, 0), (1000, 0), (5000, 0.5), (9000, 2), (12000, 1.5),
                       (16000, 0), (20000, -2)]),
        .init(id: "rode-nt5", brand: "RØDE", model: "NT5", kind: .smallDiaphragm, pattern: .cardioid,
              points: [(20, -2), (50, -0.5), (100, 0), (1000, 0), (4000, 0.5), (8000, 2), (12000, 2.5),
                       (16000, 1), (20000, -1)]),
        .init(id: "oktava-mk012", brand: "Октава", model: "МК-012", kind: .smallDiaphragm, pattern: .cardioid,
              points: [(20, -3), (50, -1), (100, 0), (1000, 0), (5000, 1), (8000, 2.5), (12000, 3),
                       (16000, 1), (20000, -2)]),
    ]

    // MARK: Large-diaphragm condensers (cardioid)

    static let largeDiaphragm: [MicrophoneProfile] = [
        .init(id: "akg-c414-xlii", brand: "AKG", model: "C414 XLII", kind: .largeDiaphragm, pattern: .cardioid,
              points: [(20, -1.5), (40, -0.5), (100, 0), (1000, 0), (2000, 0.5), (4000, 1.5), (6000, 2.5),
                       (10000, 3.5), (12000, 3.5), (15000, 2), (20000, -1)]),
        .init(id: "akg-c414-xls", brand: "AKG", model: "C414 XLS", kind: .largeDiaphragm, pattern: .cardioid,
              points: [(20, -1.5), (40, -0.5), (100, 0), (1000, 0), (5000, 0.5), (8000, 1), (12000, 1),
                       (15000, 0), (20000, -2)]),
        .init(id: "soyuz-022-bomblet", brand: "Soyuz", model: "022 Bomblet", kind: .largeDiaphragm, pattern: .cardioid,
              points: [(20, -3), (40, -1), (100, 0), (1000, 0), (3000, 1), (5000, 2.5), (8000, 3),
                       (12000, 2), (16000, 0), (20000, -3)]),
        .init(id: "neumann-u87ai", brand: "Neumann", model: "U 87 Ai", kind: .largeDiaphragm, pattern: .cardioid,
              points: [(20, -2), (40, -0.5), (100, 0), (1000, 0), (3000, 0.5), (6000, 1.5), (10000, 2),
                       (12000, 1), (16000, -1), (20000, -4)]),
        .init(id: "rode-nt1a", brand: "RØDE", model: "NT1-A", kind: .largeDiaphragm, pattern: .cardioid,
              points: [(20, -2), (50, -0.5), (100, 0), (1000, 0), (3000, 1), (6000, 2), (10000, 3),
                       (13000, 2.5), (17000, 0), (20000, -2)]),
        .init(id: "audio-technica-at4050", brand: "Audio-Technica", model: "AT4050", kind: .largeDiaphragm, pattern: .cardioid,
              points: [(20, -1.5), (50, -0.5), (100, 0), (1000, 0), (5000, 0.5), (8000, 1.5), (12000, 1.5),
                       (16000, 0), (20000, -2)]),
    ]

    // MARK: Dynamic (cardioid / supercardioid), far field

    static let dynamic: [MicrophoneProfile] = [
        .init(id: "shure-sm57", brand: "Shure", model: "SM57", kind: .dynamic, pattern: .cardioid,
              points: [(40, -6), (60, -4), (100, -2), (200, -0.5), (1000, 0), (2000, 1), (3000, 2.5),
                       (5000, 5), (6000, 5), (8000, 2), (10000, 2), (12000, -1), (15000, -6), (20000, -12)]),
        .init(id: "shure-sm58", brand: "Shure", model: "SM58", kind: .dynamic, pattern: .cardioid,
              points: [(50, -6), (100, -3), (200, -1), (1000, 0), (2000, 1), (3000, 3), (5000, 4.5),
                       (6000, 3.5), (8000, 1), (10000, 2), (12000, -2), (15000, -8), (20000, -14)]),
        .init(id: "sennheiser-e935", brand: "Sennheiser", model: "e 935", kind: .dynamic, pattern: .cardioid,
              points: [(40, -5), (80, -2), (150, 0), (1000, 0), (3000, 2), (5000, 3.5), (8000, 2),
                       (12000, 0), (16000, -4), (20000, -10)]),
    ]
}
