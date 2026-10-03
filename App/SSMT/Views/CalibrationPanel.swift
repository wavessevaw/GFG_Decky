import SSMTCore
import SwiftUI
import UniformTypeIdentifiers

/// Microphone correction (individual files or built-in typical profiles) and SPL calibration.
struct CalibrationPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    @State private var importing = false
    @State private var dBFSText = ""
    @State private var calibratorLevel = 94.0

    var body: some View {
        Panel(title: loc.t("cal.title")) {
            Picker(loc.t("cal.mic"), selection: Binding(get: { model.calibration.selectedMicrophoneID },
                                                       set: { model.selectMicrophone($0) })) {
                Text(loc.t("cal.mic.none")).tag(UUID?.none)
                if !model.calibration.microphones.isEmpty {
                    Section(loc.t("cal.section.files")) {
                        ForEach(model.calibration.microphones) { m in
                            Text(m.name).tag(UUID?.some(m.id))
                        }
                    }
                }
                ForEach(MicrophoneProfile.Kind.allCases, id: \.self) { kind in
                    Section(loc.t("cal.section.\(kind.rawValue)")) {
                        ForEach(MicrophoneProfiles.all.filter { $0.kind == kind }) { p in
                            Text(p.displayName).tag(UUID?.some(p.uuid))
                        }
                    }
                }
            }
            if let mic = model.calibration.selectedMicrophone {
                MicCurvePreview(calibration: mic).frame(height: 70)
                if let profile = model.calibration.selectedProfile {
                    profileNotes(profile)
                } else {
                    HStack {
                        StatusBadge(level: .good, text: loc.t("cal.individual"))
                        Text(loc.t("cal.points", mic.frequencies.count)).font(Theme.mono(11)).foregroundStyle(Theme.textMuted)
                        Spacer()
                        Button { model.removeMicrophone(mic.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help(loc.t("cal.remove"))
                    }
                    if let h = mic.sensitivityHeader {
                        Text(h).font(Theme.mono(11)).foregroundStyle(Theme.textMuted).lineLimit(1)
                    }
                }
            } else {
                StatusBadge(level: .warning, text: loc.t("cal.mic.uncalibrated"))
            }
            Button {
                importing = true
            } label: {
                Label(loc.t("cal.import"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(SSMTButtonStyle())
            .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .commaSeparatedText, .text, .data]) { result in
                if case .success(let url) = result {
                    let scoped = url.startAccessingSecurityScopedResource()
                    model.importMicrophoneCalibration(from: url)
                    if scoped { url.stopAccessingSecurityScopedResource() }
                }
            }

            TechDivider()

            HStack {
                Text(loc.t("cal.spl")).font(Theme.label(11)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if let spl = model.calibration.spl {
                    Text(String(format: "%.1f dBFS @ 94 dB", spl.dBFSAt94dBSPL)).font(Theme.mono(11))
                } else {
                    StatusBadge(level: .idle, text: loc.t("cal.spl.none"))
                }
            }
            HStack {
                TextField("dBFS @ 94 dB SPL", text: $dBFSText)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11))
                    .onSubmit { applyText() }
                Button(loc.t("cal.apply")) { applyText() }.buttonStyle(SSMTButtonStyle())
            }
            HStack {
                Picker("", selection: $calibratorLevel) {
                    Text("94 dB").tag(94.0)
                    Text("114 dB").tag(114.0)
                }
                .labelsHidden()
                .frame(width: 90)
                Button(loc.t("cal.calibrator")) { model.calibrateWithCalibrator(level: calibratorLevel) }
                    .buttonStyle(SSMTButtonStyle())
                    .disabled(!model.isRunning)
                    .help(loc.t("cal.calibrator.help"))
            }
        }
    }

    @ViewBuilder private func profileNotes(_ p: MicrophoneProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusBadge(level: p.isNominallyFlat ? .idle : .warning,
                        text: loc.t(p.isNominallyFlat ? "cal.typical.flat" : "cal.typical"))
            Text(loc.t(p.isNominallyFlat ? "cal.typical.flat.note" : "cal.typical.note"))
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if p.pattern == .cardioid {
                Text(loc.t("cal.cardioid.note"))
                    .font(.system(size: 11)).foregroundStyle(Theme.signalYellow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func applyText() {
        let v = Double(dBFSText.replacingOccurrences(of: ",", with: "."))
        model.setSPLCalibration(dBFSAt94: v)
    }
}

/// Small plot of the microphone response that will be removed (±10 dB, 20 Hz–20 kHz).
struct MicCurvePreview: View {
    var calibration: MicrophoneCalibration

    var body: some View {
        Canvas { ctx, size in
            let axis = FrequencyAxis()
            func y(_ db: Double) -> CGFloat { size.height / 2 - CGFloat(max(-10, min(10, db))) * size.height / 20 }
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: size.height / 2)); zero.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(zero, with: .color(.white.opacity(0.15)), lineWidth: 1)
            for f in [100.0, 1000, 10000] {
                let x = axis.x(f, width: size.width)
                var g = Path(); g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(g, with: .color(.white.opacity(0.06)), lineWidth: 1)
                ctx.draw(Text(FrequencyAxis.label(f)).font(Theme.mono(9)).foregroundColor(Theme.textMuted),
                         at: CGPoint(x: x + 3, y: size.height - 6), anchor: .leading)
            }
            var curve = Path()
            var f = 20.0, first = true
            while f <= 20000 {
                let p = CGPoint(x: axis.x(f, width: size.width), y: y(calibration.deviation(at: f)))
                if first { curve.move(to: p); first = false } else { curve.addLine(to: p) }
                f *= pow(2, 1.0 / 12)
            }
            ctx.stroke(curve, with: .color(Theme.accent), lineWidth: 1.5)
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Color.white.opacity(0.03)))
    }
}

/// Compact microphone chooser (same list as the calibration panel) for the preparation checklist.
struct MicProfileMenu: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        Menu {
            Button(loc.t("cal.mic.none")) { model.selectMicrophone(nil) }
            if !model.calibration.microphones.isEmpty {
                Section(loc.t("cal.section.files")) {
                    ForEach(model.calibration.microphones) { m in
                        Button(m.name) { model.selectMicrophone(m.id) }
                    }
                }
            }
            ForEach(MicrophoneProfile.Kind.allCases, id: \.self) { kind in
                Section(loc.t("cal.section.\(kind.rawValue)")) {
                    ForEach(MicrophoneProfiles.all.filter { $0.kind == kind }) { p in
                        Button(p.displayName) { model.selectMicrophone(p.uuid) }
                    }
                }
            }
        } label: {
            Text(title).lineLimit(1)
        }
        .fixedSize()
        .help(loc.t("prep.mic.profile"))
    }

    private var title: String {
        if let p = model.calibration.selectedProfile { return p.displayName }
        return model.calibration.selectedMicrophone?.name ?? loc.t("cal.mic.none")
    }
}
