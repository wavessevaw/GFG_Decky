"""Comic pages in the bright, saturated style of 16-bit comic games: panels of different sizes laid out on
a page with gutters and yellow route arrows. Each page has its own colour theme (two 15-colour palettes)."""
import math
import numpy as np
import scenes
from scenes import Scene, R, shade_into, ink_ring, cast_shadow, stencil, snap_ramps, INK
from art import (tube, ellipsoid, poly, inflate, ramp, rect_mask, normals_from_height, noise, toon, lambert,
                 bayer, md, LIGHT)

THEMES = {
    'backstage': dict(
        wall=ramp('#08301c', '#145a28', '#22903c', '#4cc04c', '#a0ec6c'),
        purple=ramp('#280840', '#5c1c8c', '#9c48d4', '#e0a0ff'),
        red=ramp('#3c1000', '#902c00', '#e06414', '#ffb03c', '#fff0a0'),
        steel=ramp('#0c1838', '#1c4888', '#4088d4', '#90d0ff', '#ffffff'),
        case=ramp('#0c0c1c', '#22223e', '#3e3e66'),
        yellow=ramp('#5c3c00', '#d4a000', '#fff040'),
        floor=ramp('#041830', '#0c3058', '#1c5c90'),
        warm=ramp('#a04c00', '#ffa820', '#fff0a0'),
        wood=ramp('#3c1400', '#7c3000', '#c0641c', '#f0a048'),
        magenta=ramp('#600040', '#c8188c', '#ff70d0'),
        cyan=ramp('#00406c', '#0098d8', '#70f0ff'),
        green=ramp('#0c3018', '#1c6c30', '#48b040'),
    ),
    'show': dict(
        purple=ramp('#0c0424', '#220c48', '#441c84', '#7c44c8'),
        curtain=ramp('#480418', '#900c38', '#e02860', '#ff84a8'),
        red=ramp('#480418', '#900c38', '#e02860', '#ff84a8', '#ffe0e8'),
        magenta=ramp('#580048', '#c010a0', '#ff60e0'),
        cyan=ramp('#00406c', '#0090d0', '#60f0ff'),
        steel=ramp('#3c2000', '#8c5800', '#dca820', '#fff078', '#ffffff'),
        case=ramp('#08081c', '#1c1c3c', '#363664'),
        yellow=ramp('#603c00', '#e0a800', '#fff050'),
        warm=ramp('#b05800', '#ffb030', '#fff0b0'),
        wall=ramp('#100428', '#220c48', '#441c84', '#7c44c8', '#c0a0ff'),
        floor=ramp('#04020c', '#140828', '#2c1450'),
        wood=ramp('#300c00', '#6c2c00', '#b05c18', '#e89848'),
        green=ramp('#003020', '#008050', '#30e090'),
        skin_dead=ramp('#18200c', '#34442c', '#5c7448'),
    ),
}


def theme(name):
    R.update(THEMES[name])


def bright(s, base=1.12):
    s.light[:] = base
    s.vignette(0.32)


# ------------------------------------------------------------------ extra bold props

def porthole(s, cx, cy, r, glass=None):
    """Big round sewer-style porthole: thick bolted ring, grille or glowing glass."""
    m, n = ellipsoid(s.h, s.w, cx, cy, r, r)
    hole, _ = ellipsoid(s.h, s.w, cx, cy, r * 0.7, r * 0.7)
    ring = m & ~hole
    cast_shadow(s.c, m, -5, 6)
    shade_into(s.c, ring, n, R['purple'], 0.3, 1.0, line=INK, lightmap=s.light, shadow=False)
    ink_ring(s.c, hole)
    if glass is not None:
        g = toon(0.5 + (s.yy - cy) / r * -0.4 + 0.2 * (np.abs(s.xx - s.yy - (cx - cy)) < r * 0.2), glass, 0.3)
        s.c.put(hole, g)
    else:
        s.c.put(hole, R['case'][0])
        bars = hole & ((((s.xx - cx) % 7) < 2) | (((s.yy - cy) % 7) < 2))
        _, bn = inflate(bars, 1.2)
        shade_into(s.c, bars, bn, R['steel'], 0.3, 1.0, lightmap=s.light, shadow=False)
    for k in range(8):
        a = k / 8 * 2 * math.pi
        bm, bn = ellipsoid(s.h, s.w, cx + math.cos(a) * r * 0.85, cy + math.sin(a) * r * 0.85, 1.6, 1.6)
        shade_into(s.c, bm, bn, R['steel'], 0.4, 1.0, lightmap=s.light, shadow=False)


