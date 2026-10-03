import Foundation

/// «Саундчек мёртвых» — a hidden 16-bit style beat-'em-up: a stage technician fights through the
/// panels of a comic book during a zombie apocalypse. Pure logic at a fixed 60 steps per second;
/// `GameRenderer` draws it.
public struct GameInput: Equatable, Sendable {
    public var left = false, right = false, up = false, down = false
    public var jump = false, punch = false, kick = false
    public var item1 = false, item2 = false, item3 = false
    public var start = false
    public init() {}
}

public enum GameEvent: Equatable, Sendable {
    case jump, punch, kick, hit, bigHit, hurt, enemyDown, pickup, heal, cableOn, strobe, shout, bossRoar,
         panelClear, panelSlide, pageTurn, gameOver, victory, step
}

public enum ItemKind: String, CaseIterable, Sendable {
    /// Gaffer tape: heals.
    case tape
    /// XLR cable: longer, harder hits for a while.
    case cable
    /// Strobe: stuns every zombie in the panel.
    case strobe
}

public enum EnemyKind: String, Sendable {
    /// Slow loader zombie.
    case loader
    /// Fast fan zombie.
    case fan
    /// Singer zombie: shouts sound waves.
    case singer
    /// The boss: zombie sound engineer "Feedback".
    case boss

    var maxHP: Int {
        switch self { case .loader: return 4; case .fan: return 2; case .singer: return 5; case .boss: return 28 }
    }
    var speed: Double {
        switch self { case .loader: return 0.45; case .fan: return 1.15; case .singer: return 0.35; case .boss: return 0.7 }
    }
    var damage: Int {
        switch self { case .loader: return 2; case .fan: return 1; case .singer: return 2; case .boss: return 3 }
    }
}

public enum PanelTheme: Sendable { case backstage, corridor, dock, dressing, wings, stage, foh }

public enum PanelExit: Sendable { case right, down, left, nextPage, end }

public struct Rect: Equatable, Sendable {
    public var x, y, w, h: Double
    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public func intersects(_ o: Rect) -> Bool { x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h }
}

public struct PanelDef: Sendable {
    public var col: Int
    public var row: Int
    public var theme: PanelTheme
    public var exit: PanelExit
    /// One-way platforms (stand on top).
    public var platforms: [Rect]
    public var enemies: [(kind: EnemyKind, x: Double, delay: Int)]
    public var items: [(kind: ItemKind, x: Double, y: Double)]
    /// Caption box at the top of the panel ("МЕЖДУ ТЕМ…").
    public var caption: String?
    /// Speech bubble of the hero when the panel starts.
    public var line: String?
}

public struct Fighter: Sendable {
    public enum State: Sendable { case spawn, idle, walk, jump, punch, kick, windup, hurt, dead, stunned }
    public var id: Int
    public var enemy: EnemyKind?
    /// Feet position in panel coordinates.
    public var x: Double
    public var y: Double
    public var vx = 0.0
    public var vy = 0.0
    public var facing = 1.0
    public var hp: Int
    public var maxHP: Int
    public var state: State
    public var timer = 0
    public var onGround = true
    public var invulnerable = 0
    public var cooldown = 0
    public var combo = 0
    public var comboTimer = 0
    public var hitDone = false
    public var animation = 0

    var box: Rect { enemy == .boss ? Rect(x - 12, y - 60, 24, 60) : Rect(x - 9, y - 50, 18, 50) }
}

public struct Projectile: Sendable {
    public var x, y, vx: Double
    public var life: Int
    public var damage: Int
    public var big: Bool
}

/// Comic effects: onomatopoeia stars and speech bubbles.
public struct Effect: Sendable {
    public enum Kind: Sendable { case burst, bubble, caption }
    public var kind: Kind
    public var text: String
    public var x, y: Double
    public var life: Int
    public var fromHero: Bool
}

public struct Pickup: Sendable {
    public var kind: ItemKind
    public var x, y: Double
    public var taken = false
}

public final class GameWorld {
    public enum Mode: Equatable, Sendable { case title, playing, panelSlide, pageTurn, gameOver, victory }

    public static let panelW = 304.0
    public static let panelH = 176.0
    public static let floorY = 160.0

