import SwiftUI

/// Panel shape with chamfered (cut) top-left and bottom-right corners.
struct CutCornerShape: Shape {
    var cut: CGFloat = 10

    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = min(cut, r.width / 4, r.height / 4)
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
}

/// Diagonal black/yellow hazard stripes for warning blocks.
struct HazardStripes: View {
    var color: Color = Theme.signalYellow
    var stripeWidth: CGFloat = 8

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height + stripeWidth, y: 0))
                p.addLine(to: CGPoint(x: x + stripeWidth, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
                x += stripeWidth * 2
            }
        }
    }
}

/// Very subtle scanline overlay (decorative, can be disabled).
struct Scanlines: View {
    var opacity: Double = 0.03

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(opacity)))
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}