def tank(s, x, y, w, h, label=None):
    """Rusty boiler / tank: vertical cylinder with domed top, rivet bands and a pressure gauge."""
    m = rect_mask(s.h, s.w, x, y + w // 4, w, h - w // 4)
    top, _ = ellipsoid(s.h, s.w, x + w / 2, y + w / 4, w / 2, w / 4)
    m |= top
    nx = np.clip((s.xx - (x + w / 2)) / (w / 2), -1, 1)
    n = np.stack([nx, np.where(top & (s.yy < y + w / 4), -0.6, 0.0), np.sqrt(np.clip(1 - nx ** 2, 0, 1))], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    shade_into(s.c, m, n, R['red'], 0.3, 1.0, line=INK, lightmap=s.light)
    for by in range(y + w // 4 + 10, y + h - 4, 16):
        band = m & (np.abs(s.yy - by) < 1.5)
        s.c.rgb[band] = R['red'][0]
        for bx in range(x + 4, x + w - 2, 6):
            if 0 <= by - 3 < s.h:
                s.c.rgb[by - 3, bx] = R['red'][-1]
    gm, gn = ellipsoid(s.h, s.w, x + w / 2, y + h / 2, 6, 6)
    shade_into(s.c, gm, gn, R['steel'], 0.6, 1.0, line=INK, lightmap=s.light, shadow=False)
    gi, _ = ellipsoid(s.h, s.w, x + w / 2, y + h / 2, 4, 4)
    s.c.put(gi, R['steel'][-1])
    nm, _, _ = tube(s.h, s.w, [(x + w / 2, y + h / 2), (x + w / 2 + 3, y + h / 2 - 2.5)], [0.6, 0.6])
    s.c.put(nm, INK)
    if label:
        stencil(s.c, label, x + 4, y + h - 14, R['yellow'][2])


def deck(s, y0, kind='water'):
    """Bold floor: a lit metal ledge with rivets over dark water / boards with glossy reflections."""
    if kind == 'water':
        s.wet_floor(y0 + 6)
    elif kind == 'stage':
        s.stage_floor(y0 + 6)
    lip = rect_mask(s.h, s.w, 0, y0, s.w, 7)
    _, n = inflate(lip, 2.0, 'bevel')
    shade_into(s.c, lip, n, R['steel'], 0.45, 1.0, line=INK, lightmap=s.light, shadow=False)
    for x in range(4, s.w, 12):
        s.c.rgb[y0 + 3, x] = R['steel'][-1]
        s.c.rgb[y0 + 4, x] = R['steel'][0]


def tiles_wall(s, y0, y1, size=16):
    """Glossy ceramic tiles (sewer-green), each tile bevelled and lit, grime at the bottom."""
    yy, xx = s.yy, s.xx
    u, v = xx % size, (yy - y0) % size
    edge = np.minimum(np.minimum(u, size - u), np.minimum(v, size - v))
    hgt = np.clip(edge / 3.0, 0, 1) * 3 + noise(s.h, s.w, 5, s.seed) * 0.6
    n = normals_from_height(hgt, 1.0)
    m = (yy >= y0) & (yy < y1)
    grime = np.clip((yy - y0) / max(1, y1 - y0) - 0.45, 0, 1) * 1.1 * (noise(s.h, s.w, 14, s.seed + 2) + 0.3)
    rng = np.random.default_rng(s.seed)
    tone = rng.uniform(-0.12, 0.08, (s.h // size + 2, s.w // size + 2))
    per_tile = tone[((yy - y0) // size).astype(int) % tone.shape[0], (xx // size).astype(int) % tone.shape[1]]
    streak = (noise(1, s.w, 5, s.seed + 7)[0] > 0.66)[None, :] * (noise(s.h, s.w, 25, s.seed + 8) > 0.5) * 0.22
    v = lambert(n, LIGHT, 0.32) * s.light - grime + per_tile - streak
    v = v + 0.25 * ((u + v * 0 < 3) & (((yy - y0) % size) < 3))
    col = toon(v, R['wall'], 0.3)
    grout = ((u < 1) | (((yy - y0) % size) < 1)) & m
    col = np.where(grout[..., None], R['wall'][0], col)
    s.c.put(m, col)


def drips(s, xs, y0, length, rmp):
    for x in xs:
        m, n, _ = tube(s.h, s.w, [(x, y0), (x, y0 + length * 0.6), (x + 0.5, y0 + length)], [1.4, 1.0, 1.6])
        shade_into(s.c, m, n, rmp, 0.5, 1.0, lightmap=s.light, shadow=False)


def neon(s, text, x, y, rmp, scale=2):
    from scenes import text_mask
    m, _ = text_mask(text, scale, s.w, s.h, x, y)
    glow = np.zeros_like(m)
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            glow |= np.roll(np.roll(m, dy, 0), dx, 1)
    b = bayer(s.h, s.w)
    on = glow & ~m & (b < 0.5)
    s.c.rgb[on] = snap_ramps(s.c.rgb[on] * 0.4 + np.asarray(rmp[1], np.float32) * 0.7)
    s.c.put(m, rmp[-1])
    edge = m & ~np.roll(m, 1, 0)
    s.c.rgb[edge] = md('#ffffff')


def caption_sign(s, text, x, y, w, rmp_bg, rmp_fg):
    m = rect_mask(s.h, s.w, x, y, w, 12)
    _, n = inflate(m, 1.5, 'bevel')
    shade_into(s.c, m, n, rmp_bg, 0.6, 0, line=INK, lightmap=s.light)
    stencil(s.c, text, x + 4, y + 4, rmp_fg)


# ------------------------------------------------------------------ page 1: backstage

def p1_boiler(w, h, seed=101):
    s = Scene(seed, w, h)
    s.floor = F = h - 30
    bright(s)
    s.lamp(w * 0.5, 30, w * 0.8, 0.5)
    tiles_wall(s, 0, F)
    # huge purple pipes with elbows and drains
    s.pipe([(-10, 18), (w + 10, 18)], 9, R['purple'], flanges=[(60, 18, False), (170, 18, False), (260, 18, False)])
    s.elbow(70, 44, 16, -math.pi / 2, 0, 7, R['purple'])
    s.pipe([(86, 44), (86, F - 30)], 7, R['purple'], flanges=[(86, 80, True)])
    s.elbow(70, F - 30, 16, 0, math.pi / 2, 7, R['purple'])
    s.pipe([(70, F - 14), (-10, F - 14)], 7, R['purple'])
    porthole(s, 160, 78, 24)
    porthole(s, 236, 70, 14, glass=R['cyan'])
    drips(s, (160, 152, 168), 102, 26, R['cyan'])
    tank(s, w - 70, F - 96, 44, 96, 'BOILER')
    s.road_case(110, F - 34, 52, 34, 'SSMT')
    s.road_case(170, F - 22, 36, 22, 'XLR')
    s.blood(214, F - 50, 5, hand=True)
    deck(s, F)
    return s.finish()


def p1_tunnel(w, h, seed=102):
    s = Scene(seed, w, h)
    s.floor = F = h - 28
    bright(s, 1.0)
    s.c.rgb[:] = R['steel'][0]
    # brick-arched service tunnel lit by hanging work lamps
    s.block_wall(0, F, bw=24, bh=12, rmp=R['red'][:4])
    arch = (np.hypot((s.xx - w / 2) / (w * 0.62), (s.yy - F) / (F * 1.05)) > 1) & (s.yy < F)
    s.c.rgb[arch] = R['case'][0]
    for lx in (50, w - 60):
        s.pipe([(lx, 0), (lx, 26)], 0.8, R['steel'])
        lm, ln = ellipsoid(s.h, s.w, lx, 30, 8, 5)
        shade_into(s.c, lm & (s.yy < 30), ln, R['steel'], 0.4, 1.0, line=INK)
        bm, bn = ellipsoid(s.h, s.w, lx, 31, 3.4, 3)
        shade_into(s.c, bm, bn, R['warm'], 0.9, 1.0, line=INK)
        s.beam(lx, 34, lx, F, 4, 34, R['yellow'][2], 0.32)
    tray = rect_mask(s.h, s.w, 0, 44, w, 4)
    _, tn = inflate(tray, 1.5, 'bevel')
    shade_into(s.c, tray, tn, R['steel'], 0.4, 1.0, line=INK, lightmap=s.light)
    s.cable_bundle(-4, w + 4, 50, 22, [R['red'][1:4], R['yellow'], R['purple'][1:], R['cyan'], R['case']])
    s.cable_bundle(-4, w + 4, 50, 34, [R['green'], R['case']])
    s.road_case(20, F - 40, 60, 40, 'MULTICORE')
    for cx in (130, 170):
        for r in (12, 8, 4):
            m, n, _ = tube(s.h, s.w, [(cx + math.cos(a) * r * 1.4, F - 6 + math.sin(a) * r * 0.45) for a in np.linspace(0, 6.3, 24)], [1.4] * 24)
            shade_into(s.c, m, n, R['yellow'], 0.4, 1.0, line=INK, lightmap=s.light)
    s.blood(w - 40, 60, 6)
    deck(s, F)
    return s.finish()


def p1_dock(w, h, seed=103):
    s = Scene(seed, w, h)
    s.floor = F = h - 26
    bright(s)
    # night sky through the open dock: deep blue gradient, stars, the moon
    sky = s.yy < F
    s.c.put(sky, toon(0.25 + s.yy / h * 0.5, R['steel'][:3], 0.5))
    rng = np.random.default_rng(seed)
    for _ in range(40):
        x, y = rng.integers(0, w), rng.integers(0, F - 30)
        s.c.rgb[y, x] = R['steel'][-1]
    mm, mn = ellipsoid(s.h, s.w, 60, 34, 16, 16)
    shade_into(s.c, mm, mn, R['yellow'], 0.6, 0, line=INK)
    s.c.put(mm & (np.hypot(s.xx - 68, s.yy - 30) < 14), R['steel'][1])
    # the tour truck with a neon logo
    s.box(118, 30, 168, F - 30, R['steel'][1:4], 3, 1.0)
    neon(s, 'SSMT TOUR', 136, 46, R['magenta'], 2)
    s.box(118, F - 30, 168, 30, R['case'], 2)
    for wx in (140, 250):
        wm, wn = ellipsoid(s.h, s.w, wx, F - 4, 14, 14)
        shade_into(s.c, wm, wn, R['case'], 0.4, 1.0, line=INK, lightmap=s.light)
        hm, hn = ellipsoid(s.h, s.w, wx, F - 4, 6, 6)
        shade_into(s.c, hm, hn, R['steel'], 0.5, 1.0, line=INK, lightmap=s.light)
    # roller door frame and hazard edges
    s.box(0, 0, w, 12, R['steel'], 2, 1.0)
    s.hazard_stripe(0, 12, w, 6)
    s.road_case(14, F - 44, 56, 44, 'AMP')
    s.road_case(76, F - 28, 40, 28, 'DI')
    s.blood(100, F - 50, 5)
    deck(s, F)
    return s.finish()


def p1_lift(w, h, seed=104):
    s = Scene(seed, w, h)
    s.floor = F = h - 30
    bright(s)
    tiles_wall(s, 0, F, size=20)
    # freight lift cage with a giant fan behind it
    fm, fn = ellipsoid(s.h, s.w, w * 0.62, 84, 52, 52)
    shade_into(s.c, fm, -fn * np.array([1, 1, -1]), R['steel'][:4], 0.35, 0, line=INK, lightmap=s.light)
    for k in range(5):
        a = k / 5 * 2 * math.pi + 0.3
        bm, bn, _ = tube(s.h, s.w, [(w * 0.62, 84), (w * 0.62 + math.cos(a) * 44, 84 + math.sin(a) * 44)], [4, 10])
        shade_into(s.c, bm, bn, R['purple'], 0.4, 1.0, line=INK, lightmap=s.light)
    hm, hn = ellipsoid(s.h, s.w, w * 0.62, 84, 9, 9)
    shade_into(s.c, hm, hn, R['red'], 0.5, 1.0, line=INK, lightmap=s.light)
    for gx in range(int(w * 0.62 - 54), int(w * 0.62 + 56), 8):
        g, gn, _ = tube(s.h, s.w, [(gx, 30), (gx, 138)], [0.9, 0.9])
        shade_into(s.c, g & fm, gn, R['steel'], 0.4, 1.0, lightmap=s.light, shadow=False)
    # catwalk platform with railings
    cw = rect_mask(s.h, s.w, 16, F - 70, 120, 6)
    _, cn = inflate(cw, 2, 'bevel')
    shade_into(s.c, cw, cn, R['steel'], 0.4, 1.0, line=INK, lightmap=s.light)
    s.platforms.append((16, F - 70, 120))
    for x in (20, 128):
        s.pipe([(x, F - 64), (x, F)], 2.0, R['steel'])
    s.pipe([(16, F - 92), (136, F - 92)], 1.6, R['yellow'])
    for x in range(22, 136, 16):
        s.pipe([(x, F - 92), (x, F - 70)], 1.0, R['yellow'])
    s.road_case(w - 74, F - 30, 60, 30, 'LIFT')
    s.hazard_stripe(0, F - 6, w, 6)
    caption_sign(s, 'B2', 10, 10, 20, R['yellow'], R['case'][0])
    deck(s, F)
    return s.finish()


def p1_dressing(w, h, seed=105):
    s = Scene(seed, w, h)
    s.floor = F = h - 28
    bright(s, 1.15)
    m = s.yy < F
    stripes = (s.xx // 8) % 2 == 0
    s.c.put(m, toon(0.55 + 0.15 * stripes + noise(s.h, s.w, 20, seed) * 0.15, R['magenta'], 0.3))
    s.mirror_bulbs(60, 48, 120, 60)
    s.box(46, 116, 148, 8, R['wood'], 2)
    s.platforms.append((46, 116, 148))
    for lx in (50, 186):
        s.box(lx, 124, 6, F - 124, R['wood'], 1.5)
    s.clothes_rack(w - 60, 64, 50, [R['cyan'], R['yellow'], R['purple'][1:], R['green']])
    s.poster(8, 40, 34, 44, 'SOLD', 'OUT')
    s.blood(120, 80, 6, hand=True)
    fl = s.yy >= F
    s.c.put(fl, toon(0.55 + noise(s.h, s.w, 8, seed + 4) * 0.3, R['wood'], 0.3))
    s.c.rgb[fl & (((s.xx + (s.yy // 6) * 21) % 36) < 1)] = R['wood'][0]
    s.c.rgb[fl & (s.yy % 6 == 0)] = R['wood'][0]
    s.c.rgb[F] = R['wood'][3]
    return s.finish()


def p1_corridor(w, h, seed=106):
    s = Scene(seed, w, h)
    s.floor = F = h - 30
    bright(s, 1.05)
    s.block_wall(0, F, bw=20, bh=10, rmp=R['wall'])
    band = (s.yy > F - 56) & (s.yy < F)
    s.c.put(band, toon((0.55 + noise(s.h, s.w, 12, seed) * 0.25) * s.light, R['red'][:4], 0.3))
    s.c.rgb[F - 56] = R['case'][0]
    s.door(24, F - 84, 46, 84)
    neon(s, 'STAGE', w - 120, 36, R['cyan'], 3)
    for k in range(3):
        ax = w - 112 + k * 30
        m = poly(s.h, s.w, [(ax, 70), (ax + 14, 76), (ax, 82)])
        s.c.put(m, R['yellow'][2], line=INK)
        ink_ring(s.c, m)
    s.pipe([(-10, 12), (w + 10, 12)], 6, R['purple'], flanges=[(90, 12, False), (210, 12, False)])
    s.road_case(110, F - 38, 52, 38, 'DRUMS')
    s.road_case(168, F - 24, 38, 24, 'MON')
    s.speaker(116, F - 82, 38, 44, 2)
    s.platforms.append((116, F - 82, 38))
    s.blood(250, 90, 7, hand=True)
    deck(s, F)
    return s.finish()


# ------------------------------------------------------------------ page 2: the show

def p2_wings(w, h, seed=201):
    s = Scene(seed, w, h)
    s.floor = F = h - 30
    bright(s, 1.1)
    s.c.rgb[:] = R['purple'][0]
    s.curtain(0, w * 0.45, 0, F, period=14)
    s.truss_v(int(w * 0.47), 0, F, 10)
    s.par_can(w - 40, 14, R['magenta'])
    s.beam(w - 37, 24, w - 70, F, 3, 40, R['magenta'][2], 0.4)
    s.speaker(w * 0.55, F - 44, 60, 44, 2)
    s.speaker(w * 0.55 + 6, F - 84, 48, 40, 2)
    s.platforms += [(int(w * 0.55), F - 44, 60), (int(w * 0.55 + 6), F - 84, 48)]
    s.road_case(14, F - 30, 56, 30, 'BACKLINE')
    s.blood(60, 80, 5)
    deck(s, F, 'stage')
    return s.finish()


def p2_stage(w, h, seed=202):
    s = Scene(seed, w, h)
    s.floor = F = h - 30
    bright(s, 1.15)
    s.c.rgb[:] = R['purple'][0]
    # LED wall with a giant zombie face
    led = rect_mask(s.h, s.w, 40, 26, w - 80, 86)
    face = 0.35 + 0.5 * np.exp(-(((s.xx - w / 2) / 50) ** 2 + ((s.yy - 70) / 34) ** 2))
    eyes = (np.hypot(s.xx - (w / 2 - 18), s.yy - 62) < 7) | (np.hypot(s.xx - (w / 2 + 18), s.yy - 62) < 7)
    mouth = (np.abs(s.yy - 88) < 5) & (np.abs(s.xx - w / 2) < 22)
    col = toon(face, R['green'], 0.4)
    col = np.where((eyes | mouth)[..., None], R['yellow'][2], col)
    grid = (s.xx % 3 == 0) | (s.yy % 3 == 0)
    col = np.where(grid[..., None], R['case'][0], col)
    s.c.put(led, col)
    ink_ring(s.c, led)
    s.truss_h(0, w, 4, 12)
    for k, (px, c) in enumerate(((30, R['magenta']), (110, R['cyan']), (w - 110, R['yellow']), (w - 34, R['magenta']))):
        s.par_can(px, 18, c)
        s.beam(px + 3, 28, px + 3 + (k - 1.5) * 34, F, 3, 36, c[-1], 0.38)
    s.box(80, F - 28, w - 160, 28, R['case'], 2)
    s.platforms.append((80, F - 28, w - 160))
    s.drum_kit(w / 2, F - 28)
    neon(s, 'DEAD LIVE', 70, 120, R['red'], 1)
    s.speaker(6, F - 64, 36, 64, 2)
    s.speaker(w - 42, F - 64, 36, 64, 2)
    s.platforms += [(6, F - 64, 36), (w - 42, F - 64, 36)]
    s.wedge(46, F)
    s.wedge(w - 76, F)
    deck(s, F, 'stage')
    return s.finish()


def p2_grid(w, h, seed=203):
    s = Scene(seed, w, h)
    s.floor = F = h - 26
    bright(s, 1.1)
    s.c.rgb[:] = R['purple'][1]
    # up in the lighting grid: rows of moving heads, chain hoists, beams cutting the haze
    haze = noise(s.h, s.w, 20, seed)
    s.c.put(s.yy < F, toon(0.3 + haze * 0.4, R['purple'], 0.4))
    s.truss_h(0, w, 20, 14)
    s.truss_h(0, w, 70, 14)
    for k, px in enumerate(range(24, w, 46)):
        c = (R['cyan'], R['magenta'], R['yellow'])[k % 3]
        hm, hn = ellipsoid(s.h, s.w, px, 46, 9, 9)
        shade_into(s.c, hm, hn, R['case'], 0.5, 1.0, line=INK)
        lm, ln = ellipsoid(s.h, s.w, px, 50, 5, 3)
        shade_into(s.c, lm, ln, c, 0.9, 1.0, line=INK)
        s.beam(px, 52, px + (k % 2 * 2 - 1) * 40, F, 3, 26, c[-1], 0.3)
    for cx in (60, w - 60):
        s.pipe([(cx, 0), (cx, 20)], 1.2, R['steel'])
        s.box(cx - 8, 84, 16, 14, R['steel'], 2, 1.0)
    cw = rect_mask(s.h, s.w, 0, F - 4, w, 4)
    s.hazard_stripe(0, F - 10, w, 6)
    deck(s, F)
    return s.finish()


def p2_dancefloor(w, h, seed=204):
    s = Scene(seed, w, h)
    s.floor = F = h - 26
    bright(s, 1.1)
    s.c.rgb[:] = R['purple'][0]
    s.truss_h(0, w, 2, 10)
    for k, px in enumerate(range(26, w, 66)):
        c = (R['cyan'], R['magenta'])[k % 2]
        s.par_can(px, 14, c)
        s.beam(px + 3, 24, px + 3 + (k - 2) * 26, F, 3, 36, c[-1], 0.32)
    # mirror ball
    bm, bn = ellipsoid(s.h, s.w, w / 2, 40, 14, 14)
    facet = ((s.xx // 3 + s.yy // 3) % 2 == 0)
    shade_into(s.c, bm, bn, R['steel'][2:], 0.6, 1.0, line=INK)
    s.c.rgb[bm & facet] = snap_ramps(s.c.rgb[bm & facet] * 0.7)
    s.crowd(F - 74, 22, seed, R['purple'][1:], hands=True, scale=1.0, body=R['purple'][:2])
    s.crowd(F - 48, 14, seed + 1, R['purple'][2:], hands=True, scale=1.3, body=R['case'])
    s.barricade(0, w, F - 4)
    s.road_case(w / 2 - 30, F - 30, 60, 30, 'FX')
    fl = s.yy >= F
    s.c.put(fl, toon(0.4 + noise(s.h, s.w, 6, seed) * 0.3, R['purple'], 0.3))
    rng = np.random.default_rng(seed)
    for _ in range(120):
        x, y = rng.integers(0, w - 2), rng.integers(F + 2, h)
        s.c.rgb[y, x:x + 2] = (R['magenta'][2], R['cyan'][2], R['yellow'][2])[rng.integers(0, 3)]
    s.c.rgb[F] = R['steel'][2]
    return s.finish()


def p2_bar(w, h, seed=205):
    s = Scene(seed, w, h)
    s.floor = F = h - 28
    bright(s, 1.1)
    m = s.yy < F
    s.c.put(m, toon(0.3 + noise(s.h, s.w, 16, seed) * 0.3, R['purple'], 0.4))
    neon(s, 'BAR', 70, 18, R['cyan'], 4)
    neon(s, '24/7', 160, 30, R['magenta'], 2)
    # shelves with glowing bottles
    for sy in (70, 96):
        s.box(20, sy, w - 40, 4, R['wood'], 1.5)
        rng = np.random.default_rng(sy)
        for bx in range(26, w - 26, 9):
            c = (R['green'], R['cyan'], R['red'][1:4], R['yellow'])[rng.integers(0, 4)]
            m2, n2, _ = tube(s.h, s.w, [(bx, sy - 2), (bx, sy - 12), (bx, sy - 18)], [3, 3, 1.2])
            shade_into(s.c, m2, n2, c, 0.6, 1.0, line=INK, lightmap=s.light)
    s.box(10, F - 44, w - 20, 44, R['wood'], 3, 0.6)          # the counter
    s.box(6, F - 50, w - 12, 7, R['steel'], 2, 1.0)
    s.platforms.append((6, F - 50, w - 12))
    for tx in (40, w - 60):
        s.pipe([(tx, F - 50), (tx, F - 70)], 1.4, R['steel'])
        s.pipe([(tx, F - 70), (tx + 8, F - 70)], 1.4, R['steel'])
    s.blood(w / 2, F - 30, 6)
    deck(s, F, 'stage')
    return s.finish()


def p2_foh(w, h, seed=206):
    s = Scene(seed, w, h)
    s.floor = F = h - 30
    bright(s, 1.15)
    s.c.rgb[:] = R['purple'][0]
    glow = s.yy < 70
    s.c.put(glow, toon(0.3 + (70 - s.yy) / 70 * 0.6, R['purple'], 0.4))
    for k, px in enumerate(range(30, w, 60)):
        s.beam(px, 0, px + (k - 2) * 18, 80, 2, 18, (R['magenta'], R['cyan'])[k % 2][2], 0.3)
    s.crowd(60, 28, seed, R['purple'][1:], hands=True, scale=0.7, body=R['purple'][:2])
    s.truss_v(4, 0, F, 8)
    s.truss_v(w - 14, 0, F, 8)
    s.truss_h(4, w - 6, 96, 8)
    neon(s, 'FOH', w / 2 - 30, 104, R['yellow'], 2)
    s.box(30, F - 40, w - 60, 40, R['case'], 2)
    s.platforms.append((30, F - 40, w - 60))
    s.desk(50, F - 70, w - 100, 30)
    deck(s, F, 'stage')
    return s.finish()


# ------------------------------------------------------------------ layout

PAGES = {
    'backstage': dict(size=(864, 448), panels=[
        ((8, 8, 296, 208), p1_boiler),
        ((312, 40, 232, 176), p1_tunnel),
        ((552, 8, 304, 152), p1_dock),
        ((568, 168, 288, 208), p1_lift),
        ((320, 232, 240, 208), p1_dressing),
        ((8, 232, 304, 208), p1_corridor),
    ], route=['right', 'right', 'down', 'left', 'left']),
    'show': dict(size=(864, 448), panels=[
        ((8, 24, 232, 192), p2_wings),
        ((248, 8, 304, 208), p2_stage),
        ((560, 8, 296, 160), p2_grid),
        ((552, 176, 304, 208), p2_dancefloor),
        ((296, 232, 248, 208), p2_bar),
        ((8, 232, 280, 208), p2_foh),
    ], route=['right', 'right', 'down', 'left', 'left']),
}

PAPER = md('#f4f0e0')
PAPER_DOT = md('#d8d0b8')


def route_arrow(img, x, y, direction):
    """Yellow comic route arrow with an ink outline, drawn over the gutter between two panels."""
    h, w = img.shape[:2]
    pts = [(-11, -5), (1, -5), (1, -11), (13, 0), (1, 11), (1, 5), (-11, 5)]
    rot = {'right': (1, 0), 'left': (-1, 0), 'down': (0, 1)}[direction]
    P = [(x + px * rot[0] - py * rot[1], y + px * rot[1] + py * rot[0]) for px, py in pts]
    m = poly(h, w, P)
    p = np.pad(m, 2)
    out = np.zeros_like(m)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            out |= p[2 + dy:2 + dy + h, 2 + dx:2 + dx + w]
    img[out] = md('#000000')
    img[m] = md('#fcd828')
    hi = m & ~np.roll(m, 2, 0)
    img[hi] = md('#ffffff')


def render_page(name):
    """Returns (page RGB image, panel list [(x, y, w, h, floor, platforms)])."""
    spec = PAGES[name]
    theme(name)
    W, H = spec['size']
    img = np.zeros((H, W, 3), np.float32)
    img[:] = PAPER
    yy, xx = np.mgrid[0:H, 0:W]
    img[(xx % 4 == 0) & (yy % 4 == 0)] = PAPER_DOT
    panels = []
    for (x, y, w, h), fn in spec['panels']:
        sc = fn(w, h)
        img[y - 3:y + h + 3, x - 3:x + w + 3] = 0
        img[y:y + h, x:x + w] = sc.rgb
        panels.append((x, y, w, h, sc.floor, list(sc.platforms)))
    rects = [p[0] for p in spec['panels']]
    for i, d in enumerate(spec['route']):
        (x0, y0, w0, h0), (x1, y1, w1, h1) = rects[i], rects[i + 1]
        if d == 'right':
            route_arrow(img, (x0 + w0 + x1) // 2, max(y0, y1) + min(y0 + h0, y1 + h1) // 2 - max(y0, y1) // 2 + 20, 'right')
        elif d == 'left':
            route_arrow(img, (x1 + w1 + x0) // 2, max(y0, y1) + 70, 'left')
        else:
            route_arrow(img, x0 + w0 // 2, (y0 + h0 + y1) // 2, 'down')
    return img, panels
