import SwiftUI

/// Retrofuturistic measuring instrument used for every check in the UI.
///
/// Retro layer: bakelite case with screws, printed scale with ticks and numbers, a physical needle
/// with spring inertia (slight overshoot), gas-discharge (nixie-style) digits, an indicator lamp.
/// Futuristic layer: an LED segment arc lit from the target to the needle in the closeness colour,
/// subtle HUD corners on the glass, a phosphor afterglow that trails the needle,
/// and a VFD-style status strip.
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
    var leftLabel = ""
    var rightLabel = ""
    var large = false
    /// Five scale labels at positions −1, −½, 0, +½, +1 (nil → generic labels).
    var scaleLabels: [String]? = nil
    var unit: String = ""

    // MARK: Derived state

    private var v: Double {
        guard let value, value.isFinite else { return 0 }
        return mode == .centered ? min(max(value, -1), 1) : min(max(value, 0), 1)
    }

    /// Needle position on the scale, −1…1.
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

    private var labels: [String] {
        if let scaleLabels, scaleLabels.count == 5 { return scaleLabels }
        return mode == .centered ? ["−", "", "0", "", "+"] : ["0", "", "50", "", "100"]
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 8) {
            Text(title.uppercased())
                .font(Theme.label(11)).tracking(1.6).foregroundStyle(Theme.textMuted)
            instrument
                .opacity(reliable ? 1 : 0.6)
            Text(instruction)
                .font(Theme.heading(large ? 20 : 16))
                .foregroundStyle(value == nil ? Theme.textMuted : color)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(height: large ? 26 : 22)
        }
        .frame(maxWidth: .infinity)
    }

    private var instrument: some View {
        let height: CGFloat = large ? 300 : 236
        return GeometryReader { geo in
            let g = MeterGeometry(size: geo.size)
            ZStack(alignment: .topLeading) {
                Bakelite()
                // Face window.
                RoundedRectangle(cornerRadius: 6)
                    .fill(RadialGradient(colors: [Color(hex: 0x1E2023), Color(hex: 0x0C0D0E)],
                                         center: UnitPoint(x: 0.5, y: 0.9), startRadius: 0, endRadius: g.face.width))
                    .frame(width: g.face.width, height: g.face.height)
                    .offset(x: g.face.minX, y: g.face.minY)
                ZStack(alignment: .topLeading) {
                    faceCanvas(g)
                    // Phosphor afterglow: a blurred needle that follows slowly.
                    NeedleShape(position: position, geometry: g, tipOnly: false)
                        .stroke(color.opacity(0.45), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .blur(radius: 3)
                        .animation(.easeOut(duration: 0.9), value: position)
                    // Physical needle: spring with slight overshoot.
                    NeedleShape(position: position, geometry: g, tipOnly: false)
                        .stroke(Color(hex: 0xECE6D6), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 2, y: 3)
                        .animation(.interpolatingSpring(stiffness: 70, damping: 8), value: position)
                    NeedleShape(position: position, geometry: g, tipOnly: true)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .animation(.interpolatingSpring(stiffness: 70, damping: 8), value: position)
                    Scanlines(opacity: 0.035)
                    LinearGradient(stops: [.init(color: .white.opacity(0.13), location: 0),
                                           .init(color: .white.opacity(0.02), location: 0.42),
                                           .init(color: .clear, location: 0.43)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .allowsHitTesting(false)
                }
                .opacity(value == nil ? 0.55 : 1)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(FaceClip(rect: g.face))
                deck(g)
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.3), value: closeness)
    }

    // MARK: Face

    private func faceCanvas(_ g: MeterGeometry) -> some View {
        Canvas { ctx, _ in
            let f = g.face
            // LED segment arc (lit from the target to the needle).
            let segments = 33
            for i in 0..<segments {
                let p = -1 + 2 * (Double(i) + 0.5) / Double(segments)
                let lit: Bool
                if value == nil {
                    lit = false
                } else if mode == .centered {
                    lit = (position >= 0 ? (p >= -0.03 && p <= position) : (p <= 0.03 && p >= position))
                        || (inTune && abs(p) <= tolerance + 0.04)
                } else {
                    lit = p <= position
                }
                var seg = Path()
                seg.move(to: g.point(p, radius: g.radius - 12))
                seg.addLine(to: g.point(p, radius: g.radius - 2))
                if lit {
                    let c = Theme.closeness(closeness(atPosition: p))
                    var glow = ctx
                    glow.addFilter(.blur(radius: 3))
                    glow.stroke(seg, with: .color(c.opacity(0.8)), lineWidth: 8)
                    ctx.stroke(seg, with: .color(c), lineWidth: 6)
                } else {
                    ctx.stroke(seg, with: .color(Color(hex: 0x2A2C30)), lineWidth: 6)
                }
            }

            // Printed colour sector (retro print) and ticks.
            let n = 60
            for i in 0..<n {
                let p0 = -1 + 2 * Double(i) / Double(n), p1 = -1 + 2 * Double(i + 1) / Double(n)
                var arc = Path()
                arc.addArc(center: g.pivot, radius: g.radius - 20, startAngle: g.angle(p0), endAngle: g.angle(p1), clockwise: false)
                ctx.stroke(arc, with: .color(Theme.closeness(closeness(atPosition: (p0 + p1) / 2)).opacity(0.25)), lineWidth: 2)
            }
            let ink = Color(hex: 0xECE6D6)
            for i in -10...10 {
                let p = Double(i) / 10
                let major = i % 10 == 0, mid = i % 5 == 0
                var t = Path()
                t.move(to: g.point(p, radius: g.radius - (major ? 46 : mid ? 40 : 34)))
                t.addLine(to: g.point(p, radius: g.radius - 24))
                ctx.stroke(t, with: .color(ink.opacity(major ? 1 : 0.55)), lineWidth: major ? 2 : 1)
            }
            // Only the ends and the target are labelled.
            for (k, label) in labels.enumerated() where !label.isEmpty && k % 2 == 0 {
                let p = -1 + 0.5 * Double(k)
                ctx.draw(Text(label).font(.system(size: large ? 17 : 15, weight: .bold).width(.condensed)).foregroundColor(ink),
                         at: g.point(p, radius: g.radius - 66))
            }

            // Subtle HUD corners in the closeness colour, unit at the lower left.
            let b: CGFloat = 12
            let r = f.insetBy(dx: 8, dy: 8)
            var brackets = Path()
            let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(r.minX, r.minY, 1, 1), (r.maxX, r.minY, -1, 1),
                                                                   (r.minX, r.maxY, 1, -1), (r.maxX, r.maxY, -1, -1)]
            for (x, y, dx, dy) in corners {
                brackets.move(to: CGPoint(x: x, y: y + dy * b))
                brackets.addLine(to: CGPoint(x: x, y: y))
                brackets.addLine(to: CGPoint(x: x + dx * b, y: y))
            }
            ctx.stroke(brackets, with: .color(color.opacity(0.45)), lineWidth: 1.2)
            if !unit.isEmpty {
                ctx.draw(Text(unit).font(.system(size: 14, weight: .bold, design: .serif)).foregroundColor(ink.opacity(0.7)),
                         at: CGPoint(x: r.minX + 14, y: r.maxY - 14), anchor: .leading)
            }
        }
    }

    // MARK: Bottom deck: nixie digits, VFD strip, lamp

    private func deck(_ g: MeterGeometry) -> some View {
        HStack(spacing: 14) {
            NixieReadout(text: readout, size: large ? 34 : 28)
                .frame(maxWidth: .infinity)
            IndicatorLamp(color: color, size: large ? 30 : 24)
        }
        .padding(.horizontal, 18)
        .frame(width: g.size.width, height: g.deckHeight)
        .offset(y: g.face.maxY + 8)
    }
}

/// Shared meter geometry: pivot below the window so only the upper part of the needle shows.
struct MeterGeometry {
    let size: CGSize
    var deckHeight: CGFloat { min(64, size.height * 0.2) }
    var face: CGRect {
        CGRect(x: 20, y: 18, width: size.width - 40, height: size.height - deckHeight - 34)
    }
    var pivot: CGPoint { CGPoint(x: size.width / 2, y: face.maxY + face.height * 0.22) }
    var radius: CGFloat { pivot.y - face.minY - 40 }
    /// Half-span of the scale in degrees, limited so the arc ends stay inside the window.
    var span: Double {
        let maxHalf = Double((face.width / 2 - 30) / radius)
        return min(40, asin(min(max(maxHalf, 0.1), 0.95)) * 180 / .pi)
    }
    func angle(_ p: Double) -> Angle { .degrees(-90 + p * span) }
    func point(_ p: Double, radius r: CGFloat) -> CGPoint {
        let a = angle(p).radians
        return CGPoint(x: pivot.x + r * CGFloat(cos(a)), y: pivot.y + r * CGFloat(sin(a)))
    }
}

/// Needle as an animatable shape so SwiftUI interpolates its angle (spring → physical overshoot).
struct NeedleShape: Shape {
    var position: Double
    var geometry: MeterGeometry
    var tipOnly: Bool

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let g = geometry
        p.move(to: g.point(position, radius: tipOnly ? g.radius - 56 : 0))
        p.addLine(to: g.point(position, radius: g.radius - 6))
        return p
    }
}

