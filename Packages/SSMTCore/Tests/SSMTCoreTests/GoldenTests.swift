import XCTest
@testable import SSMTCore

/// Regression ("golden") results: a fixed, seeded simulation must keep producing the same alignment
/// and EQ. Tolerances absorb FFT backend differences (Accelerate vs portable) but catch real changes.
/// To re-record after an intentional algorithm change: `SSMT_RECORD_GOLDEN=1 swift test --filter GoldenTests`.
final class GoldenTests: XCTestCase {
    struct Golden: Codable {
        var alignmentDelayMs: Double
        var invertPolarity: Bool
        var subGainDB: Double
        var crossover: Double
        var dipAfterDB: Double
        var filters: [GoldenFilter]
        var eqRmsBefore: Double
        var eqRmsAfter: Double
    }
    struct GoldenFilter: Codable {
        var frequency: Double
        var gainDB: Double
        var q: Double
        var group: String
    }

    static var goldenURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Golden/demo-session.json")
    }

    func compute() throws -> Golden {
        // The alignment golden values are the correction the live phase match asked for.
        let (w, rig, reading) = try WizardTests.runWizardKeepingRig()
        var wizard = w
        wizard.beginEQ()
        for p in 0..<wizard.configuration.eqPointCount {
            rig.backend.moveMicrophone(toPoint: p)
            rig.run(seconds: 0.5)
            wizard.submit(try XCTUnwrap(rig.capture("eq\(p)", seconds: 8)))
        }
        let r = try XCTUnwrap(wizard.computeEQ())
        return Golden(alignmentDelayMs: reading.delayError * 1000, invertPolarity: reading.polarityWrong,
                      subGainDB: reading.levelError, crossover: reading.crossover,
                      dipAfterDB: wizard.report?.after?.dipDepthDB ?? .nan,
                      filters: r.filters.map { GoldenFilter(frequency: $0.frequency, gainDB: $0.gainDB, q: $0.q, group: $0.group.rawValue) },
                      eqRmsBefore: r.rmsBeforeDB, eqRmsAfter: r.rmsAfterDB)
    }

    func testDemoSessionMatchesGolden() throws {
        let now = try compute()
        if ProcessInfo.processInfo.environment["SSMT_RECORD_GOLDEN"] == "1" || !FileManager.default.fileExists(atPath: Self.goldenURL.path) {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: Self.goldenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try e.encode(now).write(to: Self.goldenURL)
            throw XCTSkip("Golden file recorded at \(Self.goldenURL.path)")
        }
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: Self.goldenURL))
        XCTAssertEqual(now.alignmentDelayMs, golden.alignmentDelayMs, accuracy: 0.05)
        XCTAssertEqual(now.invertPolarity, golden.invertPolarity)
        XCTAssertEqual(now.subGainDB, golden.subGainDB, accuracy: 0.5)
        XCTAssertEqual(now.crossover, golden.crossover, accuracy: 0.5)
        XCTAssertEqual(now.dipAfterDB, golden.dipAfterDB, accuracy: 1.0)
        XCTAssertEqual(now.eqRmsBefore, golden.eqRmsBefore, accuracy: 0.2)
        XCTAssertEqual(now.eqRmsAfter, golden.eqRmsAfter, accuracy: 0.3)
        XCTAssertEqual(now.filters.count, golden.filters.count, "filter count changed")
        for (n, g) in zip(now.filters, golden.filters) {
            XCTAssertEqual(log2(n.frequency / g.frequency), 0, accuracy: 0.1, "Fc \(n.frequency) vs \(g.frequency)")
            XCTAssertEqual(n.gainDB, g.gainDB, accuracy: 0.6)
            XCTAssertEqual(n.group, g.group)
        }
    }
}
