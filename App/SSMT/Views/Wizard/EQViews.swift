import SSMTCore
import SwiftUI

/// Step 6 (zone points) and step 8 (verification points): one point at a time, quality needle.
struct EQPointsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    @State private var editingTarget = false

    private var verifying: Bool { model.wizard.step == .eqVerification }
    private var done: Int { verifying ? model.wizard.eqVerificationPoints.count : model.wizard.eqPoints.count }
    private var total: Int { verifying ? model.wizard.eqPoints.count : model.wizard.configuration.eqPointCount }
    private var complete: Bool { done >= total }

    var body: some View {
        StepScaffold(title: title, subtitle: complete ? "" : loc.t("eq.points.subtitle"), info: loc.t("eq.points.info")) {
            VStack(spacing: 22) {
                if verifying && complete {
                    EQResultGauges()
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        PointMap(total: total, done: done, qualities: qualities).frame(width: 280).glassCard(padding: 16)
                        SignalQualityGauge(band: 40...16000)
                    }
                    if model.wizardCaptureRunning { CaptureProgressBar() }
                    if let acc = model.lastAcceptance, case .rejected(let reasons) = acc {
                        Text(loc.t("eq.point.rejected") + " " + reasons.map { loc.t("reason.\($0.rawValue)") }.joined(separator: " "))
                            .font(.system(size: 13)).foregroundStyle(Theme.statusError)
                    }
                    HStack(spacing: 18) {
                        if !verifying { targetMenu }
                        if model.isSimulation && !complete {
                            QuietButton(title: loc.t("sim.movePoint", done + 1), icon: "wand.and.stars") { model.simulateMoveToNextPoint() }
                        }
                    }
                }
            }
        } actions: {
            if verifying && complete {
                ActionRow(primaryTitle: loc.t("eq.finish"), primaryIcon: "flag.checkered", primaryAction: { model.wizardFinish() }) {
                    QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.wizardBack() }
                    if model.wizard.canIterateEQ {
                        QuietButton(title: loc.t("eq.iterate"), icon: "arrow.triangle.2.circlepath") { model.wizardIterateEQ() }
                    }
                }
            } else if complete {
                ActionRow(primaryTitle: loc.t("eq.compute"), primaryIcon: "slider.horizontal.3",
                          primaryAction: { model.wizardComputeEQ() }) {
                    QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.wizardBack() }
                }
            } else {
                ActionRow(primaryTitle: model.wizardCaptureRunning ? loc.t("action.cancel") : loc.t("eq.capturePoint", done + 1),
                          primaryIcon: model.wizardCaptureRunning ? "xmark" : "record.circle",
                          primaryEnabled: model.isRunning,
                          primaryAction: { model.wizardCaptureRunning ? model.wizardCancelCapture() : model.wizardCapture() }) {
                    QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.wizardBack() }
                    if !verifying && model.wizard.canComputeEQ {
                        QuietButton(title: loc.t("eq.compute"), icon: "slider.horizontal.3") { model.wizardComputeEQ() }
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
    }

    private var title: String {
        if verifying && complete { return loc.t("eq.verify.done") }
        if complete { return loc.t("eq.points.done") }
        return loc.t(verifying ? "eq.verify.point" : "eq.points.point", done + 1, total)
    }

    private var qualities: [CaptureQuality] {
        (verifying ? model.wizard.eqVerificationPoints : model.wizard.eqPoints).map(\.assessment.quality)
    }

    private var targetMenu: some View {
        Menu {
            ForEach(TargetCurve.Preset.allCases.filter { $0 != .custom }, id: \.self) { p in
                Button(loc.t("target.\(p.rawValue)")) { model.wizard.configuration.target = .preset(p) }
            }
            Divider()
            Button(loc.t("target.editor") + "…") { editingTarget = true }
            Divider()
            Picker(loc.t("eq.grid.title"), selection: $model.wizard.configuration.eq.frequencyGrid) {
                ForEach(EQFrequencyGrid.allCases, id: \.self) { Text(loc.t("eq.grid.\($0.rawValue)")).tag($0) }
            }
            Picker(loc.t("eq.pointCount.title"), selection: $model.wizard.configuration.eqPointCount) {
                ForEach(3...9, id: \.self) { Text("\($0)").tag($0) }
            }
        } label: {
            Text(loc.t("eq.target") + ": " + loc.t("target.\(model.wizard.configuration.target.preset.rawValue)"))
                .font(Theme.label(13))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .sheet(isPresented: $editingTarget) { TargetEditorView() }
    }
}

/// Simple top view of the listening area with numbered measurement points.
struct PointMap: View {
    @EnvironmentObject var loc: Localizer
    var total: Int
    var done: Int
    var qualities: [CaptureQuality]

    var body: some View {
        VStack(spacing: 8) {
            Text(loc.t("eq.map")).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Canvas { ctx, size in
                // Stage with two mains and the sub.
                let stage = CGRect(x: size.width * 0.15, y: 4, width: size.width * 0.7, height: 16)
                ctx.fill(Path(roundedRect: stage, cornerRadius: 4), with: .color(.white.opacity(0.08)))
                ctx.draw(Text(loc.t("eq.map.stage")).font(Theme.label(11)).foregroundColor(Theme.textMuted),
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
            .frame(height: 200)
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
                               readout: String(format: "±%.1f", after.rmsDeviationDB),
                               instruction: String(format: loc.t("gauge.before"), s.before.rmsDeviationDB),
                               large: model.stageMode,
                               scaleLabels: ["6", "", "3", "", "0"], unit: "dB")
                    TunerGauge(title: loc.t("gauge.score"),
                               value: Double(after.score) / 100, mode: .oneSided, tolerance: 0.8,
                               readout: "\(after.score)",
                               instruction: String(format: loc.t("gauge.beforeScore"), s.before.score),
                               large: model.stageMode,
                               scaleLabels: ["0", "", "50", "", "100"])
                }
                HStack { Spacer(); InfoButton(text: loc.t("gauge.score.note")) }
            }
        }
    }
}

