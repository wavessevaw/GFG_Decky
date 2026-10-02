import SSMTCore
import SwiftUI

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    var brandNamespace: Namespace.ID? = nil
    var showBrand = true
    @State private var showAbout = false

    var body: some View {
        HStack(spacing: 14) {
            Button { showAbout = true } label: {
                ZStack {
                    if showBrand {
                        BrandMark(variant: .compact, height: 22).modifier(MatchedBrand(namespace: brandNamespace))
                    }
                }
                .frame(minWidth: 40, minHeight: 22)
            }
            .buttonStyle(.plain)
            .help(loc.t("about.title"))
            .popover(isPresented: $showAbout) { AboutView() }
            VStack(alignment: .leading, spacing: 0) {
                Text(loc.t("app.title")).font(Theme.heading(15)).tracking(1.5).foregroundStyle(Theme.textPrimary)
                Text(loc.t("app.subtitle")).font(Theme.label(9)).tracking(1).foregroundStyle(Theme.textMuted)
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 26)
            Picker("", selection: $model.appMode) {
                Text(loc.t("mode.wizard")).tag(AppMode.wizard)
                Text(loc.t("mode.expert")).tag(AppMode.expert)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 200)
            Toggle(loc.t("mode.stage"), isOn: $model.stageMode)
                .toggleStyle(.button)
                .help(loc.t("mode.stage.help"))
            engineStatus
            Spacer()
            if let d = model.delay {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(loc.t("delay.locked")).font(Theme.label(9)).foregroundStyle(Theme.textMuted)
                    Text(String(format: "%.2f ms  ·  %.2f m", d.milliseconds, d.meters(celsius: model.temperatureCelsius)))
                        .font(Theme.mono(12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                }
            }
            Button {
                model.toggleNoise()
            } label: {
                Label(model.noiseOn ? loc.t("noise.on") : loc.t("noise.start"),
                      systemImage: model.noiseOn ? "waveform" : "play.fill")
            }
            .buttonStyle(SSMTButtonStyle(kind: .primary, active: model.noiseOn))
            .keyboardShortcut(.space, modifiers: [])

            Button {
                MiniPanelController.shared.toggle()
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
            .buttonStyle(SSMTButtonStyle())
            .help(loc.t("mini.toggle"))

            Button {
                model.emergencyStop()
            } label: {
                Label(loc.t("action.stop"), systemImage: "stop.fill")
                    .font(Theme.heading(model.stageMode ? 26 : 16))
                    .padding(.horizontal, model.stageMode ? 22 : 10)
                    .padding(.vertical, model.stageMode ? 6 : 0)
            }
            .buttonStyle(SSMTButtonStyle(kind: .danger))
            .help(loc.t("action.stop.help"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    @ViewBuilder private var engineStatus: some View {
        if model.isRunning {
            StatusBadge(level: .good, text: loc.t("engine.running"))
        } else {
            StatusBadge(level: .idle, text: loc.t("engine.stopped"))
        }
        if let s = model.snapshot, s.discontinuities > 0 {
            StatusBadge(level: .warning, text: loc.t("engine.dropouts"))
        }
    }
}
