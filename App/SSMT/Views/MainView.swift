import SSMTCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            HStack(spacing: 0) {
                SetupSidebar()
                Rectangle().fill(Theme.hairline).frame(width: 1)
                VStack(spacing: 12) {
                    MeterPanel()
                    graphs
                }
                .padding(12)
            }
        }
        .background(Theme.background)
        .overlay(Scanlines().ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .frame(minWidth: 1100, minHeight: 720)
    }

    private var graphs: some View {
        let tf = model.snapshot?.transfer
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
