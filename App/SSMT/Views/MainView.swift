import SSMTCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    var brandNamespace: Namespace.ID? = nil
    var showBrand = true

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(brandNamespace: brandNamespace, showBrand: showBrand, showSettings: $showSettings)
            HStack(spacing: 0) {
                // The setup panel is permanent only in Expert mode; the wizard keeps it in a sheet.
                if model.appMode == .expert && !model.stageMode {
                    SetupSidebar(expert: true)
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                }
                switch model.appMode {
                case .wizard:
                    WizardView(showSettings: $showSettings)
                case .expert:
                    VStack(spacing: 12) {
                        MeterPanel()
                        graphs
                    }
                    .padding(12)
                }
            }
        }
        .background(Theme.background)
        .overlay(Scanlines(opacity: 0.02).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .frame(minWidth: 1100, minHeight: 720)
        .sheet(isPresented: $showSettings) {
            VStack(spacing: 0) {
                HStack {
                    Text(loc.t("settings.title")).font(Theme.heading(18))
                    Spacer()
                    Button(loc.t("settings.done")) { showSettings = false }.buttonStyle(SSMTButtonStyle(kind: .primary))
                }
                .padding(16)
                SetupSidebar(expert: false)
            }
            .frame(width: 340, height: 640)
            .background(Theme.background)
            .environmentObject(model)
            .environmentObject(loc)
            .preferredColorScheme(.dark)
        }
    }

    private var graphs: some View {
        let tf = model.displayTransfer
        let kinds = GraphKind.allCases.filter { model.visibleGraphs.contains($0) }
        return Panel(title: loc.t("graphs.title"), marking: model.smoothing == .none ? "RAW" : "1/\(model.smoothing.rawValue) OCT") {
            if tf == nil {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 30)).foregroundStyle(Theme.textMuted)
                    Text(loc.t("graphs.empty")).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    ForEach(kinds) { k in
                        TransferPlotView(kind: k, transfer: tf, smoothing: model.smoothing,
                                         coherenceThreshold: model.coherenceThreshold,
                                         title: loc.t("graph.\(k.rawValue)"))
                            .frame(maxHeight: k == .magnitude ? .infinity : 200)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
