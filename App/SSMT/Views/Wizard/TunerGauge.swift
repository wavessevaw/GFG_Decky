import SwiftUI

/// The instrument used for every check in the UI: a thin arc scale with a target zone, a fill
/// from the target to the current value and a round pointer, with a large light number inside.
/// Colour carries meaning only: red far from the target → orange → yellow → green on target.
///
/// - `.centered`: value −1…1, target 0 ("more / less"); red at both ends, green in the middle.
/// - `.oneSided`: value 0…1, target at the right (quality); red on the left, green on the right.
struct TunerGauge: View {
    enum Mode { case centered, oneSided }

    var title: String
    var value: Double?
    var mode: Mode = .centered
    /// Centered: |value| ≤ tolerance is on target. One-sided: value ≥ tolerance is on target.
    var tolerance: Double
    var readout: String
    var instruction: String
    var reliable = true
    var large = false
    /// Five scale labels at positions −1, −½, 0, +½, +1; only the ends and the middle are shown.
    var scaleLabels: [String]? = nil
    var unit: String = ""

    // MARK: Derived state

    private var v: Double {
        guard let value, value.isFinite else { return 0 }
        return mode == .centered ? min(max(value, -1), 1) : min(max(value, 0), 1)
    }

    /// Pointer position on the scale, −1…1.
    private var position: Double { mode == .centered ? v : v * 2 - 1 }

    private func closeness(atPosition p: Double) -> Double {
        switch mode {
        case .centered:
            let a = abs(p)
            return a <= tolerance ? 1 : max(0, 1 - (a - tolerance) / max(1 - tolerance, 1e-6))
        case .oneSided:
            let x = (p + 1) / 2
            return x >= tolerance ? 1 : x / max(tolerance, 1e-6)
        }
    }

    private var closeness: Double { value == nil ? 0 : closeness(atPosition: position) }
    var inTune: Bool { value != nil && closeness >= 1 }
    private var color: Color { value == nil ? Theme.textMuted : Theme.closeness(closeness) }

    /// Target zone on the scale, in positions.
    private var targetZone: ClosedRange<Double> {
        mode == .centered ? -tolerance...tolerance : (tolerance * 2 - 1)...1
    }
    /// Where the fill starts: the target for centered gauges, the left end for one-sided ones.
    private var fillOrigin: Double { mode == .centered ? 0 : -1 }

    private var labels: [String] {
        if let scaleLabels, scaleLabels.count == 5 { return [scaleLabels[0], scaleLabels[2], scaleLabels[4]] }
        return mode == .centered ? ["−", "0", "+"] : ["", "", ""]
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: large ? 15 : 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            instrument
                .opacity(reliable ? 1 : 0.5)
            HStack(spacing: 6) {
                if inTune { Image(systemName: "checkmark.circle.fill") }
                Text(instruction).lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.system(size: large ? 18 : 15, weight: .medium))
            .foregroundStyle(value == nil ? Theme.textMuted : color)
            .frame(height: large ? 24 : 20)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 16)
        .animation(.easeInOut(duration: 0.25), value: inTune)
    }

    private var instrument: some View {
        GeometryReader { geo in
            let g = ArcGeometry(size: geo.size, large: large)
            ZStack {
                ArcScale(geometry: g, targetZone: targetZone, labels: labels)
                if value != nil {
                    ArcFill(geometry: g, from: fillOrigin, to: position)
                        .stroke(color, style: StrokeStyle(lineWidth: g.lineWidth, lineCap: .round))
                    ArcPointer(geometry: g, position: position)
                        .fill(color)
                        .overlay(ArcPointer(geometry: g, position: position)
                            .stroke(Color(hex: 0x131715), lineWidth: g.lineWidth * 0.6))
                        .shadow(color: color.opacity(0.35), radius: 6)
                }
                VStack(spacing: 2) {
                    Text(readout)
                        .font(Theme.numeral(large ? 54 : 42))
                        .foregroundStyle(value == nil ? Theme.textMuted : Theme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if !unit.isEmpty {
                        Text(unit).font(.system(size: large ? 14 : 12)).foregroundStyle(Theme.textMuted)
                    }
                }
                .frame(width: g.radius * 1.3)
                .position(x: g.center.x, y: g.center.y - g.radius * 0.6 + (large ? 30 : 24))
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: position)
            .animation(.easeInOut(duration: 0.3), value: closeness)
        }
        .frame(height: large ? 214 : 158)
    }
}

/// Arc layout: a 120° arc around the top of a circle whose centre lies below the readout.
struct ArcGeometry {
    let size: CGSize
    var large = false
    /// Half-span of the arc in degrees.
    let span: Double = 60
    var lineWidth: CGFloat { large ? 7 : 5 }

