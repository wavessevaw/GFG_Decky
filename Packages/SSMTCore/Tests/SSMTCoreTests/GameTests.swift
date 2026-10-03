import XCTest
@testable import SSMTCore

final class GameTests: XCTestCase {
    private func run(_ w: GameWorld, _ frames: Int, _ input: GameInput = GameInput()) {
        for _ in 0..<frames { w.step(input) }
    }

    private func press(_ w: GameWorld, _ set: (inout GameInput) -> Void) {
        var i = GameInput(); set(&i)
        w.step(i)
        w.step(GameInput())
    }

    func testTitleStartsTheGame() {
        let w = GameWorld()
        XCTAssertEqual(w.mode, .title)
        press(w) { $0.start = true }
        XCTAssertEqual(w.mode, .playing)
        XCTAssertEqual(w.page, 0)
        XCTAssertEqual(w.panel, 0)
    }

    func testHeroWalksJumpsAndLands() {
        let w = GameWorld()
        press(w) { $0.start = true }
        let x0 = w.hero.x
        var right = GameInput(); right.right = true
        run(w, 30, right)
        XCTAssertGreaterThan(w.hero.x, x0 + 30)
        press(w) { $0.jump = true }
        XCTAssertLessThan(w.hero.y, GameWorld.floorY)
        run(w, 60)
        XCTAssertEqual(w.hero.y, GameWorld.floorY)
        XCTAssertTrue(w.hero.onGround)
    }

    func testPunchingDefeatsTheFirstZombieAndOpensTheExit() {
        let w = GameWorld()
        press(w) { $0.start = true }
        run(w, 100) // the loader is drawn in
        XCTAssertEqual(w.enemies.count, 1)
        // Walk next to it, then punch until it falls.
        var guardFrames = 0
        while w.enemies.contains(where: { $0.state != .dead }) && guardFrames < 4000 {
            var i = GameInput()
            let e = w.enemies[0]
            if abs(e.x - w.hero.x) > 18 { i.right = e.x > w.hero.x; i.left = e.x < w.hero.x }
            else if guardFrames % 16 == 0 { i.punch = true; i.left = e.x < w.hero.x; i.right = e.x > w.hero.x }
            w.step(i)
            guardFrames += 1
        }
        XCTAssertLessThan(guardFrames, 4000)
        run(w, 60)
        XCTAssertTrue(w.exitOpen)
        // Walk out to the right: the camera slides to panel 2.
        var right = GameInput(); right.right = true
        run(w, 400, right)
        run(w, 60)
        XCTAssertEqual(w.panel, 1)
        XCTAssertEqual(w.mode, .playing)
    }

    func testItemsAndDamage() {
        let w = GameWorld()
        press(w) { $0.start = true }
        // Pick up the gaffer tape on the platform.
        var right = GameInput(); right.right = true
        while w.hero.x < 200 { w.step(right) }
        press(w) { $0.jump = true }
        var guardFrames = 0
        while w.inventory.isEmpty && guardFrames < 300 { w.step(right); guardFrames += 1 }
        XCTAssertEqual(w.inventory, [.tape])
        press(w) { $0.item1 = true }
        XCTAssertTrue(w.inventory.isEmpty)
    }

    func testRendererDrawsEveryScreen() {
        let w = GameWorld()
        let r = GameRenderer()
        r.render(w)
        XCTAssertNotEqual(Set(r.fb.pixels).count, 1, "title screen has content")
        press(w) { $0.start = true }
        run(w, 120)
        r.render(w)
        // HUD and panel border exist.
        XCTAssertEqual(r.fb.get(0, 200), GameRenderer.ink)
        XCTAssertGreaterThan(Set(r.fb.pixels).count, 10)
        XCTAssertEqual(r.fb.rgbaBytes.count, 320 * 224 * 4)
    }

    func testFontCoversTheGameTexts() {
        for text in ["САУНДЧЕК МЁРТВЫХ", "ЗАНАВЕС", "ВОКАЛИСТ? ДАЖЕ ПОСЛЕ СМЕРТИ ОРЁТ МИМО НОТ.", "ХРЯСЬ! ШМЯК! БАБАХ!",
                     "ПУЛЬТ FOH", "ENTER — ЕЩЁ ДУБЛЬ", "СТРЕЛКИ · ПРОБЕЛ ПРЫЖОК · Z УДАР · X ПИНОК · 1 2 3 ВЕЩИ", "23:47. ДО ШОУ 13 МИНУТ…"] {
            for ch in text.uppercased() where ch != " " {
                XCTAssertNotNil(PixelFont.glyph(ch), "missing glyph \(ch)")
            }
        }
        for p in GameWorld.story.flatMap({ $0 }) {
            for ch in ((p.caption ?? "") + (p.line ?? "")).uppercased() where ch != " " {
                XCTAssertNotNil(PixelFont.glyph(ch), "missing glyph \(ch) in \(p.caption ?? "")")
            }
        }
    }

    /// Writes a few screens as PPM files when SSMT_GAME_SNAP points to a folder (for looking at the art).
    func testDumpScreens() throws {
        guard let dir = ProcessInfo.processInfo.environment["SSMT_GAME_SNAP"] else { return }
        let w = GameWorld()
        let r = GameRenderer()
        func dump(_ name: String) throws {
            r.render(w)
            var data = Data("P6 320 224 255\n".utf8)
            for p in r.fb.pixels { data.append(contentsOf: [UInt8((p >> 24) & 0xFF), UInt8((p >> 16) & 0xFF), UInt8((p >> 8) & 0xFF)]) }
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".ppm"))
        }
        run(w, 30); try dump("title")
        press(w) { $0.start = true }
        run(w, 20); try dump("panel1-start")
        run(w, 110)
        var i = GameInput(); i.right = true
        run(w, 50, i)
        var p = GameInput(); p.punch = true
        w.step(p); run(w, 6); try dump("panel1-fight")
        for _ in 0..<2000 where w.enemies.contains(where: { $0.state != .dead }) {
            var k = GameInput()
            let e = w.enemies[0]
            if abs(e.x - w.hero.x) > 18 { k.right = e.x > w.hero.x; k.left = e.x < w.hero.x } else if w.frame % 16 == 0 { k.punch = true }
            w.step(k)
        }
        run(w, 40); try dump("panel1-clear")
        run(w, 400, i); 
        // mid-slide
        try dump("slide")
        run(w, 120); try dump("panel2")
        run(w, 200); try dump("panel2-enemies")
    }
}
