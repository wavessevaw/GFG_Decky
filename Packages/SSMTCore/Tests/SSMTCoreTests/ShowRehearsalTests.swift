import XCTest
@testable import SSMTCore

final class ShowRehearsalTests: XCTestCase {
    func testWholeShowEngineerRidesAndGuardReacts() {
        let console = SimulatedConsole.scenario(.musical)
        let show = ShowRehearsal(console: console, character: .musical, sceneSeconds: 12)
        var sentStrips = 0, sentBuses = 0
        while show.time < 12 * 7 {
            let r = show.step(dt: 0.25)
            sentStrips += r.strips.count
            sentBuses += r.buses.count
        }
        let scenes = show.events.compactMap { if case let .scene(s) = $0.event { return s } else { return nil } }
        XCTAssertEqual(scenes, ShowRehearsal.Scene.allCases)
        // The engineer's hands moved faders all through the show, and the lead was ridden.
        let lead = console.strips.values.first { $0.name == "Vox Anna" }!.id
        let leadMoves = show.events.filter { if case .engineerFader(lead, _) = $0.event { return true }; return false }.count
        XCTAssertGreaterThan(sentStrips, 100)
        XCTAssertGreaterThan(leadMoves, 3)
        let log = show.guardian.log.map(\.action)
        func has(_ f: (GuardAction) -> Bool) -> Bool { log.contains(where: f) }
        XCTAssertTrue(has { if case .unmask = $0 { return true }; return false }, "chorus: lead not protected")
        XCTAssertTrue(has { if case .monitorDip(bus: 2, _) = $0 { return true }; return false }, "monitor push: no dip")
        XCTAssertTrue(has { if case .tonalHold(lead, _, _) = $0 { return true }; return false }, "ballad: no proximity hold")
        XCTAssertTrue(has { if case .notch = $0 { return true }; return false }, "hot vocal: no feedback notch")
        XCTAssertGreaterThan(sentBuses, 0)
        // Faders: nothing above +10 dB, outro brought everything down.
        XCTAssertTrue(show.strips.values.allSatisfy { $0.faderDB <= -60 })
        for a in log { print("GUARD", a) }
    }
}