    public private(set) var mode: Mode = .title
    public private(set) var pages: [[PanelDef]]
    public private(set) var page = 0
    public private(set) var panel = 0
    public private(set) var hero: Fighter
    public private(set) var enemies: [Fighter] = []
    public private(set) var projectiles: [Projectile] = []
    public private(set) var effects: [Effect] = []
    public private(set) var pickups: [Pickup] = []
    public private(set) var inventory: [ItemKind] = []
    public private(set) var cableHits = 0
    public private(set) var frame = 0
    /// 0…1 progress of the current panel slide / page turn.
    public private(set) var transition = 0.0
    public private(set) var fromPanel = 0
    public private(set) var exitOpen = false
    public private(set) var events: [GameEvent] = []
    private var pendingSpawns: [(kind: EnemyKind, x: Double, delay: Int)] = []
    private var previous = GameInput()
    private var nextID = 1
    private var rng: UInt64

    public init(seed: UInt64 = 0x5EED) {
        rng = seed
        pages = GameWorld.story
        hero = Fighter(id: 0, enemy: nil, x: 40, y: GameWorld.floorY, hp: 20, maxHP: 20, state: .idle)
    }

    public var currentPanel: PanelDef { pages[page][panel] }

    private func random() -> Double {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Double(rng >> 11) / Double(1 << 53)
    }

    // MARK: Story

    /// Two pages of the comic: backstage, then the stage and front of house.
    static let story: [[PanelDef]] = [
        [
            PanelDef(col: 0, row: 0, theme: .backstage, exit: .right, platforms: [Rect(200, 128, 52, 6)],
                     enemies: [(.loader, 250, 90)], items: [(.tape, 222, 128)],
                     caption: "23:47. ДО ШОУ 13 МИНУТ…", line: "ОПЯТЬ ГРУЗЧИКИ НАПИЛИСЬ? ЭЙ, ТЫ ЧЕГО?!"),
            PanelDef(col: 1, row: 0, theme: .corridor, exit: .down, platforms: [Rect(90, 132, 40, 6), Rect(170, 112, 40, 6)],
                     enemies: [(.loader, 270, 40), (.fan, 20, 160), (.loader, 280, 260)], items: [],
                     caption: "КОРИДОР ЗА СЦЕНОЙ", line: "ОНИ ВСЕ… ЗОМБИ?!"),
            PanelDef(col: 1, row: 1, theme: .dock, exit: .left, platforms: [Rect(40, 124, 60, 6), Rect(206, 124, 60, 6)],
                     enemies: [(.fan, 280, 40), (.fan, 20, 70), (.loader, 150, 200), (.fan, 280, 260)], items: [(.cable, 236, 124)],
                     caption: "ПОГРУЗОЧНАЯ ЗОНА", line: "XLR-КАБЕЛЬ! СЕЙЧАС ПОКОММУТИРУЕМ…"),
            PanelDef(col: 0, row: 1, theme: .dressing, exit: .nextPage, platforms: [],
                     enemies: [(.singer, 260, 60), (.fan, 30, 120), (.fan, 280, 200)], items: [(.strobe, 60, 160)],
                     caption: "ГРИМЁРКА", line: "ВОКАЛИСТ? ДАЖЕ ПОСЛЕ СМЕРТИ ОРЁТ МИМО НОТ."),
        ],
        [
            PanelDef(col: 0, row: 0, theme: .wings, exit: .right, platforms: [Rect(120, 120, 64, 6)],
                     enemies: [(.loader, 270, 40), (.loader, 20, 120), (.fan, 280, 200), (.loader, 150, 300)], items: [(.tape, 152, 120)],
                     caption: "СТРАНИЦА 2. КУЛИСЫ", line: "СЦЕНА РЯДОМ. ТОЛЬКО БЫ ДОБРАТЬСЯ ДО ПУЛЬТА."),
            PanelDef(col: 1, row: 0, theme: .stage, exit: .down, platforms: [Rect(30, 104, 80, 6), Rect(194, 104, 80, 6)],
                     enemies: [(.singer, 60, 40), (.singer, 250, 100), (.fan, 150, 160), (.fan, 290, 240)], items: [(.strobe, 240, 104)],
                     caption: "НА СЦЕНЕ. ФЕРМЫ ЕЩЁ ДЕРЖАТ", line: "ХОР МЁРТВЫХ… БЕЗ МИКРОФОНОВ, СЛАВА БОГУ."),
            PanelDef(col: 1, row: 1, theme: .foh, exit: .end, platforms: [Rect(40, 118, 50, 6), Rect(214, 118, 50, 6)],
                     enemies: [(.boss, 240, 60)], items: [(.tape, 64, 118)],
                     caption: "ПУЛЬТ FOH", line: "ФИДБЭК… ГЛАВНЫЙ ЗВУКАРЬ. ВЕРНИ МНЕ ПУЛЬТ!"),
        ],
    ]

