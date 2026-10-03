import Foundation

/// Draws `GameWorld` into a 320×224 framebuffer: comic pages with panels, procedural pixel-art
/// characters, onomatopoeia, speech bubbles and a console-style HUD. Everything is drawn in code.
public final class GameRenderer {
    public let fb = Framebuffer(width: 320, height: 224)
    static let cellW = 320, cellH = 192, inset = 8

    // Palette (16-bit-ish).
    static let ink = rgb(0x0B0B10), paper = rgb(0xEADFB8), paperDot = rgb(0xD5C690), white = rgb(0xFFFFFF)
    static let red = rgb(0xD62828), yellow = rgb(0xFCD34D), orange = rgb(0xF08A24), green = rgb(0x8DB36B), darkGreen = rgb(0x5E7E45)
    static let skin = rgb(0xF2B38A), hair = rgb(0x3B2416), tee = rgb(0x22232B), pants = rgb(0x3E4756), boots = rgb(0x17120E)
    static let steel = rgb(0x9AA3AE), purple = rgb(0x6B3FA0), blue = rgb(0x3A86C8), accent = rgb(0x2EE59D)

    public init() {}

    @discardableResult
    public func render(_ w: GameWorld) -> Framebuffer {
        fb.originX = 0; fb.originY = 0
        fb.resetClip()
        switch w.mode {
        case .title: drawTitle(w)
        case .victory: drawVictory(w)
        default:
            drawPage(w)
            if w.mode == .gameOver { drawGameOver(w) }
        }
        return fb
    }

    // MARK: Page and panels

    private func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    private func drawPaper() {
        fb.clear(GameRenderer.paper)
        fb.dither(0, 0, 320, 192, GameRenderer.paperDot, step: 4)
    }

    private func cellOrigin(_ p: PanelDef) -> (Int, Int) { (p.col * GameRenderer.cellW, p.row * GameRenderer.cellH) }

    private func drawPage(_ w: GameWorld) {
        drawPaper()
        let panels = w.pages[w.page]
        var camX = 0, camY = 0
        let (cx, cy) = cellOrigin(w.currentPanel)
        camX = cx; camY = cy
        if w.mode == .panelSlide {
            let (fx, fy) = cellOrigin(panels[w.fromPanel])
            let t = ease(w.transition)
            camX = Int(Double(fx) + Double(cx - fx) * t)
            camY = Int(Double(fy) + Double(cy - fy) * t)
        }
        // Panels near the camera (neighbours show during a slide, like turning the eye across a page).
        for (i, p) in panels.enumerated() {
            let (px, py) = cellOrigin(p)
            let sx = px - camX, sy = py - camY
            guard sx > -GameRenderer.cellW, sx < 320, sy > -GameRenderer.cellH, sy < 192 else { continue }
            drawPanel(w, p, live: i == w.panel && w.mode != .panelSlide, sx: sx, sy: sy)
        }
        if w.mode == .pageTurn { drawPageTurn(w) }
        drawHUD(w)
    }

    /// The previous page lifts away to the left, showing the new page underneath.
    private func drawPageTurn(_ w: GameWorld) {
        let t = ease(w.transition)
        let edge = Int(320 * (1 - t))
        guard edge > 0, w.page > 0 else { return }
        let old = w.pages[w.page - 1]
        let last = old[old.count - 1]
        fb.setClip(x: 0, y: 0, w: edge, h: 192)
        fb.rect(0, 0, 320, 192, GameRenderer.paper)
        fb.dither(0, 0, 320, 192, GameRenderer.paperDot, step: 4)
        drawPanel(w, last, live: false, sx: 0, sy: 0)
        fb.resetClip()
        // Curl: shadow and the back of the page.
        let back = max(4, Int(40 * sin(t * .pi)))
        fb.rect(edge, 0, back, 192, rgb(0xC9BA86))
        fb.dither(edge, 0, back, 192, rgb(0xA8996A), step: 2)
        fb.rect(edge + back, 0, 3, 192, rgb(0x6B5E3A))
    }

