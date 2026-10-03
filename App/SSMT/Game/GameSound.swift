import AVFoundation
import Foundation
import SSMTCore

/// Chip-style sound for the hidden game: square / triangle / noise voices like a 16-bit console,
/// plus a looping bass-and-drums groove. Synthesised in real time; no audio files.
final class GameSound: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let lock = NSLock()
    private var voices: [Voice] = []
    private var musicOn = true
    private var sampleRate = 44100.0
    private var musicPos = 0.0

    enum Wave { case square(Double), triangle, noise }

    struct Voice {
        var wave: Wave
        var f0: Double, f1: Double
        var length: Double
        var t = 0.0
        var phase = 0.0
        var gain: Double
        var noise: UInt32 = 0x1234567
        var held = 0.0
    }

    func start() {
        guard node == nil else { return }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        sampleRate = fmt.sampleRate
        let n = AVAudioSourceNode(format: fmt) { [weak self] _, _, frames, abl -> OSStatus in
            guard let self else { return noErr }
            let buf = UnsafeMutableAudioBufferListPointer(abl)[0]
            guard let out = buf.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.render(out, Int(frames))
            return noErr
        }
        node = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.5
        try? engine.start()
    }

    func stop() {
        engine.stop()
        if let node { engine.detach(node) }
        node = nil
    }

    func setMusic(_ on: Bool) { lock.lock(); musicOn = on; lock.unlock() }

    private func add(_ v: Voice) {
        lock.lock()
        if voices.count > 12 { voices.removeFirst() }
        voices.append(v)
        lock.unlock()
    }

    func play(_ e: GameEvent) {
        switch e {
        case .jump: add(Voice(wave: .square(0.25), f0: 300, f1: 720, length: 0.12, gain: 0.18))
        case .punch: add(Voice(wave: .noise, f0: 1800, f1: 600, length: 0.06, gain: 0.16))
        case .kick: add(Voice(wave: .noise, f0: 900, f1: 200, length: 0.1, gain: 0.2))
        case .hit: add(Voice(wave: .noise, f0: 2400, f1: 300, length: 0.09, gain: 0.32)); add(Voice(wave: .square(0.5), f0: 160, f1: 70, length: 0.08, gain: 0.2))
        case .bigHit: add(Voice(wave: .noise, f0: 3000, f1: 200, length: 0.16, gain: 0.38)); add(Voice(wave: .square(0.5), f0: 120, f1: 45, length: 0.15, gain: 0.25))
        case .hurt: add(Voice(wave: .square(0.5), f0: 520, f1: 140, length: 0.22, gain: 0.22))
        case .enemyDown: add(Voice(wave: .noise, f0: 700, f1: 60, length: 0.4, gain: 0.3)); add(Voice(wave: .triangle, f0: 110, f1: 40, length: 0.4, gain: 0.35))
        case .pickup: for (i, f) in [660.0, 880, 1320].enumerated() { var v = Voice(wave: .square(0.25), f0: f, f1: f, length: 0.06 + Double(i) * 0.06, gain: 0.14); v.held = Double(i) * 0.06; add(v) }
        case .heal: for (i, f) in [523.0, 659, 784, 1046].enumerated() { var v = Voice(wave: .triangle, f0: f, f1: f, length: 0.08 + Double(i) * 0.07, gain: 0.25); v.held = Double(i) * 0.07; add(v) }
        case .cableOn: add(Voice(wave: .square(0.125), f0: 200, f1: 1600, length: 0.3, gain: 0.15))
        case .strobe: for i in 0..<5 { var v = Voice(wave: .noise, f0: 6000, f1: 6000, length: 0.03 + Double(i) * 0.08, gain: 0.2); v.held = Double(i) * 0.08; add(v) }
        case .shout: add(Voice(wave: .square(0.5), f0: 330, f1: 290, length: 0.35, gain: 0.12))
        case .bossRoar: add(Voice(wave: .square(0.5), f0: 90, f1: 60, length: 0.6, gain: 0.25)); add(Voice(wave: .square(0.125), f0: 2200, f1: 2600, length: 0.6, gain: 0.08))
        case .panelClear: for (i, f) in [784.0, 988, 1175].enumerated() { var v = Voice(wave: .square(0.5), f0: f, f1: f, length: 0.09 + Double(i) * 0.09, gain: 0.12); v.held = Double(i) * 0.09; add(v) }
        case .panelSlide: add(Voice(wave: .noise, f0: 1200, f1: 3000, length: 0.35, gain: 0.08))
        case .pageTurn: add(Voice(wave: .noise, f0: 800, f1: 4000, length: 0.7, gain: 0.12))
        case .gameOver: for (i, f) in [392.0, 330, 262, 196].enumerated() { var v = Voice(wave: .triangle, f0: f, f1: f * 0.98, length: 0.25 + Double(i) * 0.25, gain: 0.3); v.held = Double(i) * 0.25; add(v) }
        case .victory: for (i, f) in [523.0, 659, 784, 1046, 784, 1046].enumerated() { var v = Voice(wave: .square(0.25), f0: f, f1: f, length: 0.12 + Double(i) * 0.12, gain: 0.14); v.held = Double(i) * 0.12; add(v) }
        case .step: add(Voice(wave: .noise, f0: 400, f1: 200, length: 0.02, gain: 0.04))
        }
    }

    // MARK: Synthesis (audio thread)

    private func render(_ out: UnsafeMutablePointer<Float>, _ n: Int) {
        lock.lock()
        let music = musicOn
        for i in 0..<n {
            var s = 0.0
            for k in voices.indices {
                if voices[k].held > 0 { voices[k].held -= 1 / sampleRate; continue }
                let v = voices[k]
                let p = min(1, v.t / v.length)
                let f = v.f0 + (v.f1 - v.f0) * p
                let env = (1 - p) * (1 - p)
                var x: Double
                switch v.wave {
                case let .square(duty): x = v.phase < duty ? 1 : -1
                case .triangle: x = v.phase < 0.5 ? v.phase * 4 - 1 : 3 - v.phase * 4
                case .noise:
                    var r = voices[k].noise
                    r ^= r << 13; r ^= r >> 17; r ^= r << 5
                    voices[k].noise = r
                    x = Double(r & 0xFFFF) / 32768 - 1
                }
                s += x * env * v.gain
                voices[k].phase += f / sampleRate
                if voices[k].phase >= 1 { voices[k].phase -= 1 }
                voices[k].t += 1 / sampleRate
            }
            if music { s += groove() }
            out[i] = Float(max(-1, min(1, s)))
        }
        voices.removeAll { $0.held <= 0 && $0.t >= $0.length }
        lock.unlock()
    }

    /// Two-bar minor groove at 128 BPM: square bass, noise hats and a soft kick.
    private func groove() -> Double {
        let bpm = 128.0
        let step = 60 / bpm / 4                          // sixteenth note
        let pos = musicPos
        musicPos += 1 / sampleRate
        let index = Int(pos / step) % 32
        let tIn = pos.truncatingRemainder(dividingBy: step)
        let bass: [Double] = [55, 0, 55, 65.4, 0, 55, 73.4, 0, 49, 0, 49, 58.3, 0, 49, 65.4, 0,
                              55, 0, 55, 65.4, 0, 82.4, 73.4, 0, 49, 0, 61.7, 58.3, 0, 49, 41.2, 0]
        var s = 0.0
        let f = bass[index]
        if f > 0 && tIn < step * 0.8 {
            let ph = (pos * f).truncatingRemainder(dividingBy: 1)
            s += (ph < 0.5 ? 1 : -1) * 0.05 * (1 - tIn / step)
        }
        if index % 2 == 1 && tIn < 0.02 { // hats
            s += (Double(Int(pos * 99991) % 200) / 100 - 1) * 0.025 * (1 - tIn / 0.02)
        }
        if index % 8 == 0 && tIn < 0.08 { // kick
            s += sin(2 * .pi * (60 + 120 * (1 - tIn / 0.08)) * tIn) * 0.12 * (1 - tIn / 0.08)
        }
        if index % 8 == 4 && tIn < 0.06 { // snare
            s += (Double(Int(pos * 77777) % 200) / 100 - 1) * 0.05 * (1 - tIn / 0.06)
        }
        return s
    }
}
