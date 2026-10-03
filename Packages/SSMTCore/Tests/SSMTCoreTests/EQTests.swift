import XCTest
@testable import SSMTCore

final class EQTests: XCTestCase {
    let fs = 48000.0
    let grid = FrequencyGrid()

    /// Synthetic spatial average: target + given response deviation, equal at all points.
    func average(_ deviation: (Double) -> Double, points: Int = 5, spread: ((Int, Double) -> Double)? = nil,
                 coherence: Double = 0.95) -> SpatialAverage {
        let f = grid.frequencies
        let tfs = (0..<points).map { p in
            TransferFunction(frequencies: f,
                             response: f.map { Complex(Decibel.toAmplitude(deviation($0) + (spread?(p, $0) ?? 0))) },
                             coherence: f.map { _ in coherence }, measurementPower: f.map { _ in 1 },
                             referencePower: f.map { _ in 1 }, averages: 30)
        }
        return SpatialAverage.compute(tfs)!
    }

    func peakingDB(_ f: Double, _ f0: Double, _ q: Double, _ g: Double) -> Double {
        Decibel.fromAmplitude(Biquad.design(.peaking, frequency: f0, q: q, gainDB: g, sampleRate: fs).response(at: f, sampleRate: fs).magnitude)
    }

    func testSpatialAverageEnergyAndSpread() {
        let f = grid.frequencies
        func tf(_ db: Double) -> TransferFunction {
            TransferFunction(frequencies: f, response: f.map { _ in Complex(Decibel.toAmplitude(db)) },
                             coherence: f.map { _ in 1 }, measurementPower: f.map { _ in 1 }, referencePower: f.map { _ in 1 }, averages: 1)
        }
        let a = SpatialAverage.compute([tf(0), tf(-6.0206)])!
        // Energy average of 1 and 0.25 → 0.625 → −2.04 dB.
        XCTAssertEqual(a.levelDB[100], Decibel.fromPower(0.625), accuracy: 1e-6)
        XCTAssertEqual(a.spreadDB[100], (2 * 3.0103 * 3.0103).squareRoot(), accuracy: 1e-3)
    }

    /// Known peaks: the fit reduces the error below the threshold, respects limits.
    func testFitsKnownPeaks() {
        let avg = average { f in
            self.peakingDB(f, 125, 4, 7) + self.peakingDB(f, 2500, 1.5, 4) + self.peakingDB(f, 600, 1, -3)
        }
        let r = EQFitter.fit(average: avg, target: .preset(.flat))
        XCTAssertGreaterThan(r.rmsBeforeDB, 2)
        XCTAssertLessThan(r.rmsAfterDB, max(1.0, r.rmsBeforeDB / 2), "\(r.filters)")
        XCTAssertLessThanOrEqual(r.filters.count, 8)
        for x in r.filters {
            XCTAssertLessThanOrEqual(x.gainDB, 3.0001)
            XCTAssertGreaterThanOrEqual(x.gainDB, -12.0001)
            XCTAssertGreaterThanOrEqual(x.q, 0.5 - 1e-9)
            XCTAssertLessThanOrEqual(x.q, 8 + 1e-9)
        }
        // The 125 Hz peak gets a cut near 125 Hz.
        XCTAssertTrue(r.filters.contains { abs(log2($0.frequency / 125)) < 0.25 && $0.gainDB < -3 })
    }

    /// Default: bands on the ISO 1/3-octave grid, in ascending order, numbered 1…N, no duplicates;
    /// the fit stays as good as with free frequencies.
    func testBandsOnStandardGridInOrder() {
        let avg = average { f in
            self.peakingDB(f, 118, 4, 7) + self.peakingDB(f, 2300, 1.5, 4) + self.peakingDB(f, 640, 1, -3)
                + self.peakingDB(f, 6700, 2, 3)
        }
        let r = EQFitter.fit(average: avg, target: .preset(.flat))
        let grid = Set(EQFrequencyGrid.thirdOctaveValues)
        XCTAssertFalse(r.filters.isEmpty)
        XCTAssertTrue(r.filters.allSatisfy { grid.contains($0.frequency) }, "\(r.filters.map(\.frequency))")
        XCTAssertEqual(r.filters.map(\.frequency), r.filters.map(\.frequency).sorted())
        XCTAssertEqual(Set(r.filters.map(\.frequency)).count, r.filters.count)
        XCTAssertEqual(r.filters.map(\.id), Array(1...r.filters.count))
        var free = EQSettings()
        free.frequencyGrid = .free
        let rf = EQFitter.fit(average: avg, target: .preset(.flat), settings: free)
        XCTAssertLessThan(r.rmsAfterDB, rf.rmsAfterDB + 0.5, "grid \(r.rmsAfterDB) vs free \(rf.rmsAfterDB)")
        XCTAssertLessThan(r.rmsAfterDB, max(1.0, r.rmsBeforeDB / 2))
    }

