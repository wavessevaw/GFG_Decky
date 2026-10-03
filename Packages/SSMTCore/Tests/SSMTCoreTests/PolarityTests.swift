import XCTest
@testable import SSMTCore

final class PolarityTests: XCTestCase {
    func testPairsAreFoundFromNames() {
        let names = ["Kick In", "Kick Out", "Snare Top", "Snare Bottom", "OH L", "OH R", "Bass DI", "Bass Mic",
                     "Vox 1", "Vox 2", "Gtr L", "Gtr R", "Keys"]
        let strips = names.enumerated().map { ChannelStrip(id: $0.offset + 1, name: $0.element) }
        let pairs = PolarityPairs.find(in: strips)
        XCTAssertEqual(pairs, [PolarityPair(reference: 1, test: 2), PolarityPair(reference: 3, test: 4), PolarityPair(reference: 5, test: 6),
                               PolarityPair(reference: 7, test: 8), PolarityPair(reference: 11, test: 12)])
        // Two singers are never a pair; overheads go against the snare when they are a single mic.
        let kit = ["Snare", "OH"].enumerated().map { ChannelStrip(id: $0.offset + 1, name: $0.element) }
        XCTAssertEqual(PolarityPairs.find(in: kit), [PolarityPair(reference: 1, test: 2)])
    }

    func testCodecSendsAndReadsPolarity() {
        var s = ChannelStrip(id: 18, name: "Snare Bottom")
        let base = s
        s.polarityInverted = true
        let m = X32Codec.messages(from: base, to: s, family: .x32)
        XCTAssertEqual(m, [OSCMessage("/ch/18/preamp/invert", [.int(1)])])
        var strips = [18: base]
        X32Codec.apply(m[0], to: &strips, family: .x32)
        XCTAssertTrue(strips[18]!.polarityInverted)
    }

    /// Runs the check in the simulator with only the given channels audible.
    func run(_ pair: PolarityPair, seed: UInt64 = 7) -> (SimulatedConsole, AssistSession) {
        let console = SimulatedConsole.demo(seed: seed)
        for (ch, s) in console.strips where ch != pair.reference && ch != pair.test { var m = s; m.muted = true; console.setStrip(m) }
        let session = AssistSession(strips: Array(console.strips.values), character: .rock)
        XCTAssertEqual(session.startPolarity([pair]), [pair])
        var steps = 0
        while session.isRunning && steps < 40 {
            let r = console.render(seconds: 1, channels: [pair.reference, pair.test])
            for s in session.tick(taps: r.taps, mic: r.mic) { console.setStrip(s) }
            steps += 1
        }
        XCTAssertFalse(session.isRunning)
        return (console, session)
    }

    func testSnareBottomGetsInverted() {
        let (console, session) = run(PolarityPair(reference: 2, test: 18))
        XCTAssertTrue(console.strips[18]!.polarityInverted)
        XCTAssertFalse(console.strips[2]!.polarityInverted)
        XCTAssertEqual(console.strips[18]!.faderDB, -10)   // faders back where they were
        guard case let .invert(d)? = session.polarity?.results[PolarityPair(reference: 2, test: 18)] else { return XCTFail("\(String(describing: session.polarity?.results))") }
        XCTAssertGreaterThan(d, 2)
    }

    func testKickOutStaysNormal() {
        let (console, session) = run(PolarityPair(reference: 1, test: 17))
        XCTAssertFalse(console.strips[17]!.polarityInverted)
        guard case .keep? = session.polarity?.results[PolarityPair(reference: 1, test: 17)] else { return XCTFail("\(String(describing: session.polarity?.results))") }
    }

    func testUnrelatedSourcesAreLeftAlone() {
        // Vocal against guitar: flipping changes nothing in the sum, so nothing is changed.
        let (console, session) = run(PolarityPair(reference: 7, test: 5))
        XCTAssertFalse(console.strips[5]!.polarityInverted)
        guard case .unclear? = session.polarity?.results[PolarityPair(reference: 7, test: 5)] else { return XCTFail("\(String(describing: session.polarity?.results))") }
    }

    func testDecisionsHoldAcrossTakes() {
        for seed: UInt64 in [1, 2, 3, 11, 23, 42] {
            XCTAssertTrue(run(PolarityPair(reference: 2, test: 18), seed: seed).0.strips[18]!.polarityInverted, "snare, take \(seed)")
            XCTAssertFalse(run(PolarityPair(reference: 7, test: 5), seed: seed).0.strips[5]!.polarityInverted, "unrelated, take \(seed)")
        }
    }
}