    private func drawPanel(_ w: GameWorld, _ p: PanelDef, live: Bool, sx: Int, sy: Int) {
        let x0 = sx + GameRenderer.inset, y0 = sy + GameRenderer.inset
        let pw = Int(GameWorld.panelW), ph = Int(GameWorld.panelH)
        // Drop shadow and black border.
        fb.rect(x0 + 3, y0 + 3, pw, ph, rgb(0x8C7F55))
        fb.rect(x0 - 2, y0 - 2, pw + 4, ph + 4, GameRenderer.ink)
        fb.setClip(x: x0, y: y0, w: pw, h: ph)
        fb.originX = -x0; fb.originY = -y0
        drawBackground(p.theme, frame: w.frame)
        for plat in p.platforms { drawPlatform(plat, theme: p.theme) }
        if live {
            for item in w.pickups where !item.taken { drawItem(item.kind, Int(item.x), Int(item.y), bob: w.frame) }
            for e in w.enemies { drawFighter(e, frame: w.frame) }
            drawFighter(w.hero, frame: w.frame, cable: w.cableHits > 0)
            for pr in w.projectiles { drawWave(pr, frame: w.frame) }
            if w.exitOpen { drawExitHint(p.exit, frame: w.frame) }
            for e in w.effects { drawEffect(e) }
        }
        fb.originX = 0; fb.originY = 0
        fb.resetClip()
    }

    // MARK: Backgrounds

    private func drawBackground(_ theme: PanelTheme, frame: Int) {
        let W = Int(GameWorld.panelW), H = Int(GameWorld.panelH), F = Int(GameWorld.floorY)
        switch theme {
        case .backstage:
            fb.rect(0, 0, W, H, rgb(0x2B2D42))
            for row in 0..<(F / 8) { // bricks
                let off = row % 2 == 0 ? 0 : 8
                var x = -off
                while x < W { fb.frame(x, row * 8, 16, 8, rgb(0x24263A)); x += 16 }
            }
            roadCase(20, F - 26, 46, 26); roadCase(70, F - 18, 30, 18)
            cableCoil(262, F - 6)
            fb.rect(130, 30, 30, 20, rgb(0xF4E8C1)); fb.text("RIG", 136, 36, GameRenderer.ink)
        case .corridor:
            fb.rect(0, 0, W, H, rgb(0x3D405B))
            for d in [30, 140, 250] {
                fb.rect(d, F - 70, 34, 70, rgb(0x2A2C40)); fb.frame(d, F - 70, 34, 70, GameRenderer.ink)
                fb.rect(d + 27, F - 38, 3, 3, GameRenderer.yellow)
            }
            fb.rect(132, 14, 40, 12, rgb(0x2E7D32)); fb.text("EXIT", 138, 17, GameRenderer.white)
            fb.dither(0, 0, W, 40, rgb(0x34364F), step: 2)
        case .dock:
            fb.rect(0, 0, W, H, rgb(0x1F2833))
            fb.rect(170, 20, 134, F - 20, rgb(0xC9CED6)); fb.rect(180, 30, 114, F - 30, rgb(0x14181E))
            fb.text("TOUR", 200, 70, rgb(0x3A3F48))
            for x in stride(from: 0, to: 160, by: 40) { fb.rect(x, F - 8, 34, 8, rgb(0x8B5A2B)); fb.rect(x, F - 5, 34, 1, rgb(0x5E3B1A)) }
            fb.dither(0, 0, 170, 60, rgb(0x2A3644), step: 2)
        case .dressing:
            fb.rect(0, 0, W, H, rgb(0x4A2C3A))
            fb.rect(110, 30, 90, 56, rgb(0xB9D7E8)); fb.frame(110, 30, 90, 56, rgb(0x2B1B22), thickness: 3)
            for i in 0..<7 { fb.disc(116 + i * 13, 26, 2, (frame / 20 + i) % 5 == 0 ? rgb(0xFFF6C8) : GameRenderer.yellow) }
            fb.rect(230, 50, 50, 3, GameRenderer.steel)
            for i in 0..<4 { fb.rect(234 + i * 12, 53, 9, 40, [GameRenderer.red, GameRenderer.purple, GameRenderer.blue, GameRenderer.orange][i]) }
        case .wings:
            fb.rect(0, 0, W, H, rgb(0x120A0C))
            for x in stride(from: 0, to: W, by: 12) {
                fb.rect(x, 0, 12, F, rgb(0x5C1A1B)); fb.rect(x + 8, 0, 3, F, rgb(0x3E1112))
            }
            speakerStack(250, F)
        case .stage:
            fb.rect(0, 0, W, H, rgb(0x0D0D18))
            // Light beams.
            for (i, bx) in [50, 150, 250].enumerated() {
                let c = [GameRenderer.yellow, rgb(0xFF5DA2), rgb(0x5DD6FF)][i]
                for y in stride(from: 14, to: F, by: 3) {
                    let half = 4 + y / 6
                    fb.dither(bx - half, y, half * 2, 1, c, step: 4 + (frame / 8 + i) % 2)
                }
            }
            truss(0, 6, W)
            fb.rect(100, F - 16, 104, 16, rgb(0x2B2B38)); fb.disc(152, F - 24, 10, rgb(0x6D6D80)); fb.disc(152, F - 24, 7, rgb(0x1B1B26))
        case .foh:
            fb.rect(0, 0, W, H, rgb(0x101820))
            fb.dither(0, 0, W, 70, rgb(0x1C2A36), step: 2)
            // Mixing desk with faders.
            fb.rect(96, F - 34, 112, 34, rgb(0x2D3339)); fb.frame(96, F - 34, 112, 34, GameRenderer.ink)
            for i in 0..<16 {
                fb.rect(102 + i * 6, F - 28, 2, 20, rgb(0x0E1114))
                fb.rect(101 + i * 6, F - 22 + ((i * 7 + frame / 30) % 9), 4, 3, GameRenderer.steel)
                fb.pixel(103 + i * 6, F - 31, (frame / 10 + i) % 4 == 0 ? GameRenderer.red : GameRenderer.accent)
            }
            for x in stride(from: 4, to: W, by: 22) { fb.disc(x, H - 8, 8, rgb(0x05080B)) } // crowd heads
        }
        // Floor.
        fb.rect(0, F, W, H - F, GameRenderer.ink)
        fb.rect(0, F, W, 2, rgb(0x55596A))
        fb.dither(0, F + 3, W, H - F - 3, rgb(0x2A2C35), step: 2)
    }