/// Step 7: enter the EQ band by band. Left: compact band list with LED bars. Right: the selected
/// band's instrument. Everything else (curves, simulation, notes) is collapsed.
struct EQTuningView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tuning: TuningData
    @EnvironmentObject var loc: Localizer

    var body: some View {
        StepScaffold(title: loc.t("eq.tune.title"), subtitle: loc.t("eq.tune.subtitle"), info: loc.t("eq.tune.text")) {
            if let r = model.wizard.eqResult {
                VStack(spacing: 22) {
                    if r.filters.isEmpty {
                        Text(loc.t("eq.nothingToDo")).font(.system(size: 15)).foregroundStyle(Theme.statusGood)
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            bandList(r).frame(width: 380)
                            VStack(spacing: 14) {
                                if model.eqTunerReady {
                                    bandGauge(r)
                                    overallLine
                                } else {
                                    startTuner
                                }
                            }
                        }
                    }
                    VStack(spacing: 12) {
                        if model.isSimulation {
                            Collapsible(title: loc.t("vproc.title")) { simulationPanel(r) }
                        }
                        Collapsible(title: loc.t("eq.curves")) {
                            ComparisonPlotView(curves: curves(r), band: r.workingRange, range: 20...20000, absolute: true)
                                .frame(height: 200)
                        }
                    }
                }
            }
        } actions: {
            ActionRow(primaryTitle: loc.t((model.eqTunerReading?.allInTune ?? false) ? "eq.tune.allSet" : "eq.tune.entered"),
                      primaryIcon: "checkmark", primaryAction: { model.wizardBeginEQVerification() }) {
                QuietButton(title: loc.t("wizard.back"), icon: "chevron.left") { model.stopEQTuner(); model.wizardBack() }
                QuietButton(title: loc.t("export.copy"), icon: "doc.on.doc") { model.copyExportToClipboard() }
            }
        }
        .onDisappear { model.stopEQTuner() }
    }

    private var startTuner: some View {
        VStack(spacing: 12) {
            Image(systemName: "tuningfork").font(.system(size: 34)).foregroundStyle(Theme.textMuted)
            if model.eqReferenceCapturing {
                ProgressView().controlSize(.small)
                Text(loc.t("tuner.waiting")).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            } else {
                Button(loc.t("eq.tune.start")) { model.startEQTuner() }
                    .buttonStyle(SSMTButtonStyle(kind: .primary))
                    .disabled(!model.isRunning)
                Text(loc.t("eq.tune.reference.short")).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(GlassBackground())
    }

    private func bandList(_ r: EQResult) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(r.filters.enumerated()), id: \.offset) { i, f in
                let reading = model.eqTunerReading?.bands.first { $0.bandIndex == i }
                Button { model.eqSelectedBand = i } label: {
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(Theme.mono(12, weight: .bold)).foregroundStyle(Theme.textMuted).frame(width: 16)
                        Text(loc.t(f.group == .sub ? "group.subs.tag" : "group.mains.tag"))
                            .font(Theme.label(11))
                            .foregroundStyle(f.group == .sub ? Theme.dataSecondary : Theme.textSecondary)
                            .frame(width: 30)
                        Text(f.frequencyLabel).font(Theme.mono(12)).frame(width: 74, alignment: .trailing)
                        Text(String(format: "%+.1f", f.gainDB)).font(Theme.mono(12, weight: .semibold)).frame(width: 40, alignment: .trailing)
                        Text(f.widthLabel(inOctaves: model.wizard.configuration.processor.bandwidthInOctaves))
                            .font(Theme.mono(11)).foregroundStyle(Theme.textMuted).frame(width: 84, alignment: .trailing)
                        Spacer(minLength: 4)
                        MiniLED(value: reading.map { $0.remainingGainDB / 6 }, tolerance: 0.5 / 6)
                            .frame(width: 70, height: 12)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(model.eqSelectedBand == i ? Theme.accent.opacity(0.12) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(GlassBackground())
    }

    @ViewBuilder private func bandGauge(_ r: EQResult) -> some View {
        let i = min(model.eqSelectedBand, max(r.filters.count - 1, 0))
        let b = model.eqTunerReading?.bands.first { $0.bandIndex == i }
        if let f = r.filters[safe: i] {
            TunerGauge(
                title: loc.t("eq.band.title", i + 1, f.frequencyLabel),
                value: b.map { $0.remainingGainDB / 6 },
                tolerance: 0.5 / 6,
                readout: b.map { String(format: "%+.1f", $0.remainingGainDB) } ?? "—",
                instruction: bandInstruction(b),
                reliable: (model.eqTunerReading?.confidence ?? 0) >= 0.6,
                large: model.stageMode,
                scaleLabels: ["−6", "", "0", "", "+6"], unit: "dB")
        }
    }

    private func bandInstruction(_ b: EQTuner.BandReading?) -> String {
        guard let b else { return loc.t("tuner.waiting") }
        if b.inTune { return loc.t("tuner.inTune") }
        if abs(b.remainingGainDB) <= 0.5 { return loc.t("eq.band.shape") }
        return String(format: loc.t(b.remainingGainDB < 0 ? "eq.band.cutMore" : "eq.band.boostMore"), abs(b.remainingGainDB))
    }

    /// One line instead of a second instrument: lamp + "EQ vs plan ±0.4 dB".
    private var overallLine: some View {
        let e = model.eqTunerReading?.overallErrorDB
        let c = e.map { $0 <= 0.75 ? 1 : max(0, 1 - ($0 - 0.75) / 3) } ?? 0
        return HStack(spacing: 10) {
            IndicatorLamp(color: e == nil ? Theme.textMuted : Theme.closeness(c), size: 14)
            Text(loc.t("eq.overall")).font(Theme.label(12)).foregroundStyle(Theme.textSecondary)
            Text(e.map { String(format: "±%.1f dB", $0) } ?? "—").font(Theme.mono(13, weight: .semibold))
                .foregroundStyle(e == nil ? Theme.textMuted : Theme.closeness(c))
        }
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

    private func simulationPanel(_ r: EQResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(r.filters.enumerated()), id: \.offset) { i, f in
                let entered = model.simulatedBandEntered(f)
                HStack {
                    Toggle("\(i + 1) · \(f.frequencyLabel)", isOn: Binding(
                        get: { entered != nil }, set: { _ in model.simulateToggleBand(f) }))
                        .frame(width: 140, alignment: .leading)
                    if let e = entered {
                        Slider(value: Binding(get: { e.gainDB }, set: { model.simulateSetBandGain(f, gain: ($0 * 2).rounded() / 2) }),
                               in: -12...3).tint(Theme.accent)
                        Text(String(format: "%+.1f dB", e.gainDB)).font(Theme.mono(12)).frame(width: 64)
                    }
                }
            }
        }
    }
}

/// Compact list indicator: hairline track, target zone and a dot (no digits).
struct MiniLED: View {
    var value: Double?
    var tolerance: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let v = min(max(value ?? 0, -1), 1)
            let a = abs(v)
            let c = a <= tolerance ? 1 : max(0, 1 - (a - tolerance) / (1 - tolerance))
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.white.opacity(0.09)).frame(width: w, height: 2).offset(y: h / 2 - 1)
                Capsule().fill(Theme.statusGood.opacity(0.3)).frame(width: max(2, w * tolerance), height: 2)
                    .offset(x: w / 2 - w * tolerance / 2, y: h / 2 - 1)
                if value != nil {
                    Circle().fill(Theme.closeness(c)).frame(width: 7, height: 7)
                        .offset(x: (CGFloat(v) + 1) / 2 * w - 3.5, y: h / 2 - 3.5)
                }
            }
        }
    }
}
