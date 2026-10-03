import XCTest
@testable import SSMTCore

final class ConsoleTestTests: XCTestCase {
    /// A short scenario keeps the test quick: a snare with two mics (bottom one physically inverted) and a singer.
    static let mini = AssistScenario(id: "mini", channels: [
        AssistScenario.ch("Snare Top", .snare, 190, .harsh, -26),
        AssistScenario.ch("Snare Btm", .snare, 190, .none, -28, same: 0, delay: 0.3, pol: -1),
        AssistScenario.ch("Vox Anna", .femaleVocal, 262, .mud, -42),
    ])

    func testFullRunAgainstTheEmulatedX32() async {
        let console = ConsoleEmulator(family: .x32)
        // Whatever the engineer had before the test.
        console.send([OSCMessage("/ch/05/config/name", [.string("Pastor")]), OSCMessage("/ch/05/mix/fader", [.float(0.6)]),
                      OSCMessage("/bus/02/mix/fader", [.float(0.7)])])
        let runner = ConsoleTestRunner(scenario: Self.mini, family: .x32, firstChannel: 5, transport: console)
        runner.windowSeconds = 1
        let checks = await runner.run()
        for c in checks { print("CHECK", c.id, c.status.rawValue, c.detail) }
        let byID = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0) })
        for id in ["connect", "backup", "names", "tuning", "polarity", "groups", "guard", "meters", "restore"] {
            XCTAssertEqual(byID[id]?.status, .ok, "\(id): \(byID[id]?.detail ?? "missing")")
        }
        // The snare bottom was inverted on the console during the test…
        XCTAssertTrue(console.received.contains { $0.address == "/ch/06/preamp/invert" && $0.arguments == [.int(1)] })
        // …the main output was muted and unmuted, and everything is back as it was.
        XCTAssertTrue(console.received.contains { $0.address == "/main/st/mix/on" && $0.arguments == [.int(0)] })
        XCTAssertEqual(console.values["/main/st/mix/on"], .int(1))
        XCTAssertEqual(console.values["/ch/05/config/name"], .string("Pastor"))
        XCTAssertEqual(console.values["/ch/06/preamp/invert"], .int(0))
        if case let .float(f)? = console.values["/bus/02/mix/fader"] { XCTAssertEqual(Double(f), 0.7, accuracy: 0.002) } else { XCTFail() }
    }

    func testReadbackSpotsAConsoleThatIgnoresAParameter() {
        var sent = ChannelStrip(id: 3, name: "Vox", gainDB: 30, highPassOn: true, highPassHz: 120)
        sent.eq[1] = StripEQBand(type: .peaking, frequency: 315, gainDB: -4, q: 2)
        XCTAssertTrue(ConsoleReadback.compare(sent: sent, read: ConsoleReadback.quantized(sent, family: .x32)).isEmpty)
        var read = ConsoleReadback.quantized(sent, family: .x32)
        read.eq[1].gainDB = 0
        XCTAssertEqual(ConsoleReadback.compare(sent: sent, read: read).map(\.parameter), ["eq2 dB"])
    }
}
