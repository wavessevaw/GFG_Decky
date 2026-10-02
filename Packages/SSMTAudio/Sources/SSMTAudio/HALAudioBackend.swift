#if os(macOS)
import AudioToolbox
import CoreAudio
import Foundation
import SSMTCore

/// Channel routing for a duplex measurement session (0-based device channel indices).
public struct HALRouting: Equatable, Codable, Sendable {
    public var deviceUID: String
    public var microphoneChannel: Int
    /// Loopback / external reference input; nil in internal-reference mode (B).
    public var referenceChannel: Int?
    /// Output channels that carry the test signal (usually one, feeding the processor input).
    public var outputChannels: [Int]
    public var sampleRate: Double

    public init(deviceUID: String, microphoneChannel: Int = 0, referenceChannel: Int? = nil,
                outputChannels: [Int] = [0], sampleRate: Double = 48000) {
        self.deviceUID = deviceUID
        self.microphoneChannel = microphoneChannel
        self.referenceChannel = referenceChannel
        self.outputChannels = outputChannels
        self.sampleRate = sampleRate
    }
}

/// State touched by the real-time callbacks. Everything is preallocated; the callbacks never
/// allocate, lock, log or call into Objective-C.
final class HALRenderContext {
    var unit: AudioUnit?
    let inputRing: RealtimeRing
    let outputRing: RealtimeRing
    let control: GeneratorControl
    let bank: GeneratorBank
    let discontinuities: AtomicCounter
    let maxFrames: Int

    let inputList: UnsafeMutableAudioBufferListPointer
    let inputData: [UnsafeMutablePointer<Float>]
    let inputPointers: UnsafeMutablePointer<UnsafePointer<Float>?>
    let outputPointers: UnsafeMutablePointer<UnsafePointer<Float>?>
    var expectedInputTime: Float64 = -1
    var expectedOutputTime: Float64 = -1

    init(inputRing: RealtimeRing, outputRing: RealtimeRing, control: GeneratorControl, bank: GeneratorBank,
         discontinuities: AtomicCounter, maxFrames: Int) {
        self.inputRing = inputRing
        self.outputRing = outputRing
        self.control = control
        self.bank = bank
        self.discontinuities = discontinuities
        self.maxFrames = maxFrames
        inputList = AudioBufferList.allocate(maximumBuffers: 2)
        inputData = (0..<2).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames)
            p.initialize(repeating: 0, count: maxFrames)
            return p
        }
        for i in 0..<2 {
            inputList[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(maxFrames * 4),
                                       mData: UnsafeMutableRawPointer(inputData[i]))
        }
        inputPointers = .allocate(capacity: 2)
        inputPointers.initialize(repeating: nil, count: 2)
        outputPointers = .allocate(capacity: 1)
        outputPointers.initialize(repeating: nil, count: 1)
    }

    deinit {
        inputData.forEach { $0.deallocate() }
        free(inputList.unsafeMutablePointer)
        inputPointers.deallocate()
        outputPointers.deallocate()
    }

    @inline(__always)
    func checkContinuity(_ ts: UnsafePointer<AudioTimeStamp>, frames: UInt32, expected: inout Float64) {
        guard ts.pointee.mFlags.contains(.sampleTimeValid) else { return }
        let t = ts.pointee.mSampleTime
        if expected >= 0 && abs(t - expected) > 0.5 {
            discontinuities.increment()
        }
        expected = t + Float64(frames)
    }
}

private let inputCallback: AURenderCallback = { refCon, flags, timeStamp, _, frames, _ in
    let ctx = Unmanaged<HALRenderContext>.fromOpaque(refCon).takeUnretainedValue()
    guard let unit = ctx.unit, Int(frames) <= ctx.maxFrames else { return noErr }
    for i in 0..<2 { ctx.inputList[i].mDataByteSize = frames * 4 }
    let status = AudioUnitRender(unit, flags, timeStamp, 1, frames, ctx.inputList.unsafeMutablePointer)
    guard status == noErr else {
        ctx.discontinuities.increment()
        return status
    }
    ctx.checkContinuity(timeStamp, frames: frames, expected: &ctx.expectedInputTime)
    ctx.inputPointers[0] = UnsafePointer(ctx.inputData[0])
    ctx.inputPointers[1] = UnsafePointer(ctx.inputData[1])
    _ = ctx.inputRing.write(UnsafePointer(ctx.inputPointers), frames: Int(frames))
    return noErr
}