    // MARK: Step

    public func step(_ input: GameInput) {
        events.removeAll(keepingCapacity: true)
        frame += 1
        let pressed = GameInput.edges(input, previous)
        previous = input
        effects = effects.compactMap { var e = $0; e.life -= 1; return e.life > 0 ? e : nil }

        switch mode {
        case .title:
            if pressed.start || pressed.punch || pressed.jump { newGame() }
        case .gameOver:
            if pressed.start || pressed.punch { restartPanel() }
        case .victory:
            if pressed.start { mode = .title }
        case .panelSlide:
            transition = min(1, transition + 1.0 / 45)
            if transition >= 1 { mode = .playing; startPanel() }
        case .pageTurn:
            transition = min(1, transition + 1.0 / 70)
            if transition >= 1 { mode = .playing; startPanel() }
        case .playing:
            play(input, pressed)
        }
    }

    public func newGame() {
        page = 0
        panel = 0
        inventory = []
        cableHits = 0
        hero = Fighter(id: 0, enemy: nil, x: 40, y: GameWorld.floorY, hp: 20, maxHP: 20, state: .idle)
        mode = .playing
        startPanel()
    }

    private func restartPanel() {
        hero.hp = hero.maxHP
        hero.state = .idle
        hero.invulnerable = 90
        mode = .playing
        startPanel()
    }

    private func startPanel() {
        let p = currentPanel
        enemies = []
        projectiles = []
        pickups = p.items.map { Pickup(kind: $0.kind, x: $0.x, y: $0.y) }
        pendingSpawns = p.enemies
        exitOpen = false
        // Entry point follows the direction we came from.
        hero.vx = 0; hero.vy = 0
        hero.state = .idle
        if let caption = p.caption { effects.append(Effect(kind: .caption, text: caption, x: 8, y: 6, life: 200, fromHero: false)) }
        if let line = p.line { effects.append(Effect(kind: .bubble, text: line, x: hero.x, y: hero.y - 58, life: 170, fromHero: true)) }
    }

    private func play(_ input: GameInput, _ pressed: GameInput) {
        // Enemies arriving: drawn into the panel one by one.
        for i in pendingSpawns.indices.reversed() {
            pendingSpawns[i].delay -= 1
            if pendingSpawns[i].delay <= 0 {
                let s = pendingSpawns.remove(at: i)
                let e = Fighter(id: nextID, enemy: s.kind, x: s.x, y: GameWorld.floorY, facing: s.x > hero.x ? -1 : 1,
                                hp: s.kind.maxHP, maxHP: s.kind.maxHP, state: .spawn, timer: 50)
                nextID += 1
                enemies.append(e)
                if s.kind == .boss { events.append(.bossRoar); say("ФИДБЭК: ТЕСТ… РАЗ… ДВА… ТРИ… ВЫ УВОЛЕНЫ!", x: s.x, enemy: true) }
            }
        }
        updateHero(input, pressed)
        for i in enemies.indices { updateEnemy(i) }
        updateProjectiles()
        enemies.removeAll { $0.state == .dead && $0.timer <= 0 }
        for i in pickups.indices where !pickups[i].taken {
            let p = pickups[i]
            if abs(p.x - hero.x) < 14 && abs(p.y - hero.y) < 24 && inventory.count < 3 {
                pickups[i].taken = true
                inventory.append(p.kind)
                events.append(.pickup)
                effects.append(Effect(kind: .burst, text: p.kind == .tape ? "СКОТЧ!" : (p.kind == .cable ? "КАБЕЛЬ!" : "СТРОБ!"),
                                      x: p.x, y: p.y - 20, life: 40, fromHero: false))
            }
        }
        // Panel cleared: open the exit.
        if !exitOpen && pendingSpawns.isEmpty && enemies.allSatisfy({ $0.state == .dead }) {
            exitOpen = true
            events.append(.panelClear)
            if currentPanel.exit == .end {
                mode = .victory
                events.append(.victory)
                return
            }
            say(["ЧИСТО. ДАЛЬШЕ!", "ЛИНИЯ СВОБОДНА.", "САУНДЧЕК ПРОЙДЕН.", "СЛЕДУЮЩИЙ!"][Int(random() * 4) % 4], x: hero.x, enemy: false)
        }
        if exitOpen { checkExit() }
        if hero.hp <= 0 && hero.state == .dead && hero.timer <= 0 {
            mode = .gameOver
            events.append(.gameOver)
        }
    }

