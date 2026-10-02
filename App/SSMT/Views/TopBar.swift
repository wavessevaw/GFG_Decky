import SSMTCore
import SwiftUI

/// Toolbar above the content: system status · noise · mini window · more · STOP.
struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        HStack(spacing: 10) {
            if model.appMode == .expert {
                Text(loc.t("mode.expert")).font(Theme.heading(15)).foregroundStyle(Theme.textPrimary)
            }
            Spacer()

            statusPill

            Button { model.toggleNoise() } label: {
                HStack(spacing: 7) {
                    Image(systemName: model.noiseOn ? "waveform" : "waveform.slash")
                    Text(loc.t("noise.short"))
                }
            }
            .buttonStyle(SSMTButtonStyle(active: model.noiseOn))
            .keyboardShortcut(.space, modifiers: [])
            .help(loc.t("noise.toggle"))

            Button { MiniPanelController.shared.toggle() } label: { Image(systemName: "rectangle.on.rectangle") }
                .buttonStyle(SSMTButtonStyle())
                .help(loc.t("mini.toggle"))

            Menu {
                Picker(loc.t("mode.title"), selection: $model.appMode) {
                    Text(loc.t("mode.wizard")).tag(AppMode.wizard)
                    Text(loc.t("mode.expert")).tag(AppMode.expert)
                }
                .pickerStyle(.inline)
                Toggle(loc.t("mode.stage"), isOn: $model.stageMode)
                Divider()
                Button(loc.t("settings.open")) { model.showSettings = true }
                Button(loc.t("session.save")) { model.saveSession() }
                Button(loc.t("session.open")) { model.openSession() }
                Button(loc.t("report.pdf")) { model.exportReport(pdf: true, localizer: loc) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Theme.textPrimary)
            .fixedSize()

            Button { model.emergencyStop() } label: {
                Label(loc.t("action.stop"), systemImage: "stop.fill")
                    .font(.system(size: model.stageMode ? 22 : 13, weight: .semibold))
                    .padding(.horizontal, model.stageMode ? 16 : 2)
                    .padding(.vertical, model.stageMode ? 6 : 0)
            }
            .buttonStyle(SSMTButtonStyle(kind: .danger))
            .help(loc.t("action.stop.help"))
        }
        .padding(.vertical, 6)
    }

    private var statusPill: some View {
        let (key, color): (String, Color) = {
            if !model.isRunning { return ("status.off", Theme.textMuted) }
            if model.snapshot?.microphone.clipped == true { return ("meters.clip", Theme.statusError) }
            if model.appMode == .wizard && !model.wizard.isPrepared { return ("status.running", Theme.accent) }
            return ("status.ready", Theme.statusGood)
        }()
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(loc.t(key)).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
            if let d = model.delay, d.isReliable {
                Text(String(format: "Δt %.2f ms", d.milliseconds)).font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
    }
}