private let renderCallback: AURenderCallback = { refCon, _, timeStamp, _, frames, ioData in
    let ctx = Unmanaged<HALRenderContext>.fromOpaque(refCon).takeUnretainedValue()
    guard let ioData else { return noErr }
    let buffers = UnsafeMutableAudioBufferListPointer(ioData)
    guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
    ctx.bank.render(into: first, count: Int(frames), control: ctx.control)
    // Any further client buffers (should not exist with a 1-channel client format) get the same signal.
    if buffers.count > 1 {
        for i in 1..<buffers.count {
            if let d = buffers[i].mData { memcpy(d, first, Int(frames) * 4) }
        }
    }
    ctx.checkContinuity(timeStamp, frames: frames, expected: &ctx.expectedOutputTime)
    ctx.outputPointers[0] = UnsafePointer(first)
    _ = ctx.outputRing.write(UnsafePointer(ctx.outputPointers), frames: Int(frames))
    return noErr
}

/// Duplex Core Audio backend on one device (or one aggregate device) through AUHAL.
/// Input and output run on the same device clock, so the output→input offset stays constant
/// for the whole session — the basis of the internal-reference mode.
public final class HALAudioBackend: AudioIOBackend, @unchecked Sendable {
    public let routing: HALRouting
    public let sampleRate: Double
    public let inputRing: RealtimeRing
    public let outputRing: RealtimeRing
    public let generatorControl = GeneratorControl()
    public let generatorBank: GeneratorBankSpec
    public let discontinuities = AtomicCounter()
    public private(set) var isRunning = false
    public let displayName: String

    private let device: AudioDeviceInfo
    private let context: HALRenderContext
    private var unit: AudioUnit?
    /// Device events that break the constant output→input offset (overload, sample-rate change by
    /// another app, device gone). Each counts as a discontinuity, so the locked delay is re-measured.
    private var listeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    private static let watchedProperties: [AudioObjectPropertySelector] = [
        kAudioDeviceProcessorOverload, kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive,
    ]

