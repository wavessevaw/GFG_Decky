import SSMTCore
import SwiftUI

/// Maps stage metres to view points: the front edge (audience) at the bottom.
struct StageGeometry {
    let plan: StagePlan
    let size: CGSize
    /// Room around the stage for the audience caption and dimensions.
    var margin: CGFloat = 28

    var scale: CGFloat {
        min((size.width - 2 * margin) / CGFloat(max(plan.width, 0.1)),
            (size.height - 2 * margin) / CGFloat(max(plan.depth, 0.1)))
    }
    var stageRect: CGRect {
        let w = CGFloat(plan.width) * scale, h = CGFloat(plan.depth) * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: stageRect.minX + CGFloat(x) * scale, y: stageRect.maxY - CGFloat(y) * scale)
    }
    func stage(_ p: CGPoint) -> (x: Double, y: Double) {
        (Double((p.x - stageRect.minX) / scale), Double((stageRect.maxY - p.y) / scale))
    }
    func rect(of item: StageItem) -> CGRect {
        let c = point(item.x, item.y)
        let w = CGFloat(item.width) * scale, h = CGFloat(item.depth) * scale
        return CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }
}

/// The whole stage plan as one vector drawing (editor background and export).
struct StagePlanDrawing: View {
    var plan: StagePlan
    var ink: StageInk
    var audience: String
    var selected: StageItem.ID? = nil
    var showGrid = true

    var body: some View {
        Canvas { ctx, size in
            let g = StageGeometry(plan: plan, size: size)
            let stage = g.stageRect
            ctx.fill(Path(stage), with: .color(ink.stage))
            if showGrid {
                var x = 0.0
                while x <= plan.width + 1e-9 {
                    var p = Path(); p.move(to: g.point(x, 0)); p.addLine(to: g.point(x, plan.depth))
                    ctx.stroke(p, with: .color(ink.grid), lineWidth: 1)
                    x += 1
                }
                var y = 0.0
                while y <= plan.depth + 1e-9 {
                    var p = Path(); p.move(to: g.point(0, y)); p.addLine(to: g.point(plan.width, y))
                    ctx.stroke(p, with: .color(ink.grid), lineWidth: 1)
                    y += 1
                }
            }
            ctx.stroke(Path(stage), with: .color(ink.line), lineWidth: 1.5)
            // Front edge = audience side.
            var front = Path(); front.move(to: CGPoint(x: stage.minX, y: stage.maxY)); front.addLine(to: CGPoint(x: stage.maxX, y: stage.maxY))
            ctx.stroke(front, with: .color(ink.line), lineWidth: 3)
            ctx.draw(Text(audience).font(.system(size: 11, weight: .medium)).foregroundColor(ink.muted),
                     at: CGPoint(x: stage.midX, y: stage.maxY + 14))
            ctx.draw(Text(String(format: "%.1f × %.1f m", plan.width, plan.depth)).font(.system(size: 10).monospacedDigit())
                        .foregroundColor(ink.muted), at: CGPoint(x: stage.maxX, y: stage.minY - 10), anchor: .trailing)

            for item in plan.items {
                let r = g.rect(of: item)
                if item.kind == .text {
                    var t = ctx
                    t.translateBy(x: r.midX, y: r.midY)
                    t.rotate(by: .degrees(item.rotation))
                    t.draw(Text(item.label).font(.system(size: CGFloat(item.fontSize) * g.scale / 40, weight: .semibold))
                            .foregroundColor(ink.text), at: .zero)
                } else {
                    var t = ctx
                    t.translateBy(x: r.midX, y: r.midY)
                    t.rotate(by: .degrees(item.rotation))
                    StageSymbols.draw(item.kind, in: CGRect(x: -r.width / 2, y: -r.height / 2, width: r.width, height: r.height),
                                      ctx: &t, ink: ink)
                    // Caption under the symbol (not rotated, so it stays readable).
                    let caption = [item.label, item.info].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !caption.isEmpty {
                        let extent = max(r.width, r.height) / 2
                        ctx.draw(Text(caption).font(.system(size: max(8, min(12, g.scale * 0.22)))).foregroundColor(ink.text),
                                 at: CGPoint(x: r.midX, y: r.midY + extent + 8))
                    }
                }
                if item.id == selected {
                    let box = r.insetBy(dx: -4, dy: -4)
                    ctx.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(Theme.accent),
                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
        }
    }
}
