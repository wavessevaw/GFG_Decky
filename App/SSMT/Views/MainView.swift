import SSMTCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    var brandNamespace: Namespace.ID? = nil
    var showBrand = true

    var body: some View {
        ZStack {
            Backdrop()
            HStack(spacing: 16) {
                if !model.stageMode {
                    AppSidebar(brandNamespace: brandNamespace, showBrand: showBrand)
                }
                VStack(spacing: 8) {
                    TopBar()
                    switch model.appMode {
                    case .wizard:
                        WizardView()
                    case .expert:
                        VStack(spacing: 14) {
                            MeterPanel()
                            ExpertGraphs()
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .padding(14)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .environment(\.reducedEffects, model.reducedEffects)
        .frame(minWidth: 1100, minHeight: 720)
        .sheet(isPresented: $model.showSettings) {
            VStack(spacing: 0) {
                HStack {
                    Text(loc.t("settings.title")).font(Theme.heading(17))
                    Spacer()
                    Button(loc.t("settings.done")) { model.showSettings = false }.buttonStyle(SSMTButtonStyle(kind: .primary))
                }
                .padding(16)
                SetupSidebar(expert: false)
            }
            .frame(width: 360, height: 660)
            .background(Backdrop())
            .ssmtEnvironment(model, loc)
            .preferredColorScheme(.dark)
        }
    }
}

/// Expert graphs: the only part of the expert screen redrawn on each live snapshot.
/// The response is smoothed once and shared by all plots.
struct ExpertGraphs: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var live: LiveData
    @EnvironmentObject var loc: Localizer

    var body: some View {
        let tf = model.displayTransfer.map { Smoothing.smooth($0, resolution: model.smoothing) }
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
                        TransferPlotView(kind: k, transfer: tf, smoothing: .none,
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
