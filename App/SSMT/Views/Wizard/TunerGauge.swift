import SwiftUI

/// Guitar-tuner style gauge used everywhere in the UI.
///
/// - `.centered`: value −1…1, target 0 (e.g. "add / remove delay"); red at both ends, green in the middle.
/// - `.oneSided`: value 0…1, target at the right (e.g. signal quality); red on the left, green on the right.
/// Needle, readout, frame and lamps take the continuous closeness colour (red → orange → yellow → green).
struct TunerGauge: View {
    enum Mode { case centered, oneSided }

    var title: String
    var value: Double?
    var mode: Mode = .centered
    /// Centered: |value| ≤ tolerance is "in tune". One-sided: value ≥ tolerance is "in tune".
    var tolerance: Double
    var readout: String
    var instruction: String
    var reliable = true
    var leftLabel = ""
    var rightLabel = ""
    var large = false

    private var v: Double {
        guard let value, value.isFinite else { return mode == .centered ? 0 : 0 }
        return mode == .centered ? min(max(value, -1), 1) : min(max(value, 0), 1)
    }

    /// 0 = far from target, 1 = on target.
    private var closeness: Double {
        guard value != nil else { return 0 }
        switch mode {
        case .centered:
            let a = abs(v)
            return a <= tolerance ? 1 : max(0, 1 - (a - tolerance) / max(1 - tolerance, 1e-6))
        case .oneSided:
            return v >= tolerance ? 1 : v / max(tolerance, 1e-6)
        }
    }

    var inTune: Bool { value != nil && closeness >= 1 }
    private var color: Color { value == nil ? Theme.textMuted : Theme.closeness(closeness) }
    /// Needle angle in units of the half scale (−1…1).
    private var needlePosition: Double { mode == .centered ? v : v * 2 - 1 }

    var body: some View {
        VStack(spacing: 8) {
            Text(title.uppercased()).font(Theme.label(12)).tracking(1.4).foregroundStyle(Theme.textSecondary)
            ZStack {
                scale
                needle
                    .rotationEffect(.degrees(needlePosition * 80), anchor: .bottom)
                    .animation(.interpolatingSpring(stiffness: 60, damping: 11), value: needlePosition)
                    .opacity(value == nil ? 0.25 : 1)
            }
            .frame(height: large ? 170 : 120)
            HStack {
                if mode == .centered {
                    directionLamp(left: true, on: value != nil && !inTune && v < 0, label: leftLabel)
                }
                Spacer()
                Text(readout)
                    .font(Theme.mono(large ? 44 : 30, weight: .bold))
                    .foregroundStyle(value == nil ? Theme.textMuted : color)
                    .shadow(color: color.opacity(inTune ? 0.6 : 0.25), radius: inTune ? 10 : 4)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                if mode == .centered {
                    directionLamp(left: false, on: value != nil && !inTune && v > 0, label: rightLabel)
                }
            }
            Text(instruction)
                .font(Theme.heading(large ? 22 : 17))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .frame(minHeight: 26)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(CutCornerShape(cut: 14).fill(Theme.panel))
        .overlay(CutCornerShape(cut: 14).stroke(value == nil ? Theme.hairlineStrong : color.opacity(inTune ? 0.9 : 0.5),
                                                lineWidth: inTune ? 2 : 1))
        .shadow(color: inTune ? color.opacity(0.35) : .clear, radius: 14)
        .opacity(reliable ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.3), value: closeness)
    }

    /// Arc of ticks coloured by how close each position is to the target.
    private var scale: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 6)
            let radius = min(size.width / 2, size.height) - 10
            func point(_ pos: Double, _ r: CGFloat) -> CGPoint {
                let a = (-90 + pos * 80) * Double.pi / 180
                return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
            }
            func closenessAt(_ pos: Double) -> Double {
                switch mode {
                case .centered:
                    let a = abs(pos)
                    return a <= tolerance ? 1 : max(0, 1 - (a - tolerance) / max(1 - tolerance, 1e-6))
                case .oneSided:
                    let x = (pos + 1) / 2
                    return x >= tolerance ? 1 : x / max(tolerance, 1e-6)
                }
            }
            // Coloured band.
            let segments = 60
            for i in 0..<segments {
                let p0 = -1 + 2 * Double(i) / Double(segments), p1 = -1 + 2 * Double(i + 1) / Double(segments)
                var arc = Path()
                arc.addArc(center: center, radius: radius - 4, startAngle: .degrees(-90 + p0 * 80),
                           endAngle: .degrees(-90 + p1 * 80), clockwise: false)
                ctx.stroke(arc, with: .color(Theme.closeness(closenessAt((p0 + p1) / 2)).opacity(0.75)), lineWidth: 7)
            }
            for i in -10...10 {
                let pos = Double(i) / 10
                let major = i % 5 == 0
                var p = Path()
                p.move(to: point(pos, radius - (major ? 24 : 16)))
                p.addLine(to: point(pos, radius - 10))
                ctx.stroke(p, with: .color(Theme.textMuted.opacity(major ? 0.9 : 0.45)), lineWidth: major ? 2 : 1)
            }
        }
    }

    private var needle: some View {
        GeometryReader { geo in
            let h = min(geo.size.width / 2, geo.size.height) - 22
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Capsule()
                    .fill(color)
                    .frame(width: 4, height: h)
                    .shadow(color: color.opacity(0.7), radius: 6)
                Circle().fill(Theme.textPrimary).frame(width: 12, height: 12).offset(y: -6)
            }
            .frame(width: geo.size.width)
        }
    }

    private func directionLamp(left: Bool, on: Bool, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: left ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                .font(.system(size: large ? 26 : 20))
                .foregroundStyle(on ? color : Theme.textMuted.opacity(0.3))
                .shadow(color: on ? color.opacity(0.8) : .clear, radius: 8)
            Text(label).font(Theme.label(10)).foregroundStyle(on ? Theme.textPrimary : Theme.textMuted)
        }
        .frame(width: 90)
    }
}