    private func roadCase(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        fb.rect(x, y, w, h, rgb(0x1A1A1A)); fb.frame(x, y, w, h, GameRenderer.steel)
        for (cx, cy) in [(x, y), (x + w - 4, y), (x, y + h - 4), (x + w - 4, y + h - 4)] { fb.rect(cx, cy, 4, 4, rgb(0xC7CCD4)) }
        fb.rect(x + w / 2 - 4, y + h / 2 - 1, 8, 3, GameRenderer.steel)
    }

    private func cableCoil(_ x: Int, _ y: Int) {
        for r in stride(from: 10, to: 3, by: -3) {
            for a in stride(from: 0.0, to: Double.pi * 2, by: 0.12) {
                fb.pixel(x + Int(cos(a) * Double(r) * 1.6), y + Int(sin(a) * Double(r) * 0.5), rgb(0x0A0A0A))
            }
        }
    }

    private func speakerStack(_ x: Int, _ floor: Int) {
        for i in 0..<3 {
            let y = floor - 30 * (i + 1)
            fb.rect(x, y, 40, 28, rgb(0x16161A)); fb.frame(x, y, 40, 28, rgb(0x3A3A42))
            fb.disc(x + 20, y + 14, 9, rgb(0x2A2A30)); fb.disc(x + 20, y + 14, 3, rgb(0x55555F))
        }
    }

    private func truss(_ x: Int, _ y: Int, _ w: Int) {
        fb.rect(x, y, w, 2, GameRenderer.steel); fb.rect(x, y + 10, w, 2, GameRenderer.steel)
        var i = x
        while i < x + w { fb.line(i, y, i + 10, y + 10, GameRenderer.steel); fb.line(i + 10, y, i, y + 10, rgb(0x6F7680)); i += 10 }
    }

    private func drawPlatform(_ r: Rect, theme: PanelTheme) {
        let x = Int(r.x), y = Int(r.y), w = Int(r.w)
        if theme == .stage {
            fb.rect(x, y, w, 2, GameRenderer.steel); fb.rect(x, y + 8, w, 2, GameRenderer.steel)
            var i = x
            while i < x + w { fb.line(i, y, i + 8, y + 8, GameRenderer.steel); i += 8 }
            fb.rect(x + 4, y + 10, 2, Int(GameWorld.floorY) - y - 10, rgb(0x6F7680)); fb.rect(x + w - 6, y + 10, 2, Int(GameWorld.floorY) - y - 10, rgb(0x6F7680))
        } else {
            roadCase(x, y, w, Int(GameWorld.floorY) - y)
        }
    }

    // MARK: Characters

    private struct Look {
        var skin, hair, shirt, shirt2, legs, shoes: UInt32
        var big = false
    }

    private func look(_ f: Fighter) -> Look {
        guard let kind = f.enemy else {
            return Look(skin: GameRenderer.skin, hair: GameRenderer.hair, shirt: GameRenderer.tee, shirt2: rgb(0x40424D), legs: GameRenderer.pants, shoes: GameRenderer.boots)
        }
        switch kind {
        case .loader: return Look(skin: GameRenderer.green, hair: rgb(0x2E3A22), shirt: GameRenderer.orange, shirt2: rgb(0xE8E8E8), legs: rgb(0x2F3A4A), shoes: rgb(0x1C1C1C))
        case .fan: return Look(skin: rgb(0x9CC07A), hair: rgb(0x6B2D1A), shirt: rgb(0xB8312F), shirt2: GameRenderer.ink, legs: rgb(0x2C4D7A), shoes: GameRenderer.white)
        case .singer: return Look(skin: rgb(0x86A86A), hair: rgb(0x1A1A1A), shirt: GameRenderer.purple, shirt2: GameRenderer.yellow, legs: GameRenderer.ink, shoes: GameRenderer.ink)
        case .boss: return Look(skin: rgb(0x7FA35F), hair: rgb(0xB8B8B8), shirt: rgb(0x1B1B1F), shirt2: GameRenderer.accent, legs: rgb(0x33363E), shoes: GameRenderer.ink, big: true)
        }
    }

