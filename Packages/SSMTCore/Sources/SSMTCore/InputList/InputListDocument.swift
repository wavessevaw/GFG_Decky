import Foundation

/// Function #2: input list + monitor mixes + stage plan of one show, saved as one document.
public struct InputListDocument: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public var version = InputListDocument.formatVersion
    public var artist = ""
    public var event = ""
    public var venue = ""
    public var date: Date?
    public var engineer = ""
    public var contact = ""
    public var notes = ""
    public var channels: [InputChannel] = []
    public var mixes: [MonitorMix] = []
    public var stage = StagePlan()

    public init() {}

    public enum DecodeError: Error, Equatable { case newerVersion(Int) }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> InputListDocument {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let doc = try d.decode(InputListDocument.self, from: data)
        guard doc.version <= formatVersion else { throw DecodeError.newerVersion(doc.version) }
        return doc
    }
}

/// How the source is picked up (stand type for the stage crew).
public enum StandType: String, Codable, Sendable, CaseIterable {
    case none, tallBoom, shortBoom, straight, clip, desk, hanging
}

/// Instrument family: colour coding and grouping in the list.
public enum ChannelGroup: String, Codable, Sendable, CaseIterable {
    case drums, percussion, bass, guitar, keys, vocals, playback, fx, other
}

public struct InputChannel: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var number: Int
    /// What is on the channel ("Kick In", "Lead Vox").
    public var source: String
    /// Microphone or DI model ("Beta 91A", "DI").
    public var mic: String
    public var stand: StandType
    /// +48 V phantom power.
    public var phantom: Bool
    /// Stage box / snake input ("SB1-05").
    public var stagebox: String
    /// Insert / processing note ("Comp", "Gate").
    public var insert: String
    public var group: ChannelGroup
    public var notes: String

    public init(number: Int, source: String = "", mic: String = "", stand: StandType = .none, phantom: Bool = false,
                stagebox: String = "", insert: String = "", group: ChannelGroup = .other, notes: String = "") {
        self.number = number
        self.source = source
        self.mic = mic
        self.stand = stand
        self.phantom = phantom
        self.stagebox = stagebox
        self.insert = insert
        self.group = group
        self.notes = notes
    }
}

public enum MixType: String, Codable, Sendable, CaseIterable {
    case wedge, iem, sidefill, drumfill, other
}

/// Monitor / output mix ("Mix 3 — Guitar, wedge").
public struct MonitorMix: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var number: Int
    public var name: String
    public var type: MixType
    public var stereo: Bool
    public var notes: String

    public init(number: Int, name: String = "", type: MixType = .wedge, stereo: Bool = false, notes: String = "") {
        self.number = number
        self.name = name
        self.type = type
        self.stereo = stereo
        self.notes = notes
    }
}
