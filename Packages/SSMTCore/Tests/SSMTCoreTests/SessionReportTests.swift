import XCTest
@testable import SSMTCore

final class SessionReportTests: XCTestCase {
    func testSessionRoundTripAndReport() throws {
        let w = try WizardTests.runWizardKeepingRig().wizard
        let file = SessionFile(wizard: w, interfaceName: "Simulation", sampleRate: 48000,
                               microphoneCalibrationName: nil, appVersion: "0.1.0")
        let data = try file.encoded()
        let back = try SessionFile.decode(data)
        XCTAssertEqual(back.wizard.step, w.step)
        XCTAssertEqual(back.wizard.alignment, w.alignment)
        XCTAssertEqual(back.wizard.report, w.report)
        XCTAssertEqual(back.interfaceName, "Simulation")

        let report = SetupReport(wizard: back.wizard, interfaceName: back.interfaceName, sampleRate: 48000, microphone: nil)
        let a = try XCTUnwrap(report.alignment)
        XCTAssertTrue(a.invertPolarity)
        XCTAssertNotNil(report.verification)
        let text = report.plainText
        XCTAssertTrue(text.contains("Subwoofer polarity: INVERT"))
        XCTAssertTrue(text.contains("Delay subwoofers: +"))
        XCTAssertTrue(text.contains("Microphone calibration: none"))
    }

    func testRejectsNewerVersion() throws {
        var f = SessionFile(wizard: SetupWizard(), interfaceName: "x", sampleRate: 48000,
                            microphoneCalibrationName: nil, appVersion: "0")
        f.version = 99
        XCTAssertThrowsError(try SessionFile.decode(try f.encoded()))
    }
}
