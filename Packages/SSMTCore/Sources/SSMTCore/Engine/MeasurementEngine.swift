import Foundation

/// Immutable state published to the UI and the mini window.
public struct LiveSnapshot: Sendable {
    public var timestamp: Date
    public var transfer: TransferFunction?
    public var microphone: ChannelMeter
    public var referenceInput: ChannelMeter
    public var generatorLevelDBFS: Double
    public var referenceMode: ReferenceMode
    public var referenceDelaySeconds: Double
    public var overflowCount: UInt64
    public var discontinuities: UInt64
    public var capture: CaptureProgress?
}

public struct CaptureProgress: Equatable, Sendable {
    public var label: String
    public var elapsed: Double
    public var duration: Double
    public var fraction: Double { duration > 0 ? min(1, elapsed / duration) : 0 }
}

/// Result of a fixed-length cumulative measurement ("capture").
public struct Capture: Identifiable, Codable, Sendable {
    public var id: UUID
    public var label: String
    public var date: Date
    public var duration: Double
    public var transfer: TransferFunction
    public var assessment: CaptureAssessment
    public var referenceMode: ReferenceMode

    public init(id: UUID = UUID(), label: String, date: Date = Date(), duration: Double,
                transfer: TransferFunction, assessment: CaptureAssessment, referenceMode: ReferenceMode) {
        self.id = id
        self.label = label
        self.date = date
        self.duration = duration
        self.transfer = transfer
        self.assessment = assessment
        self.referenceMode = referenceMode
    }
}

/// Consumer side of the measurement chain. Runs on its own serial queue, independent of any window:
/// minimizing or closing UI never interrupts averaging.
public final class MeasurementEngine: @unchecked Sendable {
    public struct Configuration: Sendable {
        public var referenceMode: ReferenceMode = .internalSignal
        public var liveAveragingSeconds: Double = 1.5
        public var clipThresholdDBFS: Double = -0.1
        public var snapshotInterval: Double = 0.1
        public var qualityBand: ClosedRange<Double> = 40...16000
        public init() {}
    }

    public let backend: AudioIOBackend
    public private(set) var configuration: Configuration

