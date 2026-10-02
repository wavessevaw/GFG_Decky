import SSMTCore
import SwiftUI
import UniformTypeIdentifiers

/// Microphone calibration library (user-imported files only) and SPL calibration.
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
                ForEach(model.calibration.microphones) { m in
                    Text(m.name).tag(UUID?.some(m.id))
                }
            }
            if let mic = model.calibration.selectedMicrophone {
                HStack {
                    Text(loc.t("cal.points", mic.frequencies.count)).font(Theme.mono(10)).foregroundStyle(Theme.textMuted)
                    if let h = mic.sensitivityHeader {
                        Text(h).font(Theme.mono(10)).foregroundStyle(Theme.textMuted).lineLimit(1)
                    }
                    Spacer()
                    Button { model.removeMicrophone(mic.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help(loc.t("cal.remove"))
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

    private func applyText() {
        let v = Double(dBFSText.replacingOccurrences(of: ",", with: "."))
        model.setSPLCalibration(dBFSAt94: v)
    }
}
