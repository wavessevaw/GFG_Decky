import SSMTCore
import SwiftUI

/// Canvas plot of one aspect of a transfer function. Points below the coherence threshold are
/// drawn muted and their frequency columns are hatched, so unreliable data is visible as such.
struct TransferPlotView: View {
    var kind: GraphKind
    var transfer: TransferFunction?
    var smoothing: SmoothingResolution
    var coherenceThreshold: Double
    var title: String
    var lineWidth: CGFloat = 1.6

    private let axis = FrequencyAxis()

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let plot = CGRect(x: 40, y: 6, width: size.width - 48, height: size.height - 22)
            drawGrid(&ctx, plot: plot)
            guard let tf = transfer else { return }
            let display = Smoothing.smooth(tf, resolution: smoothing)
            let mask = display.coherenceMask(threshold: coherenceThreshold)
            if kind != .coherence { drawHatch(&ctx, plot: plot, tf: display, mask: mask) }
            drawTrace(&ctx, plot: plot, tf: display, mask: mask)
        }
        .overlay(alignment: .topLeading) {
            Text(title)
                .font(Theme.label(11))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 46).padding(.top, 8)
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).fill(Color.white.opacity(0.03)))
    }

    // MARK: - Ranges

    private var range: ClosedRange<Double> {
        switch kind {
        case .magnitude: return -30...18
        case .phase: return -180...180
        case .coherence: return 0...1
        }
    }

    private var gridValues: [Double] {
        switch kind {
        case .magnitude: return [-24, -18, -12, -6, 0, 6, 12]
        case .phase: return [-180, -90, 0, 90, 180]
        case .coherence: return [0, 0.25, 0.5, 0.75, 1]
        }
    }

    private func y(_ v: Double, plot: CGRect) -> CGFloat {
        let t = (v - range.lowerBound) / (range.upperBound - range.lowerBound)
        return plot.maxY - CGFloat(min(max(t, 0), 1)) * plot.height
    }

    private func value(_ tf: TransferFunction, _ i: Int, offsetDB: Double) -> Double? {
        guard tf.isValid(i) else { return nil }
        switch kind {
        case .magnitude: return Decibel.fromAmplitude(tf.response[i].magnitude) - offsetDB
        case .phase: return tf.response[i].phase * 180 / .pi
        case .coherence: return tf.coherence[i]
        }
    }

    /// Normalizes the magnitude so the median of coherent points in 100 Hz–10 kHz sits at 0 dB.
    private func magnitudeOffset(_ tf: TransferFunction, mask: [Bool]) -> Double {
        guard kind == .magnitude else { return 0 }
        let vals = tf.frequencies.indices
            .filter { tf.frequencies[$0] >= 100 && tf.frequencies[$0] <= 10000 && mask[$0] && tf.isValid($0) }
            .map { Decibel.fromAmplitude(tf.response[$0].magnitude) }
            .sorted()
        return vals.isEmpty ? 0 : vals[vals.count / 2]
    }

    // MARK: - Drawing

    private func drawGrid(_ ctx: inout GraphicsContext, plot: CGRect) {
        for f in FrequencyAxis.minorTicks {
            let x = plot.minX + axis.x(f, width: plot.width)
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: plot.minY)); $0.addLine(to: CGPoint(x: x, y: plot.maxY)) },
                       with: .color(.white.opacity(0.04)), lineWidth: 1)
        }
        for f in FrequencyAxis.majorTicks {
            let x = plot.minX + axis.x(f, width: plot.width)
            ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: plot.minY)); $0.addLine(to: CGPoint(x: x, y: plot.maxY)) },
                       with: .color(.white.opacity(0.10)), lineWidth: 1)
            ctx.draw(Text(FrequencyAxis.label(f)).font(Theme.mono(10)).foregroundColor(Theme.textMuted),
                     at: CGPoint(x: x, y: plot.maxY + 9))
        }
        for v in gridValues {
            let yy = y(v, plot: plot)
            ctx.stroke(Path { $0.move(to: CGPoint(x: plot.minX, y: yy)); $0.addLine(to: CGPoint(x: plot.maxX, y: yy)) },
                       with: .color(.white.opacity(v == 0 && kind != .coherence ? 0.18 : 0.07)), lineWidth: 1)
            let label = kind == .coherence ? String(format: "%.2f", v) : String(format: "%+.0f", v)
            ctx.draw(Text(label).font(Theme.mono(10)).foregroundColor(Theme.textMuted),
                     at: CGPoint(x: plot.minX - 18, y: yy))
        }
        if kind == .coherence {
            let yy = y(coherenceThreshold, plot: plot)
            ctx.stroke(Path { $0.move(to: CGPoint(x: plot.minX, y: yy)); $0.addLine(to: CGPoint(x: plot.maxX, y: yy)) },
                       with: .color(Theme.signalYellow.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    private func drawHatch(_ ctx: inout GraphicsContext, plot: CGRect, tf: TransferFunction, mask: [Bool]) {
        var region = Path()
        let n = tf.frequencies.count
        var i = 0
        while i < n {
            guard !mask[i] else { i += 1; continue }
            let start = i
            while i < n && !mask[i] { i += 1 }
            let f0 = tf.frequencies[start] / pow(2, 1.0 / 48), f1 = tf.frequencies[i - 1] * pow(2, 1.0 / 48)
            let x0 = plot.minX + axis.x(max(f0, axis.minFrequency), width: plot.width)
            let x1 = plot.minX + axis.x(min(f1, axis.maxFrequency), width: plot.width)
            region.addRect(CGRect(x: x0, y: plot.minY, width: max(1, x1 - x0), height: plot.height))
        }
        guard !region.isEmpty else { return }
        ctx.drawLayer { layer in
            layer.clip(to: region)
            layer.fill(Path(plot), with: .color(.white.opacity(0.025)))
            var hatch = Path()
            var x = plot.minX - plot.height
            while x < plot.maxX {
                hatch.move(to: CGPoint(x: x, y: plot.maxY))
                hatch.addLine(to: CGPoint(x: x + plot.height, y: plot.minY))
                x += 7
            }
            layer.stroke(hatch, with: .color(.white.opacity(0.07)), lineWidth: 1)
        }
    }

    private func drawTrace(_ ctx: inout GraphicsContext, plot: CGRect, tf: TransferFunction, mask: [Bool]) {
        let offset = magnitudeOffset(tf, mask: mask)
        var good = Path(), weak = Path()
        var lastPoint: CGPoint?
        var lastValue: Double?
        var lastGood = false
        for i in tf.frequencies.indices {
            let f = tf.frequencies[i]
            guard f >= axis.minFrequency, f <= axis.maxFrequency, let v = value(tf, i, offsetDB: offset) else {
                lastPoint = nil
                continue
            }
            let p = CGPoint(x: plot.minX + axis.x(f, width: plot.width), y: y(v, plot: plot))
            let isGood = mask[i] || kind == .coherence
            // Break the phase trace at wraps instead of drawing vertical lines.
            let wrapped = kind == .phase && lastValue.map { abs(v - $0) > 180 } == true
            if let lp = lastPoint, !wrapped {
                var seg = Path()
                seg.move(to: lp)
                seg.addLine(to: p)
                if isGood && lastGood { good.addPath(seg) } else { weak.addPath(seg) }
            }
            lastPoint = p
            lastValue = v
            lastGood = isGood
        }
        let color: Color = kind == .coherence ? Theme.signalYellow : Theme.accent
        ctx.stroke(weak, with: .color(Theme.textMuted.opacity(0.6)), lineWidth: lineWidth * 0.8)
        // Soft glow under the main trace.
        ctx.stroke(good, with: .color(color), lineWidth: lineWidth)
    }
}
