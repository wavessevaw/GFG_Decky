import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import SSMTAudio

/// Multichannel input for FOH Assist: the console's USB / Dante card (one interface input per console
/// channel) and the measurement microphone. Keeps the last few seconds of every input so the assistant
/// can read a 2-second window of any channel.
final class AssistCapture {
    let engine = AVAudioEngine()
    let sampleRate: Double
    let channelCount: Int
    let deviceName: String
    private let lock = NSLock()
    private var rings: [[Float]]
    private var writePos = 0
    private let capacity: Int

    enum CaptureError: Error, CustomStringConvertible {
        case device(String), noInputs, start(Error)
        var description: String {
            switch self {
            case let .device(n): return "Cannot use \(n)"
            case .noInputs: return "The device has no inputs"
            case let .start(e): return e.localizedDescription
            }
        }
    }

    init(deviceUID: String?, seconds: Double = 4) throws {
        let input = engine.inputNode
        var name = "System input"
        if let uid = deviceUID, let info = DeviceCatalog.device(uid: uid), info.inputChannels > 0 {
            var id = info.id
            guard let unit = input.audioUnit,
                  AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                       &id, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
                throw CaptureError.device(info.name)
            }
            name = info.name
        } else if let id = DeviceCatalog.defaultDevice(input: true), let info = DeviceCatalog.info(for: id) {
            name = info.name
        }
        deviceName = name
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw CaptureError.noInputs }
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 48000
        channelCount = Int(format.channelCount)
        capacity = Int(sampleRate * seconds)
        rings = Array(repeating: [Float](repeating: 0, count: capacity), count: channelCount)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.store(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { throw CaptureError.start(error) }
    }

    private func store(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        let chans = min(channelCount, Int(buffer.format.channelCount))
        lock.lock()
        defer { lock.unlock() }
        for c in 0..<chans {
            let src = data[c]
            var p = writePos
            for i in 0..<n {
                rings[c][p] = src[i]
                p += 1
                if p == capacity { p = 0 }
            }
        }
        writePos = (writePos + n) % capacity
    }

    /// The last `seconds` of input `index` (1-based), oldest sample first.
    func latest(input index: Int, seconds: Double = 2) -> [Float]? {
        let c = index - 1
        guard c >= 0, c < channelCount else { return nil }
        let n = min(capacity, Int(seconds * sampleRate))
        lock.lock()
        defer { lock.unlock() }
        var out = [Float](repeating: 0, count: n)
        var p = (writePos - n + capacity) % capacity
        for i in 0..<n {
            out[i] = rings[c][p]
            p += 1
            if p == capacity { p = 0 }
        }
        return out
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
