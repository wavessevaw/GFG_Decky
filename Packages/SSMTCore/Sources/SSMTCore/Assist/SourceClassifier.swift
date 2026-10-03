import Foundation

/// Decides what a channel carries from its console name and from its sound.
///
/// The name is the strongest hint (engineers label channels "Kick In", "Vox 1", "Скрипка 2"). The sound
/// confirms or decides when the name is missing: pitch range, harmonicity, crest factor, spectral
/// balance and onset rate. This is a rule-based classifier, not a trained model: it separates the broad
/// families reliably and says so when it is unsure (low confidence), so the user can correct it.
public enum SourceClassifier {
    public struct Result: Equatable, Sendable {
        public var kind: SourceKind
        /// 0…1.
        public var confidence: Double
        /// What decided it ("name", "sound", "name + sound").
        public var basis: String
    }

    // MARK: names

    /// Lower-case name fragments → kind, checked in order (more specific first).
    static let nameRules: [(keys: [String], kind: SourceKind)] = [
        (["pb", "playback", "track", "click", "плейбек", "фонограм", "минус"], .playback),
        (["kick", "kik", "bd", "bassdrum", "bass drum", "бочка", "бочк", "бас-барабан", "бас барабан"], .kick),
        (["snare", "snr", "sn ", "sn1", "sn2", "малый", "рабоч", "снейр"], .snare),
        (["tom", "floor", "ft ", "том", "альт-том", "флор"], .tom),
        (["hh", "hihat", "hi-hat", "hi hat", "hat", "хэт", "хет", "хай-хэт"], .hiHat),
        (["oh", "overhead", "over", "ovh", "оверхед", "овер", "тарелк", "cym", "ride", "райд"], .overhead),
        (["timp", "литавр", "perc", "перк", "conga", "конг", "bongo", "бонг", "cajon", "кахон", "glock", "xylo", "marimba", "маримб", "ксилоф"], .percussion),
        (["contrabass", "double bass", "dbass", "cb", "контрабас", "kb "], .doubleBass),
        (["cello", "vc", "vlc", "виолонч", "чело"], .cello),
        (["viola", "vla", "va "], .viola),
        (["violin", "vln", "vn", "vl1", "vl2", "скрипк", "скр"], .violin),
        (["harp", "арф"], .harp),
        (["flute", "fl ", "fl1", "fl2", "piccolo", "флейт", "пикколо"], .flute),
        (["clarinet", "clar", "cl ", "cl1", "кларнет"], .clarinet),
        (["oboe", "ob ", "гобой"], .oboe),
        (["bassoon", "fag", "фагот"], .bassoon),
        (["sax", "сакс"], .saxophone),
        (["trumpet", "tpt", "trp", "труб"], .trumpet),
        (["trombone", "tbn", "trb", "тромбон"], .trombone),
        (["horn", "hrn", "валторн"], .frenchHorn),
        (["tuba", "туба"], .tuba),
        (["choir", "chor", "хор", "soprano", "сопрано", "tenor", "тенор", "ensemble", "ансамбл"], .choir),
        (["bv", "bvox", "back", "bkg", "бэк", "бек"], .backingVocal),
        (["speech", "mc", "host", "talk", "spk", "podium", "lectern", "ведущ", "речь", "спикер", "трибун", "конфер"], .speech),
        (["vox", "vocal", "voc", "вокал", "вок", "голос", "солист"], .maleVocal),
        (["bass", "bas ", "бас"], .bassGuitar),
        (["ac gtr", "acgtr", "acoustic", "agtr", "акуст"], .acousticGuitar),
        (["gtr", "guitar", "git", "гит", "гитар", "гтр"], .electricGuitar),
        (["piano", "pno", "grand", "рояль", "фортеп", "пиан"], .piano),
        (["keys", "key", "synth", "rhodes", "organ", "клав", "синт", "орган"], .keys),
    ]

    /// Kind suggested by a channel name, or nil. `choirContext`: other channels mention a choir, so
    /// "Alto" / "Альт" / "Bass" are choir sections rather than viola or bass guitar.
    public static func kind(forName raw: String, choirContext: Bool = false) -> SourceKind? {
        let name = " " + raw.lowercased().replacingOccurrences(of: "_", with: " ") + " "
        guard name.trimmingCharacters(in: .whitespaces).isEmpty == false else { return nil }
        if name.contains("sax") || name.contains("сакс") { return .saxophone }
        if choirContext {
            // A bare section name ("Alto 2", "Bass L", "Сопрано", "T1") is a choir mic.
            let word = name.filter { $0.isLetter || $0 == " " }.split(separator: " ").filter { !["l", "r"].contains($0) }
            let sections: Set<String> = ["s", "a", "t", "b", "sop", "sopr", "soprano", "alto", "alt", "ten", "tenor", "bass", "bas",
                                         "сопрано", "сопр", "альт", "альты", "тенор", "теноры", "бас", "басы"]
            if word.count == 1 && sections.contains(String(word[0])) { return .choir }
        }
        // "Альт" alone is a viola in an orchestra ("альт-том" is a tom); "Alto" is a choir section.
        if name.contains("альт") && !name.contains("том") { return .viola }
        if name.contains("alto") { return .choir }
        for rule in nameRules {
            for key in rule.keys {
                let t = key.trimmingCharacters(in: .whitespaces)
                // Short tokens must stand alone or next to a digit ("OH L", "Vn1"); longer ones may be part of a word.
                if t.count <= 3 ? containsToken(name, t) : name.contains(key) { return rule.kind }
            }
        }
        return nil
    }

