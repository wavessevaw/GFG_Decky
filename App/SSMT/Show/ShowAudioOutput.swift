import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import SSMTAudio
import SSMTCore

/// Audio output of Qtrl: an AVAudioEngine source node on the chosen interface that pulls
/// every channel from the `ShowMixer`.
final class ShowAudioOutput {
    let engine = AVAudioEngine()
    let mixer: ShowMixer
    let sampleRate: Double
    let channelCount: Int
    let deviceName: String
    private var source: AVAudioSourceNode?
    private let channelPointers: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let silence: UnsafeMutablePointer<Float>
    private static let maxFrames = 8192

    enum OutputError: Error, CustomStringConvertible {
        case device(String), format, start(Error)
        var description: String {
            switch self {
            case let .device(name): return "Cannot use \(name)"
            case .format: return "Unsupported output format"
            case let .start(e): return "\(e.localizedDescription)"
            }
        }
    }

    init(deviceUID: String?, maxOutputs: Int) throws {
        let output = engine.outputNode
        var name = "System output"
        if let uid = deviceUID, let info = DeviceCatalog.device(uid: uid), info.outputChannels > 0 {
            var id = info.id
            guard let unit = output.audioUnit,
                  AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                       &id, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
                throw OutputError.device(info.name)
            }
            name = info.name
        } else if let id = DeviceCatalog.defaultDevice(input: false), let info = DeviceCatalog.info(for: id) {
            name = info.name
        }
        deviceName = name
        let hw = output.outputFormat(forBus: 0)
        sampleRate = hw.sampleRate > 0 ? hw.sampleRate : 48000
        channelCount = max(1, Int(hw.channelCount))
        mixer = ShowMixer(sampleRate: sampleRate, maxOutputs: maxOutputs)
        channelPointers = .allocate(capacity: channelCount)
        silence = .allocate(capacity: Self.maxFrames)
        silence.initialize(repeating: 0, count: Self.maxFrames)

        let format: AVAudioFormat?
        if channelCount <= 2 {
            format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channelCount))
        } else if let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channelCount)) {
            format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channelLayout: layout)
        } else {
            format = nil
        }
        guard let format else { throw OutputError.format }

        let mixer = self.mixer
        let pointers = channelPointers
        let count = channelCount
        let silence = self.silence
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let frames = Int(frameCount)
            for c in 0..<count {
                if c < buffers.count, let data = buffers[c].mData {
                    pointers[c] = data.assumingMemoryBound(to: Float.self)
                } else {
                    pointers[c] = silence // never more channels than buffers in practice
                }
            }
            mixer.render(UnsafePointer(pointers), channelCount: min(count, buffers.count), frames: min(frames, ShowAudioOutput.maxFrames))
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: output, format: format)
        engine.prepare()
        do { try engine.start() } catch { throw OutputError.start(error) }
    }

    func stop() {
        engine.stop()
        if let source { engine.detach(source) }
        source = nil
    }

    deinit {
        stop()
        channelPointers.deallocate()
        silence.deallocate()
    }
}

/// Decodes audio files into memory at the output sample rate. Thread-safe.
final class ClipCache: @unchecked Sendable {
    private var clips: [String: AudioClip] = [:]
    private var failed: [String: String] = [:]
    private let lock = NSLock()

    var totalBytes: Int { lock.lock(); defer { lock.unlock() }; return clips.values.reduce(0) { $0 + $1.bytes } }

    func cached(_ path: String, sampleRate: Double) -> AudioClip? {
        lock.lock(); defer { lock.unlock() }
        guard let c = clips[path], c.sampleRate == sampleRate else { return nil }
        return c
    }

    func failure(_ path: String) -> String? { lock.lock(); defer { lock.unlock() }; return failed[path] }

    func forget(except keep: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        clips = clips.filter { keep.contains($0.key) }
    }

    /// Loads (or returns the cached) clip. Slow: call off the main thread.
    @discardableResult
    func load(_ path: String, sampleRate: Double) -> AudioClip? {
        if let c = cached(path, sampleRate: sampleRate) { return c }
        do {
            let clip = try Self.decode(URL(fileURLWithPath: path), sampleRate: sampleRate)
            lock.lock(); clips[path] = clip; failed[path] = nil; lock.unlock()
            return clip
        } catch {
            lock.lock(); failed[path] = "\(error.localizedDescription)"; lock.unlock()
            return nil
        }
    }

    static func decode(_ url: URL, sampleRate: Double) throws -> AudioClip {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: input)
        var buffer = input
        if abs(inFormat.sampleRate - sampleRate) > 0.5 {
            guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                                channels: inFormat.channelCount, interleaved: false),
                  let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
                throw CocoaError(.fileReadUnsupportedScheme)
            }
            converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
            let capacity = AVAudioFrameCount(Double(frames) * sampleRate / inFormat.sampleRate) + 4096
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var fed = false
            var convError: NSError?
            let status = converter.convert(to: out, error: &convError) { _, outStatus in
                if fed { outStatus.pointee = .endOfStream; return nil }
                fed = true
                outStatus.pointee = .haveData
                return input
            }
            if status == .error { throw convError ?? CocoaError(.fileReadCorruptFile) }
            buffer = out
        }
        guard let data = buffer.floatChannelData else { throw CocoaError(.fileReadCorruptFile) }
        let n = Int(buffer.frameLength)
        let channels = (0..<Int(buffer.format.channelCount)).map { Array(UnsafeBufferPointer(start: data[$0], count: n)) }
        return AudioClip(sampleRate: sampleRate, channels: channels)
    }
}
