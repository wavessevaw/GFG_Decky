import XCTest
@testable import SSMTCore

final class MicrophoneProfileTests: XCTestCase {
    func testProfilesAreWellFormed() {
        XCTAssertGreaterThanOrEqual(MicrophoneProfiles.all.count, 20)
        for p in MicrophoneProfiles.all {
            XCTAssertGreaterThanOrEqual(p.points.count, 3, p.id)
            for i in 1..<p.points.count {
                XCTAssertGreaterThan(p.points[i].0, p.points[i - 1].0, "\(p.id): frequencies must ascend")
            }
            // Normalized at 1 kHz, plausible deviations only.
            XCTAssertEqual(p.calibration.deviation(at: 1000), 0, accuracy: 1e-9, p.id)
            XCTAssertTrue(p.points.allSatisfy { abs($0.1) <= 15 }, p.id)
        }
    }

    func testRequestedModelsArePresent() {
        let names = Set(MicrophoneProfiles.all.map(\.displayName))
        for n in ["Shure SM81", "Soyuz 011 FET", "Soyuz 013 FET", "Soyuz 022 Bomblet", "AKG C414 XLII"] {
            XCTAssertTrue(names.contains(n), n)
        }
    }

    func testStableUniqueIdentifiers() {
        let ids = MicrophoneProfiles.all.map(\.uuid)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(MicrophoneProfile.stableUUID("shure-sm81"), MicrophoneProfile.stableUUID("shure-sm81"))
        let sm81 = MicrophoneProfiles.all.first { $0.id == "shure-sm81" }!
        XCTAssertEqual(MicrophoneProfiles.profile(id: sm81.uuid)?.id, "shure-sm81")
        XCTAssertTrue(sm81.calibration.isTypical)
    }

    func testTypicalCurveFlattensMeasurement() {
        let p = MicrophoneProfiles.all.first { $0.id == "akg-c414-xlii" }!
        let freqs = [50.0, 200, 1000, 4000, 10000, 15000]
        // A flat system measured through the microphone shows the microphone's own response.
        let ones = [Double](repeating: 1, count: freqs.count)
        let measured = TransferFunction(frequencies: freqs,
                                        response: freqs.map { Complex(Decibel.toAmplitude(p.calibration.deviation(at: $0))) },
                                        coherence: ones, measurementPower: ones, referencePower: ones, averages: 1)
        let corrected = p.calibration.apply(to: measured)
        for i in freqs.indices {
            XCTAssertEqual(Decibel.fromAmplitude(corrected.response[i].magnitude), 0, accuracy: 1e-6)
        }
    }

    func testOldCalibrationFilesDecodeAsIndividual() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"x","frequencies":[20,1000,20000],"deviationDB":[0,0,0]}"#
        let c = try JSONDecoder().decode(MicrophoneCalibration.self, from: Data(json.utf8))
        XCTAssertFalse(c.isTypical)
    }
}
