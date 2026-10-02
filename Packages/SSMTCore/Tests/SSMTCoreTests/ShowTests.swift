import XCTest
@testable import SSMTCore

/// Mixer + engine driven together, as the app does (render blocks, engine ticks between them).
private final class ShowRig {
    let sr = 48000.0
    let mixer: ShowMixer
    let engine: ShowEngine
    var clips: [String: AudioClip] = [:]
    var ops: [MixerOp] = []
    let channels = 4
    var out: [[Float]]

    init(_ doc: ShowDocument) {
        let m = ShowMixer(sampleRate: 48000, maxOutputs: 8, maxVoices: 16)
        mixer = m
        out = Array(repeating: [], count: 4)
        var opsRef: [MixerOp] = []
        _ = opsRef
        engine = ShowEngine(document: doc, sampleRate: 48000, lookahead: 256, send: { _ in }, clipProvider: { _ in nil })
        engine.send = { [unowned self] op in self.ops.append(op); m.send(op) }
        engine.clipProvider = { [unowned self] cue in self.clips[cue.audio?.file ?? ""] }
        opsRef = []
    }

    var now: Int64 { Int64(mixer.framesRendered.value) }

    /// Renders `frames` frames in blocks of 256 and appends them to `out`.
    func run(_ frames: Int) {
        var left = frames
        let block = 256
        let bufs = (0..<channels).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: block) }
        defer { bufs.forEach { $0.deallocate() } }
        while left > 0 {
            let n = min(block, left)
            engine.advance(to: now)
            bufs.withUnsafeBufferPointer { mixer.render($0.baseAddress!, channelCount: channels, frames: n) }
            for c in 0..<channels { out[c] += Array(UnsafeBufferPointer(start: bufs[c], count: n)) }
            mixer.collectGarbage()
            left -= n
        }
    }

    func runSeconds(_ s: Double) { run(Int(s * sr)) }
}

private func constClip(_ value: Float, frames: Int, channels: Int = 2) -> AudioClip {
    AudioClip(sampleRate: 48000, channels: Array(repeating: Array(repeating: value, count: frames), count: channels))
}

private func audioCue(_ file: String, _ number: String, plays: Int = 1) -> Cue {
    var c = Cue.audio(file: file, number: number)
    c.audio?.plays = plays
    return c
}

final class ShowTests: XCTestCase {
    // MARK: Mixer

