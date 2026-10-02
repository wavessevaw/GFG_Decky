import Foundation
import SSMTCore

/// User's microphone calibration library and SPL calibration, persisted in Application Support.
/// The selection can be an imported individual file or a built-in typical profile.
struct CalibrationLibrary: Codable {
    var microphones: [MicrophoneCalibration] = []
    var selectedMicrophoneID: UUID?
    var spl: SPLCalibration?

    var selectedMicrophone: MicrophoneCalibration? {
        guard let id = selectedMicrophoneID else { return nil }
        return microphones.first { $0.id == id } ?? MicrophoneProfiles.profile(id: id)?.calibration
    }

    var selectedProfile: MicrophoneProfile? {
        selectedMicrophoneID.flatMap { MicrophoneProfiles.profile(id: $0) }
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
