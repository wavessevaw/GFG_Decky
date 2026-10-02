import Foundation

/// What the console / loudspeaker processor that receives the corrections can actually do, so the
/// recommendations can be entered as they are: delay step and maximum, PEQ bands available on the
/// subwoofer and satellite outputs, gain step, Q range, and whether the band width is set as Q or
/// in octaves. The measurement itself does not depend on it (the whole chain is measured).
///
/// Presets contain only values confirmed from published specifications (`source`); everything else
/// stays at the generic value (nil = no limit). "Custom" is filled in by the user from their console.
public struct ProcessorProfile: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Delay resolution (ms).
    public var delayStepMs: Double = 0.01
    /// Maximum output delay (ms); nil = not limited / unknown.
    public var maxDelayMs: Double?
    /// PEQ bands available on the subwoofer output and on the satellite output; nil = unknown.
    public var peqBandsSub: Int?
    public var peqBandsMains: Int?
    /// Gain resolution of the PEQ (dB).
    public var gainStepDB: Double = 0.1
    /// Q range of the PEQ; nil = generic 0.5–8.
    public var minQ: Double?
    public var maxQ: Double?
    /// The console sets the band width in octaves instead of Q.
    public var bandwidthInOctaves = false
    /// Where the preset values come from (shown to the user); nil for generic and custom.
    public var source: String?

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var isCustom: Bool { id == Self.customID }
    public static let customID = "custom"

    public static let generic = ProcessorProfile(id: "generic", name: "Generic")

    public static var customDefault: ProcessorProfile {
        var p = ProcessorProfile(id: customID, name: "Custom")
        p.maxDelayMs = 500
        p.peqBandsSub = 4
        p.peqBandsMains = 6
        return p
    }

    public static let presets: [ProcessorProfile] = {
        var sq = ProcessorProfile(id: "ah-sq", name: "Allen & Heath SQ-5/6/7")
        sq.maxDelayMs = 682
        sq.peqBandsSub = 4
        sq.peqBandsMains = 4
        sq.bandwidthInOctaves = true
        // Bell width 1/9 … 1.5 octave.
        sq.minQ = q(octaves: 1.5)
        sq.maxQ = q(octaves: 1.0 / 9)
        sq.source = "Mix processing: delay up to 682 ms, 4-band PEQ, bell width 1/9–1.5 oct (manufacturer specifications)"

        var x32 = ProcessorProfile(id: "behringer-x32", name: "Behringer X32 / Midas M32")
        x32.peqBandsSub = 6
        x32.peqBandsMains = 6
        x32.source = "Buses, matrices and main: 6-band PEQ (manufacturer specifications)"

        var dlive = ProcessorProfile(id: "ah-dlive", name: "Allen & Heath dLive")
        dlive.maxDelayMs = 682
        dlive.peqBandsSub = 4
        dlive.peqBandsMains = 4
        dlive.source = "Mix outputs: delay up to 682 ms (firmware 1.80+), 4-band PEQ; NEQ12 (12 bands) can replace the GEQ (manufacturer information)"

        var hd96 = ProcessorProfile(id: "midas-hd96", name: "Midas HD96")
        hd96.maxDelayMs = 500
        hd96.peqBandsSub = 4
        hd96.peqBandsMains = 4
        hd96.source = "Flexi aux / matrix outputs: 4-band PEQ, delay up to 500 ms (manufacturer specifications)"

        var cl = ProcessorProfile(id: "yamaha-cl", name: "Yamaha CL / QL")
        cl.maxDelayMs = 1000
        cl.source = "Output delay 0–1000 ms (manufacturer specifications)"

        return [generic, x32, sq, dlive, hd96, cl]
    }()

    public static func profile(id: String) -> ProcessorProfile? { presets.first { $0.id == id } }

    /// Q of a bell with the given bandwidth in octaves: Q = √(2^N) / (2^N − 1).
    public static func q(octaves n: Double) -> Double {
        let p = pow(2, n)
        return p.squareRoot() / (p - 1)
    }

    /// Bandwidth in octaves of a bell with quality factor Q: N = (2 / ln 2) · asinh(1 / 2Q).
    public static func octaves(q: Double) -> Double {
        2 / log(2) * asinh(1 / (2 * q))
    }

    /// Applies the profile's resolution and limits to the wizard / EQ settings.
    public func apply(to c: inout WizardConfiguration) {
        c.delayStep = delayStepMs / 1000
        c.eq.maxBandsSub = peqBandsSub
        c.eq.maxBandsMains = peqBandsMains
        c.eq.gainStepDB = gainStepDB
        c.eq.minQ = max(EQSettings().minQ, minQ ?? EQSettings().minQ)
        c.eq.maxQ = min(EQSettings().maxQ, maxQ ?? EQSettings().maxQ)
    }

    /// True if a delay (s) can be entered on this console.
    public func canEnter(delaySeconds: Double) -> Bool {
        guard let m = maxDelayMs else { return true }
        return abs(delaySeconds) * 1000 <= m + 1e-9
    }
}