    public init(routing: HALRouting, bank: GeneratorBankSpec = GeneratorBankSpec(),
                safety: GeneratorSafety = GeneratorSafety()) throws {
        guard let dev = DeviceCatalog.device(uid: routing.deviceUID) else { throw AudioIOError.deviceNotFound }
        guard routing.microphoneChannel < dev.inputChannels,
              (routing.referenceChannel ?? 0) < dev.inputChannels,
              !routing.outputChannels.isEmpty,
              routing.outputChannels.allSatisfy({ $0 < dev.outputChannels }) else {
            throw AudioIOError.channelOutOfRange
        }
        self.routing = routing
        device = dev
        sampleRate = routing.sampleRate
        displayName = dev.name
        generatorBank = bank
        let ringFrames = Int(routing.sampleRate * 4)
        inputRing = RealtimeRing(minimumFrames: ringFrames, channels: 2)
        outputRing = RealtimeRing(minimumFrames: ringFrames, channels: 1)
        let generators = GeneratorBank(spec: bank, sampleRate: routing.sampleRate, safety: safety,
                                       seed: UInt64(Date().timeIntervalSince1970 * 1000))
        context = HALRenderContext(inputRing: inputRing, outputRing: outputRing, control: generatorControl,
                                   bank: generators, discontinuities: discontinuities, maxFrames: 8192)
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard !isRunning else { return }
        try DeviceCatalog.setNominalSampleRate(device.id, sampleRate)

        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                             componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AudioIOError.osStatus("Find AUHAL", -1)
        }
        var newUnit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &newUnit), "Create AUHAL")
        guard let au = newUnit else { throw AudioIOError.osStatus("Create AUHAL", -1) }

        do {
            var one: UInt32 = 1
            let u32 = UInt32(MemoryLayout<UInt32>.size)
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, u32),
                      "Enable input")
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, u32),
                      "Enable output")
            var devID = device.id
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                           &devID, UInt32(MemoryLayout<AudioDeviceID>.size)), "Select device")

            var maxFrames = UInt32(context.maxFrames)
            try check(AudioUnitSetProperty(au, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                                           &maxFrames, u32), "Max frames")

            // Client formats: 2-channel input (mic, ref), 1-channel output, Float32 non-interleaved.
            var inFormat = Self.floatFormat(sampleRate: sampleRate, channels: 2)
            var outFormat = Self.floatFormat(sampleRate: sampleRate, channels: 1)
            let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                           &inFormat, asbdSize), "Input format")
            try check(AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                           &outFormat, asbdSize), "Output format")

            // Input channel map: client channel i ← device channel map[i].
            var inMap: [Int32] = [Int32(routing.microphoneChannel),
                                  Int32(routing.referenceChannel ?? routing.microphoneChannel)]
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Output, 1,
                                           &inMap, UInt32(inMap.count * 4)), "Input channel map")
            // Output channel map: one entry per device output channel; −1 = silent.
            var outMap = [Int32](repeating: -1, count: device.outputChannels)
            for c in routing.outputChannels { outMap[c] = 0 }
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_ChannelMap, kAudioUnitScope_Input, 0,
                                           &outMap, UInt32(outMap.count * 4)), "Output channel map")

            let refCon = Unmanaged.passUnretained(context).toOpaque()
            var inCB = AURenderCallbackStruct(inputProc: inputCallback, inputProcRefCon: refCon)
            try check(AudioUnitSetProperty(au, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                           &inCB, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "Input callback")
            var outCB = AURenderCallbackStruct(inputProc: renderCallback, inputProcRefCon: refCon)
            try check(AudioUnitSetProperty(au, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                                           &outCB, UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "Render callback")

            context.unit = au
            context.expectedInputTime = -1
            context.expectedOutputTime = -1
            inputRing.clear()
            outputRing.clear()
            try check(AudioUnitInitialize(au), "Initialize AUHAL")
            try check(AudioOutputUnitStart(au), "Start AUHAL")
        } catch {
            context.unit = nil
            AudioComponentInstanceDispose(au)
            throw error
        }
        unit = au
        isRunning = true
        installListeners()
    }

    public func stop() {
        guard let au = unit else { return }
        generatorControl.emergencyStop()
        AudioOutputUnitStop(au)
        AudioUnitUninitialize(au)
        context.unit = nil
        AudioComponentInstanceDispose(au)
        unit = nil
        isRunning = false
        removeListeners()
    }

    /// Output + input latency reported by the device (samples), for the expert view.
    public var reportedRoundTripLatency: Int {
        func latency(_ scope: AudioObjectPropertyScope) -> Int {
            var total = 0
            for sel in [kAudioDevicePropertyLatency, kAudioDevicePropertySafetyOffset] {
                var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
                var v: UInt32 = 0
                var size = UInt32(4)
                if AudioObjectGetPropertyData(device.id, &addr, 0, nil, &size, &v) == noErr { total += Int(v) }
            }
            return total
        }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyBufferFrameSize,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var buf: UInt32 = 0
        var size = UInt32(4)
        _ = AudioObjectGetPropertyData(device.id, &addr, 0, nil, &size, &buf)
        return latency(kAudioObjectPropertyScopeInput) + latency(kAudioObjectPropertyScopeOutput) + 2 * Int(buf)
    }

    private static func floatFormat(sampleRate: Double, channels: UInt32) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: channels,
            mBitsPerChannel: 32, mReserved: 0)
    }

    private func installListeners() {
        let counter = discontinuities
        for selector in Self.watchedProperties {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { _, _ in counter.increment() }
            if AudioObjectAddPropertyListenerBlock(device.id, &addr, DispatchQueue.global(qos: .utility), block) == noErr {
                listeners.append((selector, block))
            }
        }
    }

    private func removeListeners() {
        for (selector, block) in listeners {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                  mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(device.id, &addr, DispatchQueue.global(qos: .utility), block)
        }
        listeners = []
    }
}
#endif
