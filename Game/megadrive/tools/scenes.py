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