    var radius: CGFloat {
        let s = CGFloat(sin(span * .pi / 180)), c = CGFloat(cos(span * .pi / 180))
        return max(40, min((size.width - 48) / (2 * s), (size.height - 26) / (1 - c)))
    }
    var center: CGPoint { CGPoint(x: size.width / 2, y: 10 + radius) }
    func angle(_ p: Double) -> Angle { .degrees(-90 + p * span) }
    func point(_ p: Double, radius r: CGFloat) -> CGPoint {
        let a = angle(p).radians
        return CGPoint(x: center.x + r * CGFloat(cos(a)), y: center.y + r * CGFloat(sin(a)))
    }
}

/// Static part of the instrument: track, target zone, fine ticks and three labels.
struct ArcScale: View {
    var geometry: ArcGeometry
    var targetZone: ClosedRange<Double>
    var labels: [String]

    var body: some View {
        Canvas { ctx, _ in
            let g = geometry
            var track = Path()
            track.addArc(center: g.center, radius: g.radius, startAngle: g.angle(-1), endAngle: g.angle(1), clockwise: false)
            ctx.stroke(track, with: .color(.white.opacity(0.09)), style: StrokeStyle(lineWidth: g.lineWidth, lineCap: .round))
            var zone = Path()
            zone.addArc(center: g.center, radius: g.radius, startAngle: g.angle(max(-1, targetZone.lowerBound)),
                        endAngle: g.angle(min(1, targetZone.upperBound)), clockwise: false)
            ctx.stroke(zone, with: .color(Theme.statusGood.opacity(0.28)), style: StrokeStyle(lineWidth: g.lineWidth, lineCap: .round))
            // Fine inner ticks; the middle and end ones are longer.
            for i in -10...10 {
                let p = Double(i) / 10
                let major = i == 0 || abs(i) == 10
                var t = Path()
                t.move(to: g.point(p, radius: g.radius - g.lineWidth - (major ? 12 : 7)))
                t.addLine(to: g.point(p, radius: g.radius - g.lineWidth - 3))
                ctx.stroke(t, with: .color(.white.opacity(major ? 0.45 : 0.16)), lineWidth: 1)
            }
            let font = Font.system(size: g.large ? 12 : 11).monospacedDigit()
            for (k, label) in labels.enumerated() where !label.isEmpty {
                let r = g.radius - g.lineWidth - (k == 1 ? 24 : 22)
                ctx.draw(Text(label).font(font).foregroundColor(Theme.textMuted), at: g.point(Double(k - 1), radius: r))
            }
        }
    }
}

/// Arc from the fill origin to the pointer (animatable).
struct ArcFill: Shape {
    var geometry: ArcGeometry
    var from: Double
    var to: Double

    var animatableData: Double {
        get { to }
        set { to = newValue }
    }

    func path(in _: CGRect) -> Path {
        var p = Path()
        let a = min(from, to), b = max(from, to)
        guard b - a > 0.001 else { return p }
        p.addArc(center: geometry.center, radius: geometry.radius, startAngle: geometry.angle(a),
                 endAngle: geometry.angle(b), clockwise: false)
        return p
    }
}

/// Round pointer sitting on the arc (animatable).
struct ArcPointer: Shape {
    var geometry: ArcGeometry
    var position: Double

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    func path(in _: CGRect) -> Path {
        let c = geometry.point(position, radius: geometry.radius)
        let r = geometry.lineWidth * 1.6
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

/// Small status dot.
struct IndicatorLamp: View {
    var color: Color
    var size: CGFloat

    var body: some View {
        Circle().fill(color).frame(width: size * 0.5, height: size * 0.5)
            .frame(width: size, height: size)
    }
}

/// Compact list indicator: a thin track with a target zone and a pointer, plus the value.
struct MiniMeter: View {
    /// Normalized error −1…1 (0 = target).
    var value: Double?
    var tolerance: Double
    var readout: String
    var width: CGFloat = 120

    private func closeness(_ p: Double) -> Double {
        let a = abs(p)
        return a <= tolerance ? 1 : max(0, 1 - (a - tolerance) / max(1 - tolerance, 1e-6))
    }

    var body: some View {
        let v = min(max(value ?? 0, -1), 1)
        let color = value == nil ? Theme.textMuted : Theme.closeness(closeness(v))
        HStack(spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width, mid = w / 2, y = geo.size.height / 2
                let x = (CGFloat(v) + 1) / 2 * w
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Color.white.opacity(0.09)).frame(width: w, height: 3).offset(y: y - 1.5)
                    Capsule().fill(Theme.statusGood.opacity(0.3))
                        .frame(width: max(3, w * tolerance), height: 3).offset(x: mid - w * tolerance / 2, y: y - 1.5)
                    if value != nil {
                        Capsule().fill(color).frame(width: abs(x - mid), height: 3).offset(x: min(x, mid), y: y - 1.5)
                        Circle().fill(color).frame(width: 9, height: 9).offset(x: x - 4.5, y: y - 4.5)
                    }
                }
            }
            .frame(width: width, height: 12)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: v)
            Text(readout)
                .font(Theme.mono(13))
                .foregroundStyle(value == nil ? Theme.textMuted : Theme.textPrimary)
                .frame(width: 64, alignment: .trailing)
        }
    }
}
