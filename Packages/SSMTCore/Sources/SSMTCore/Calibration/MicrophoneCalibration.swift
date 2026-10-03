import Foundation

/// Microphone magnitude calibration: an individual file imported by the user, or a built-in
/// typical curve (see `MicrophoneProfiles`). Only magnitude is applied (phase columns are ignored).
public struct MicrophoneCalibration: Equatable, Codable, Sendable, Identifiable {
    public enum Source: String, Codable, Sendable {
        /// Individual calibration file of this very microphone.
        case file
        /// Typical response of the model from published data (±2–3 dB).
        case typical
    }

    public var id: UUID
    public var name: String
    /// Ascending frequencies (Hz) and microphone response deviation (dB) at each.
    public var frequencies: [Double]
    public var deviationDB: [Double]
    /// Raw sensitivity header if the file had one (e.g. "Sens Factor =-1.378dB"), not interpreted.
    public var sensitivityHeader: String?
    /// Parsed numeric value of the header, in dB, if present.
    public var sensitivityDB: Double?
    public var serialNumber: String?
    /// nil in files saved before built-in profiles existed → treated as `.file`.
    public var source: Source?

    public var isTypical: Bool { source == .typical }

    public init(id: UUID = UUID(), name: String, frequencies: [Double], deviationDB: [Double],
                sensitivityHeader: String? = nil, sensitivityDB: Double? = nil, serialNumber: String? = nil,
                source: Source = .file) {
        self.id = id
        self.name = name
        self.frequencies = frequencies
        self.deviationDB = deviationDB
        self.sensitivityHeader = sensitivityHeader
        self.sensitivityDB = sensitivityDB
        self.serialNumber = serialNumber
        self.source = source
    }

    public enum ParseError: Error, Equatable {
        case noData
        case tooFewPoints(Int)
        case nonMonotonicFrequencies
    }

    /// Parses text files of the form "frequency  dB  [phase]" with optional header/comment lines.
    /// Accepts tab, space, comma or semicolon separators, comments starting with *, #, ; or ",
    /// and sensitivity headers like `"Sens Factor =-1.378dB, SERNO: 7023270"` or `Sensitivity: -37.2 dBFS`.
    public static func parse(_ text: String, name: String) throws -> MicrophoneCalibration {
        var points: [(Double, Double)] = []
        var header: String?
        var sens: Double?
        var serial: String?
        let sensPatterns = [
            #"Sens(?:itivity)?\s*Factor\s*[=:]\s*([-+]?\d+(?:[.,]\d+)?)\s*dB"#,
            #"Sensitivity\s*[=:]?\s*([-+]?\d+(?:[.,]\d+)?)\s*dB"#,
        ]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if header == nil {
                for pattern in sensPatterns {
                    if let r = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                        header = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"*#; "))
                        let m = String(line[r])
                        if let num = m.range(of: #"[-+]?\d+(?:[.,]\d+)?"#, options: .regularExpression) {
                            sens = Double(m[num].replacingOccurrences(of: ",", with: "."))
                        }
                        break
                    }
                }
            }
            if serial == nil, let r = line.range(of: #"SERNO\s*[:=]\s*([A-Za-z0-9-]+)"#, options: [.regularExpression, .caseInsensitive]) {
                serial = String(line[r]).components(separatedBy: CharacterSet(charactersIn: ":=")).last?
                    .trimmingCharacters(in: .whitespaces)
            }
            guard let first = line.first, first.isNumber || first == "." || first == "-" || first == "+" else { continue }
            let numbers = Self.numbers(in: line)
            guard numbers.count >= 2, numbers[0] > 0 else { continue }
            points.append((numbers[0], numbers[1]))
        }
        guard !points.isEmpty else { throw ParseError.noData }
        guard points.count >= 3 else { throw ParseError.tooFewPoints(points.count) }
        for i in 1..<points.count where points[i].0 <= points[i - 1].0 {
            throw ParseError.nonMonotonicFrequencies
        }
        return MicrophoneCalibration(name: name, frequencies: points.map(\.0), deviationDB: points.map(\.1),
                                     sensitivityHeader: header, sensitivityDB: sens, serialNumber: serial)
    }

    /// Splits a data line. Semicolon or whitespace separated → commas are decimal marks;
    /// otherwise commas separate fields (CSV).
    static func numbers(in line: String) -> [Double] {
        let fields: [Substring]
        if line.contains(";") || line.contains(where: { $0 == " " || $0 == "\t" }) {
            fields = line.split(whereSeparator: { $0 == ";" || $0 == " " || $0 == "\t" })
        } else {
            fields = line.split(separator: ",")
        }
        return fields.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    /// Microphone deviation at f (dB), linear interpolation in log frequency, clamped at the ends.
    public func deviation(at f: Double) -> Double {
        guard let first = frequencies.first, let last = frequencies.last else { return 0 }
        if f <= first { return deviationDB[0] }
        if f >= last { return deviationDB[deviationDB.count - 1] }
        var lo = 0, hi = frequencies.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if frequencies[mid] <= f { lo = mid } else { hi = mid }
        }
        let t = log(f / frequencies[lo]) / log(frequencies[hi] / frequencies[lo])
        return deviationDB[lo] + t * (deviationDB[hi] - deviationDB[lo])
    }

    /// Removes the microphone response from a measured transfer function (magnitude only).
    public func apply(to tf: TransferFunction) -> TransferFunction {
        var out = tf
        for i in tf.frequencies.indices {
            out.response[i] = tf.response[i] * Decibel.toAmplitude(-deviation(at: tf.frequencies[i]))
        }
        return out
    }
}