    /// Procedural sprite: feet at (x, y). Parts are drawn with a 1-pixel ink outline.
    private func drawFighter(_ f: Fighter, frame: Int, cable: Bool = false) {
        let L = look(f)
        let s = L.big ? 2 : 1 // boss: wider and taller parts
        let x = Int(f.x.rounded()), y = Int(f.y.rounded())
        let dir = f.facing >= 0 ? 1 : -1
        if f.state == .dead && f.enemy != nil {
            // Lying on the floor, blinking before vanishing.
            if f.timer < 20 && frame % 4 < 2 { return }
            part(x - 22, y - 9, 34, 9, L.shirt); part(x + 12, y - 10, 12, 4, L.legs); part(x + (dir > 0 ? -32 : 24), y - 11, 11, 10, L.skin)
            return
        }
        if f.invulnerable > 0 && f.enemy == nil && frame % 6 < 3 { return }
        var clipTop: Int?
        if f.state == .spawn { clipTop = y - Int(Double(54 + 12 * (s - 1)) * (1 - Double(f.timer) / 50)) } // drawn in from the top
        if let top = clipTop {
            let old = fb.clip
            fb.clip = (old.x0, max(old.y0, top - fb.originY), old.x1, old.y1)
            drawBody(f, L, x: x, y: y, dir: dir, s: s, frame: frame, cable: cable)
            fb.clip = old
            fb.line(x - 12, top, x + 12, top, GameRenderer.ink) // the artist's pencil line
            fb.rect(x + 12, top - 6, 2, 8, rgb(0xE0B44C))
            return
        }
        let flash = (f.state == .hurt && frame % 4 < 2)
        drawBody(f, flash ? Look(skin: GameRenderer.white, hair: GameRenderer.white, shirt: GameRenderer.white, shirt2: GameRenderer.white,
                                  legs: GameRenderer.white, shoes: GameRenderer.white, big: L.big) : L,
                 x: x, y: y, dir: dir, s: s, frame: frame, cable: cable)
        if f.state == .stunned {
            for i in 0..<3 {
                let a = Double(frame) / 6 + Double(i) * 2.1
                fb.rect(x + Int(cos(a) * 11) - 1, y - 58 - 8 * (s - 1) + Int(sin(a) * 3), 3, 3, GameRenderer.yellow)
            }
        }
    }

    private func part(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32) {
        fb.rect(x - 1, y - 1, w + 2, h + 2, GameRenderer.ink)
        fb.rect(x, y, w, h, c)
    }

    /// Darker shade of a colour for two-tone shading.
    private func shade(_ c: UInt32) -> UInt32 {
        let r = (c >> 24) & 0xFF, g = (c >> 16) & 0xFF, b = (c >> 8) & 0xFF
        return ((r * 3 / 5) << 24) | ((g * 3 / 5) << 16) | ((b * 3 / 5) << 8)
    }

    /// Outlined part with a shaded back side.
    private func shaded(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: UInt32, dir: Int) {
        part(x, y, w, h, c)
        let sw = max(1, w / 4)
        fb.rect(dir > 0 ? x : x + w - sw, y, sw, h, shade(c))
    }

