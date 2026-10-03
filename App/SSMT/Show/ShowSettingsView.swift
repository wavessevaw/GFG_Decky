import SSMTAudio
import SSMTCore
import SwiftUI

/// Audio interface, show outputs (names and patch), panic and double-GO settings.
struct ShowSettingsView: View {
    @EnvironmentObject var show: ShowStore
    @EnvironmentObject var loc: Localizer
    @State private var devices: [AudioDeviceInfo] = []

    private var device: AudioDeviceInfo? { show.doc.deviceUID.flatMap { uid in devices.first { $0.uid == uid } } }
    private var deviceChannels: Int { device?.outputChannels ?? 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(loc.t("show.settings")).font(Theme.heading(17))
                Spacer()
                Button(loc.t("settings.done")) {
                    show.restartOutput() // device, patch or output count may have changed
                    show.showSettings = false
                }
                .buttonStyle(SSMTButtonStyle(kind: .primary))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(loc.t("setup.interface")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Picker("", selection: Binding(get: { show.doc.deviceUID ?? "" }, set: { v in
                    show.edit { $0.deviceUID = v.isEmpty ? nil : v }
                })) {
                    Text(loc.t("show.device.default")).tag("")
                    ForEach(devices.filter { $0.outputChannels > 0 }) { d in
                        Text("\(d.name) · \(d.outputChannels) out").tag(d.uid)
                    }
                }
                .labelsHidden()
            }
            HStack {
                Text(String(format: loc.t("show.outputs.count"), show.doc.outputs.count)).font(.system(size: 13))
                Stepper("", value: Binding(get: { show.doc.outputs.count }, set: { n in
                    show.edit { d in
                        let n = min(64, max(1, n))
                        while d.outputs.count < n {
                            let i = d.outputs.count
                            d.outputs.append(ShowOutput(name: "\(i + 1)", deviceChannel: i))
                        }
                        if d.outputs.count > n { d.outputs.removeLast(d.outputs.count - n) }
                    }
                }), in: 1...64)
                .labelsHidden()
                Spacer()
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(show.doc.outputs.enumerated()), id: \.offset) { i, o in
                        HStack(spacing: 10) {
                            Text("\(i + 1)").font(Theme.mono(12)).foregroundStyle(Theme.textSecondary).frame(width: 24, alignment: .trailing)
                            TextField("", text: Binding(get: { o.name }, set: { v in show.edit { $0.outputs[i].name = v } }))
                                .textFieldStyle(.roundedBorder)
                            Image(systemName: "arrow.right").foregroundStyle(Theme.textMuted)
                            Picker("", selection: Binding(get: { o.deviceChannel ?? -1 }, set: { v in
                                show.edit { $0.outputs[i].deviceChannel = v < 0 ? nil : v }
                            })) {
                                Text("—").tag(-1)
                                ForEach(0..<max(deviceChannels, (o.deviceChannel ?? 0) + 1), id: \.self) { ch in
                                    Text(String(format: loc.t("show.channel"), ch + 1)).tag(ch)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
            HStack(spacing: 16) {
                stepper(loc.t("show.panicFade"), value: Binding(get: { show.doc.panicFade }, set: { v in show.edit { $0.panicFade = v } }), range: 0...10, step: 0.5)
                stepper(loc.t("show.goGuard"), value: Binding(get: { show.doc.doubleGoGuard }, set: { v in show.edit { $0.doubleGoGuard = v } }), range: 0...2, step: 0.1)
            }
            HStack(spacing: 10) {
                Text(loc.t("show.buffer")).font(.system(size: 13))
                Picker("", selection: $show.bufferFrames) {
                    ForEach([128, 256, 512, 1024, 2048], id: \.self) { n in
                        Text(String(format: loc.t("show.buffer.value"), n, Double(n) / max(1, show.sampleRate) * 1000)).tag(n)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
                Spacer()
            }
            Text(loc.t("show.buffer.hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(loc.t("show.settings.hint")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 520)
        .background(Backdrop())
        .onAppear {
            devices = DeviceCatalog.allDevices()
        }
    }

    private func stepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        Stepper(String(format: title, value.wrappedValue), value: value, in: range, step: step)
            .font(.system(size: 13))
    }
}
