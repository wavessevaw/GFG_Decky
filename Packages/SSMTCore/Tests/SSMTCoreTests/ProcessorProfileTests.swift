import XCTest
@testable import SSMTCore

final class ProcessorProfileTests: XCTestCase {
    func testBandwidthConversion() {
        XCTAssertEqual(ProcessorProfile.q(octaves: 1), 1.414, accuracy: 0.001)
        XCTAssertEqual(ProcessorProfile.octaves(q: 1.414), 1, accuracy: 0.001)
        for n in [1.0 / 9, 1.0 / 3, 0.5, 1.5] {
            XCTAssertEqual(ProcessorProfile.octaves(q: ProcessorProfile.q(octaves: n)), n, accuracy: 1e-9)
        }
    }

    func testProfileAppliesToConfiguration() {
        var c = WizardConfiguration()
        var p = ProcessorProfile.customDefault
        p.delayStepMs = 0.02
        p.gainStepDB = 0.5
        c.processor = p
        XCTAssertEqual(c.delayStep, 0.00002, accuracy: 1e-12)
        XCTAssertEqual(c.eq.maxBandsSub, 4)
        XCTAssertEqual(c.eq.maxBandsMains, 6)
        XCTAssertEqual(c.eq.gainStepDB, 0.5)
        let sq = ProcessorProfile.profile(id: "ah-sq")!
        c.processor = sq
        XCTAssertEqual(c.eq.maxBandsSub, 4)
        XCTAssertLessThanOrEqual(c.eq.maxQ, 8)
        XCTAssertGreaterThanOrEqual(c.eq.minQ, 0.5)
        XCTAssertFalse(sq.canEnter(delaySeconds: 0.7))
        for id in ["behringer-x32", "ah-sq", "ah-dlive", "midas-hd96", "yamaha-cl", "yamaha-tf", "yamaha-rivage"] { XCTAssertNotNil(ProcessorProfile.profile(id: id), id) }
        XCTAssertEqual(ProcessorProfile.profile(id: "midas-hd96")?.maxDelayMs, 500)
        XCTAssertTrue(sq.canEnter(delaySeconds: 0.68))
    }

    /// Group band limits and the gain step are respected by the fit.
    func testFitRespectsConsoleLimits() {
        let grid = FrequencyGrid()
        let f = grid.frequencies
        func peak(_ x: Double, _ f0: Double, _ q: Double, _ g: Double) -> Double {
            Decibel.fromAmplitude(Biquad.design(.peaking, frequency: f0, q: q, gainDB: g, sampleRate: 48000)
                .response(at: x, sampleRate: 48000).magnitude)
        }
        let dev: (Double) -> Double = { x in
            peak(x, 300, 3, 6) + peak(x, 900, 3, -5) + peak(x, 2500, 3, 5) + peak(x, 6000, 3, -5)
        }
        let tfs = (0..<3).map { _ in
            TransferFunction(frequencies: f, response: f.map { Complex(Decibel.toAmplitude(dev($0))) },
                             coherence: f.map { _ in 0.95 }, measurementPower: f.map { _ in 1 },
                             referencePower: f.map { _ in 1 }, averages: 30)
        }
        let avg = SpatialAverage.compute(tfs)!
        var s = EQSettings()
        s.maxBandsMains = 2
        s.gainStepDB = 0.5
        let r = EQFitter.fit(average: avg, target: .preset(.flat), settings: s)
        XCTAssertLessThanOrEqual(r.filters.filter { $0.group == .mains }.count, 2, "\(r.filters)")
        XCTAssertFalse(r.filters.isEmpty)
        for x in r.filters {
            XCTAssertEqual((x.gainDB / 0.5).rounded() * 0.5, x.gainDB, accuracy: 1e-9)
        }
    }

    /// Sessions saved before profiles existed still decode (generic profile).
    func testOldConfigurationDecodes() throws {
        var c = WizardConfiguration()
        c.processor = ProcessorProfile.profile(id: "behringer-x32")!
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
        json.removeValue(forKey: "processorStorage")
        var eq = json["eq"] as! [String: Any]
        eq.removeValue(forKey: "gainStepStorage")
        eq.removeValue(forKey: "maxBandsSub")
        eq.removeValue(forKey: "maxBandsMains")
        json["eq"] = eq
        let back = try JSONDecoder().decode(WizardConfiguration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(back.processor.id, "generic")
        XCTAssertEqual(back.eq.gainStepDB, 0.1)
    }
}