    private func drawBody(_ f: Fighter, _ L: Look, x: Int, y: Int, dir: Int, s: Int, frame: Int, cable: Bool) {
        let big = L.big ? 1 : 0
        let legH = 19 + 4 * big, bodyH = 19 + 6 * big, headH = 12 + 2 * big
        let bw = 16 + 8 * big, hw = 12 + 4 * big
        let hip = y - legH, shoulder = hip - bodyH, top = shoulder - headH
        let walking = f.state == .walk
        let phase = walking ? Int((sin(Double(f.animation) / 4) * 4).rounded()) : 0
        let zombie = f.enemy != nil
        let armY = shoulder + 2
        let armLen = 15 + 3 * big
        // Back arm.
        if !zombie || f.state == .windup {
            shaded(x - dir * (bw / 2) - (dir > 0 ? 4 : 0), armY, 4, armLen, L.skin, dir: dir)
        }
        // Legs.
        if f.state == .kick {
            shaded(x - 5, hip, 6, legH, L.legs, dir: dir)
            let kx = dir > 0 ? x + 1 : x - 21
            part(kx, hip + 3, 20, 6, L.legs); part(dir > 0 ? kx + 20 : kx - 5, hip + 1, 5, 9, L.shoes)
        } else if f.state == .jump {
            shaded(x - 7, hip, 6, legH - 6, L.legs, dir: dir); shaded(x + 1, hip - 2, 6, legH - 6, L.legs, dir: dir)
            part(x - 8, hip + legH - 7, 7, 4, L.shoes); part(x + 1, hip + legH - 9, 7, 4, L.shoes)
        } else {
            shaded(x - 7 + phase, hip, 6, legH - 3, L.legs, dir: dir); shaded(x + 1 - phase, hip, 6, legH - 3, L.legs, dir: dir)
            part(x - 8 + phase, y - 4, 8, 4, L.shoes); part(x + 1 - phase, y - 4, 8, 4, L.shoes)
        }
        // Torso.
        shaded(x - bw / 2, shoulder, bw, bodyH, L.shirt, dir: dir)
        if !zombie {
            fb.rect(x - bw / 2, hip - 4, bw, 3, rgb(0x0F0F12))          // belt
            fb.disc(x + dir * 4, hip - 3, 3, rgb(0x8A8F96)); fb.pixel(x + dir * 4, hip - 3, GameRenderer.ink) // gaffer tape
            fb.text("C", x - 2, shoulder + 5, rgb(0x6C6E78))            // crew t-shirt print
            fb.rect(x - dir * 2, shoulder + 13, 2, 3, rgb(0xB0B4BC))    // multitool on the pocket
        } else {
            switch f.enemy! {
            case .loader:
                fb.rect(x - bw / 2, shoulder + 7, bw, 3, rgb(0xE8E8E8)); fb.rect(x - bw / 2, shoulder + 13, bw, 2, rgb(0xE8E8E8))
            case .fan:
                fb.disc(x, shoulder + 8, 4, GameRenderer.ink); fb.pixel(x - 1, shoulder + 7, GameRenderer.red); fb.pixel(x + 1, shoulder + 7, GameRenderer.red)
            case .singer:
                fb.rect(x - 2, shoulder, 4, bodyH, GameRenderer.yellow); fb.rect(x - bw / 2, shoulder, 3, bodyH, shade(L.shirt))
            case .boss:
                fb.text("FOH", x - 8, shoulder + 6, GameRenderer.accent)
                fb.rect(x - bw / 2 + 2, shoulder + bodyH - 6, bw - 4, 2, rgb(0x55555F))
            }
            // Torn clothes.
            fb.rect(x - 3, shoulder + bodyH - 3, 3, 3, shade(L.shirt)); fb.pixel(x + 4, shoulder + 5, GameRenderer.ink)
            fb.rect(x + bw / 2 - 3, shoulder + 9, 2, 4, L.skin)
        }
        // Neck and head.
        fb.rect(x - 2, shoulder - 2, 4, 3, shade(L.skin))
        shaded(x - hw / 2, top, hw, headH, L.skin, dir: -dir)
        fb.rect(x - hw / 2, top, hw, 3 + big, L.hair)
        fb.rect(dir > 0 ? x - hw / 2 : x + hw / 2 - 3, top, 3, 7, L.hair) // back of the head
        let eyeX = x + dir * 3
        if zombie {
            fb.rect(eyeX - 1, top + 5, 3, 2, rgb(0xFFF2A8)); fb.pixel(eyeX + dir, top + 5, GameRenderer.red)
            fb.rect(x + dir * 2 - 2, top + headH - 3, 5, 2, rgb(0x3A1010))       // open jaw
            fb.pixel(x + dir * 2 - 1, top + headH - 3, GameRenderer.white)
            fb.rect(x - dir * 3, top + 7, 2, 2, shade(L.skin))                    // rot
            if f.enemy == .boss { // studio headphones, ponytail
                fb.rect(x - hw / 2 - 3, top + 3, 4, 8, GameRenderer.ink); fb.rect(x + hw / 2 - 1, top + 3, 4, 8, GameRenderer.ink)
                fb.rect(x - hw / 2 - 2, top - 3, hw + 4, 3, GameRenderer.ink)
                fb.rect(dir > 0 ? x - hw / 2 - 5 : x + hw / 2 + 2, top + 4, 3, 18, L.hair)
            }
        } else {
            fb.rect(eyeX - 1, top + 5, 3, 2, GameRenderer.white); fb.pixel(eyeX + (dir > 0 ? 1 : -1), top + 5, GameRenderer.ink)
            fb.rect(x + dir * 2 - 1, top + 9, 3, 1, shade(L.skin))
            fb.rect(x - hw / 2, top + headH - 3, hw, 2, rgb(0x5A3A26)) // stubble
            // Headset with boom mic.
            fb.rect(x - hw / 2 - 1, top - 1, hw + 2, 2, GameRenderer.steel)
            fb.rect(x - dir * (hw / 2) - 1, top + 3, 3, 5, rgb(0x2B2B30))
            fb.line(x - dir * (hw / 2 - 1), top + 7, x + dir * 4, top + 10, GameRenderer.steel)
            fb.rect(x + dir * 4 - 1, top + 9, 2, 2, GameRenderer.ink)
        }
        // Front arm.
        if f.state == .punch {
            let ax = dir > 0 ? x + bw / 2 - 2 : x - bw / 2 - 16
            part(ax, armY + 2, 18, 4, L.skin)
            part(dir > 0 ? ax + 16 : ax - 2, armY + 1, 5, 6, L.skin) // fist
            if cable {
                let ex = dir > 0 ? ax + 21 : ax - 2
                fb.line(ex, armY + 3, ex + dir * 24, armY + 6, GameRenderer.ink)
                fb.line(ex, armY + 4, ex + dir * 24, armY + 7, GameRenderer.ink)
                fb.rect(ex + dir * 24 - 3, armY + 3, 6, 6, GameRenderer.steel)
            }
        } else if zombie && f.state != .windup {
            let ax = dir > 0 ? x + bw / 2 - 3 : x - bw / 2 - 12
            part(ax, armY + 3, 15, 4, L.skin)
            fb.rect(dir > 0 ? ax + 15 : ax - 2, armY + 2, 2, 2, L.skin); fb.rect(dir > 0 ? ax + 15 : ax - 2, armY + 6, 2, 2, L.skin) // claws
        } else if zombie && f.state == .windup {
            part(x + dir * (bw / 2) - (dir > 0 ? 0 : 4), armY - 10, 4, 14, L.skin)
        } else {
            shaded(x + dir * (bw / 2) - (dir > 0 ? 1 : 3), armY, 4, armLen, L.skin, dir: dir)
        }
        if f.enemy == .singer {
            fb.rect(x + dir * (bw / 2 + 6), armY + 2, 2, 9, GameRenderer.ink); fb.disc(x + dir * (bw / 2 + 7), armY, 3, GameRenderer.steel)
        }
    }

