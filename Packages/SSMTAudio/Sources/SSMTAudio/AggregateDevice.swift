#if os(macOS)
import CoreAudio
import Foundation

/// Private aggregate device combining separate input and output interfaces on one clock
/// (output device = clock master, input device drift-compensated). Required for the
/// internal-reference mode when microphone and output are on different devices.
public final class AggregateDevice {
    public let deviceID: AudioDeviceID
    public let uid: String
    /// Offset of the input device's first input channel inside the aggregate.
    public let inputChannelOffset: Int
    /// Offset of the output device's first output channel inside the aggregate.
    public let outputChannelOffset: Int

    public init(inputUID: String, outputUID: String) throws {
        guard DeviceCatalog.device(uid: inputUID) != nil,
              let output = DeviceCatalog.device(uid: outputUID) else { throw AudioIOError.deviceNotFound }
        let uid = "com.soundsolutions.ssmt.aggregate.\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SSMT Measurement",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
                [kAudioSubDeviceUIDKey: inputUID, kAudioSubDeviceDriftCompensationKey: 1],
            ],
        ]
        var id = AudioDeviceID(0)
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &id), "Create aggregate device")
        deviceID = id
        self.uid = uid
        // Channels are concatenated in sub-device order: output device first, then input device.
        inputChannelOffset = output.inputChannels
        outputChannelOffset = 0
        // Give Core Audio a moment to publish the new device.
        for _ in 0..<50 where DeviceCatalog.device(uid: uid) == nil {
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    deinit {
        AudioHardwareDestroyAggregateDevice(deviceID)
    }
}
#endif
