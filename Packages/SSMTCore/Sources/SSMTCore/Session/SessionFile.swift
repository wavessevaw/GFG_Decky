import Foundation

/// Saved setup session (`.ssmtsession`, JSON). Contains the complete wizard state, so a setup
/// can be reopened, compared or reported later.
public struct SessionFile: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var savedAt: Date
    public var appVersion: String
    public var interfaceName: String
    public var sampleRate: Double
    public var microphoneCalibrationName: String?
    public var wizard: SetupWizard

    public init(wizard: SetupWizard, interfaceName: String, sampleRate: Double,
                microphoneCalibrationName: String?, appVersion: String, savedAt: Date = Date()) {
        version = Self.currentVersion
        self.savedAt = savedAt
        self.appVersion = appVersion
        self.interfaceName = interfaceName
        self.sampleRate = sampleRate
        self.microphoneCalibrationName = microphoneCalibrationName
        self.wizard = wizard
    }

    public enum LoadError: Error, Equatable { case unsupportedVersion(Int) }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        e.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> SessionFile {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        let s = try d.decode(SessionFile.self, from: data)
        guard s.version <= currentVersion else { throw LoadError.unsupportedVersion(s.version) }
        return s
    }
}
