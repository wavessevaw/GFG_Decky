import SSMTCore
import SwiftUI

/// Step 6 (zone points) and step 8 (verification points): one point at a time, tuner-style quality needle.
struct EQPointsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    private var verifying: Bool { model.wizard.step == .eqVerification }
    private var done: Int { verifying ? model.wizard.eqVerificationPoints.count : model.wizard.eqPoints.count }
    private var total: Int { verifying ? model.wizard.eqPoints.count : model.wizard.configuration.eqPointCount }
    private var complete: Bool { done >= total }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(marking: verifying ? "STEP 8 · EQ CHECK" : "STEP 6 · ZONE",
                              title: loc.t(verifying ? "eq.verify.title" : "eq.points.title"),
                              text: complete ? "" : loc.t("eq.points.text", done + 1, total))
            if !verifying && done == 0 { targetPicker }
            HStack(alignment: .top, spacing: 12) {
                PointMap(total: total, done: done, qualities: qualities)
                SignalQualityGauge(band: 40...16000)
            }
            if verifying && complete {
                EQResultGauges()
            } else if !complete {
                if model.isSimulation {
                    Button(loc.t("sim.movePoint", done + 1)) { model.simulateMoveToNextPoint() }.buttonStyle(SSMTButtonStyle())
                }
                captureRow
            }
            if let acc = model.lastAcceptance, case .rejected(let reasons) = acc {
                HazardNotice(text: loc.t("eq.point.rejected") + " " + reasons.map { loc.t("reason.\($0.rawValue)") }.joined(separator: " "),
                             color: Theme.statusError)
            }
            HStack(spacing: 12) {
                Button(loc.t("wizard.back")) { model.wizardBack() }.buttonStyle(SSMTButtonStyle())
                if !verifying {
                    WizardPrimaryButton(title: loc.t("eq.compute"), systemImage: "slider.horizontal.3",
                                        enabled: model.wizard.canComputeEQ && !model.wizardCaptureRunning) {
                        model.wizardComputeEQ()
                    }
                } else if complete {
                    if model.wizard.canIterateEQ {
                        Button(loc.t("eq.iterate")) { model.wizardIterateEQ() }.buttonStyle(SSMTButtonStyle())
                    }
                    WizardPrimaryButton(title: loc.t("eq.finish"), systemImage: "flag.checkered") { model.wizardFinish() }
                }
            }
            if verifying && complete && !model.wizard.canIterateEQ {
                Text(loc.t("eq.iterationLimit")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var qualities: [CaptureQuality] {
        (verifying ? model.wizard.eqVerificationPoints : model.wizard.eqPoints).map(\.assessment.quality)
    }

    private var captureRow: some View {
        let p = model.snapshot?.capture
        return HStack(spacing: 12) {
            if model.wizardCaptureRunning {
                ProgressView(value: p?.fraction ?? 0).tint(Theme.closeness(p?.fraction ?? 0)).frame(maxWidth: .infinity)
                Text(p.map { String(format: "%.0f / %.0f s", $0.elapsed, $0.duration) } ?? "").font(Theme.mono(14))
                Button(loc.t("action.cancel")) { model.wizardCancelCapture() }.buttonStyle(SSMTButtonStyle())
            } else {
                WizardPrimaryButton(title: loc.t("eq.capturePoint", done + 1), systemImage: "record.circle",
                                    enabled: model.isRunning) { model.wizardCapture() }
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private var targetPicker: some View {
        Panel(title: loc.t("eq.target"), marking: "TGT") {
            Picker("", selection: Binding(get: { model.wizard.configuration.target.preset },
                                          set: { model.wizard.configuration.target = .preset($0) })) {
                ForEach(TargetCurve.Preset.allCases.filter { $0 != .custom }, id: \.self) {
                    Text(loc.t("target.\($0.rawValue)")).tag($0)
                }
            }
            .labelsHidden().pickerStyle(.segmented)
            Stepper(value: $model.wizard.configuration.eqPointCount, in: 3...9) {
                Text(loc.t("eq.pointCount", model.wizard.configuration.eqPointCount)).font(Theme.label(12))
            }
        }
    }
}

/// Simple top view of the listening area with numbered measurement points.
struct PointMap: View {
    @EnvironmentObject var loc: Localizer
    var total: Int
    var done: Int
    var qualities: [CaptureQuality]

    var body: some View {
        Panel(title: loc.t("eq.map"), marking: "\(done)/\(total)") {
            Canvas { ctx, size in
                // Stage with two mains and the sub.
                let stage = CGRect(x: size.width * 0.15, y: 4, width: size.width * 0.7, height: 16)
                ctx.fill(Path(stage), with: .color(Theme.panelRaised))
                ctx.draw(Text(loc.t("eq.map.stage")).font(Theme.label(9)).foregroundColor(Theme.textMuted),
                         at: CGPoint(x: stage.midX, y: stage.midY))
                for x in [stage.minX - 8, stage.maxX + 8] {
                    ctx.fill(Path(CGRect(x: x - 6, y: 2, width: 12, height: 20)), with: .color(Theme.textSecondary))
                }
                // Points spread over the audience area in a zig-zag.
                let positions = (0..<total).map { i -> CGPoint in
                    let cols = 3
                    let row = i / cols, col = i % cols
                    let rows = max(1, (total + cols - 1) / cols)
                    let x = size.width * (0.25 + 0.25 * Double(row % 2 == 0 ? col : cols - 1 - col))
                    let y = 40 + (size.height - 56) * (rows == 1 ? 0.5 : Double(row) / Double(rows - 1))
                    return CGPoint(x: x, y: y)
                }
                for (i, p) in positions.enumerated() {
                    let color: Color
                    if i < done {
                        switch qualities[safe: i] {
                        case .some(.good): color = Theme.closeness(1)
                        case .some(.weak): color = Theme.closeness(0.7)
                        default: color = Theme.closeness(0)
                        }
                    } else if i == done {
                        color = Theme.accent
                    } else {
                        color = Theme.textMuted
                    }
                    let r: CGFloat = i == done ? 13 : 10
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(color.opacity(i < done ? 0.9 : 0.25)))
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(color), lineWidth: i == done ? 2 : 1)
                    ctx.draw(Text("\(i + 1)").font(Theme.mono(11, weight: .bold)).foregroundColor(i < done ? .black : Theme.textPrimary),
                             at: p)
                }
            }
            .frame(height: 170)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Before/after gauges of the EQ round: deviation from target and the quality score.
struct EQResultGauges: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        if let s = model.wizard.eqScores(microphone: model.calibration.selectedMicrophone) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    let after = s.after ?? s.before
                    TunerGauge(title: loc.t("gauge.deviation"),
                               value: 1 - after.rmsDeviationDB / 6, mode: .oneSided, tolerance: 1 - 1.5 / 6,
                               readout: String(format: "±%.1f dB", after.rmsDeviationDB),
                               instruction: String(format: loc.t("gauge.before"), s.before.rmsDeviationDB),
                               large: model.stageMode,
                               scaleLabels: ["6", "4.5", "3", "1.5", "0"], unit: "dB",
                               telemetry: ("63 Hz–12.5k", "TARGET ≤1.5"))
                    TunerGauge(title: loc.t("gauge.score"),
                               value: Double(after.score) / 100, mode: .oneSided, tolerance: 0.8,
                               readout: "\(after.score)",
                               instruction: String(format: loc.t("gauge.beforeScore"), s.before.score),
                               large: model.stageMode,
                               scaleLabels: ["0", "25", "50", "75", "100"],
                               telemetry: ("SCORE", "TARGET ≥80"))
                }
                Text(loc.t("gauge.score.note")).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

/// Step 7: enter the EQ band by band, guided by needles.
struct EQTuningView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstructionHeader(marking: "STEP 7 · EQ TUNE", title: loc.t("eq.tune.title"), text: loc.t("eq.tune.text"))
            if let r = model.wizard.eqResult {
                if r.filters.isEmpty {
                    HazardNotice(text: loc.t("eq.nothingToDo"), color: Theme.statusGood)
                }
                notCorrectable(r)
                HStack(alignment: .top, spacing: 12) {
                    bandList(r)
                    VStack(spacing: 12) {
                        if model.eqTunerReady {
                            bandGauge(r)
                            overallGauge
                        } else {
                            startPanel
                        }
                    }
                }
                Panel(title: loc.t("eq.curves"), marking: "PLAN / LIVE") {
                    ComparisonPlotView(curves: curves(r), band: r.workingRange, range: 20...20000, absolute: true)
                        .frame(height: 200)
                }
                if model.isSimulation { simulationPanel(r) }
                HStack(spacing: 12) {
                    Button(loc.t("wizard.back")) { model.stopEQTuner(); model.wizardBack() }.buttonStyle(SSMTButtonStyle())
                    Button(loc.t("export.copy")) { model.copyExportToClipboard() }.buttonStyle(SSMTButtonStyle())
                    WizardPrimaryButton(title: loc.t((model.eqTunerReading?.allInTune ?? false) ? "eq.tune.allSet" : "eq.tune.entered"),
                                        systemImage: "checkmark.seal.fill") {
                        model.wizardBeginEQVerification()
                    }
                }
            }
        }
        .onDisappear { model.stopEQTuner() }
    }

    private var startPanel: some View {
        Panel(title: loc.t("tuner.title"), marking: "REF") {
            Text(loc.t("eq.tune.reference")).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.eqReferenceCapturing {
                HStack { ProgressView().controlSize(.small); Text(loc.t("tuner.waiting")).font(.system(size: 12)) }
            } else {
                WizardPrimaryButton(title: loc.t("eq.tune.start"), systemImage: "tuningfork", enabled: model.isRunning) {
                    model.startEQTuner()
                }
            }
        }
    }

    private func bandList(_ r: EQResult) -> some View {
        Panel(title: loc.t("eq.bands"), marking: "\(r.filters.count) PEQ") {
            ForEach(Array(r.filters.enumerated()), id: \.offset) { i, f in
                let reading = model.eqTunerReading?.bands.first { $0.bandIndex == i }
                let c = reading.map { closeness($0) }
                Button {
                    model.eqSelectedBand = i
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("\(i + 1)").font(Theme.mono(12, weight: .bold)).frame(width: 18)
                            Text(loc.t(f.group == .sub ? "group.subs" : "group.mains")).font(Theme.label(10))
                                .foregroundStyle(Theme.textSecondary).frame(width: 74, alignment: .leading)
                            Text(String(format: "%6.0f Hz", f.frequency)).font(Theme.mono(12))
                            Text(String(format: "%+5.1f dB", f.gainDB)).font(Theme.mono(12, weight: .semibold))
                            Text(String(format: "Q %4.2f", f.q)).font(Theme.mono(12))
                            if f.groupAmbiguous { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.signalYellow) }
                            Spacer()
                        }
                        HStack {
                            Spacer().frame(width: 26)
                            MiniMeter(value: reading.map { $0.remainingGainDB / 6 }, tolerance: 0.5 / 6,
                                      readout: reading.map { String(format: "%+.1f dB", $0.remainingGainDB) } ?? "—")
                            Text(c.map { $0 >= 1 ? loc.t("tuner.inTune") : "" } ?? "")
                                .font(Theme.label(10)).foregroundStyle(Theme.closeness(c ?? 0))
                        }
                    }
                    .padding(6)
                    .background(model.eqSelectedBand == i ? Theme.accent.opacity(0.12) : Color.clear)
                    .overlay(Rectangle().stroke(model.eqSelectedBand == i ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 440)
    }

    private func closeness(_ b: EQTuner.BandReading) -> Double {
        let g = abs(b.remainingGainDB), sh = b.shapeErrorDB
        if b.inTune { return 1 }
        return max(0, 1 - max((g - 0.5) / 5.5, (sh - 1) / 4))
    }

    @ViewBuilder private func bandGauge(_ r: EQResult) -> some View {
        let i = min(model.eqSelectedBand, max(r.filters.count - 1, 0))
        let b = model.eqTunerReading?.bands.first { $0.bandIndex == i }
        if let f = r.filters[safe: i] {
            TunerGauge(
                title: loc.t("eq.band.title", i + 1, f.frequency),
                value: b.map { $0.remainingGainDB / 6 },
                tolerance: 0.5 / 6,
                readout: b.map { String(format: "%+.1f dB", $0.remainingGainDB) } ?? "—",
                instruction: bandInstruction(b),
                reliable: (model.eqTunerReading?.confidence ?? 0) >= 0.6,
                leftLabel: loc.t("tuner.cut"), rightLabel: loc.t("tuner.boost"),
                large: model.stageMode,
                scaleLabels: ["−6", "−3", "0", "+3", "+6"], unit: "dB",
                telemetry: (String(format: "PEQ %ld · %@", i + 1, loc.t(f.group == .sub ? "group.subs" : "group.mains").uppercased()),
                            String(format: "Fc %.0f · Q %.2f", f.frequency, f.q)))
        }
    }

    private func bandInstruction(_ b: EQTuner.BandReading?) -> String {
        guard let b else { return loc.t("tuner.waiting") }
        if b.inTune { return loc.t("tuner.inTune") }
        if abs(b.remainingGainDB) <= 0.5 { return loc.t("eq.band.shape") }
        return String(format: loc.t(b.remainingGainDB < 0 ? "eq.band.cutMore" : "eq.band.boostMore"), abs(b.remainingGainDB))
    }

    private var overallGauge: some View {
        let e = model.eqTunerReading?.overallErrorDB
        return TunerGauge(title: loc.t("eq.overall"), value: e.map { 1 - $0 / 4 }, mode: .oneSided,
                          tolerance: 1 - 0.75 / 4,
                          readout: e.map { String(format: "±%.1f dB", $0) } ?? "—",
                          instruction: e.map { $0 <= 0.75 ? loc.t("tuner.inTune") : loc.t("eq.overall.hint") } ?? loc.t("tuner.waiting"),
                          large: model.stageMode,
                          scaleLabels: ["4", "3", "2", "1", "0"], unit: "dB",
                          telemetry: ("EQ vs PLAN", "TARGET ≤0.75"))
    }

    private func curves(_ r: EQResult) -> [ComparisonPlotView.Curve] {
        var c: [ComparisonPlotView.Curve] = [
            .init(label: loc.t("curve.plan"), transfer: .fromDB(model.eqTunerReading?.plannedDB ?? r.filterResponseDB, frequencies: r.frequencies),
                  color: Theme.dataBlue, dashed: true),
        ]
        if let applied = model.eqTunerReading?.appliedDB {
            c.append(.init(label: loc.t("curve.entered"), transfer: .fromDB(applied, frequencies: r.frequencies),
                           color: Theme.closeness(model.eqTunerReading.map { max(0, 1 - ($0.overallErrorDB - 0.75) / 3) } ?? 0)))
        }
        return c
    }

    private func notCorrectable(_ r: EQResult) -> some View {
        let dips = r.uncorrectable.filter { $0 == .narrowDip }.count
        let spread = r.uncorrectable.filter { $0 == .highSpread }.count
        return Group {
            if dips + spread > 0 {
                HazardNotice(text: loc.t("eq.notCorrectable"))
            }
        }
    }

    private func simulationPanel(_ r: EQResult) -> some View {
        Panel(title: loc.t("vproc.title"), marking: "SIM DSP") {
            Text(loc.t("vproc.eq.hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            ForEach(Array(r.filters.enumerated()), id: \.offset) { i, f in
                let entered = model.simulatedBandEntered(f)
                HStack {
                    Toggle(String(format: "%d · %.0f Hz", i + 1, f.frequency), isOn: Binding(
                        get: { entered != nil }, set: { _ in model.simulateToggleBand(f) }))
                        .frame(width: 140, alignment: .leading)
                    if let e = entered {
                        Slider(value: Binding(get: { e.gainDB }, set: { model.simulateSetBandGain(f, gain: $0) }),
                               in: -12...3, step: 0.5).tint(Theme.accent)
                        Text(String(format: "%+.1f dB", e.gainDB)).font(Theme.mono(12)).frame(width: 64)
                    }
                }
            }
        }
    }
}
