"""Panel backgrounds, built from lit pieces: pipes, walls, cases, cables, wet floor reflections."""
import math
import numpy as np
from art import (Canvas, tube, ellipsoid, poly, inflate, ramp, rect_mask, normals_from_height, noise, toon, lambert,
                 specular, bayer, grid, smooth, md, LIGHT)

PW, PH = 304, 208           # panel interior
FLOOR = 176                 # feet line inside the panel
INK = np.array(md('#000000'), np.float32)

R = dict(
    wall=ramp('#0c1a1e', '#16302f', '#24484a', '#36605e', '#4c7c74'),
    red=ramp('#300810', '#6c1424', '#a82c3c', '#e06470', '#ffb4b4'),
    steel=ramp('#141c2c', '#2c4058', '#5c7c9c', '#a0bcd8', '#f0f8ff'),
    case=ramp('#08080c', '#1c1c24', '#34343c'),
    yellow=ramp('#5c4000', '#c09000', '#fcd828'),
    floor=ramp('#04080c', '#0c1418', '#142424'),
    warm=ramp('#783c08', '#e09030', '#fcdc90'),
)


def cast_shadow(c, mask, dx=-4, dy=5, k=0.55):
    sh = np.zeros_like(mask)
    h, w = mask.shape
    ys, xs = slice(max(0, dy), h), slice(max(0, dx), w)
    yd, xd = slice(0, h - max(0, dy)), slice(0, w - max(0, dx))
    if dx < 0:
        xs, xd = slice(0, w + dx), slice(-dx, w)
    sh[ys, xs] = mask[yd, xd]
    sh &= ~mask
    c.rgb[sh] = snap_ramps(c.rgb[sh] * k)


def ink_ring(c, mask):
    p = np.pad(mask, 1)
    ring = ~mask & (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])
    c.rgb[ring] = INK


def shade_into(c, mask, normal, rmp, ambient=0.25, spec=0.0, line=None, extra=None, lightmap=None, shadow=True):
    if shadow and lightmap is not None:
        cast_shadow(c, mask)
    v = lambert(normal, LIGHT, ambient)
    if extra is not None:
        v = v + extra
    if lightmap is not None:
        v = v * lightmap
    col = toon(v, rmp, 0.35)
    if spec:
        s = specular(normal, 24) * spec
        col = np.where((s > 0.55)[..., None], rmp[-1], col)
    pid = c.put(mask, col, line=line)
    if line is not None and lightmap is not None:
        ink_ring(c, mask)
    return pid