    private func checkExit() {
        let p = currentPanel
        let leaving: Bool
        switch p.exit {
        case .right, .nextPage: leaving = hero.x >= GameWorld.panelW - 10
        case .left: leaving = hero.x <= 10
        case .down: leaving = hero.x > GameWorld.panelW / 2 - 30 && hero.x < GameWorld.panelW / 2 + 30 && hero.y >= GameWorld.floorY && hero.state != .jump && previousDown
        case .end: leaving = false
        }
        guard leaving else { return }
        fromPanel = panel
        transition = 0
        pickups = []
        projectiles = []
        effects = []
        switch p.exit {
        case .nextPage:
            page += 1
            panel = 0
            mode = .pageTurn
            hero.x = 30
            events.append(.pageTurn)
        case .right:
            panel += 1
            mode = .panelSlide
            hero.x = 20
            events.append(.panelSlide)
        case .left:
            panel += 1
            mode = .panelSlide
            hero.x = GameWorld.panelW - 20
            events.append(.panelSlide)
        case .down:
            panel += 1
            mode = .panelSlide
            hero.x = GameWorld.panelW / 2
            events.append(.panelSlide)
        case .end: break
        }
        hero.y = GameWorld.floorY
    }

    private var previousDown = false

    // MARK: Hero

    private func updateHero(_ input: GameInput, _ pressed: GameInput) {
        previousDown = input.down
        var h = hero
        if h.invulnerable > 0 { h.invulnerable -= 1 }
        if h.comboTimer > 0 { h.comboTimer -= 1 } else { h.combo = 0 }
        if h.timer > 0 { h.timer -= 1 }

        // Items.
        for (k, p) in [pressed.item1, pressed.item2, pressed.item3].enumerated() where p && k < inventory.count && h.state != .dead {
            use(inventory.remove(at: k), hero: &h)
            break
        }

        switch h.state {
        case .dead:
            h.vx = 0
        case .hurt:
            if h.timer <= 0 { h.state = .idle }
        case .punch, .kick:
            let attack = h.state
            let hitStart = attack == .punch ? 9 : 13, hitEnd = attack == .punch ? 5 : 8
            if !h.hitDone && h.timer <= hitStart && h.timer >= hitEnd {
                if heroHits(&h, kick: attack == .kick) { h.hitDone = true }
            }
            if h.onGround { h.vx *= 0.7 }
            if h.timer <= 0 { h.state = h.onGround ? .idle : .jump }
        default:
            var dir = 0.0
            if input.left { dir -= 1 }
            if input.right { dir += 1 }
            if dir != 0 { h.facing = dir }
            h.vx = dir * 1.6
            if pressed.jump && h.onGround {
                h.vy = -6.2
                h.onGround = false
                events.append(.jump)
            }
            if pressed.punch || pressed.kick {
                let kick = pressed.kick || !h.onGround
                h.state = kick ? .kick : .punch
                h.timer = kick ? 20 : 14
                h.hitDone = false
                if !kick { h.combo += 1; h.comboTimer = 30 }
                events.append(kick ? .kick : .punch)
            } else {
                h.state = !h.onGround ? .jump : (dir != 0 ? .walk : .idle)
            }
        }
        physics(&h)
        if h.state == .walk { h.animation += 1; if h.animation % 16 == 0 { events.append(.step) } }
        hero = h
    }

