import Foundation
import SSMTCore

/// User's microphone calibration library and SPL calibration, persisted in Application Support.
/// Contains only files imported by the user — no built-in microphone data.
struct CalibrationLibrary: Codable {
    var microphones: [MicrophoneCalibration] = []
    var selectedMicrophoneID: UUID?
    var spl: SPLCalibration?

    var selectedMicrophone: MicrophoneCalibration? {
        microphones.first { $0.id == selectedMicrophoneID }
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SSMT", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("calibration.json")
    }

    static func load() -> CalibrationLibrary {
        guard let data = try? Data(contentsOf: fileURL),
              let lib = try? JSONDecoder().decode(CalibrationLibrary.self, from: data) else { return CalibrationLibrary() }
        return lib
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