    static func containsToken(_ name: String, _ token: String) -> Bool {
        let chars = Array(name)
        let t = Array(token)
        guard t.count <= chars.count else { return false }
        for i in 0...(chars.count - t.count) where Array(chars[i..<i + t.count]) == t {
            let before = i == 0 ? " " : chars[i - 1]
            let after = i + t.count < chars.count ? chars[i + t.count] : " "
            if !before.isLetter && !after.isLetter { return true }
        }
        return false
    }

    // MARK: sound

    /// Best guess from the sound alone.
    public static func kind(forSound f: SignalFeatures) -> Result {
        guard f.hasSignal else { return Result(kind: .unknown, confidence: 0, basis: "sound") }
        let b = f.bandsDB
        func band(_ lo: Double, _ hi: Double) -> Double {
            let idx = ThirdOctave.centers.indices.filter { ThirdOctave.centers[$0] >= lo && ThirdOctave.centers[$0] <= hi }
            return Decibel.fromPower(idx.reduce(0.0) { $0 + pow(10, b[$1] / 10) } + 1e-15)
        }
        let low = band(25, 160), lowMid = band(200, 630), mid = band(800, 2500), high = band(3150, 8000), air = band(10000, 20000)
        let total = Decibel.fromPower([low, lowMid, mid, high, air].reduce(0.0) { $0 + pow(10, $1 / 10) })
        let pitched = f.harmonicity > 0.45 && f.pitchHz > 0
        // Struck sources: repeated attacks with a high crest factor. A drum may have a pitch (kick, toms)
        // but its energy sits either very low or very high, unlike a bowed or sung note.
        let percussive = f.onsetRate > 0.7 && f.crestDB > 11 && (f.harmonicity < 0.6 || f.centroidHz < 160 || f.centroidHz > 2500)

        if percussive {
            if f.centroidHz < 400 && low - total > -4 {
                return Result(kind: f.pitchHz >= 80 ? .tom : .kick, confidence: 0.65, basis: "sound")
            }
            if lowMid > high - 18 && f.centroidHz > 900 { return Result(kind: .snare, confidence: 0.55, basis: "sound") }
            if f.centroidHz > 5000 { return Result(kind: .hiHat, confidence: 0.55, basis: "sound") }
            if f.centroidHz < 900 { return Result(kind: .tom, confidence: 0.45, basis: "sound") }
            return Result(kind: .percussion, confidence: 0.4, basis: "sound")
        }
        if pitched {
            let p = f.pitchHz
            if p < 110 && low - total > -4 { return Result(kind: f.crestDB > 14 ? .bassGuitar : .doubleBass, confidence: 0.45, basis: "sound") }
            // Voice: pitch in the speaking/singing range, energy concentrated below 4 kHz with a presence peak.
            let voiceShape = mid > high + 4 && lowMid > low - 6
            if voiceShape && (85...180).contains(p) { return Result(kind: .maleVocal, confidence: 0.55, basis: "sound") }
            if voiceShape && (180...420).contains(p) && f.crestDB > 3 { return Result(kind: .femaleVocal, confidence: 0.5, basis: "sound") }
            if (190...1400).contains(p) && high > mid - 6 { return Result(kind: .violin, confidence: 0.45, basis: "sound") }
            if (65...400).contains(p) && lowMid > mid { return Result(kind: .cello, confidence: 0.4, basis: "sound") }
            if p > 500 && high < mid - 10 { return Result(kind: .flute, confidence: 0.4, basis: "sound") }
            return Result(kind: .keys, confidence: 0.3, basis: "sound")
        }
        if f.centroidHz > 1500 && f.crestDB < 14 && f.onsetRate > 2 { return Result(kind: .speech, confidence: 0.35, basis: "sound") }
        return Result(kind: .unknown, confidence: 0.2, basis: "sound")
    }

    /// Combines both. A recognised name wins unless the sound clearly contradicts its family.
    public static func classify(name: String, features: SignalFeatures?, choirContext: Bool = false) -> Result {
        let byName = kind(forName: name, choirContext: choirContext)
        guard let f = features, f.hasSignal else {
            return byName.map { Result(kind: $0, confidence: 0.75, basis: "name") } ?? Result(kind: .unknown, confidence: 0, basis: "—")
        }
        let bySound = kind(forSound: f)
        guard var named = byName else { return bySound }
        // Refine a generic vocal name by pitch.
        if named == .maleVocal, f.pitchHz > 175, f.harmonicity > 0.45 { named = .femaleVocal }
        if bySound.kind == named || bySound.kind.family == named.family || bySound.confidence < 0.55 {
            return Result(kind: named, confidence: min(0.95, 0.75 + (bySound.kind.family == named.family ? 0.2 : 0)), basis: "name + sound")
        }
        return Result(kind: named, confidence: 0.5, basis: "name (sound disagrees: \(bySound.kind.rawValue))")
    }
}
