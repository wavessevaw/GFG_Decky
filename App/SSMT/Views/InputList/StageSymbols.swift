import SSMTCore
import SwiftUI

/// Colours of the stage drawing: dark for the editor, black on white for printing and export.
struct StageInk {
    var line: Color
    var fill: Color
    var accent: Color
    var text: Color
    var muted: Color
    var stage: Color
    var grid: Color

    static let editor = StageInk(line: Theme.textPrimary.opacity(0.85), fill: Color.white.opacity(0.07), accent: Theme.accent,
                                 text: Theme.textPrimary, muted: Theme.textSecondary, stage: Color.white.opacity(0.03),
                                 grid: Color.white.opacity(0.05))
    static let print = StageInk(line: .black, fill: Color(white: 0.92), accent: Color(white: 0.25), text: .black,
                                muted: Color(white: 0.35), stage: .white, grid: Color(white: 0.9))
}

/// Simple top-view vector symbols of typical stage equipment, drawn into a rectangle.
enum StageSymbols {
    static func draw(_ kind: StageItemKind, in r: CGRect, ctx: inout GraphicsContext, ink: StageInk) {
        let lw: CGFloat = max(1, min(r.width, r.height) * 0.04)
        func stroke(_ p: Path, _ w: CGFloat? = nil) { ctx.stroke(p, with: .color(ink.line), lineWidth: w ?? lw) }
        func fill(_ p: Path) { ctx.fill(p, with: .color(ink.fill)) }
        func box(_ rect: CGRect, radius: CGFloat = 0) {
            let p = Path(roundedRect: rect, cornerRadius: radius)
            fill(p); stroke(p)
        }
        func circle(_ c: CGPoint, _ rad: CGFloat, filled: Bool = true) {
            let p = Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: 2 * rad, height: 2 * rad))
            if filled { fill(p) }
            stroke(p)
        }
        func line(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat? = nil) {
            var p = Path(); p.move(to: a); p.addLine(to: b); stroke(p, w)
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        let s = min(r.width, r.height)

        switch kind {
        case .drumKit:
            circle(pt(0.5, 0.42), s * 0.22)                       // kick
            circle(pt(0.24, 0.62), s * 0.11)                      // snare
            circle(pt(0.38, 0.2), s * 0.09)                       // tom 1
            circle(pt(0.62, 0.2), s * 0.09)                       // tom 2
            circle(pt(0.78, 0.6), s * 0.13)                       // floor tom
            circle(pt(0.1, 0.4), s * 0.1, filled: false)          // hi-hat
            circle(pt(0.18, 0.12), s * 0.13, filled: false)       // crash
            circle(pt(0.88, 0.22), s * 0.15, filled: false)       // ride
            circle(pt(0.5, 0.88), s * 0.05)                       // throne
        case .percussion:
            circle(pt(0.25, 0.45), s * 0.2)
            circle(pt(0.55, 0.4), s * 0.22)
            circle(pt(0.82, 0.6), s * 0.12)
            circle(pt(0.82, 0.3), s * 0.1)
        case .guitarAmp, .bassAmp:
            box(r.insetBy(dx: lw, dy: lw), radius: s * 0.08)
            let rows = kind == .bassAmp ? 2 : 1
            let cols = kind == .bassAmp ? 2 : 2
            for i in 0..<rows {
                for j in 0..<cols {
                    let cx = r.minX + (CGFloat(j) + 0.5) / CGFloat(cols) * r.width
                    let cy = r.minY + (CGFloat(i) + 0.5) / CGFloat(rows) * r.height
                    circle(CGPoint(x: cx, y: cy), min(r.width / CGFloat(cols), r.height / CGFloat(rows)) * 0.32, filled: false)
                }
            }
        case .keyboard:
            box(r.insetBy(dx: lw, dy: lw), radius: s * 0.06)
            let keys = r.insetBy(dx: r.width * 0.05, dy: r.height * 0.18)
            let n = 14
            for k in 1..<n {
                let x = keys.minX + keys.width * CGFloat(k) / CGFloat(n)
                line(CGPoint(x: x, y: keys.minY + keys.height * 0.25), CGPoint(x: x, y: keys.maxY), lw * 0.6)
            }
            stroke(Path(keys), lw * 0.8)
        case .piano:
            var body = Path()
            body.move(to: pt(0.08, 0.95))
            body.addLine(to: pt(0.08, 0.15))
            body.addQuadCurve(to: pt(0.55, 0.05), control: pt(0.15, 0.0))
            body.addQuadCurve(to: pt(0.92, 0.6), control: pt(0.95, 0.15))
            body.addLine(to: pt(0.92, 0.95))
            body.closeSubpath()
            fill(body); stroke(body)
            let kb = CGRect(x: r.minX + r.width * 0.08, y: r.minY + r.height * 0.86, width: r.width * 0.84, height: r.height * 0.09)
            stroke(Path(kb), lw * 0.8)
        case .vocalMic:
            line(pt(0.5, 0.5), pt(0.15, 0.85))
            circle(pt(0.5, 0.5), s * 0.08)
            circle(pt(0.62, 0.36), s * 0.14)
        case .micStand:
            for a: CGFloat in [90, 210, 330] {
                let rad = a * .pi / 180
                line(pt(0.5, 0.5), CGPoint(x: r.midX + cos(rad) * s * 0.42, y: r.midY + sin(rad) * s * 0.42))
            }
            circle(pt(0.5, 0.5), s * 0.1)
        case .diBox:
            box(r.insetBy(dx: lw, dy: lw), radius: s * 0.1)
            ctx.draw(Text("DI").font(.system(size: s * 0.42, weight: .bold)).foregroundColor(ink.line), at: CGPoint(x: r.midX, y: r.midY))
        case .wedge:
            var p = Path()
            p.move(to: pt(0.05, 0.95)); p.addLine(to: pt(0.95, 0.95))
            p.addLine(to: pt(0.82, 0.08)); p.addLine(to: pt(0.18, 0.08)); p.closeSubpath()
            fill(p); stroke(p)
            circle(pt(0.5, 0.58), s * 0.18, filled: false)
        case .iem:
            var arc = Path()
            arc.addArc(center: pt(0.5, 0.62), radius: s * 0.32, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            stroke(arc)
            box(CGRect(x: r.midX - s * 0.42, y: r.midY - s * 0.05, width: s * 0.16, height: s * 0.32), radius: s * 0.05)
            box(CGRect(x: r.midX + s * 0.26, y: r.midY - s * 0.05, width: s * 0.16, height: s * 0.32), radius: s * 0.05)
        case .sideFill, .speaker:
            box(r.insetBy(dx: lw, dy: lw), radius: s * 0.05)
            circle(pt(0.5, kind == .sideFill ? 0.62 : 0.5), s * 0.28, filled: false)
            if kind == .sideFill {
                box(CGRect(x: r.midX - r.width * 0.25, y: r.minY + r.height * 0.1, width: r.width * 0.5, height: r.height * 0.18))
            }
        case .riser:
            let rr = r.insetBy(dx: lw, dy: lw)
            fill(Path(rr))
            ctx.drawLayer { layer in
                layer.clip(to: Path(rr))
                var x = rr.minX - rr.height
                while x < rr.maxX {
                    var h = Path(); h.move(to: CGPoint(x: x, y: rr.maxY)); h.addLine(to: CGPoint(x: x + rr.height, y: rr.minY))
                    layer.stroke(h, with: .color(ink.line.opacity(0.25)), lineWidth: lw * 0.6)
                    x += max(8, s * 0.12)
                }
            }
            stroke(Path(rr), lw * 1.2)
        case .person:
            let shoulders = Path(ellipseIn: CGRect(x: r.minX + r.width * 0.1, y: r.minY + r.height * 0.42, width: r.width * 0.8, height: r.height * 0.42))
            fill(shoulders); stroke(shoulders)
            circle(pt(0.5, 0.4), s * 0.2)
        case .chair:
            box(CGRect(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.25, width: r.width * 0.7, height: r.height * 0.65), radius: s * 0.1)
            box(CGRect(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.08, width: r.width * 0.7, height: r.height * 0.14), radius: s * 0.05)
        case .musicStand:
            box(CGRect(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.15, width: r.width * 0.9, height: r.height * 0.3), radius: 1)
            line(pt(0.5, 0.45), pt(0.5, 0.9))
        case .powerDrop:
            circle(pt(0.5, 0.5), s * 0.45)
            var bolt = Path()
            bolt.move(to: pt(0.56, 0.12)); bolt.addLine(to: pt(0.36, 0.55)); bolt.addLine(to: pt(0.52, 0.55))
            bolt.addLine(to: pt(0.44, 0.88)); bolt.addLine(to: pt(0.66, 0.42)); bolt.addLine(to: pt(0.5, 0.42)); bolt.closeSubpath()
            ctx.fill(bolt, with: .color(ink.accent))
        case .text:
            break
        }
    }
}

/// Small palette icon for a symbol kind.
struct StageSymbolIcon: View {
    var kind: StageItemKind
    var ink: StageInk = .editor

    var body: some View {
        Canvas { ctx, size in
            if kind == .text {
                ctx.draw(Text("T").font(.system(size: size.height * 0.7, weight: .semibold)).foregroundColor(ink.line),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
            } else {
                let d = kind.defaultSize
                let aspect = d.w / d.d
                let w = aspect >= 1 ? size.width : size.height * aspect
                let h = aspect >= 1 ? size.width / aspect : size.height
                let rect = CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: min(h, size.height))
                StageSymbols.draw(kind, in: rect, ctx: &ctx, ink: ink)
            }
        }
    }
}