    func testMixerStartsOnExactFrameAndEndsAtRegionEnd() {
        let m = ShowMixer(sampleRate: 48000, maxOutputs: 4, maxVoices: 4)
        let clip = constClip(0.5, frames: 300)
        let setup = VoiceSetup(regionStart: 0, regionLength: 300, plays: 1, rate: 1, levelDB: 0,
                               outputLevelsDB: [0, 0], crosspointsDB: [[0, showSilenceDB], [showSilenceDB, 0]])
        m.send(.start(UUID(), clip: clip, setup: setup, at: 100))
        let bufs = (0..<2).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: 512) }
        defer { bufs.forEach { $0.deallocate() } }
        bufs.withUnsafeBufferPointer { m.render($0.baseAddress!, channelCount: 2, frames: 512) }
        XCTAssertEqual(bufs[0][99], 0)
        XCTAssertEqual(bufs[0][100], 0.5, accuracy: 1e-6)
        XCTAssertEqual(bufs[1][399], 0.5, accuracy: 1e-6)
        XCTAssertEqual(bufs[0][400], 0)
        XCTAssertEqual(m.framesRendered.value, 512)
    }

    func testMixerLoopsAndDevampEndsAfterCurrentIteration() {
        let m = ShowMixer(sampleRate: 48000, maxOutputs: 2, maxVoices: 4)
        let id = UUID()
        let clip = constClip(1, frames: 100, channels: 1)
        let setup = VoiceSetup(regionStart: 0, regionLength: 100, plays: 0, rate: 1, levelDB: 0,
                               outputLevelsDB: [0], crosspointsDB: [[0]])
        m.send(.start(id, clip: clip, setup: setup, at: 0))
        m.send(.devamp(id, at: 250)) // in iteration 3 → ends at 300
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: 600)
        defer { buf.deallocate() }
        var ptrs = [buf]
        ptrs.withUnsafeMutableBufferPointer { p in
            p.withMemoryRebound(to: UnsafeMutablePointer<Float>.self) { m.render(UnsafePointer($0.baseAddress!), channelCount: 1, frames: 600) }
        }
        _ = ptrs
        XCTAssertEqual(buf[299], 1, accuracy: 1e-6)
        XCTAssertEqual(buf[300], 0)
    }

    func testFadeCurvesReachTargets() {
        var r = LevelRamp(0)
        r.set(to: showSilenceDB, at: 0, frames: 1000, curve: .linearGain)
        XCTAssertEqual(r.gain(at: 500), 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.gain(at: 1000), 0)
        r = LevelRamp(-20)
        r.set(to: 0, at: 0, frames: 1000, curve: .linearDB)
        XCTAssertEqual(r.dB(at: 500), -10, accuracy: 1e-6)
        XCTAssertEqual(r.gain(at: 2000), 1, accuracy: 1e-9)
        XCTAssertEqual(FadeCurve.sCurve.shape(0.5), 0.5, accuracy: 1e-12)
    }

    // MARK: Engine

    func testGoHonoursPreWaitAndMovesPlayhead() {
        var doc = ShowDocument()
        var a = audioCue("a", "1"); a.preWait = 0.5
        let b = audioCue("a", "2")
        doc.lists[0].cues = [a, b]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(0.25, frames: 4800)
        XCTAssertEqual(rig.engine.playhead, a.id)
        rig.engine.go(now: rig.now)
        XCTAssertEqual(rig.engine.playhead, b.id)
        rig.runSeconds(1)
        guard case let .start(id, _, _, at)? = rig.ops.first else { return XCTFail("no start") }
        XCTAssertEqual(id, a.id)
        XCTAssertEqual(at, 256 + 24000)
        XCTAssertEqual(rig.out[0][Int(at) - 1], 0)
        XCTAssertEqual(rig.out[0][Int(at)], 0.25, accuracy: 1e-6)
    }

    func testAutoContinueChainIsSkippedByPlayhead() {
        var doc = ShowDocument()
        var a = audioCue("a", "1"); a.continueMode = .autoContinue; a.postWait = 0.1
        var b = audioCue("a", "2"); b.continueMode = .autoFollow
        let c = audioCue("a", "3")
        let d = audioCue("a", "4")
        doc.lists[0].cues = [a, b, c, d]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(0.1, frames: 4800) // 0.1 s
        rig.engine.go(now: rig.now)
        XCTAssertEqual(rig.engine.playhead, d.id, "playhead skips the continue chain")
        rig.runSeconds(1)
        let starts = rig.ops.compactMap { op -> (UUID, Int64)? in
            if case let .start(id, _, _, at) = op { return (id, at) } else { return nil }
        }
        XCTAssertEqual(starts.map(\.0), [a.id, b.id, c.id])
        XCTAssertEqual(starts[1].1 - starts[0].1, 4800, "auto-continue after post-wait")
        XCTAssertEqual(starts[2].1 - starts[1].1, 4800, "auto-follow at the end of the audio")
        XCTAssertFalse(rig.engine.isActive)
    }

    func testDoubleGoGuard() {
        var doc = ShowDocument()
        doc.lists[0].cues = [audioCue("a", "1"), audioCue("a", "2")]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(0.1, frames: 48000)
        XCTAssertTrue(rig.engine.go(now: 0))
        XCTAssertFalse(rig.engine.go(now: 100))
        XCTAssertTrue(rig.engine.go(now: 48000))
    }

    func testGroupModes() {
        var doc = ShowDocument()
        var g = Cue(kind: .group)
        g.groupMode = .simultaneous
        var k1 = audioCue("a", ""); k1.preWait = 0.1
        let k2 = audioCue("b", "")
        g.children = [k1, k2]
        var p = Cue(kind: .group)
        p.groupMode = .playlist
        p.children = [audioCue("a", ""), audioCue("b", "")]
        doc.lists[0].cues = [g, p]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(0.1, frames: 4800)
        rig.clips["b"] = constClip(0.1, frames: 2400)
        rig.engine.go(now: 0)
        rig.runSeconds(0.5)
        var starts = rig.ops.compactMap { op -> (UUID, Int64)? in
            if case let .start(id, _, _, at) = op { return (id, at) } else { return nil }
        }
        XCTAssertEqual(Set(starts.map(\.0)), [k1.id, k2.id])
        XCTAssertEqual(starts.first { $0.0 == k1.id }!.1 - starts.first { $0.0 == k2.id }!.1, 4800)
        XCTAssertFalse(rig.engine.isActive, "group ends with its last child")
        rig.ops.removeAll()
        rig.engine.go(now: rig.now)
        rig.runSeconds(0.5)
        starts = rig.ops.compactMap { op -> (UUID, Int64)? in
            if case let .start(id, _, _, at) = op { return (id, at) } else { return nil }
        }
        XCTAssertEqual(starts.map(\.0), p.children.map(\.id))
        XCTAssertEqual(starts[1].1 - starts[0].1, 4800, "playlist: next child at the end of the previous")
    }

    func testFadeCueFadesAndStops() {
        var doc = ShowDocument()
        let a = audioCue("a", "1", plays: 0)
        var f = Cue(kind: .fade, number: "2")
        f.target = a.id
        f.fade?.duration = 0.5
        f.fade?.curve = .linearGain
        doc.lists[0].cues = [a, f]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(1, frames: 4800)
        rig.engine.go(now: 0)
        rig.runSeconds(0.5)
        rig.engine.go(now: rig.now)
        let fadeStart = Int(rig.now) + 256
        rig.runSeconds(1)
        XCTAssertEqual(rig.out[0][fadeStart + 12000], 0.5, accuracy: 0.01)
        XCTAssertEqual(rig.out[0][fadeStart + 24100], 0)
        XCTAssertFalse(rig.engine.isActive, "stop when done ends the looping cue")
    }

    func testDevampPredictionMatchesAudio() {
        var doc = ShowDocument()
        var a = audioCue("a", "1", plays: 0)
        a.audio?.rate = 1.5
        var d = Cue(kind: .devamp, number: "2")
        d.target = a.id
        d.devampStartsNext = true
        let after = audioCue("b", "3")
        doc.lists[0].cues = [a, d, after]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(1, frames: 1000, channels: 1)
        rig.clips["b"] = constClip(0.5, frames: 1000, channels: 1)
        rig.engine.go(now: 0)
        rig.run(20000)
        rig.engine.go(now: rig.now)
        rig.run(4000)
        let lastLoud = rig.out[0].lastIndex { abs($0 - 1) < 1e-6 }!
        let next = rig.ops.compactMap { op -> Int64? in
            if case let .start(id, _, _, at) = op, id == after.id { return at } else { return nil }
        }.first!
        XCTAssertEqual(Int(next), lastLoud + 1, "next cue starts on the first frame after the loop")
    }

    func testPauseResumeShiftsEnd() {
        var doc = ShowDocument()
        var a = audioCue("a", "1"); a.continueMode = .autoFollow
        let b = audioCue("a", "2")
        doc.lists[0].cues = [a, b]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(0.1, frames: 4800)
        rig.engine.go(now: 0)
        rig.run(2048)
        rig.engine.pause(a.id, now: rig.now)
        rig.run(4800)
        XCTAssertTrue(rig.engine.snapshot(now: rig.now).running.first?.paused == true)
        rig.engine.resume(a.id, now: rig.now)
        rig.runSeconds(0.5)
        let starts = rig.ops.compactMap { op -> Int64? in
            if case let .start(_, _, _, at) = op { return at } else { return nil }
        }
        XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(starts[1] - starts[0], 4800 + 4800, "end moved by the pause length")
    }

    func testPanicFadesThenCuts() {
        var doc = ShowDocument()
        doc.lists[0].cues = [audioCue("a", "1", plays: 0)]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(1, frames: 4800)
        rig.engine.go(now: 0)
        rig.runSeconds(0.1)
        rig.engine.panic(now: rig.now)
        rig.runSeconds(0.2)
        XCTAssertTrue(rig.engine.isActive, "first panic fades")
        rig.engine.panic(now: rig.now)
        XCTAssertFalse(rig.engine.isActive, "second panic cuts")
        rig.run(512)
        XCTAssertEqual(rig.out[0].last, 0)
    }

    func testControlCues() {
        var doc = ShowDocument()
        let a = audioCue("a", "1", plays: 0)
        var stop = Cue(kind: .stop, number: "2"); stop.target = a.id
        var dis = Cue(kind: .disarm, number: "3"); dis.target = a.id
        var goTo = Cue(kind: .goTo, number: "4"); goTo.target = a.id
        doc.lists[0].cues = [a, stop, dis, goTo]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(1, frames: 4800)
        var changed = false
        rig.engine.documentChanged = { _ in changed = true }
        rig.engine.go(now: 0); rig.run(20000)
        rig.engine.go(now: rig.now); rig.run(20000)
        XCTAssertFalse(rig.engine.isActive)
        rig.engine.go(now: rig.now); rig.run(20000)
        XCTAssertTrue(changed)
        XCTAssertEqual(rig.engine.document.cue(a.id)?.armed, false)
        rig.engine.go(now: rig.now); rig.run(20000)
        XCTAssertEqual(rig.engine.playhead, a.id)
        rig.engine.go(now: rig.now); rig.run(20000)
        XCTAssertEqual(rig.ops.filter { if case .start = $0 { return true } else { return false } }.count, 1,
                       "disarmed cue does not play")
    }

    func testMissingFileIsReportedAndChainContinues() {
        var doc = ShowDocument()
        var a = audioCue("missing", "1"); a.continueMode = .autoFollow
        let b = audioCue("a", "2")
        doc.lists[0].cues = [a, b]
        let rig = ShowRig(doc)
        rig.clips["a"] = constClip(0.1, frames: 480)
        rig.engine.go(now: 0)
        rig.run(2048)
        XCTAssertEqual(rig.engine.problems[a.id], "error.show.missingFile")
        XCTAssertEqual(rig.ops.count, 1)
    }

    // MARK: Editing

    func testEditingOperations() {
        var doc = ShowDocument()
        let l = doc.lists[0].id
        let a = audioCue("a", "1"), b = audioCue("b", "2"), c = audioCue("c", "3")
        var f = Cue(kind: .fade); f.target = b.id
        doc.insert([a, b, c, f], after: nil, list: l)
        let g = doc.group([c.id, a.id], list: l)!
        XCTAssertEqual(doc.lists[0].cues.map(\.id), [g, b.id, f.id])
        XCTAssertEqual(doc.cue(g)?.children.map(\.id), [a.id, c.id])
        let copies = doc.duplicate([g], list: l)
        XCTAssertEqual(doc.lists[0].cues.count, 4)
        XCTAssertNotEqual(doc.cue(copies[0])?.children.first?.id, a.id)
        doc.ungroup(g, list: l)
        XCTAssertEqual(doc.lists[0].cues.prefix(2).map(\.id), [a.id, c.id])
        doc.delete([b.id])
        XCTAssertNil(doc.cue(f.id)?.target, "targets of deleted cues are cleared")
        doc.move(f.id, by: -1, list: l)
        doc.move([f.id], before: a.id, list: l)
        XCTAssertEqual(doc.lists[0].cues.first?.id, f.id)
        doc.renumber(list: l, start: 10, step: 10)
        XCTAssertEqual(doc.cue(f.id)?.number, "10")
        XCTAssertEqual(doc.cue(a.id)?.number, "20")
    }

    func testIssuesAndCodable() throws {
        var doc = ShowDocument(name: "Test")
        var a = audioCue("a.wav", "1"); a.hotkey = "q"
        var b = audioCue("b.wav", "1"); b.hotkey = "Q"
        let s = Cue(kind: .stop)
        b.audio?.end = 0
        doc.lists[0].cues = [a, b, s, Cue(kind: .group)]
        let issues = doc.issues { $0.audio?.file == "a.wav" }
        XCTAssertTrue(issues.contains(.missingFile(b.id)))
        XCTAssertTrue(issues.contains(.missingTarget(s.id)))
        XCTAssertTrue(issues.contains(.duplicateNumber("1")))
        XCTAssertTrue(issues.contains(.duplicateHotkey("q")))
        XCTAssertTrue(issues.contains(.invalidRegion(b.id)))
        let back = try ShowDocument.decode(doc.encoded())
        XCTAssertEqual(back, doc)
        // Older / partial files decode with defaults.
        let minimal = #"{"lists":[{"id":"\#(UUID())","name":"L","cues":[{"id":"\#(UUID())","kind":"memo"}]}]}"#
        let m = try ShowDocument.decode(Data(minimal.utf8))
        XCTAssertEqual(m.lists[0].cues[0].armed, true)
    }
}