    private func use(_ item: ItemKind, hero h: inout Fighter) {
        switch item {
        case .tape:
            h.hp = min(h.maxHP, h.hp + 8)
            events.append(.heal)
            effects.append(Effect(kind: .burst, text: "+8", x: h.x, y: h.y - 62, life: 40, fromHero: true))
        case .cable:
            cableHits = 8
            events.append(.cableOn)
            say("ПОСЛУШАЙ, КАК ЗВУЧИТ ХОРОШАЯ КОММУТАЦИЯ!", x: h.x, enemy: false)
        case .strobe:
            events.append(.strobe)
            for i in enemies.indices where enemies[i].state != .dead && enemies[i].state != .spawn {
                enemies[i].state = .stunned
                enemies[i].timer = enemies[i].enemy == .boss ? 90 : 200
                enemies[i].vx = 0
            }
            effects.append(Effect(kind: .burst, text: "ВСПЫШКА!", x: GameWorld.panelW / 2, y: 60, life: 50, fromHero: false))
        }
    }

    /// Resolves the hero's attack; returns true if something was hit.
    private func heroHits(_ h: inout Fighter, kick: Bool) -> Bool {
        let cable = cableHits > 0
        let reach = cable ? 48.0 : (kick ? 36 : 30)
        let zone = Rect(h.facing > 0 ? h.x : h.x - reach, h.y - 46, reach, 34)
        var hit = false
        for i in enemies.indices {
            var e = enemies[i]
            guard e.state != .dead, e.state != .spawn, e.invulnerable == 0, zone.intersects(e.box) else { continue }
            var damage = kick ? 2 : 1
            if !kick && h.combo >= 3 { damage = 2; h.combo = 0 }
            if cable { damage += 2 }
            e.hp -= damage
            e.invulnerable = 12
            e.vx = h.facing * (kick ? 3.2 : 2.0) * (e.enemy == .boss ? 0.4 : 1)
            e.vy = kick ? -2.5 : -1
            e.onGround = false
            if e.hp <= 0 {
                e.state = .dead
                e.timer = 50
                events.append(.enemyDown)
                effects.append(Effect(kind: .burst, text: ["ХРЯСЬ!", "БАБАХ!", "ШМЯК!"][Int(random() * 3) % 3], x: e.x, y: e.y - 54, life: 36, fromHero: false))
            } else {
                if e.enemy != .boss || kick { e.state = .hurt; e.timer = 18 }
                events.append(damage >= 3 ? .bigHit : .hit)
                effects.append(Effect(kind: .burst, text: damage >= 3 ? "БАЦ!!" : (kick ? "БУМ!" : "БАЦ!"), x: e.x, y: e.y - 52, life: 24, fromHero: false))
            }
            enemies[i] = e
            hit = true
        }
        if hit && cable { cableHits -= 1 }
        return hit
    }

    // MARK: Enemies

    private func updateEnemy(_ i: Int) {
        var e = enemies[i]
        guard let kind = e.enemy else { return }
        if e.invulnerable > 0 { e.invulnerable -= 1 }
        if e.cooldown > 0 { e.cooldown -= 1 }
        if e.timer > 0 { e.timer -= 1 }
        let dx = hero.x - e.x
        switch e.state {
        case .spawn:
            if e.timer <= 0 { e.state = .idle; e.cooldown = 30 }
        case .dead:
            e.vx *= 0.9
        case .hurt, .stunned:
            if e.timer <= 0 { e.state = .idle }
        case .windup:
            e.vx = 0
            if e.timer == (kind == .boss ? 14 : 10) {
                if kind == .singer || (kind == .boss && random() < 0.5) {
                    projectiles.append(Projectile(x: e.x + e.facing * 16, y: e.y - (kind == .boss ? 40 : 36), vx: e.facing * (kind == .boss ? 2.6 : 2.0),
                                                  life: 140, damage: kind.damage, big: kind == .boss))
                    events.append(kind == .boss ? .bossRoar : .shout)
                    if random() < 0.3 { say(kind == .boss ? "FEEDBACK!!!" : "А-А-А-А-А!", x: e.x, enemy: true) }
                } else if abs(dx) < (kind == .boss ? 40 : 30) && abs(hero.y - e.y) < 24 {
                    hurtHero(kind.damage, from: e.x)
                }
            }
            if e.timer <= 0 { e.state = .idle; e.cooldown = kind == .boss ? 50 : (kind == .fan ? 45 : 70) }
        default:
            e.facing = dx >= 0 ? 1 : -1
            let ranged = kind == .singer || (kind == .boss && abs(dx) > 70)
            let range = ranged ? 160.0 : (kind == .boss ? 34 : 24)
            if hero.state == .dead {
                e.vx = 0
                e.state = .idle
            } else if abs(dx) > range {
                e.vx = e.facing * kind.speed * (kind == .boss && abs(dx) > 120 ? 2.2 : 1)
                e.state = .walk
                e.animation += 1
            } else {
                e.vx = 0
                e.state = .idle
                if e.cooldown == 0 {
                    e.state = .windup
                    e.timer = kind == .boss ? 34 : 28
                }
            }
            // Singers keep some distance.
            if kind == .singer && abs(dx) < 60 { e.vx = -e.facing * kind.speed; e.state = .walk; e.animation += 1 }
        }
        physics(&e)
        if e.state == .dead && e.timer <= 0 { e.timer = 0 }
        enemies[i] = e
    }

