import SSMTCore
import SwiftUI

/// Editor for the user's own target curve: points (frequency, dB), log interpolation, live preview.
struct TargetEditorView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Localizer
    @Environment(\.dismiss) private var dismiss
    @State private var points: [TargetPoint] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc.t("target.editor")).font(Theme.heading(20))
            Text(loc.t("target.editor.hint")).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            ComparisonPlotView(curves: [.init(label: loc.t("target.custom"), transfer: preview, color: Theme.dataBlue)],
                               band: nil, range: 20...20000, absolute: true)
                .frame(height: 180)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(points.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(Theme.mono(12)).frame(width: 20)
                            TextField("Hz", value: Binding(get: { points[i].frequency },
                                                          set: { points[i].frequency = min(max($0, 10), 24000) }),
                                      format: .number.precision(.fractionLength(0)))
                                .textFieldStyle(.roundedBorder).font(Theme.mono(12)).frame(width: 90)
                            Text("Hz").font(Theme.label(11)).foregroundStyle(Theme.textMuted)
                            Stepper(value: Binding(get: { points[i].gainDB }, set: { points[i].gainDB = min(max($0, -12), 12) }),
                                    in: -12...12, step: 0.5) {
                                Text(String(format: "%+.1f dB", points[i].gainDB)).font(Theme.mono(12)).frame(width: 70, alignment: .trailing)
                            }
                            Spacer()
                            Button { points.remove(at: i) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).disabled(points.count <= 2)
                        }
                    }
                }
            }
            .frame(height: 220)
            HStack {
                Button(loc.t("target.addPoint")) {
                    let last = points.last?.frequency ?? 1000
                    points.append(TargetPoint(min(last * 2, 20000), points.last?.gainDB ?? 0))
                }
                .buttonStyle(SSMTButtonStyle())
                Menu(loc.t("target.startFrom")) {
                    ForEach(TargetCurve.Preset.allCases.filter { $0 != .custom }, id: \.self) { p in
                        Button(loc.t("target.\(p.rawValue)")) { points = TargetCurve.preset(p).points }
                    }
                }
                .frame(width: 180)
                Spacer()
                Button(loc.t("action.cancel")) { dismiss() }.buttonStyle(SSMTButtonStyle())
                Button(loc.t("cal.apply")) {
                    model.wizard.configuration.target = TargetCurve(preset: .custom, name: loc.t("target.custom"),
                                                                    points: points.sorted { $0.frequency < $1.frequency })
                    dismiss()
                }
                .buttonStyle(SSMTButtonStyle(kind: .primary))
            }
        }
        .padding(20)
        .frame(width: 620)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
        .onAppear {
            let current = model.wizard.configuration.target
            points = current.preset == .custom ? current.points : TargetCurve.preset(current.preset).points
        }
    }

    private var preview: TransferFunction {
        let curve = TargetCurve(preset: .custom, name: "", points: points)
        let f = FrequencyGrid().frequencies
        return .fromDB(f.map { curve.value(at: $0) }, frequencies: f)
    }
}