class Scene:
    def __init__(self, seed=1, w=PW, h=PH):
        self.w, self.h = w, h
        self.c = Canvas(w, h, bg=R['wall'][0])
        self.seed = seed
        yy, xx = grid(h, w)
        self.yy, self.xx = yy, xx
        self.light = np.ones((h, w), np.float32)
        self.platforms = []

    def lamp(self, x, y, radius, power=0.5):
        d = np.hypot(self.xx - x, (self.yy - y) * 1.2)
        self.light += power * np.clip(1 - d / radius, 0, 1) ** 1.5

    def vignette(self, k=0.35):
        d = np.hypot((self.xx - self.w / 2) / self.w, (self.yy - self.h * 0.45) / self.h)
        self.light *= 1 - k * np.clip(d * 1.6, 0, 1) ** 2

    # -- walls
    def block_wall(self, y0, y1, bw=24, bh=12, rmp=None):
        h, w = self.h, self.w
        rmp = rmp if rmp is not None else R['wall']
        yy, xx = self.yy, self.xx
        row = np.floor((yy - y0) / bh)
        off = (row % 2) * (bw / 2)
        u = (xx + off) % bw
        v = (yy - y0) % bh
        edge = np.minimum(np.minimum(u, bw - u), np.minimum(v, bh - v))
        hgt = np.clip(edge / 2.0, 0, 1) * 2.2
        n = noise(h, w, 10, self.seed) * 1.8 + noise(h, w, 3, self.seed + 1) * 0.8
        hgt = hgt + n * 0.6
        nrm = normals_from_height(hgt, 1.2)
        m = (yy >= y0) & (yy < y1)
        grime = noise(h, w, 24, self.seed + 5)
        stain = np.clip((grime - 0.55) * 3, 0, 1) * np.clip((yy - y0) / (y1 - y0), 0, 1)
        v = lambert(nrm, LIGHT, 0.35) * 0.95 - stain * 0.35
        # water streaks running down
        streak = (noise(1, w, 6, self.seed + 9)[0] > 0.68)[None, :] & (noise(h, w, 30, self.seed + 3) > 0.45)
        v = v - streak * 0.18
        v = v * self.light
        col = toon(v, rmp, 0.35)
        mortar = (np.minimum(u, v * 0 + bw) < 1) | (((yy - y0) % bh) < 1)
        col = np.where((mortar & m)[..., None], rmp[0], col)
        self.c.put(m, col)

    # -- pipes
    def pipe(self, pts, r, rmp, flanges=(), spec=0.8):
        m, n, t = tube(self.h, self.w, pts, [r] * len(pts))
        shade_into(self.c, m, n, rmp, 0.22, spec, line=rmp[0], lightmap=self.light)
        for (fx, fy, vertical) in flanges:
            fr = r + 2.2
            if vertical:
                ps = [(fx, fy - 2), (fx, fy + 2)]
            else:
                ps = [(fx - 2, fy), (fx + 2, fy)]
            # flange ring = short fat tube perpendicular to the pipe direction
            if vertical:
                mm, nn = ellipsoid(self.h, self.w, fx, fy, fr, 2.6)
            else:
                mm, nn = ellipsoid(self.h, self.w, fx, fy, 2.6, fr)
            nn = nn.copy()
            if vertical:
                nn[..., 1] *= 0.3
            else:
                nn[..., 0] *= 0.3
            nn /= np.linalg.norm(nn, axis=-1, keepdims=True)
            shade_into(self.c, mm, nn, rmp, 0.22, 1.0, line=INK, lightmap=self.light)
            # bolts
            for k in (-1, 1):
                bx, by = (fx + k * (fr - 1), fy) if vertical else (fx, fy + k * (fr - 1))
                if 0 <= int(by) < self.h and 0 <= int(bx) < self.w:
                    self.c.rgb[int(by), int(bx)] = rmp[-1]
        return m

    def elbow(self, cx, cy, rad, a0, a1, r, rmp):
        pts = [(cx + rad * math.cos(a), cy + rad * math.sin(a)) for a in np.linspace(a0, a1, 10)]
        return self.pipe(pts, r, rmp)

    def bracket(self, x, y0, y1, w=4):
        m = rect_mask(self.h, self.w, x - w // 2, y0, w, y1 - y0)
        _, n = inflate(m, 1.5, 'bevel')
        shade_into(self.c, m, n, R['steel'], 0.2, 0, line=INK, lightmap=self.light)

    # -- props
    def road_case(self, x, y, w, h, label=None, platform=True):
        if platform:
            self.platforms.append((x, y, w))
        m = rect_mask(self.h, self.w, x, y, w, h)
        _, n = inflate(m, 2.5, 'bevel')
        shade_into(self.c, m, n, R['case'], 0.35, 0, line=INK, lightmap=self.light)
        # aluminium edges and ball corners
        for ex in (x, x + w - 3):
            mm = rect_mask(self.h, self.w, ex, y, 3, h)
            _, nn = inflate(mm, 1.5, 'bevel')
            shade_into(self.c, mm, nn, R['steel'], 0.3, 1.0, lightmap=self.light)
        for ey in (y, y + h - 3):
            mm = rect_mask(self.h, self.w, x, ey, w, 3)
            _, nn = inflate(mm, 1.5, 'bevel')
            shade_into(self.c, mm, nn, R['steel'], 0.3, 1.0, lightmap=self.light)
        for cx, cy in ((x + 2, y + 2), (x + w - 3, y + 2), (x + 2, y + h - 3), (x + w - 3, y + h - 3)):
            mm, nn = ellipsoid(self.h, self.w, cx, cy, 3, 3)
            shade_into(self.c, mm, nn, R['steel'], 0.3, 1.0, line=INK, lightmap=self.light)
        # handle / latch
        mm = rect_mask(self.h, self.w, x + w // 2 - 5, y + h // 2 - 2, 10, 4)
        _, nn = inflate(mm, 1.5, 'bevel')
        shade_into(self.c, mm, nn, R['steel'], 0.3, 1.0, line=INK, lightmap=self.light)
        if label:
            stencil(self.c, label, x + 6, y + 5, R['steel'][2])

    def cable_bundle(self, x0, x1, y, sag, colors, spacing=2.2):
        for i, rmp in enumerate(colors):
            pts = []
            for k in range(13):
                t = k / 12
                px = x0 + (x1 - x0) * t
                py = y + i * spacing + sag * (1 - (2 * t - 1) ** 2) * (1 + i * 0.15)
                pts.append((px, py))
            m, n, _ = tube(self.h, self.w, pts, [1.3] * len(pts))
            shade_into(self.c, m, n, rmp, 0.3, 1.0, line=INK, lightmap=self.light)

    def exit_sign(self, x, y):
        m = rect_mask(self.h, self.w, x, y, 30, 12)
        _, n = inflate(m, 1.5, 'bevel')
        g = ramp('#002010', '#108040', '#40e080')
        shade_into(self.c, m, n, g, 0.6, 0, line=INK)
        stencil(self.c, 'EXIT', x + 4, y + 3, md('#e0ffe0'))
        self.lamp(x + 15, y + 6, 40, 0.35)

    def door(self, x, y, w, h):
        m = rect_mask(self.h, self.w, x, y, w, h)
        _, n = inflate(m, 3, 'bevel')
        shade_into(self.c, m, n, R['steel'][:3], 0.25, 0, line=INK, lightmap=self.light)
        inner = rect_mask(self.h, self.w, x + 4, y + 4, w - 8, h - 4)
        _, n2 = inflate(inner, 2, 'bevel')
        shade_into(self.c, inner, -n2 * np.array([1, 1, -1]), R['steel'][:3], 0.2, 0, lightmap=self.light)
        bar = rect_mask(self.h, self.w, x + 4, y + h // 2, w - 8, 3)
        _, nb = inflate(bar, 1.5)
        shade_into(self.c, bar, nb, R['steel'], 0.3, 1.0, line=INK, lightmap=self.light)

    def hazard_stripe(self, x, y, w, h):
        m = rect_mask(self.h, self.w, x, y, w, h)
        stripes = ((self.xx + self.yy) // 6) % 2 == 0
        self.c.put(m & stripes, R['yellow'][2])
        self.c.put(m & ~stripes, INK)

    # -- floor
    def wet_floor(self, y0):
        """Dark wet concrete; puddles mirror the wall above with a ripple."""
        h, w = self.h, self.w
        src = self.c.rgb.copy()
        out = self.c.rgb
        nz = noise(h, w * 1, 14, self.seed + 21)
        # puddles are wide flat blobs (squash noise vertically)
        puddle = np.zeros((h, w), bool)
        for y in range(y0, h):
            d = y - y0
            yy = y0 + d * 3
            puddle[y] = nz[min(h - 1, (yy * 7) % h)] > 0.47
        for y in range(y0, h):
            d = y - y0
            sy = max(0, int(y0 - 2 - d * 1.7))
            ripple = int(round(math.sin(y * 1.3 + d * 0.4) * (0.5 + d * 0.12)))
            row = np.roll(src[sy], ripple, axis=0)
            refl = row * 0.62 + np.array([0, 6, 14])
            base = R['floor'][1] if d % 5 else R['floor'][0]
            chk = ((np.arange(w) + y) % 2 == 0)
            pud = puddle[y]
            use = pud | (chk & (bayer(1, w, 0, y)[0] < 0.30))
            out[y] = np.where(use[:, None], refl, base)
            # puddle rims glint
            edge = pud & ~np.roll(pud, 1)
            out[y][edge] = R['wall'][4]
        out[y0] = R['steel'][1]
        out[y0 + 1] = R['floor'][0]
        self.c.rgb = snap_ramps(out)

    def blood(self, x, y, size, drips=True, hand=False):
        rng = np.random.default_rng(int(x * 31 + y))
        red = ramp('#300008', '#680010', '#a01020')
        m = np.zeros((self.h, self.w), bool)
        for _ in range(int(size * 1.5)):
            r = rng.uniform(0.6, 2.2) * (size / 8 + 0.5)
            ox, oy = rng.normal(0, size * 0.6), rng.normal(0, size * 0.4)
            mm, _ = ellipsoid(self.h, self.w, x + ox, y + oy, r, r * 0.8)
            m |= mm
        if drips:
            for _ in range(int(size / 2) + 1):
                dx = x + rng.normal(0, size * 0.5)
                ln = rng.uniform(size * 0.8, size * 2.5)
                mm, _, _ = tube(self.h, self.w, [(dx, y), (dx, y + ln)], [0.9, 0.6])
                m |= mm
        if hand:
            for k in range(4):
                mm, _, _ = tube(self.h, self.w, [(x - 4 + k * 3, y), (x - 4 + k * 3 + 1, y + 16)], [1.0, 0.8])
                m |= mm
        col = np.where(((self.xx + self.yy) % 3 == 0)[..., None], red[0], red[1])
        col = np.where((noise(self.h, self.w, 3, int(x)) > 0.62)[..., None], red[2], col)
        self.c.put(m, col)

    def poster(self, x, y, w, h, title, sub):
        m = rect_mask(self.h, self.w, x, y, w, h)
        torn = noise(self.h, self.w, 3, x) > 0.3
        m &= torn | (rect_mask(self.h, self.w, x + 2, y + 2, w - 4, h - 4))
        cast_shadow(self.c, m, -2, 2)
        paper = ramp('#584838', '#a89070', '#d8c8a0')
        col = toon(0.55 + noise(self.h, self.w, 6, x) * 0.5 - (self.yy - y) / h * 0.3, paper, 0.4)
        self.c.put(m, col)
        band = rect_mask(self.h, self.w, x + 3, y + 3, w - 6, 13) & m
        self.c.put(band, md('#a01020'))
        stencil(self.c, title, x + 5, y + 7, md('#fce0a0'))
        stencil(self.c, sub, x + 5, y + 20, md('#202020'))
        ink_ring(self.c, m)

    def finish(self):
        self.c.platforms = self.platforms
        return self.c


def snap_ramps(rgb):
    return np.clip(np.round(rgb / 36.0), 0, 7) * 36


FONT3x5 = {
    'A': ['###', '#.#', '###', '#.#', '#.#'], 'B': ['##.', '#.#', '##.', '#.#', '##.'], 'C': ['###', '#..', '#..', '#..', '###'],
    'D': ['##.', '#.#', '#.#', '#.#', '##.'], 'E': ['###', '#..', '##.', '#..', '###'], 'F': ['###', '#..', '##.', '#..', '#..'],
    'G': ['###', '#..', '#.#', '#.#', '###'], 'H': ['#.#', '#.#', '###', '#.#', '#.#'], 'I': ['###', '.#.', '.#.', '.#.', '###'],
    'K': ['#.#', '#.#', '##.', '#.#', '#.#'], 'L': ['#..', '#..', '#..', '#..', '###'], 'M': ['#.#', '###', '###', '#.#', '#.#'],
    'N': ['##.', '#.#', '#.#', '#.#', '#.#'], 'O': ['###', '#.#', '#.#', '#.#', '###'], 'P': ['###', '#.#', '###', '#..', '#..'],
    'R': ['##.', '#.#', '##.', '#.#', '#.#'], 'S': ['###', '#..', '###', '..#', '###'], 'T': ['###', '.#.', '.#.', '.#.', '.#.'],
    'U': ['#.#', '#.#', '#.#', '#.#', '###'], 'V': ['#.#', '#.#', '#.#', '#.#', '.#.'], 'W': ['#.#', '#.#', '###', '###', '#.#'],
    'X': ['#.#', '#.#', '.#.', '#.#', '#.#'], 'Y': ['#.#', '#.#', '.#.', '.#.', '.#.'], ' ': ['...'] * 5,
    '0': ['###', '#.#', '#.#', '#.#', '###'], '1': ['.#.', '##.', '.#.', '.#.', '###'], '2': ['###', '..#', '###', '#..', '###'],
    '3': ['###', '..#', '.##', '..#', '###'], '4': ['#.#', '#.#', '###', '..#', '..#'], '5': ['###', '#..', '###', '..#', '###'],
    '6': ['###', '#..', '###', '#.#', '###'], '7': ['###', '..#', '.#.', '.#.', '.#.'], '8': ['###', '#.#', '###', '#.#', '###'],
    '9': ['###', '#.#', '###', '..#', '###'], '-': ['...', '...', '###', '...', '...'], '!': ['.#.', '.#.', '.#.', '...', '.#.'],
    'Р': ['###', '#.#', '###', '#..', '#..'], 'Щ': ['#.#.#'] * 4 + ['#####'],
}


def stencil(c, text, x, y, color):
    for ch in text:
        g = FONT3x5.get(ch, FONT3x5[' '])
        for dy, row in enumerate(g):
            for dx, p in enumerate(row):
                if p == '#' and 0 <= y + dy < c.h and 0 <= x + dx < c.w:
                    c.rgb[y + dy, x + dx] = color
        x += len(g[0]) + 1


# ------------------------------------------------------------------ the panels

def basement(seed=3):
    s = Scene(seed)
    s.lamp(150, 40, 160, 0.55)
    s.lamp(250, 120, 90, 0.25)
    s.vignette(0.45)
    s.block_wall(0, FLOOR)
    # Door and EXIT sign.
    s.door(196, 92, 44, FLOOR - 92)
    s.exit_sign(203, 74)
    s.hazard_stripe(190, FLOOR - 8, 56, 8)
    # Pipes: two red sprinkler mains and a steel water main along the ceiling, risers down the wall.
    s.pipe([(-10, 14), (PW + 10, 14)], 6.5, R['steel'], flanges=[(40, 14, False), (150, 14, False), (262, 14, False)])
    s.pipe([(-10, 34), (90, 34)], 4.5, R['red'], flanges=[(30, 34, False)])
    s.elbow(90, 46, 12, -math.pi / 2, 0, 4.5, R['red'])
    s.pipe([(102, 46), (102, 140)], 4.5, R['red'], flanges=[(102, 80, True), (102, 128, True)])
    s.elbow(114, 140, 12, math.pi, math.pi / 2, 4.5, R['red'])
    s.pipe([(114, 152), (180, 152)], 4.5, R['red'])
    s.pipe([(268, 22), (268, FLOOR + 2)], 5.5, R['steel'], flanges=[(268, 60, True), (268, 120, True)])
    s.pipe([(PW + 10, 40), (280, 40)], 3.5, R['red'])
    for bx in (60, 140, 230):
        s.bracket(bx, 0, 22)
    # Valve wheel on the red riser.
    m, n = ellipsoid(s.h, s.w, 102, 100, 9, 9)
    hole, _ = ellipsoid(s.h, s.w, 102, 100, 6.5, 6.5)
    ring = m & ~hole
    shade_into(s.c, ring, n, R['red'], 0.3, 1.0, line=INK, lightmap=s.light)
    for a in (0, math.pi / 2):
        mm, nn, _ = tube(s.h, s.w, [(102 - 7 * math.cos(a), 100 - 7 * math.sin(a)), (102 + 7 * math.cos(a), 100 + 7 * math.sin(a))], [1.2, 1.2])
        shade_into(s.c, mm, nn, R['red'], 0.3, 1.0, line=INK, lightmap=s.light)
    # Cable tray with hanging multicore and stage cables.
    tray = rect_mask(s.h, s.w, 0, 52, 70, 4)
    _, tn = inflate(tray, 1.5, 'bevel')
    shade_into(s.c, tray, tn, R['steel'], 0.3, 1.0, line=INK, lightmap=s.light)
    s.cable_bundle(-4, 74, 57, 14, [R['case'], R['red'], R['case'], R['yellow'], R['case']])
    s.cable_bundle(110, 196, 60, 22, [R['case'], R['steel'][:4], R['case']])
    # Road cases stacked on the left.
    s.road_case(8, FLOOR - 40, 62, 40, 'SSMT TOUR')
    s.road_case(14, FLOOR - 66, 48, 26, 'FOH 2')
    s.road_case(132, FLOOR - 22, 40, 22, 'XLR')
    s.poster(146, 86, 40, 50, 'TOUR', '2026')
    s.blood(226, 120, 6, hand=True)
    s.blood(150, 140, 4)
    s.blood(40, FLOOR - 70, 5)
    s.wet_floor(FLOOR)
    return s.finish()


# ------------------------------------------------------------------ more props

R.update(
    purple=ramp('#0c0618', '#1c1030', '#2c1c4c', '#48306c'),
    curtain=ramp('#200408', '#4c0c14', '#801824', '#c03440'),
    wood=ramp('#1c0c04', '#3c2010', '#6c4020', '#a06838'),
    magenta=ramp('#5c0840', '#c02880', '#ff7cc8'),
    cyan=ramp('#004c6c', '#20a0d0', '#a0f0ff'),
    green=ramp('#0c2410', '#1c5024', '#40a048'),
    skin_dead=ramp('#18200c', '#34442c', '#5c7448'),
)


def _scene_methods():
    def box(self, x, y, w, h, rmp, bevel=2.0, spec=0.0, shadow=True, line=True):
        m = rect_mask(self.h, self.w, int(x), int(y), int(w), int(h))
        _, n = inflate(m, bevel, 'bevel')
        shade_into(self.c, m, n, rmp, 0.3, spec, line=INK if line else None, lightmap=self.light if shadow else None)
        return m

    def flat(self, mask, color):
        self.c.put(mask, np.asarray(color, np.float32))

    def roller_door(self, x, y, w, h):
        m = rect_mask(self.h, self.w, x, y, w, h)
        hgt = np.sin((self.yy - y) / 6.0 * math.pi) * 1.5
        n = normals_from_height(hgt, 1.0)
        shade_into(self.c, m, n, R['steel'][:4], 0.25, 0, line=INK, lightmap=self.light)
        rows = m & (((self.yy - y) % 6) < 1)
        self.c.rgb[rows] = R['steel'][0]
        self.box(x - 4, y - 8, w + 8, 8, R['steel'], 2, 1.0)

    def pallet(self, x, y, w):
        for k in range(3):
            self.box(x, y + k * 4, w, 3, R['wood'], 1, 0, shadow=False)
        for bx in (x + 2, x + w // 2 - 3, x + w - 8):
            self.box(bx, y + 3, 6, 9, R['wood'], 1, 0, shadow=False)

    def locker(self, x, y, w, h):
        self.box(x, y, w, h, R['green'], 2)
        for vy in range(y + 6, y + 18, 3):
            self.c.rgb[vy, x + 4:x + w - 4] = R['green'][0]
        self.c.rgb[y + h // 2:y + h // 2 + 6, x + w - 6] = R['steel'][3]

    def mirror_bulbs(self, x, y, w, h):
        self.box(x - 6, y - 6, w + 12, h + 12, R['wood'], 2)
        m = rect_mask(self.h, self.w, x, y, w, h)
        g = (self.xx - x + (self.yy - y)) / (w + h)
        col = toon(0.35 + g * 0.5 + (np.abs(((self.xx - self.yy) % 40) - 20) < 3) * 0.3, R['steel'][1:], 0.4)
        self.c.put(m, col)
        for k in range(8):
            bx = x - 3 + k * (w + 6) / 7
            mm, nn = ellipsoid(self.h, self.w, bx, y - 3, 2.6, 2.6)
            shade_into(self.c, mm, nn, R['warm'], 0.7, 1.0, line=INK)
            self.lamp(bx, y - 3, 30, 0.18)

    def clothes_rack(self, x, y, w, colors):
        self.pipe([(x, y), (x + w, y)], 1.5, R['steel'])
        for xx in (x + 2, x + w - 2):
            self.pipe([(xx, y), (xx, FLOOR)], 1.2, R['steel'])
        k = 0
        for gx in range(int(x + 6), int(x + w - 6), 9):
            rmp = colors[k % len(colors)]
            k += 1
            pts = [(gx - 4, y + 3), (gx + 4, y + 3), (gx + 5, y + 40), (gx - 5, y + 40)]
            m = poly(self.h, self.w, pts)
            _, n = inflate(m, 3)
            shade_into(self.c, m, n, rmp, 0.3, 0, line=INK, lightmap=self.light)

    def curtain(self, x0, x1, y0, y1, rmp=None, period=14):
        rmp = rmp if rmp is not None else R['curtain']
        m = (self.xx >= x0) & (self.xx < x1) & (self.yy >= y0) & (self.yy < y1)
        hgt = np.sin((self.xx - x0) / period * 2 * math.pi + (self.yy - y0) * 0.02) * 3.5
        n = normals_from_height(hgt, 1.0)
        v = lambert(n, LIGHT, 0.2) * self.light
        col = toon(v, rmp, 0.4)
        self.c.put(m, col)

    def speaker(self, x, y, w, h, cones=2):
        self.box(x, y, w, h, R['case'], 2)
        grille = rect_mask(self.h, self.w, x + 3, y + 3, w - 6, h - 6)
        dots = grille & (((self.xx + self.yy) % 2) == 0)
        self.c.rgb[dots] = R['case'][0]
        for k in range(cones):
            cy = y + h * (k + 0.5) / cones
            r = min(w, h / cones) * 0.36
            mm, nn = ellipsoid(self.h, self.w, x + w / 2, cy, r, r)
            shade_into(self.c, mm, -nn * np.array([1, 1, -1]), R['case'], 0.35, 0, line=INK, lightmap=self.light)
            mm, nn = ellipsoid(self.h, self.w, x + w / 2, cy, r * 0.35, r * 0.35)
            shade_into(self.c, mm, nn, R['steel'][:3], 0.35, 1.0, lightmap=self.light)

    def truss_h(self, x0, x1, y, s=10):
        for yy in (y, y + s):
            self.pipe([(x0, yy), (x1, yy)], 1.3, R['steel'])
        x = x0
        k = 0
        while x < x1:
            a, b = (x, y), (x + s, y + s)
            if k % 2:
                a, b = (x, y + s), (x + s, y)
            m, n, _ = tube(self.h, self.w, [a, b], [0.9, 0.9])
            shade_into(self.c, m, n, R['steel'], 0.3, 0.6, lightmap=self.light, shadow=False)
            x += s
            k += 1

    def truss_v(self, x, y0, y1, s=10):
        for xx in (x, x + s):
            self.pipe([(xx, y0), (xx, y1)], 1.3, R['steel'])
        y = y0
        k = 0
        while y < y1:
            a, b = (x, y), (x + s, y + s)
            if k % 2:
                a, b = (x + s, y), (x, y + s)
            m, n, _ = tube(self.h, self.w, [a, b], [0.9, 0.9])
            shade_into(self.c, m, n, R['steel'], 0.3, 0.6, lightmap=self.light, shadow=False)
            y += s
            k += 1

    def par_can(self, x, y, color):
        m, n, _ = tube(self.h, self.w, [(x, y), (x + 3, y + 9)], [3.6, 4.2])
        shade_into(self.c, m, n, R['case'], 0.35, 1.0, line=INK, lightmap=self.light, shadow=False)
        mm, nn = ellipsoid(self.h, self.w, x + 3.3, y + 10, 3.6, 2.0)
        shade_into(self.c, mm, nn, color, 0.9, 1.0, line=INK)

    def beam(self, x, y, x2, y2, w0, w1, color, density=0.35):
        """Translucent light cone: dithered pixels of the beam colour over the scene."""
        t = np.clip(((self.xx - x) * (x2 - x) + (self.yy - y) * (y2 - y)) / ((x2 - x) ** 2 + (y2 - y) ** 2), 0, 1)
        cx, cy = x + (x2 - x) * t, y + (y2 - y) * t
        d = np.hypot(self.xx - cx, self.yy - cy)
        wdt = w0 + (w1 - w0) * t
        m = (d < wdt) & (t > 0) & (t < 1)
        fall = (1 - d / np.maximum(wdt, 1)) * (1 - t * 0.6)
        b = bayer(self.h, self.w)
        on = m & (fall * density * 2 > b)
        self.c.rgb[on] = snap_ramps(self.c.rgb[on] * 0.4 + np.asarray(color, np.float32) * 0.75)

    def stage_floor(self, y0):
        """Glossy black stage boards with soft reflections."""
        src = self.c.rgb.copy()
        out = self.c.rgb
        h, w = self.h, self.w
        for y in range(y0, h):
            d = y - y0
            sy = max(0, y0 - 2 - d * 2)
            row = src[sy] * 0.42
            board = R['purple'][0] if (d // 6) % 2 else R['case'][0]
            chk = (np.arange(w) + y) % 2 == 0
            b = bayer(1, w, 0, y)[0]
            use = chk & (row.mean(-1) / 255 * 2.6 > b)
            out[y] = np.where(use[:, None], row, board)
            out[y][((np.arange(w) + (d // 6) * 23) % 61) == 0] = R['purple'][1]
        out[y0] = R['steel'][2]
        out[y0 + 1] = R['case'][0]
        self.c.rgb = snap_ramps(out)

    def drum_kit(self, x, y):
        # bass drum, toms, snare, cymbals
        mm, nn = ellipsoid(self.h, self.w, x, y - 14, 14, 14)
        shade_into(self.c, mm, nn, R['red'], 0.35, 1.0, line=INK, lightmap=self.light)
        mm, nn = ellipsoid(self.h, self.w, x, y - 14, 10, 10)
        shade_into(self.c, mm, nn, R['steel'][1:4], 0.5, 0, lightmap=self.light, shadow=False)
        stencil(self.c, 'SSMT', x - 7, y - 16, R['case'][0])
        for tx, ty, r in ((x - 13, y - 32, 6), (x + 13, y - 32, 6), (x + 24, y - 18, 7)):
            mm, nn = ellipsoid(self.h, self.w, tx, ty, r, r * 0.6)
            shade_into(self.c, mm, nn, R['red'], 0.35, 1.0, line=INK, lightmap=self.light)
        for cx, cy in ((x - 26, y - 44), (x + 30, y - 40)):
            self.pipe([(cx, cy), (cx, y)], 0.8, R['steel'])
            mm, nn = ellipsoid(self.h, self.w, cx, cy, 11, 2.2)
            shade_into(self.c, mm, nn, R['yellow'], 0.4, 1.0, line=INK, lightmap=self.light)

    def mic_stand(self, x, y):
        self.pipe([(x, y), (x, y - 40)], 0.8, R['steel'])
        self.pipe([(x, y - 40), (x + 10, y - 46)], 0.8, R['steel'])
        mm, nn = ellipsoid(self.h, self.w, x + 11, y - 47, 2.2, 1.8)
        shade_into(self.c, mm, nn, R['case'], 0.4, 1.0, line=INK)
        for dx in (-6, 6):
            self.pipe([(x, y - 3), (x + dx, y)], 0.7, R['steel'])

    def wedge(self, x, y, w=30):
        pts = [(x, y), (x + w, y), (x + w, y - 8), (x + 6, y - 16)]
        m = poly(self.h, self.w, pts)
        _, n = inflate(m, 2, 'bevel')
        shade_into(self.c, m, n, R['case'], 0.3, 0, line=INK, lightmap=self.light)
        g = m & ((self.xx + self.yy) % 2 == 0) & (self.yy < y - 3) & (self.xx > x + 8)
        self.c.rgb[g] = R['case'][0]

    def crowd(self, y, n, seed, rmp, hands=True, scale=1.0, body=None):
        """Silhouetted (undead) audience: dark shoulders, lit heads, raised arms."""
        rng = np.random.default_rng(seed)
        body = body if body is not None else R['case']
        xs = np.sort(rng.uniform(-10, self.w + 10, n))
        for x in xs:
            s = rng.uniform(0.85, 1.15) * scale
            hy = y - rng.uniform(0, 8)
            pts = [(x - 12 * s, hy + 30 * s), (x - 10 * s, hy + 12 * s), (x - 4 * s, hy + 8 * s), (x + 4 * s, hy + 8 * s),
                   (x + 10 * s, hy + 12 * s), (x + 12 * s, hy + 30 * s)]
            m = poly(self.h, self.w, pts)
            _, nn = inflate(m, 3)
            shade_into(self.c, m, nn, body, 0.15, 0, line=INK, lightmap=self.light, shadow=False)
            if hands and rng.random() < 0.5:
                hx = x + rng.uniform(-12, 12)
                pts = [(x + rng.choice([-6, 6]) * s, hy + 12 * s), (hx, hy - 10 * s), (hx + rng.uniform(-4, 4), hy - 20 * s)]
                m, nrm, _ = tube(self.h, self.w, pts, [2.0 * s, 1.7 * s, 1.5 * s])
                shade_into(self.c, m, nrm, rmp, 0.25, 0, line=INK, lightmap=self.light, shadow=False)
            mm, nn = ellipsoid(self.h, self.w, x + rng.uniform(-1.5, 1.5), hy + 1, 5.2 * s, 6.2 * s)
            shade_into(self.c, mm, nn, rmp, 0.25, 0, line=INK, lightmap=self.light, shadow=False)
            # glowing eyes
            ex, ey = int(x), int(hy)
            if 0 <= ey < self.h and 1 <= ex < self.w - 2:
                self.c.rgb[ey, ex - 2] = R['yellow'][2]
                self.c.rgb[ey, ex + 2] = R['yellow'][2]

    def barricade(self, x0, x1, y, h=26):
        self.pipe([(x0, y - h), (x1, y - h)], 1.6, R['steel'])
        self.pipe([(x0, y - 4), (x1, y - 4)], 1.4, R['steel'])
        for x in range(int(x0) + 4, int(x1), 7):
            self.pipe([(x, y - h), (x, y - 4)], 0.8, R['steel'])
        for x in range(int(x0) + 10, int(x1), 48):
            pts = [(x - 10, y), (x, y - h), (x + 10, y)]
            m, n, _ = tube(self.h, self.w, pts, [1.4] * 3)
            shade_into(self.c, m, n, R['steel'], 0.3, 1.0, line=INK, lightmap=self.light)

    def desk(self, x, y, w, h):
        """Mixing console: angled surface with channel strips, faders, LEDs and two screens."""
        pts = [(x + 6, y), (x + w - 6, y), (x + w, y + h), (x, y + h)]
        m = poly(self.h, self.w, pts)
        _, n = inflate(m, 2.5, 'bevel')
        shade_into(self.c, m, n, R['case'], 0.45, 0, line=INK, lightmap=self.light)
        ch = 0
        for cx in range(int(x + 10), int(x + w - 10), 6):
            self.c.rgb[y + 4:y + h - 4, cx] = R['case'][0]
            fy = int(y + 10 + ((ch * 7) % 11))
            self.c.rgb[fy:fy + 3, cx - 1:cx + 2] = R['steel'][3]
            for k in range(3):
                col = (R['green'][2], R['yellow'][2], R['red'][3])[k]
                if (ch + k) % 3 != 2:
                    self.c.rgb[y + 3 + k * 2, cx + 2] = col
            ch += 1
        for sx in (x + w // 2 - 34, x + w // 2 + 6):
            self.box(sx, y - 20, 28, 18, R['case'], 1.5)
            scr = rect_mask(self.h, self.w, sx + 3, y - 17, 22, 12)
            self.c.put(scr, R['cyan'][0])
            for k in range(5):
                hh = 2 + (k * 5 + sx) % 9
                self.c.rgb[y - 6 - hh:y - 6, sx + 5 + k * 4:sx + 7 + k * 4] = R['cyan'][1 + (k % 2)]
        self.lamp(x + w / 2, y, 60, 0.25)

    for k, v in list(locals().items()):
        setattr(Scene, k, v)


_scene_methods()


def loading_dock(seed=21):
    s = Scene(seed)
    s.lamp(220, 30, 170, 0.6)
    s.vignette(0.5)
    s.block_wall(0, FLOOR, bw=32, bh=16)
    s.roller_door(150, 34, 140, FLOOR - 34)
    # Tour truck backed into the bay: trailer doors open, darkness inside.
    tr = rect_mask(s.h, s.w, 164, 60, 112, FLOOR - 60)
    s.c.put(tr, R['case'][0])
    s.box(160, 56, 120, 6, R['steel'], 1.5, 1.0)
    s.box(158, 56, 6, FLOOR - 56, R['steel'], 1.5, 1.0)
    s.box(276, 56, 6, FLOOR - 56, R['steel'], 1.5, 1.0)
    stencil(s.c, 'SSMT TOUR 2026', 186, 70, R['steel'][2])
    # Light spilling from inside the trailer.
    s.beam(220, 64, 210, FLOOR, 4, 50, md('#405870'), 0.3)
    s.pallet(14, FLOOR - 12, 50)
    s.road_case(18, FLOOR - 44, 44, 32, 'AMP RACK')
    s.road_case(80, FLOOR - 30, 54, 30, 'CABLE')
    s.speaker(90, FLOOR - 82, 36, 52, 2)
    s.platforms.append((90, FLOOR - 82, 36))
    s.hazard_stripe(150, FLOOR - 6, 140, 6)
    s.pipe([(-10, 12), (PW + 10, 12)], 5.5, R['steel'], flanges=[(70, 12, False), (240, 12, False)])
    s.cable_bundle(0, 140, 22, 18, [R['case'], R['yellow'], R['case']])
    s.blood(120, 110, 6)
    s.blood(290, 120, 5, hand=True)
    s.wet_floor(FLOOR)
    return s.finish()


def dressing_room(seed=31):
    s = Scene(seed)
    s.lamp(150, 70, 170, 0.55)
    s.vignette(0.55)
    # Wallpaper: vertical stripes in dark plum.
    m = (s.yy < FLOOR)
    stripes = ((s.xx // 6) % 2 == 0)
    v = (0.45 + 0.1 * stripes + noise(s.h, s.w, 20, seed) * 0.2) * s.light
    s.c.put(m, toon(v, R['purple'], 0.4))
    s.mirror_bulbs(108, 52, 92, 56)
    s.box(96, 112, 116, 8, R['wood'], 2)                 # make-up table
    s.platforms.append((96, 112, 116))
    for lx in (100, 206):
        s.box(lx, 120, 6, FLOOR - 120, R['wood'], 1.5)
    s.clothes_rack(220, 70, 70, [R['red'], R['purple'], R['magenta'], R['cyan']])
    s.locker(14, 64, 26, FLOOR - 64)
    s.locker(42, 64, 26, FLOOR - 64)
    s.poster(74, 40, 28, 36, 'SOLD', 'OUT')
    s.blood(160, 80, 6, hand=True)
    s.blood(60, 130, 5)
    # Wooden floor with a soft sheen.
    fl = (s.yy >= FLOOR)
    planks = ((s.xx + (s.yy // 5) * 17) % 40 < 1)
    s.c.put(fl, toon(0.45 + noise(s.h, s.w, 8, seed + 4) * 0.3, R['wood'], 0.4))
    s.c.rgb[fl & planks] = R['wood'][0]
    s.c.rgb[fl & (s.yy % 5 == 0)] = R['wood'][0]
    s.c.rgb[FLOOR] = R['wood'][3]
    return s.finish()


def corridor(seed=41):
    s = Scene(seed)
    s.lamp(160, 20, 200, 0.5)
    s.vignette(0.5)
    s.block_wall(0, FLOOR, bw=20, bh=10)
    # Lower wall paint band.
    band = (s.yy > FLOOR - 50) & (s.yy < FLOOR)
    s.c.put(band, toon((0.4 + noise(s.h, s.w, 12, seed) * 0.3) * s.light, R['red'][:3], 0.4))
    s.c.rgb[FLOOR - 50] = R['case'][0]
    s.door(30, 92, 44, FLOOR - 92)
    s.door(226, 92, 44, FLOOR - 92)
    stencil(s.c, 'СЦЕНА', 136, 50, R['steel'][3]) if False else stencil(s.c, 'STAGE', 140, 50, R['steel'][3])
    m, n, _ = tube(s.h, s.w, [(150, 66), (170, 66)], [3, 3])
    shade_into(s.c, m, n, R['steel'], 0.4, 1.0, line=INK)
    s.exit_sign(135, 24)
    s.pipe([(-10, 10), (PW + 10, 10)], 4.5, R['red'], flanges=[(100, 10, False), (210, 10, False)])
    s.road_case(110, FLOOR - 36, 48, 36, 'DRUMS')
    s.road_case(160, FLOOR - 24, 36, 24, 'MON')
    s.speaker(116, FLOOR - 80, 34, 44, 2)
    s.platforms.append((116, FLOOR - 80, 34))
    s.blood(250, 70, 7, hand=True)
    s.blood(90, 140, 5)
    s.wet_floor(FLOOR)
    return s.finish()


def wings(seed=51):
    s = Scene(seed)
    s.lamp(250, 60, 180, 0.7)
    s.vignette(0.55)
    s.c.rgb[:] = R['purple'][0]
    s.curtain(0, 120, 0, FLOOR, period=16)
    s.curtain(250, PW, 0, FLOOR, period=12)
    s.truss_v(126, 0, FLOOR, 10)
    s.speaker(150, FLOOR - 44, 60, 44, 2)
    s.speaker(156, FLOOR - 84, 48, 40, 2)
    s.speaker(162, FLOOR - 118, 36, 34, 1)
    s.platforms += [(150, FLOOR - 44, 60), (156, FLOOR - 84, 48)]
    s.par_can(220, 20, R['magenta'])
    s.beam(223, 30, 280, FLOOR, 3, 34, R['magenta'][2], 0.32)
    s.road_case(30, FLOOR - 30, 60, 30, 'BACKLINE')
    s.mic_stand(240, FLOOR)
    s.blood(70, 90, 6)
    s.stage_floor(FLOOR)
    return s.finish()


def stage(seed=61):
    s = Scene(seed)
    s.lamp(150, 90, 200, 0.8)
    s.vignette(0.6)
    s.c.rgb[:] = R['purple'][0]
    # Backdrop with the band logo.
    m = (s.yy > 20) & (s.yy < FLOOR - 20)
    v = (0.3 + noise(s.h, s.w, 30, seed) * 0.4) * s.light
    s.c.put(m, toon(v, R['purple'], 0.4))
    logo(s, 'DEAD LIVE', 40, 2, R['red'][2:], R['red'][:2], 2)
    s.truss_h(0, PW, 4, 12)
    for k, (px, col) in enumerate(((40, R['magenta']), (110, R['cyan']), (180, R['warm']), (250, R['magenta']))):
        s.par_can(px, 18, col)
        s.beam(px + 3, 28, px + 3 + (k - 1.5) * 30, FLOOR, 3, 30, col[-1], 0.3)
    s.drum_kit(150, FLOOR - 26)
    s.box(96, FLOOR - 26, 110, 26, R['case'], 2)            # drum riser
    s.platforms.append((96, FLOOR - 26, 110))
    s.speaker(10, FLOOR - 60, 34, 60, 2)
    s.speaker(260, FLOOR - 60, 34, 60, 2)
    s.platforms += [(10, FLOOR - 60, 34), (260, FLOOR - 60, 34)]
    s.wedge(60, FLOOR)
    s.wedge(214, FLOOR)
    s.mic_stand(150, FLOOR - 26)
    s.blood(150, 120, 5)
    s.stage_floor(FLOOR)
    return s.finish()


def dancefloor(seed=71):
    s = Scene(seed)
    s.lamp(150, 20, 220, 0.6)
    s.vignette(0.55)
    s.c.rgb[:] = R['purple'][0]
    s.truss_h(0, PW, 2, 10)
    for k, px in enumerate((30, 100, 170, 240)):
        col = (R['cyan'], R['magenta'])[k % 2]
        s.par_can(px, 14, col)
        s.beam(px + 3, 24, px + 3 + (k - 1.5) * 26, FLOOR, 3, 34, col[-1], 0.26)
    s.crowd(FLOOR - 78, 24, seed, R['purple'][:3], hands=True, scale=1.0, body=R['purple'][:2])
    s.crowd(FLOOR - 52, 16, seed + 1, R['purple'][1:], hands=True, scale=1.3, body=R['case'])
    s.barricade(0, PW, FLOOR - 4)
    s.road_case(120, FLOOR - 30, 60, 30, 'FX')
    s.blood(60, FLOOR - 20, 6)
    # Concrete floor with confetti.
    fl = s.yy >= FLOOR
    s.c.put(fl, toon(0.35 + noise(s.h, s.w, 6, seed) * 0.3, R['wall'][:3], 0.4))
    rng = np.random.default_rng(seed)
    for _ in range(90):
        x, y = rng.integers(0, PW), rng.integers(FLOOR + 2, PH)
        s.c.rgb[y, x:x + 2] = (R['magenta'][2], R['cyan'][2], R['yellow'][2])[rng.integers(0, 3)]
    s.c.rgb[FLOOR] = R['steel'][1]
    return s.finish()


def foh(seed=81):
    s = Scene(seed)
    s.lamp(150, 100, 190, 0.7)
    s.vignette(0.6)
    s.c.rgb[:] = R['purple'][0]
    # Distant stage glow and crowd silhouettes behind the FOH riser.
    glow = (s.yy < 70)
    s.c.put(glow, toon((0.2 + (70 - s.yy) / 70 * 0.5) * s.light, R['purple'], 0.5))
    for k, px in enumerate((40, 120, 200, 270)):
        s.beam(px, 0, px + (k - 1.5) * 20, 80, 2, 18, (R['magenta'], R['cyan'])[k % 2][2], 0.22)
    s.crowd(64, 30, seed, R['purple'][1:], hands=True, scale=0.7, body=R['purple'][:2])
    # FOH tent frame and the console.
    s.truss_v(4, 0, FLOOR, 8)
    s.truss_v(288, 0, FLOOR, 8)
    s.truss_h(4, 296, 100, 8)
    s.box(40, FLOOR - 40, 224, 40, R['case'], 2)            # riser
    s.platforms.append((40, FLOOR - 40, 224))
    s.desk(66, FLOOR - 70, 172, 30)
    s.road_case(14, FLOOR - 26, 26, 26, 'FX', platform=False)
    s.blood(250, FLOOR - 50, 6)
    s.stage_floor(FLOOR)
    return s.finish()


# ------------------------------------------------------------------ cover and ending (full 320x224 cells)

def _font():
    import os
    import re
    txt = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pixelfont.txt'), encoding='utf-8').read()
    g = {}
    for m in re.finditer(r'"(\\?.)": \[([^\]]*)\]', txt):
        rows = re.findall(r'"([.#]+)"', m.group(2))
        if len(rows) == 7:
            g[m.group(1).replace('\\', '')] = rows
    alias = {'А': 'A', 'В': 'B', 'Е': 'E', 'К': 'K', 'М': 'M', 'Н': 'H', 'О': 'O', 'Р': 'P', 'С': 'C', 'Т': 'T', 'Х': 'X', 'Ё': 'Ë'}
    for k, v in alias.items():
        g[k] = g[v]
    return g


def text_mask(text, scale, w, h, x, y, gap=2):
    g = _font()
    m = np.zeros((h, w), bool)
    cx = x
    for ch in text:
        rows = g.get(ch, ['...'] * 7) if ch != ' ' else ['...'] * 7
        for ry, row in enumerate(rows):
            for rx, p in enumerate(row):
                if p == '#':
                    m[max(0, y + ry * scale):max(0, y + (ry + 1) * scale), max(0, cx + rx * scale):max(0, cx + (rx + 1) * scale)] = True
        cx += (len(rows[0]) + gap) * scale
    return m, cx - x - gap * scale


def logo(s, text, cy, scale, top, bottom, depth=5):
    """Chunky 3D comic logo: ink extrusion, gradient face, white highlight, thick outline."""
    _, tw = text_mask(text, scale, s.w, s.h, 0, 0)
    x = (s.w - tw) // 2
    face, _ = text_mask(text, scale, s.w, s.h, x, cy)
    ext = np.zeros_like(face)
    for d in range(1, depth + 1):
        ext |= np.roll(np.roll(face, d, 0), d, 1)
    p = np.pad(face | ext, 2)
    out = np.zeros_like(face)
    for dy in range(-2, 3):
        for dx in range(-2, 3):
            out |= p[2 + dy:2 + dy + s.h, 2 + dx:2 + dx + s.w]
    s.c.put(out, INK)
    s.c.put(ext & ~face, R['red'][1])
    t = np.clip((s.yy - cy) / (7 * scale), 0, 1)
    col = toon(1 - t * 0.9, np.array([bottom[0], bottom[1], top[0], top[1], top[2]], np.float32), 0.5)
    s.c.put(face, col)
    hl = face & ~np.roll(face, 1, 0)
    s.c.rgb[hl] = md('#ffffff')


def cover(seed=91):
    import chars
    s = Scene(seed, 320, 224)
    s.c.rgb[:] = R['purple'][0]
    s.lamp(160, 150, 200, 0.9)
    s.vignette(0.6)
    # Sunburst behind the hero.
    ang = np.arctan2(s.yy - 150, s.xx - 160)
    rays = (np.floor((ang + math.pi) / (math.pi / 12)) % 2 == 0)
    v = (0.25 + 0.35 * rays) * s.light
    s.c.put(s.yy < 224, toon(v, R['purple'], 0.5))
    for k, (px, col) in enumerate(((20, R['magenta']), (300, R['cyan']))):
        s.beam(px, 0, 160 + (k * 2 - 1) * 30, 200, 3, 40, col[2], 0.35)
    logo(s, 'САУНДЧЕК', 12, 4, R['yellow'], R['warm'], 5)
    logo(s, 'МЁРТВЫХ', 50, 4, R['red'][2:], R['red'][:2], 5)
    stencil(s.c, 'SSMT', 8, 210, R['steel'][2])
    stencil(s.c, '16-BIT', 278, 210, R['steel'][2])
    # Zombie hands reaching up from the bottom edge.
    rng = np.random.default_rng(seed)
    for x in (18, 52, 88, 232, 268, 302):
        hx = x + rng.uniform(-6, 6)
        m, n, _ = tube(s.h, s.w, [(x, 230), (hx, 196), (hx + rng.uniform(-6, 6), 176)], [5, 4.4, 4])
        shade_into(s.c, m, n, R['skin_dead'], 0.3, 0, line=INK, lightmap=s.light)
        for f in range(4):
            fx = hx - 5 + f * 3.4
            mm, nn, _ = tube(s.h, s.w, [(fx, 178), (fx + (f - 1.5) * 1.5, 166 - abs(f - 1.5) * 2)], [1.4, 1.1])
            shade_into(s.c, mm, nn, R['skin_dead'], 0.3, 0, line=INK, lightmap=s.light)
    s.platforms = []

    def paste(img, x0, y0):
        a = np.asarray(img.image())
        hh = min(a.shape[0], s.h - y0)
        ww = min(a.shape[1], s.w - x0)
        a = a[:hh, :ww]
        m = a[..., 3] > 0
        s.c.rgb[y0:y0 + hh, x0:x0 + ww][m] = a[..., :3][m]

    zl = chars.Puppet(80, 96, chars.ZOMBIE_PAL, chars.LOADER).draw(chars.zombie_pose('strike', chars.LOADER))
    zf = chars.Puppet(80, 96, chars.ZOMBIE_PAL, chars.FAN).draw(chars.zombie_pose('shamble1', chars.FAN))
    zf.rgb = zf.rgb[:, ::-1].copy()
    zf.alpha = zf.alpha[:, ::-1].copy()
    paste(zf, 196, 118)
    zl.rgb = zl.rgb[:, ::-1].copy()
    zl.alpha = zl.alpha[:, ::-1].copy()
    paste(zl, 214, 120)
    import hero
    paste(hero.Hero().draw('jab1'), 84, 122)
    return s.finish()


def ending(seed=93):
    import chars
    s = Scene(seed, 320, 224)
    s.c.rgb[:] = R['purple'][0]
    s.lamp(160, 120, 220, 0.9)
    s.vignette(0.5)
    ang = np.arctan2(s.yy - 120, s.xx - 160)
    rays = (np.floor((ang + math.pi) / (math.pi / 16)) % 2 == 0)
    s.c.put(s.yy < 224, toon((0.3 + 0.3 * rays) * s.light, R['purple'], 0.5))
    logo(s, 'КОНЕЦ', 14, 5, R['yellow'], R['warm'], 6)
    s.desk(80, 170, 160, 30)
    import hero
    hero_img = hero.Hero().draw('cheer')
    a = np.asarray(hero_img.image())
    m = a[..., 3] > 0
    y0, x0 = 170 - 92, 112
    sub = s.c.rgb[y0:y0 + 96, x0:x0 + 96]
    sub[m] = a[..., :3][m]
    return s.finish()