    /// A later EQ round does not reuse a frequency already on the processor.
    func testOccupiedFrequenciesAreAvoided() {
        let avg = average { f in self.peakingDB(f, 125, 4, 7) }
        let r = EQFitter.fit(average: avg, target: .preset(.flat), occupied: [125])
        XCTAssertFalse(r.filters.contains { $0.frequency == 125 }, "\(r.filters)")
    }

    /// Narrow deep dip: never boosted, flagged as not correctable.
    func testNoBoostIntoNarrowDip() {
        let avg = average { f in self.peakingDB(f, 400, 14, -15) + self.peakingDB(f, 3000, 1, 4) }
        let r = EQFitter.fit(average: avg, target: .preset(.flat))
        let dipIdx = grid.nearestIndex(to: 400)
        XCTAssertEqual(r.uncorrectable[dipIdx], .narrowDip)
        for x in r.filters where x.gainDB > 0 {
            XCTAssertGreaterThan(abs(log2(x.frequency / 400)), 0.5, "boost near the dip: \(x)")
        }
        let filterAt400 = r.filters.reduce(0) { $0 + $1.responseDB(at: 400) }
        XCTAssertLessThan(filterAt400, 0.5)
    }

    /// Comb filtering that differs between points (high spread): EQ does not chase it.
    func testCombFilteringIsNotTreated() {
        let avg = average({ _ in 0 }, points: 5, spread: { p, f in
            // Each position has a different reflection delay → combs at different frequencies.
            let d = 0.002 + 0.0007 * Double(p)
            return Decibel.fromAmplitude(Complex.one.re + 0) + Decibel.fromAmplitude((Complex.one + Complex.expj(-2 * .pi * f * d) * 0.7).magnitude)
        })
        let r = EQFitter.fit(average: avg, target: .preset(.flat))
        let flagged = r.uncorrectable.filter { $0 == .highSpread || $0 == .narrowDip }.count
        XCTAssertGreaterThan(flagged, 30)
        // Whatever is done stays gentle.
        XCTAssertTrue(r.filters.allSatisfy { abs($0.gainDB) <= 6 })
    }

    func testBoostAndCutLimits() {
        // A broad hole of −8 dB and a broad bump of +18 dB.
        let avg = average { f in self.peakingDB(f, 300, 0.7, -8) + self.peakingDB(f, 4000, 0.7, 18) }
        let r = EQFitter.fit(average: avg, target: .preset(.flat))
        XCTAssertTrue(r.filters.allSatisfy { $0.gainDB <= 3 + 1e-9 && $0.gainDB >= -12 - 1e-9 })
        XCTAssertTrue(r.filters.filter { $0.gainDB > 0 }.allSatisfy { $0.q <= 2 + 1e-9 })
    }

    func testTargetPresetsAndInterpolation() {
        let t = TargetCurve.preset(.livePA)
        XCTAssertEqual(t.value(at: 10), 3)
        XCTAssertEqual(t.value(at: 1000), 0)
        XCTAssertEqual(t.value(at: 2000), -1, accuracy: 1e-9)
        XCTAssertEqual(t.value(at: 2000 * pow(2, 0.5)), -1.5, accuracy: 1e-9)
        for p in TargetCurve.Preset.allCases { XCTAssertFalse(TargetCurve.preset(p).points.isEmpty) }
    }

    func testExportFormats() {
        let f = [PEQFilter(id: 1, frequency: 63, gainDB: -6.5, q: 4.2, group: .sub, groupAmbiguous: false),
                 PEQFilter(id: 2, frequency: 2500, gainDB: -3, q: 1.4, group: .mains, groupAmbiguous: true)]
        let text = PEQExport.filterSettingsText(f)
        XCTAssertTrue(text.contains("Group: Subwoofers"))
        XCTAssertTrue(text.contains("Fc    63.0 Hz"))
        XCTAssertTrue(text.contains("(check group)"))
        let csv = PEQExport.csv(f)
        XCTAssertTrue(csv.contains("sub,1,PK,63.0,-6.5,4.20"))
        XCTAssertTrue(csv.contains("mains,1,PK,2500.0,-3.0,1.40"))
    }

