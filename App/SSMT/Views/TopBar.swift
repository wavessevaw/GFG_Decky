import SSMTCore
import SwiftUI

/// Minimal top bar: logo · step progress · noise · mini window · menu · STOP.
struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    var brandNamespace: Namespace.ID? = nil
    var showBrand = true
    @Binding var showSettings: Bool
    @State private var showAbout = false

    var body: some View {
        HStack(spacing: 16) {
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

            if model.appMode == .wizard {
                ProgressStrip(step: SSMTCoreStep(index: model.wizard.step.rawValue))
            } else {
                Text(loc.t("mode.expert").uppercased()).font(Theme.label(11)).tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let d = model.delay, d.isReliable {
                Text(String(format: "Δt %.2f ms", d.milliseconds)).font(Theme.mono(11)).foregroundStyle(Theme.textMuted)
            }

            Button { model.toggleNoise() } label: {
                HStack(spacing: 6) {
                    Circle().fill(model.noiseOn ? Theme.accentHot : Theme.textMuted).frame(width: 7, height: 7)
                        .shadow(color: model.noiseOn ? Theme.accentHot : .clear, radius: 4)
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
                if model.appMode == .wizard {
                    Button(loc.t("settings.open")) { showSettings = true }
                }
                Button(loc.t("session.save")) { model.saveSession() }
                Button(loc.t("session.open")) { model.openSession() }
                Button(loc.t("report.pdf")) { model.exportReport(pdf: true, localizer: loc) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 34)

            Button { model.emergencyStop() } label: {
                Label(loc.t("action.stop"), systemImage: "stop.fill")
                    .font(Theme.heading(model.stageMode ? 24 : 15))
                    .padding(.horizontal, model.stageMode ? 20 : 8)
                    .padding(.vertical, model.stageMode ? 6 : 0)
            }
            .buttonStyle(SSMTButtonStyle(kind: .danger))
            .help(loc.t("action.stop.help"))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
