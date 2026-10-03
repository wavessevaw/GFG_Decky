import Foundation

/// 16-bit era screen: 320×224, 32-bit RGBA pixels drawn with integer coordinates only.
/// The app scales it up with nearest-neighbour filtering, so every pixel stays a crisp square.
public final class Framebuffer {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt32]
    /// Drawing offset (camera).
    public var originX = 0
    public var originY = 0
    /// Clip rectangle in screen pixels.
    public var clip: (x0: Int, y0: Int, x1: Int, y1: Int)

    public init(width: Int = 320, height: Int = 224) {
        self.width = width
        self.height = height
        pixels = [UInt32](repeating: 0, count: width * height)
        clip = (0, 0, width, height)
    }

    public func resetClip() { clip = (0, 0, width, height) }

    public func setClip(x: Int, y: Int, w: Int, h: Int) {
        clip = (max(0, x), max(0, y), min(width, x + w), min(height, y + h))
    }

    public func clear(_ c: UInt32) {
        for i in pixels.indices { pixels[i] = c }
    }

    @inline(__always) public func pixel(_ x: Int, _ y: Int, _ c: UInt32) {
        let sx = x - originX, sy = y - originY
        guard sx >= clip.x0, sy >= clip.y0, sx < clip.x1, sy < clip.y1 else { return }
        pixels[sy * width + sx] = c
    }

    public func get(_ x: Int, _ y: Int) -> UInt32 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return pixels[y * width + x]
    }

    public func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32) {
        guard w > 0, h > 0 else { return }
        let x0 = max(x - originX, clip.x0), x1 = min(x - originX + w, clip.x1)
        let y0 = max(y - originY, clip.y0), y1 = min(y - originY + h, clip.y1)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            let row = yy * width
            for xx in x0..<x1 { pixels[row + xx] = c }
        }
    }

    public func frame(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32, thickness t: Int = 1) {
        rect(x, y, w, t, c); rect(x, y + h - t, w, t, c)
        rect(x, y, t, h, c); rect(x + w - t, y, t, h, c)
    }

    public func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: UInt32) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            pixel(x, y, c)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    public func disc(_ cx: Int, _ cy: Int, _ r: Int, _ c: UInt32) {
        guard r > 0 else { pixel(cx, cy, c); return }
        for dy in -r...r {
            let w = Int(Double(r * r - dy * dy).squareRoot())
            rect(cx - w, cy + dy, 2 * w + 1, 1, c)
        }
    }

    /// Ordered 2×2 dither fill (the classic 16-bit "halftone").
    public func dither(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32, step: Int = 2) {
        guard w > 0, h > 0 else { return }
        for yy in y..<(y + h) where yy % step == 0 {
            var xx = x + ((yy / step) % 2 == 0 ? 0 : step / 2)
            while xx < x + w { pixel(xx, yy, c); xx += step }
        }
    }

    /// Draws a pixel sprite given as rows of characters; each character maps to a colour
    /// (missing / "." = transparent). `flip` mirrors horizontally.
    public func sprite(_ rows: [String], _ x: Int, _ y: Int, palette: [Character: UInt32], flip: Bool = false, scale: Int = 1) {
        for (j, row) in rows.enumerated() {
            let chars = Array(row)
            for (i, ch) in chars.enumerated() {
                guard let c = palette[ch] else { continue }
                let px = flip ? chars.count - 1 - i : i
                if scale == 1 { pixel(x + px, y + j, c) } else { rect(x + px * scale, y + j * scale, scale, scale, c) }
            }
        }
    }

    // MARK: Text

    /// Draws text with the 5×7 pixel font; returns the width in pixels. `scale` enlarges each pixel.
    @discardableResult
    public func text(_ s: String, _ x: Int, _ y: Int, _ c: UInt32, scale: Int = 1, shadow: UInt32? = nil) -> Int {
        var cx = x
        for ch in s.uppercased() {
            if ch == " " { cx += 4 * scale; continue }
            guard let g = PixelFont.glyph(ch) else { cx += 6 * scale; continue }
            for (row, bits) in g.enumerated() {
                for (col, b) in bits.enumerated() where b == "#" {
                    if let shadow { rect(cx + col * scale + scale, y + row * scale + scale, scale, scale, shadow) }
                    rect(cx + col * scale, y + row * scale, scale, scale, c)
                }
            }
            cx += (g.first?.count ?? 5) * scale + scale
        }
        return cx - x - scale
    }

    public static func textWidth(_ s: String, scale: Int = 1) -> Int {
        var w = 0
        for ch in s.uppercased() {
            if ch == " " { w += 4 * scale; continue }
            w += ((PixelFont.glyph(ch)?.first?.count ?? 5) + 1) * scale
        }
        return max(0, w - scale)
    }

    /// RGBA bytes (for CGImage on the app side).
    public var rgbaBytes: [UInt8] {
        var out = [UInt8](repeating: 0, count: pixels.count * 4)
        for (i, p) in pixels.enumerated() {
            out[i * 4] = UInt8((p >> 24) & 0xFF)
            out[i * 4 + 1] = UInt8((p >> 16) & 0xFF)
            out[i * 4 + 2] = UInt8((p >> 8) & 0xFF)
            out[i * 4 + 3] = 255
        }
        return out
    }
}

/// Colour as 0xRRGGBB00.
@inline(__always) public func rgb(_ hex: UInt32) -> UInt32 { hex << 8 }