    private let queue = DispatchQueue(label: "SSMT.MeasurementEngine", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var live: MultiWindowAnalyzer
    private var captureAnalyzer: MultiWindowAnalyzer?
    private var captureState: (label: String, duration: Double, elapsed: Double, clipped: Bool,
                               discontinuitiesAtStart: UInt64,
                               completion: (Capture) -> Void)?
    private var micMeter: MeterAccumulator
    private var refMeter: MeterAccumulator
    private var referenceDelay = 0
    private var lastSnapshotTime = Date.distantPast
    private var snapshotHandler: (@Sendable (LiveSnapshot) -> Void)?

    public init(backend: AudioIOBackend, configuration: Configuration = Configuration()) {
        self.backend = backend
        self.configuration = configuration
        live = MultiWindowAnalyzer(config: .standard(sampleRate: backend.sampleRate,
                                                     averaging: .exponential(timeConstant: configuration.liveAveragingSeconds)))
        micMeter = MeterAccumulator(clipThresholdDBFS: configuration.clipThresholdDBFS, sampleRate: backend.sampleRate)
        refMeter = MeterAccumulator(clipThresholdDBFS: configuration.clipThresholdDBFS, sampleRate: backend.sampleRate)
    }

    /// Snapshot callback, invoked on the engine queue. Hop to the main actor in the UI layer.
    public func setSnapshotHandler(_ handler: (@Sendable (LiveSnapshot) -> Void)?) {
        queue.async { self.snapshotHandler = handler }
    }

    public func start() throws {
        try backend.start()
        queue.async { self.startTimer() }
    }

    public func stop() {
        queue.async {
            self.timer?.cancel()
            self.timer = nil
        }
        backend.generatorControl.emergencyStop()
        backend.stop()
    }

    /// STOP from any state: silences the output on the next audio buffer.
    public func emergencyStop() {
        backend.generatorControl.emergencyStop()
    }

    public func setReferenceMode(_ mode: ReferenceMode) {
        queue.async {
            self.configuration.referenceMode = mode
            self.live.reset()
        }
    }

    /// Locks the reference delay (samples) used for every subsequent analysis.
    public func setReferenceDelay(samples: Int) {
        queue.async {
            self.referenceDelay = max(0, samples)
            self.live.setReferenceDelay(samples: self.referenceDelay)
        }
    }

    public func resetLiveAverages() { queue.async { self.live.reset() } }
    public func resetClipIndicators() {
        queue.async {
            self.micMeter.resetClip()
            self.refMeter.resetClip()
        }
    }

    /// Starts a cumulative capture of `duration` seconds. The completion runs on the engine queue.
    public func capture(label: String, duration: Double, completion: @escaping (Capture) -> Void) {
        queue.async {
            let a = MultiWindowAnalyzer(config: .standard(sampleRate: self.backend.sampleRate))
            a.setReferenceDelay(samples: self.referenceDelay)
            self.captureAnalyzer = a
            self.captureState = (label, duration, 0, false, self.backend.discontinuities.value, completion)
        }
    }

    public func cancelCapture() {
        queue.async {
            self.captureAnalyzer = nil
            self.captureState = nil
        }
    }

    /// Processes everything that is currently buffered (also used by tests to drive the engine synchronously).
    public func drainNow() {
        queue.sync { self.process() }
    }

    // MARK: - Processing

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(5))
        t.setEventHandler { [weak self] in self?.process() }
        t.resume()
        timer = t
    }

    private func process() {
        let chunk = 8192
        while true {
            let n = min(backend.inputRing.readable, backend.outputRing.readable, chunk)
            if n <= 0 { break }
            let input = backend.inputRing.read(maxFrames: n)
            let output = backend.outputRing.read(maxFrames: n)
            let mic = input[0]
            let refIn = input[1]
            let reference = configuration.referenceMode == .internalSignal ? output[0] : refIn
            micMeter.process(mic)
            refMeter.process(refIn)
            live.ingest(reference: reference, measurement: mic)
            if let a = captureAnalyzer, var st = captureState {
                a.ingest(reference: reference, measurement: mic)
                st.elapsed += Double(mic.count) / backend.sampleRate
                if mic.contains(where: { abs($0) >= micMeter.clipThreshold }) { st.clipped = true }
                captureState = st
                if st.elapsed >= st.duration { finishCapture() }
            }
        }
        let now = Date()
        if now.timeIntervalSince(lastSnapshotTime) >= configuration.snapshotInterval {
            lastSnapshotTime = now
            publishSnapshot(now)
        }
    }

    private func finishCapture() {
        guard let a = captureAnalyzer, let st = captureState else { return }
        let tf = a.snapshot()
        let discontinuity = backend.discontinuities.value != st.discontinuitiesAtStart
        let assessment = CaptureAssessment.assess(tf, band: configuration.qualityBand, clipped: st.clipped,
                                                  discontinuity: discontinuity)
        let capture = Capture(label: st.label, duration: st.elapsed, transfer: tf, assessment: assessment,
                              referenceMode: configuration.referenceMode)
        captureAnalyzer = nil
        captureState = nil
        st.completion(capture)
    }

    private func publishSnapshot(_ now: Date) {
        guard let handler = snapshotHandler else { return }
        let tf = live.averages > 0 ? live.snapshot() : nil
        let progress = captureState.map { CaptureProgress(label: $0.label, elapsed: $0.elapsed, duration: $0.duration) }
        let snap = LiveSnapshot(
            timestamp: now, transfer: tf, microphone: micMeter.read(), referenceInput: refMeter.read(),
            generatorLevelDBFS: Double(backend.generatorControl.currentLevelDBFS.value),
            referenceMode: configuration.referenceMode,
            referenceDelaySeconds: Double(referenceDelay) / backend.sampleRate,
            overflowCount: backend.inputRing.overflowCount + backend.outputRing.overflowCount,
            discontinuities: backend.discontinuities.value, capture: progress)
        handler(snap)
    }
}
