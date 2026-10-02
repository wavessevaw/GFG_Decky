import SSMTCore
import SwiftUI

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        HStack(spacing: 14) {
            BrandMark(variant: .compact, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(loc.t("app.title")).font(Theme.heading(15)).tracking(1.5).foregroundStyle(Theme.textPrimary)
                Text(loc.t("app.subtitle")).font(Theme.label(9)).tracking(1).foregroundStyle(Theme.textMuted)
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 26)
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
                model.emergencyStop()
            } label: {
                Label(loc.t("action.stop"), systemImage: "stop.fill")
                    .font(Theme.heading(16))
                    .padding(.horizontal, 10)
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