    private func drawItem(_ kind: ItemKind, _ x: Int, _ y: Int, bob: Int) {
        let yy = y - 8 - (bob / 10) % 2
        drawItemIcon(kind, x, yy)
    }

    private func drawItemIcon(_ kind: ItemKind, _ x: Int, _ y: Int) {
        switch kind {
        case .tape:
            fb.disc(x, y, 5, GameRenderer.ink); fb.disc(x, y, 4, rgb(0x8A8F96)); fb.disc(x, y, 2, GameRenderer.paper)
        case .cable:
            for a in stride(from: 0.0, to: 6.2, by: 0.3) { fb.pixel(x + Int(cos(a) * 5), y + Int(sin(a) * 3), GameRenderer.ink) }
            fb.rect(x + 4, y - 4, 4, 3, GameRenderer.steel)
        case .strobe:
            fb.rect(x - 4, y - 3, 8, 6, GameRenderer.white); fb.frame(x - 4, y - 3, 8, 6, GameRenderer.ink)
            fb.line(x - 7, y - 6, x - 5, y - 4, GameRenderer.yellow); fb.line(x + 7, y - 6, x + 5, y - 4, GameRenderer.yellow)
        }
    }

    private func drawWave(_ p: Projectile, frame: Int) {
        let x = Int(p.x), y = Int(p.y)
        let dir = p.vx > 0 ? 1 : -1
        for k in 0..<(p.big ? 3 : 2) {
            let r = 4 + k * 3 + (frame / 3) % 2
            for a in stride(from: -1.0, through: 1.0, by: 0.12) {
                fb.pixel(x + dir * (Int(cos(a) * Double(r)) - 6), y + Int(sin(a) * Double(r)), p.big ? GameRenderer.accent : GameRenderer.purple)
            }
        }
    }

    private func drawExitHint(_ exit: PanelExit, frame: Int) {
        guard frame % 40 < 26 else { return }
        let W = Int(GameWorld.panelW), F = Int(GameWorld.floorY)
        switch exit {
        case .right, .nextPage: arrow(W - 20, F - 50, dx: 1, dy: 0)
        case .left: arrow(20, F - 50, dx: -1, dy: 0)
        case .down:
            arrow(W / 2, F - 50, dx: 0, dy: 1)
            fb.text("ВНИЗ", W / 2 - 11, F - 70, GameRenderer.yellow, shadow: GameRenderer.ink)
        case .end: break
        }
    }

