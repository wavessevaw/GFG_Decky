#if os(macOS)
import CoreAudio
import Foundation

public struct AudioDeviceInfo: Identifiable, Hashable, Sendable {
    public var id: AudioDeviceID
    public var uid: String
    public var name: String
    public var inputChannels: Int
    public var outputChannels: Int
    public var nominalSampleRate: Double
    public var availableSampleRates: [Double]
    public var isAggregate: Bool

    public var isDuplex: Bool { inputChannels > 0 && outputChannels > 0 }

    public func supports(sampleRate: Double) -> Bool {
        availableSampleRates.contains { abs($0 - sampleRate) < 0.5 }
    }
}

public enum AudioIOError: Error, CustomStringConvertible {
    case osStatus(String, OSStatus)
    case deviceNotFound
    case sampleRateUnsupported(Double)
    case channelOutOfRange

    public var description: String {
        switch self {
        case .osStatus(let what, let status): return "\(what) failed (OSStatus \(status))"
        case .deviceNotFound: return "Audio device not found"
        case .sampleRateUnsupported(let sr): return "Device cannot run at \(Int(sr)) Hz"
        case .channelOutOfRange: return "Selected channel does not exist on the device"
        }
    }
}

@inline(__always)
func check(_ status: OSStatus, _ what: String) throws {
    if status != noErr { throw AudioIOError.osStatus(what, status) }
}

/// Enumerates Core Audio devices and their capabilities.
public enum DeviceCatalog {
    public static func allDevices() -> [AudioDeviceInfo] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.compactMap(info(for:))
    }

    public static func info(for id: AudioDeviceID) -> AudioDeviceInfo? {
        guard let name = stringProperty(id, kAudioObjectPropertyName),
              let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
        let transport = uint32Property(id, kAudioDevicePropertyTransportType) ?? 0
        return AudioDeviceInfo(
            id: id, uid: uid, name: name,
            inputChannels: channelCount(id, scope: kAudioObjectPropertyScopeInput),
            outputChannels: channelCount(id, scope: kAudioObjectPropertyScopeOutput),
            nominalSampleRate: nominalSampleRate(id) ?? 0,
            availableSampleRates: availableSampleRates(id),
            isAggregate: transport == kAudioDeviceTransportTypeAggregate)
    }

    public static func device(uid: String) -> AudioDeviceInfo? {
        allDevices().first { $0.uid == uid }
    }

    public static func defaultDevice(input: Bool) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    public static func nominalSampleRate(_ id: AudioDeviceID) -> Double? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &rate) == noErr else { return nil }
        return rate
    }

    /// Sets the device nominal sample rate and waits briefly for it to take effect.
    public static func setNominalSampleRate(_ id: AudioDeviceID, _ rate: Double) throws {
        if let current = nominalSampleRate(id), abs(current - rate) < 0.5 { return }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value = Float64(rate)
        try check(AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float64>.size), &value),
                  "Set sample rate")
        for _ in 0..<50 {
            if let current = nominalSampleRate(id), abs(current - rate) < 0.5 { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        throw AudioIOError.sampleRateUnsupported(rate)
    }

    static func availableSampleRates(_ id: AudioDeviceID) -> [Double] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &ranges) == noErr else { return [] }
        let common: [Double] = [44100, 48000, 88200, 96000, 176400, 192000]
        return common.filter { r in ranges.contains { r >= $0.mMinimum - 0.5 && r <= $0.mMaximum + 0.5 } }
    }

    static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, list) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    static func uint32Property(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
#endif
