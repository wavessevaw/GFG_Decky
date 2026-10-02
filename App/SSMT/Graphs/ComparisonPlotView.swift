import SSMTCore
import SwiftUI

/// Magnitude-only comparison of several curves (before / prediction / after), 1/6-oct smoothed.
/// Used on wizard screens, where phase and coherence are deliberately not shown.
struct ComparisonPlotView: View {
    struct Curve: Identifiable {
        var id: String { label }
        var label: String
        var transfer: TransferFunction
        var color: Color
        var dashed = false
    }

    var curves: [Curve]
    var band: ClosedRange<Double>?
    var range: ClosedRange<Double> = 20...1000

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { ctx, size in
                let plot = CGRect(x: 36, y: 6, width: size.width - 42, height: size.height - 22)
                let axis = FrequencyAxis(minFrequency: range.lowerBound, maxFrequency: range.upperBound)
                let smoothed = curves.map { Smoothing.smooth($0.transfer, resolution: .oct6) }
                // Common vertical reference: the median of the first curve in the plotted range.
                let ref = medianDB(smoothed.first)
                func y(_ db: Double) -> CGFloat {
                    let t = (db - ref + 24) / 36
                    return plot.maxY - CGFloat(min(max(t, 0), 1)) * plot.height
                }
                if let b = band {
                    let x0 = plot.minX + axis.x(max(b.lowerBound, range.lowerBound), width: plot.width)
                    let x1 = plot.minX + axis.x(min(b.upperBound, range.upperBound), width: plot.width)
                    ctx.fill(Path(CGRect(x: x0, y: plot.minY, width: x1 - x0, height: plot.height)),
                             with: .color(Theme.accent.opacity(0.07)))
                }
                ctx.stroke(Path(plot), with: .color(Theme.hairline), lineWidth: 1)
                for f in [20.0, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000] where range.contains(f) {
                    let x = plot.minX + axis.x(f, width: plot.width)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: plot.minY)); $0.addLine(to: CGPoint(x: x, y: plot.maxY)) },
                               with: .color(.white.opacity(0.08)), lineWidth: 1)
                    ctx.draw(Text(FrequencyAxis.label(f)).font(Theme.mono(9)).foregroundColor(Theme.textMuted),
                             at: CGPoint(x: x, y: plot.maxY + 9))
                }
                for db in stride(from: -18.0, through: 12, by: 6) {
                    let yy = y(ref + db)
                    ctx.stroke(Path { $0.move(to: CGPoint(x: plot.minX, y: yy)); $0.addLine(to: CGPoint(x: plot.maxX, y: yy)) },
                               with: .color(.white.opacity(db == 0 ? 0.16 : 0.06)), lineWidth: 1)
                    ctx.draw(Text(String(format: "%+.0f", db)).font(Theme.mono(9)).foregroundColor(Theme.textMuted),
                             at: CGPoint(x: plot.minX - 16, y: yy))
                }
                for (c, tf) in zip(curves, smoothed) {
                    var p = Path()
                    var started = false
                    for i in tf.frequencies.indices where range.contains(tf.frequencies[i]) && tf.isValid(i) {
                        let pt = CGPoint(x: plot.minX + axis.x(tf.frequencies[i], width: plot.width),
                                         y: y(Decibel.fromAmplitude(tf.response[i].magnitude)))
                        if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
                    }
                    ctx.stroke(p, with: .color(c.color),
                               style: StrokeStyle(lineWidth: 2, dash: c.dashed ? [6, 4] : []))
                }
            }
            HStack(spacing: 14) {
                ForEach(curves) { c in
                    HStack(spacing: 5) {
                        Rectangle().fill(c.color).frame(width: 14, height: 2)
                        Text(c.label).font(Theme.label(10)).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.leading, 36)
        }
        .background(Color.black.opacity(0.35))
    }

    private func medianDB(_ tf: TransferFunction?) -> Double {
        guard let tf else { return 0 }
        let v = tf.frequencies.indices.filter { range.contains(tf.frequencies[$0]) && tf.isValid($0) }
            .map { Decibel.fromAmplitude(tf.response[$0].magnitude) }.sorted()
        return v.isEmpty ? 0 : v[v.count / 2]
    }
}