    /// Acceptance criterion 2 (EQ part): in the simulated room, after entering the suggested
    /// filters the RMS deviation from target in the working band drops at least 2× (or ≤ threshold).
    func testEQImprovesSimulatedRoom() throws {
        var sys = VirtualSystem.typicalPA(sampleRate: fs, crossover: 90, subDistance: 9.5, mainDistance: 9.5,
                                          room: VirtualRoom(reflections: [VirtualReflection(delaySamples: 900, gain: 0.25)],
                                                            modes: [Biquad.design(.peaking, frequency: 63, q: 5, gainDB: 8, sampleRate: fs)]),
                                          micNoiseDBFS: -80)
        // Mains with a typical "horn honk" and a bright top.
        sys.main.filters += [Biquad.design(.peaking, frequency: 1800, q: 1.2, gainDB: 5, sampleRate: fs),
                             Biquad.design(.peaking, frequency: 9000, q: 0.8, gainDB: 3, sampleRate: fs)]
        func spatial(_ s: VirtualSystem) -> SpatialAverage {
            let pts = (0..<5).map { p -> TransferFunction in
                let sp = s.atListeningPoint(p)
                return TestSignals.measure(system: sp, seconds: 8, referenceDelay: 128 + sp.main.delaySamples, seed: UInt64(10 + p))
            }
            return SpatialAverage.compute(pts)!
        }
        let before = spatial(sys)
        var m = sys; m.sub.enabled = false
        var s = sys; s.main.enabled = false
        let lock = 128 + sys.main.delaySamples
        let hm = TestSignals.measure(system: m, seconds: 6, referenceDelay: lock, seed: 2)
        let hs = TestSignals.measure(system: s, seconds: 6, referenceDelay: lock, seed: 3)
        let r = EQFitter.fit(average: before, target: .preset(.flat), main: hm, sub: hs, crossoverBand: 60...135)
        XCTAssertFalse(r.filters.isEmpty)
        XCTAssertTrue(r.filters.contains { $0.group == .sub }, "63 Hz mode belongs to the sub group: \(r.filters)")
        XCTAssertTrue(r.filters.contains { $0.group == .mains })

        for x in r.filters {
            if x.group == .sub { sys.sub.processorEQ.append(x.biquad(sampleRate: fs)) }
            else { sys.main.processorEQ.append(x.biquad(sampleRate: fs)) }
        }
        let after = spatial(sys)
        let check = EQFitter.fit(average: after, target: .preset(.flat), settings: {
            var st = EQSettings(); st.maxBands = 0; return st }())
        XCTAssertLessThan(check.rmsBeforeDB, max(r.rmsBeforeDB / 2, 1.5),
                          "before \(r.rmsBeforeDB) dB, after \(check.rmsBeforeDB) dB, filters \(r.filters)")
        let q0 = QualityScore.compute(levelDB: r.measuredDB, targetDB: r.targetDB, average: before, crossoverDipDB: nil)
        let q1 = QualityScore.compute(levelDB: check.measuredDB, targetDB: check.targetDB, average: after, crossoverDipDB: nil)
        XCTAssertGreaterThan(q1.score, q0.score)
    }

    /// EQ tuner: live/reference ratio = entered EQ, independent of the room.
    func testEQTunerReadsEnteredBands() throws {
        var sys = VirtualSystem.typicalPA(sampleRate: fs, subDistance: 9.5, mainDistance: 9.5,
                                          room: VirtualRoom(reflections: [VirtualReflection(delaySamples: 600, gain: 0.3)]),
                                          micNoiseDBFS: -80)
        let lock = 128 + sys.main.delaySamples
        let reference = TestSignals.measure(system: sys, seconds: 8, referenceDelay: lock, seed: 1)
        let plan = [PEQFilter(id: 1, frequency: 1800, gainDB: -5, q: 1.2, group: .mains, groupAmbiguous: false),
                    PEQFilter(id: 2, frequency: 250, gainDB: -3, q: 2, group: .mains, groupAmbiguous: false)]
        let tuner = EQTuner(reference: reference, filters: plan, workingRange: 40...16000)

        // Band 1 entered with only −2 dB so far: needle says "cut 3 dB more".
        sys.main.processorEQ = [Biquad.design(.peaking, frequency: 1800, q: 1.2, gainDB: -2, sampleRate: fs)]
        var r = try XCTUnwrap(tuner.read(live: TestSignals.measure(system: sys, seconds: 8, referenceDelay: lock, seed: 2)))
        XCTAssertEqual(r.bands[0].remainingGainDB, -3, accuracy: 0.5)
        XCTAssertFalse(r.bands[0].inTune)

        // Both bands entered exactly: everything in tune.
        sys.main.processorEQ = plan.map { $0.biquad(sampleRate: fs) }
        r = try XCTUnwrap(tuner.read(live: TestSignals.measure(system: sys, seconds: 8, referenceDelay: lock, seed: 3)))
        XCTAssertTrue(r.bands.allSatisfy(\.inTune), "\(r.bands)")
        XCTAssertLessThan(r.overallErrorDB, 0.75)
        XCTAssertTrue(r.allInTune)

        // Right gain, wrong frequency → shape error flags it.
        sys.main.processorEQ = [Biquad.design(.peaking, frequency: 1300, q: 1.2, gainDB: -5, sampleRate: fs),
                                plan[1].biquad(sampleRate: fs)]
        r = try XCTUnwrap(tuner.read(live: TestSignals.measure(system: sys, seconds: 8, referenceDelay: lock, seed: 4)))
        XCTAssertFalse(r.bands[0].inTune)
    }
}