    private func hurtHero(_ damage: Int, from x: Double) {
        guard hero.invulnerable == 0, hero.state != .dead else { return }
        hero.hp -= damage
        hero.invulnerable = 60
        hero.vx = (hero.x < x ? -1 : 1) * 2.5
        hero.vy = -2
        hero.onGround = false
        events.append(.hurt)
        if hero.hp <= 0 {
            hero.hp = 0
            hero.state = .dead
            hero.timer = 90
            effects.append(Effect(kind: .bubble, text: "НЕТ… ШОУ… ДОЛЖНО…", x: hero.x, y: hero.y - 58, life: 90, fromHero: true))
        } else {
            hero.state = .hurt
            hero.timer = 16
            effects.append(Effect(kind: .burst, text: "АЙ!", x: hero.x, y: hero.y - 54, life: 22, fromHero: false))
        }
    }

    private func updateProjectiles() {
        for i in projectiles.indices {
            projectiles[i].x += projectiles[i].vx
            projectiles[i].life -= 1
            let p = projectiles[i]
            let box = Rect(p.x - (p.big ? 8 : 5), p.y - (p.big ? 8 : 5), p.big ? 16 : 10, p.big ? 16 : 10)
            if box.intersects(hero.box) && hero.invulnerable == 0 && hero.state != .dead {
                hurtHero(p.damage, from: p.x - p.vx * 4)
                projectiles[i].life = 0
            }
        }
        projectiles.removeAll { $0.life <= 0 || $0.x < -20 || $0.x > GameWorld.panelW + 20 }
    }

    // MARK: Physics

    private func physics(_ f: inout Fighter) {
        let wasAbove = f.y
        f.vy += 0.32
        f.x += f.vx
        f.y += f.vy
        f.onGround = false
        if f.y >= GameWorld.floorY {
            f.y = GameWorld.floorY
            f.vy = 0
            f.onGround = true
        } else if f.vy >= 0 {
            for p in currentPanel.platforms where f.x > p.x - 4 && f.x < p.x + p.w + 4 && wasAbove <= p.y + 0.01 && f.y >= p.y {
                f.y = p.y
                f.vy = 0
                f.onGround = true
            }
        }
        if !f.onGround && f.enemy == nil && f.state == .idle { f.state = .jump }
        // Panel borders: the hero may leave only through an open exit.
        let minX = 8.0, maxX = GameWorld.panelW - 8
        if f.enemy == nil && exitOpen {
            switch currentPanel.exit {
            case .right, .nextPage: f.x = min(max(f.x, minX), GameWorld.panelW)
            case .left: f.x = min(max(f.x, 0), maxX)
            default: f.x = min(max(f.x, minX), maxX)
            }
        } else {
            f.x = min(max(f.x, minX), maxX)
        }
    }

    private func say(_ text: String, x: Double, enemy: Bool) {
        effects.removeAll { $0.kind == .bubble }
        effects.append(Effect(kind: .bubble, text: text, x: x, y: (enemy ? 90 : hero.y - 58), life: 120, fromHero: !enemy))
    }
}

extension GameInput {
    /// Buttons pressed this step (not held from the previous one).
    static func edges(_ now: GameInput, _ before: GameInput) -> GameInput {
        var p = GameInput()
        p.jump = now.jump && !before.jump
        p.punch = now.punch && !before.punch
        p.kick = now.kick && !before.kick
        p.item1 = now.item1 && !before.item1
        p.item2 = now.item2 && !before.item2
        p.item3 = now.item3 && !before.item3
        p.start = now.start && !before.start
        p.down = now.down && !before.down
        return p
    }
}