struct FaceClip: Shape {
    var rect: CGRect
    func path(in _: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: 6) }
}

/// Bakelite case with four slotted screws and subtle grain.
struct Bakelite: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(hex: 0x2A2622), Color(hex: 0x16130F), Color(hex: 0x0B0A08)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
            Canvas { ctx, size in
                let pts = [CGPoint(x: 11, y: 11), CGPoint(x: size.width - 11, y: 11),
                           CGPoint(x: 11, y: size.height - 11), CGPoint(x: size.width - 11, y: size.height - 11)]
                for (k, c) in pts.enumerated() {
                    let r: CGFloat = 5.5
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(hex: 0x3B352E)))
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(.black), lineWidth: 1)
                    let a = [20.0, 75, 130, 160][k] * .pi / 180
                    let dx = CGFloat(4 * cos(a)), dy = CGFloat(4 * sin(a))
                    var slot = Path()
                    slot.move(to: CGPoint(x: c.x - dx, y: c.y - dy))
                    slot.addLine(to: CGPoint(x: c.x + dx, y: c.y + dy))
                    ctx.stroke(slot, with: .color(Color(hex: 0x0D0B09)), lineWidth: 1.8)
                }
            }
        }
    }
}

/// Gas-discharge style digits: dim "8" cathodes behind glowing orange numerals.
struct NixieReadout: View {
    var text: String
    var size: CGFloat