    private func arrow(_ x: Int, _ y: Int, dx: Int, dy: Int) {
        for i in 0..<10 {
            let w = 10 - i
            if dx != 0 { fb.rect(x + dx * i - (dx < 0 ? 0 : 0), y - w, 1, 2 * w + 1, GameRenderer.yellow) }
            else { fb.rect(x - w, y + dy * i, 2 * w + 1, 1, GameRenderer.yellow) }
        }
        if dx != 0 { fb.rect(dx > 0 ? x - 10 : x + 1, y - 3, 10, 7, GameRenderer.yellow) } else { fb.rect(x - 3, y - 10, 7, 10, GameRenderer.yellow) }
    }

    // MARK: Comic effects

    private func drawEffect(_ e: Effect) {
        switch e.kind {
        case .burst: burst(e.text, Int(e.x), Int(e.y))
        case .bubble: bubble(e.text, Int(e.x), Int(e.y), hero: e.fromHero)
        case .caption: caption(e.text, Int(e.x), Int(e.y))
        }
    }

    private func burst(_ text: String, _ cx: Int, _ cy: Int) {
        let tw = Framebuffer.textWidth(text)
        let r = max(10, tw / 2 + 6)
        for k in 0..<14 { // spikes
            let a = Double(k) / 14 * .pi * 2
            fb.line(cx, cy, cx + Int(cos(a) * Double(r + 6)), cy + Int(sin(a) * Double(r / 2 + 6)), GameRenderer.red)
        }
        fb.disc(cx, cy, r / 2 + 3, GameRenderer.red)
        fb.rect(cx - r, cy - 6, 2 * r, 12, GameRenderer.yellow)
        fb.frame(cx - r, cy - 6, 2 * r, 12, GameRenderer.red)
        fb.text(text, cx - tw / 2, cy - 3, GameRenderer.ink)
    }

