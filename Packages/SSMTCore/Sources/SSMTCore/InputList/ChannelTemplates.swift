import Foundation

/// Ready-made blocks of channels ("Drum kit", "Keys stereo") with typical mics and stands.
/// Source names are in English — the usual language of riders and console scribble strips.
public struct ChannelTemplate: Identifiable, Sendable {
    public var id: String
    public var group: ChannelGroup
    public var channels: [InputChannel]

    static func ch(_ source: String, _ mic: String, _ stand: StandType, _ phantom: Bool = false,
                   _ group: ChannelGroup, insert: String = "") -> InputChannel {
        InputChannel(number: 0, source: source, mic: mic, stand: stand, phantom: phantom, insert: insert, group: group)
    }

    public static let all: [ChannelTemplate] = [
        ChannelTemplate(id: "drums", group: .drums, channels: [
            ch("Kick In", "Beta 91A", .none, true, .drums, insert: "Gate"),
            ch("Kick Out", "Beta 52A", .shortBoom, false, .drums),
            ch("Snare Top", "SM57", .shortBoom, false, .drums, insert: "Comp"),
            ch("Snare Bottom", "SM57", .shortBoom, false, .drums),
            ch("Hi-Hat", "KM184", .shortBoom, true, .drums),
            ch("Tom 1", "e604", .clip, false, .drums, insert: "Gate"),
            ch("Tom 2", "e604", .clip, false, .drums, insert: "Gate"),
            ch("Floor Tom", "e604", .clip, false, .drums, insert: "Gate"),
            ch("OH L", "C414", .tallBoom, true, .drums),
            ch("OH R", "C414", .tallBoom, true, .drums),
        ]),
        ChannelTemplate(id: "drumsSmall", group: .drums, channels: [
            ch("Kick", "Beta 52A", .shortBoom, false, .drums),
            ch("Snare", "SM57", .shortBoom, false, .drums),
            ch("OH L", "SM81", .tallBoom, true, .drums),
            ch("OH R", "SM81", .tallBoom, true, .drums),
        ]),
        ChannelTemplate(id: "bass", group: .bass, channels: [
            ch("Bass DI", "DI", .none, true, .bass, insert: "Comp"),
            ch("Bass Mic", "Beta 52A", .shortBoom, false, .bass),
        ]),
        ChannelTemplate(id: "guitar", group: .guitar, channels: [
            ch("E-Gtr", "e906", .none, false, .guitar),
        ]),
        ChannelTemplate(id: "acoustic", group: .guitar, channels: [
            ch("Ac-Gtr", "DI", .none, true, .guitar, insert: "Comp"),
        ]),
        ChannelTemplate(id: "keys", group: .keys, channels: [
            ch("Keys L", "DI", .none, true, .keys),
            ch("Keys R", "DI", .none, true, .keys),
        ]),
        ChannelTemplate(id: "leadVocal", group: .vocals, channels: [
            ch("Lead Vox", "Beta 58A", .tallBoom, false, .vocals, insert: "Comp"),
        ]),
        ChannelTemplate(id: "backingVocals", group: .vocals, channels: [
            ch("BV 1", "SM58", .tallBoom, false, .vocals),
            ch("BV 2", "SM58", .tallBoom, false, .vocals),
            ch("BV 3", "SM58", .tallBoom, false, .vocals),
        ]),
        ChannelTemplate(id: "playback", group: .playback, channels: [
            ch("Playback L", "DI", .none, true, .playback),
            ch("Playback R", "DI", .none, true, .playback),
        ]),
        ChannelTemplate(id: "percussion", group: .percussion, channels: [
            ch("Conga", "SM57", .shortBoom, false, .percussion),
            ch("Bongo", "SM57", .shortBoom, false, .percussion),
            ch("Perc OH", "KM184", .tallBoom, true, .percussion),
        ]),
        ChannelTemplate(id: "ambience", group: .fx, channels: [
            ch("Amb L", "SM81", .tallBoom, true, .fx),
            ch("Amb R", "SM81", .tallBoom, true, .fx),
        ]),
        ChannelTemplate(id: "talkback", group: .other, channels: [
            ch("Talkback", "SM58", .straight, false, .other),
        ]),
    ]

    public static func template(id: String) -> ChannelTemplate? { all.first { $0.id == id } }
}

/// Microphones and DIs offered as suggestions while typing (any text is still allowed).
public enum MicLibrary {
    public static let models: [String] = [
        "SM58", "Beta 58A", "SM57", "Beta 57A", "Beta 52A", "Beta 91A", "Beta 98", "SM7B", "SM81", "KSM9",
        "e604", "e904", "e906", "e935", "e945", "e614", "MD421", "MD441", "e602",
        "D112", "D6", "D2", "D4", "i5", "OM7", "C214", "C414", "C451", "KM184", "KMS105", "U87",
        "Soyuz 011 FET", "Soyuz 013 FET", "Soyuz 022", "AT4050", "AE5400", "DPA 4099", "DPA d:facto",
        "RE20", "M88", "M201", "SM137",
        "DI", "Stereo DI", "Radial J48", "Radial ProD2", "BSS AR-133", "Klark DN100",
        "Wireless", "ULXD", "Axient", "EW-DX", "Line",
    ]

    /// Suggestions for a typed prefix (case-insensitive, prefix matches first).
    public static func suggestions(for text: String, limit: Int = 8) -> [String] {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return [] }
        let prefix = models.filter { $0.lowercased().hasPrefix(t) }
        let contains = models.filter { !$0.lowercased().hasPrefix(t) && $0.lowercased().contains(t) }
        return Array((prefix + contains).prefix(limit))
    }

    /// Condenser microphones and active DIs from the library that usually need +48 V
    /// (a suggestion when the model is typed; the user can always change it).
    public static func needsPhantom(_ model: String) -> Bool {
        let m = model.trimmingCharacters(in: .whitespaces).lowercased()
        let phantom: Set<String> = ["beta 91a", "beta 98", "ksm9", "sm81", "sm137", "e614", "c214", "c414", "c451",
                                    "km184", "kms105", "u87", "soyuz 011 fet", "soyuz 013 fet", "soyuz 022", "at4050",
                                    "ae5400", "dpa 4099", "dpa d:facto", "di", "stereo di", "radial j48", "bss ar-133",
                                    "klark dn100"]
        return phantom.contains(m)
    }
}