    var body: some View {
        let ghost = String(text.map { $0.isNumber ? "8" : $0 })
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x070605))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x2C2620), lineWidth: 1))
            Text(ghost).foregroundStyle(Color(hex: 0x3A1D0A))
            Text(text).foregroundStyle(Color(hex: 0xFF8A3D))
                .shadow(color: Color(hex: 0xFF6B1A).opacity(0.9), radius: 6)
                .shadow(color: Color(hex: 0xFF4419).opacity(0.5), radius: 12)
        }
        .font(.system(size: size, weight: .regular, design: .monospaced))
        .lineLimit(1).minimumScaleFactor(0.5)
        .frame(height: size * 1.55)
    }
}

/// Vacuum-fluorescent status strip in the closeness colour.
struct VFDStrip: View {
    var text: String
    var color: Color
    var size: CGFloat

    /// Upper case like a real VFD, but units keep their correct spelling (dB, Hz, ms).
    static func display(_ text: String) -> String {
        var t = text.uppercased()
        for (wrong, right) in [("DB", "dB"), ("HZ", "Hz"), ("KHZ", "kHz"), ("MS", "ms")] {
            t = t.replacingOccurrences(of: "(?<=[0-9 ])\(wrong)\\b", with: right, options: .regularExpression)
        }
        return t
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x050807))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x1D2A26), lineWidth: 1))
            Text(Self.display(text))
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.8), radius: 4)
                .lineLimit(2).minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .frame(minHeight: size * 2.4, maxHeight: .infinity)
    }
}

struct IndicatorLamp: View {
    var color: Color
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(color).shadow(color: color.opacity(0.9), radius: size * 0.35)
            Circle().stroke(Color.black, lineWidth: 3)
            Circle().fill(.white.opacity(0.35)).frame(width: size * 0.28).offset(x: -size * 0.17, y: -size * 0.17)
        }
        .frame(width: size, height: size)
    }
}

/// Compact list indicator: LED bar with a small needle and a nixie value.
struct MiniMeter: View {
    /// Normalized error −1…1 (0 = target).
    var value: Double?
    var tolerance: Double
    var readout: String
    var segments = 25

    private func closeness(_ p: Double) -> Double {
        let a = abs(p)
        return a <= tolerance ? 1 : max(0, 1 - (a - tolerance) / max(1 - tolerance, 1e-6))
    }

    var body: some View {
        let v = min(max(value ?? 0, -1), 1)
        let inTune = value != nil && closeness(v) >= 1
        HStack(spacing: 8) {
            Canvas { ctx, size in
                let w = size.width / CGFloat(segments)
                for i in 0..<segments {
                    let p = -1 + 2 * (Double(i) + 0.5) / Double(segments)
                    let lit = value != nil && ((v >= 0 ? (p >= -0.05 && p <= v) : (p <= 0.05 && p >= v)) || (inTune && abs(p) <= tolerance + 0.06))
                    let rect = CGRect(x: CGFloat(i) * w, y: 6, width: w - 2, height: size.height - 8)
                    if lit {
                        let c = Theme.closeness(closeness(p))
                        var glow = ctx
                        glow.addFilter(.blur(radius: 2))
                        glow.fill(Path(rect), with: .color(c.opacity(0.7)))
                        ctx.fill(Path(rect), with: .color(c))
                    } else {
                        ctx.fill(Path(rect), with: .color(Color(hex: 0x2A2C30)))
                    }
                }
                let cx = size.width / 2
                var centre = Path()
                centre.move(to: CGPoint(x: cx, y: 2)); centre.addLine(to: CGPoint(x: cx, y: size.height))
                ctx.stroke(centre, with: .color(Color(hex: 0xECE6D6).opacity(0.5)), lineWidth: 1)
                if value != nil {
                    let nx = (CGFloat(v) + 1) / 2 * size.width
                    var tri = Path()
                    tri.move(to: CGPoint(x: nx - 4, y: 0)); tri.addLine(to: CGPoint(x: nx + 4, y: 0)); tri.addLine(to: CGPoint(x: nx, y: 6))
                    tri.closeSubpath()
                    ctx.fill(tri, with: .color(Color(hex: 0xECE6D6)))
                }
            }
            .frame(width: 130, height: 22)
            Text(readout)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: 0xFF8A3D))
                .shadow(color: Color(hex: 0xFF6B1A).opacity(0.8), radius: 3)
                .frame(width: 64, alignment: .trailing)
        }
    }
}