    private func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        var cur = ""
        for word in text.split(separator: " ") {
            let candidate = cur.isEmpty ? String(word) : cur + " " + word
            if Framebuffer.textWidth(candidate) > width && !cur.isEmpty { lines.append(cur); cur = String(word) } else { cur = candidate }
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    private func bubble(_ text: String, _ ax: Int, _ ay: Int, hero: Bool) {
        let lines = wrap(text, width: 130)
        let w = (lines.map { Framebuffer.textWidth($0) }.max() ?? 0) + 10
        let h = lines.count * 9 + 7
        let W = Int(GameWorld.panelW)
        let bx = min(max(4, ax - w / 2), W - w - 4)
        let by = max(18, ay - h - 8)
        fb.rect(bx - 1, by - 1, w + 2, h + 2, GameRenderer.ink)
        fb.rect(bx, by, w, h, hero ? GameRenderer.white : rgb(0xFFE3E3))
        // Tail.
        for i in 0..<7 { fb.rect(min(max(bx + 6, ax - 3 + i / 2), bx + w - 10), by + h + i - 1, max(1, 6 - i), 1, GameRenderer.ink) }
        for (i, l) in lines.enumerated() { fb.text(l, bx + 5, by + 4 + i * 9, GameRenderer.ink) }
    }

    private func caption(_ text: String, _ x: Int, _ y: Int) {
        let w = Framebuffer.textWidth(text) + 10
        fb.rect(x - 1, y - 1, w + 2, 15, GameRenderer.ink)
        fb.rect(x, y, w, 13, GameRenderer.yellow)
        fb.text(text, x + 5, y + 3, GameRenderer.ink)
    }

    // MARK: HUD

    private func drawHUD(_ w: GameWorld) {
        fb.rect(0, 192, 320, 32, GameRenderer.ink)
        fb.rect(0, 192, 320, 1, rgb(0x3A3A48))
        fb.text("ТЕХНИК", 8, 198, GameRenderer.yellow)
        let hp = max(0, w.hero.hp)
        for i in 0..<w.hero.maxHP {
            fb.rect(8 + i * 5, 208, 4, 8, i < hp ? (hp <= 6 ? GameRenderer.red : GameRenderer.accent) : rgb(0x2A2A35))
        }
        for k in 0..<3 {
            let bx = 128 + k * 26
            fb.frame(bx, 198, 22, 20, rgb(0x55596A))
            fb.text("\(k + 1)", bx + 1, 199, rgb(0x55596A))
            if k < w.inventory.count { drawItemIcon(w.inventory[k], bx + 12, 209) }
        }
        if w.cableHits > 0 { fb.text("XLR×\(w.cableHits)", 210, 198, GameRenderer.steel) }
        fb.text("СТР \(w.page + 1)", 268, 198, GameRenderer.paper)
        for i in 0..<w.pages[w.page].count {
            fb.rect(268 + i * 8, 210, 6, 6, i == w.panel ? GameRenderer.yellow : (i < w.panel ? rgb(0x8C7F55) : rgb(0x2A2A35)))
        }
    }

    // MARK: Screens

    private func drawTitle(_ w: GameWorld) {
        drawPaper()
        fb.rect(10, 8, 300, 208, GameRenderer.ink)
        fb.rect(13, 11, 294, 202, rgb(0x1A1028))
        // Halftone sunrise behind the title.
        for r in stride(from: 120, to: 10, by: -12) { fb.dither(160 - r, 120 - r / 2, 2 * r, r, r % 24 == 0 ? rgb(0x4A1A2A) : rgb(0x6A1A2A), step: 3) }
        fb.text("САУНДЧЕК", 160 - Framebuffer.textWidth("САУНДЧЕК", scale: 3) / 2, 26, GameRenderer.yellow, scale: 3, shadow: GameRenderer.ink)
        fb.text("МЁРТВЫХ", 160 - Framebuffer.textWidth("МЁРТВЫХ", scale: 3) / 2, 54, GameRenderer.red, scale: 3, shadow: GameRenderer.ink)
        fb.text("КОМИКС В 16 БИТ ОТ SSMT", 160 - Framebuffer.textWidth("КОМИКС В 16 БИТ ОТ SSMT") / 2, 84, GameRenderer.paper)
        var hero = w.hero
        hero.x = 130; hero.y = 168; hero.facing = 1; hero.state = .idle; hero.invulnerable = 0
        drawFighter(hero, frame: w.frame)
        var z = Fighter(id: 9, enemy: .loader, x: 196, y: 168, facing: -1, hp: 1, maxHP: 1, state: .walk)
        z.animation = w.frame
        drawFighter(z, frame: w.frame)
        fb.rect(13, 168, 294, 2, rgb(0x55596A))
        if w.frame % 60 < 40 {
            fb.text("НАЖМИТЕ ENTER", 160 - Framebuffer.textWidth("НАЖМИТЕ ENTER") / 2, 178, GameRenderer.white)
        }
        let help = "СТРЕЛКИ · ПРОБЕЛ ПРЫЖОК · Z УДАР · X ПИНОК · 1 2 3 ВЕЩИ"
        fb.text(help, 160 - Framebuffer.textWidth(help) / 2, 196, rgb(0x9AA3AE))
    }

    private func drawGameOver(_ w: GameWorld) {
        fb.dither(0, 0, 320, 192, GameRenderer.ink, step: 2)
        let t = "ЗАНАВЕС"
        fb.text(t, 160 - Framebuffer.textWidth(t, scale: 3) / 2, 70, GameRenderer.red, scale: 3, shadow: GameRenderer.ink)
        let s = "ENTER — ЕЩЁ ДУБЛЬ"
        if w.frame % 60 < 40 { fb.text(s, 160 - Framebuffer.textWidth(s) / 2, 110, GameRenderer.white) }
    }

    private func drawVictory(_ w: GameWorld) {
        drawPaper()
        fb.rect(10, 8, 300, 208, GameRenderer.ink)
        fb.rect(13, 11, 294, 202, rgb(0x0F2018))
        for r in stride(from: 140, to: 10, by: -14) { fb.dither(160 - r, 110 - r / 2, 2 * r, r, rgb(0x1E4D36), step: 3) }
        fb.text("КОНЕЦ", 160 - Framebuffer.textWidth("КОНЕЦ", scale: 3) / 2, 34, GameRenderer.yellow, scale: 3, shadow: GameRenderer.ink)
        let a = "ПУЛЬТ СПАСЁН. ШОУ ДОЛЖНО ПРОДОЛЖАТЬСЯ!"
        fb.text(a, 160 - Framebuffer.textWidth(a) / 2, 70, GameRenderer.white)
        var hero = w.hero
        hero.x = 160; hero.y = 160; hero.state = .idle; hero.invulnerable = 0
        drawFighter(hero, frame: w.frame)
        fb.rect(13, 160, 294, 2, rgb(0x55596A))
        let c = "SSMT · SOUNDSOLUTION MULTI TOOL"
        fb.text(c, 160 - Framebuffer.textWidth(c) / 2, 176, GameRenderer.accent)
        if w.frame % 60 < 40 { fb.text("ENTER", 160 - Framebuffer.textWidth("ENTER") / 2, 194, GameRenderer.paper) }
    }
}
