"""The hero, drawn as a comic-book fighter: athletic proportions, big hands and feet, open white work
shirt over a black tank, dark cargo pants, fingerless gloves, sneakers, blond hair in a ponytail, headset.
Bold ink outlines and 3-4 tone cel shading, the way 16-bit comic games drew their heroes."""
import math
import numpy as np
from art import Canvas, tube, ellipsoid, poly, inflate, ramp, rect_mask, lambert, toon, specular, LIGHT
from chars import fk

INK = np.array([0, 0, 0], np.float32)

PAL = {
    'skin': ramp('#6c2c18', '#b4603c', '#f0a070', '#ffdcb4'),
    'shirt': ramp('#485878', '#98a8c4', '#dce4f0', '#ffffff'),
    'dark': ramp('#0c0c14', '#30304c', '#6c6c94'),
    'hair': ramp('#844c0c', '#dc9c24', '#fce070'),
}

LOOK = dict(torso=24, thighlen=19, shinlen=18, ualen=12, falen=12, shoulders=12.5, headlen=8.0, headfwd=2.0)

# Keyframes (degrees from straight down, positive = towards the facing side).
POSES = {
    'guard': dict(lean=8, head=-4, fl=(24, 2), bl=(-18, -8), fa=(34, 158), ba=(14, 150)),
    'step1': dict(lean=10, fl=(32, 6), bl=(-26, -12), fa=(16, 150), ba=(36, 160)),
    'step2': dict(lean=10, fl=(12, -24), bl=(-6, 4), fa=(26, 158), ba=(26, 158), lift=1),
    'step3': dict(lean=10, fl=(-24, -14), bl=(30, 6), fa=(36, 160), ba=(16, 150)),
    'step4': dict(lean=10, fl=(-4, 6), bl=(12, -24), fa=(26, 158), ba=(26, 158), lift=1),
    'jab0': dict(lean=4, head=-4, fl=(24, 4), bl=(-20, -8), fa=(-16, 168), ba=(14, 150), dx=-2),
    'jab1': dict(lean=16, head=-6, fl=(28, 6), bl=(-24, -10), fa=(88, 90), ba=(4, 156), dx=4),
    'cross1': dict(lean=20, head=-8, fl=(30, 6), bl=(-28, -12), fa=(24, 164), ba=(86, 88), dx=6, bfront=True),
    'kick0': dict(lean=-6, fl=(76, -36), bl=(-4, -4), fa=(36, 158), ba=(-24, 150)),
    'kick1': dict(lean=-18, head=4, fl=(94, 92), bl=(-8, -2), fa=(48, 168), ba=(-44, 100), ftoe=1.4),
    'jump': dict(lean=6, fl=(66, -10), bl=(22, -32), fa=(150, 172), ba=(-30, 120), hipy=46),
    'fall': dict(lean=10, fl=(34, 10), bl=(-10, -22), fa=(110, 140), ba=(-60, 60), hipy=46),
    'jkick': dict(lean=-12, fl=(100, 96), bl=(44, -40), fa=(44, 172), ba=(-60, 60), hipy=44, ftoe=1.4),
    'hurt': dict(lean=-20, head=-16, fl=(18, 6), bl=(-14, -6), fa=(140, 172), ba=(-40, 130), dx=-3, ffist=False, bfist=False),
    'cheer': dict(lean=0, head=-10, fl=(16, 4), bl=(-16, -4), fa=(172, 186), ba=(-30, 30)),
}


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


class Hero:
    def __init__(self, w=96, h=96):
        self.w, self.h = w, h
        yy, xx = np.mgrid[0:h, 0:w]
        self.yy, self.xx = yy + 0.5, xx + 0.5

    # -- shading helpers
    def part(self, c, m, n, rmp, dark=0.0, spec=0.0, rim=0.25, line=True):
        v = lambert(n, LIGHT, 0.22) - dark
        # comic rim light on the back edge
        v = v + rim * (np.clip(1 - n[..., 2], 0, 1) ** 2) * (n[..., 0] < -0.3)
        col = toon(v, rmp, 0.18)
        if spec:
            s = specular(n, 20) * spec
            col = np.where((s > 0.5)[..., None], rmp[-1], col)
        return c.put(m, col, line=INK if line else None)

    def muscle(self, c, a, b, r0, rmax, r1, rmp, dark=0.0, at=0.35):
        m, n, _ = tube(self.h, self.w, [a, lerp(a, b, at), b], [r0, rmax, r1])
        self.part(c, m, n, rmp, dark)
        return m

    def blob(self, c, cx, cy, rx, ry, rmp, dark=0.0, spec=0.0):
        m, n = ellipsoid(self.h, self.w, cx, cy, rx, ry)
        self.part(c, m, n, rmp, dark, spec)
        return m

    def shape(self, c, pts, rmp, dark=0.0, bevel=3.0, spec=0.0):
        m = poly(self.h, self.w, pts)
        _, n = inflate(m, bevel)
        self.part(c, m, n, rmp, dark, spec)
        return m

    # -- body parts
    def arm(self, c, s, e, h, dark, fist):
        """Bare bodybuilder arm: round deltoid, huge biceps/triceps, thick forearm, big gloved fist."""
        P = PAL
        self.blob(c, s[0], s[1] + 1.5, 6.4, 6.0, P['skin'], dark, spec=0.5)              # deltoid
        self.muscle(c, s, e, 5.6, 6.6, 4.4, P['skin'], dark, at=0.4)                       # biceps / triceps
        # vein / muscle split line on the upper arm
        m, n, _ = tube(self.h, self.w, [lerp(s, e, 0.25), lerp(s, e, 0.7)], [0.5, 0.5])
        c.rgb[m & (c.part == c.parts)] = P['skin'][1]
        self.muscle(c, e, h, 4.6, 5.4, 3.6, P['skin'], dark, at=0.3)                       # forearm
        self.muscle(c, lerp(e, h, 0.82), h, 3.8, 3.9, 3.8, P['dark'], dark)                # wrist wrap
        d = (h[0] - e[0], h[1] - e[1])
        ln = math.hypot(*d) or 1
        ux, uy = d[0] / ln, d[1] / ln
        fx, fy = h[0] + ux * 2.6, h[1] + uy * 2.6
        r = 5.4 if fist else 4.4
        self.blob(c, fx, fy, r, r * 0.86, P['dark'] if fist else P['skin'], dark, spec=0.8)
        if fist:
            for k in (-1, 0, 1):
                kx, ky = fx + ux * 3.4 - uy * k * 2.0, fy + uy * 3.4 + ux * k * 2.0
                if 0 <= int(ky) < self.h and 0 <= int(kx) < self.w:
                    c.rgb[int(ky), int(kx)] = P['skin'][2]

    def leg(self, c, hip, knee, ank, toe, dark, f):
        P = PAL
        self.muscle(c, hip, knee, 6.8, 7.4, 5.2, P['dark'], dark)                # thigh
        self.muscle(c, knee, ank, 5.4, 6.2, 4.0, P['dark'], dark, at=0.3)        # shin with calf
        # cargo pocket and knee pad
        k = lerp(hip, knee, 0.55)
        m = rect_mask(self.h, self.w, int(k[0] - 3), int(k[1] - 2), 6, 5)
        m &= c.part == c.parts - 1
        c.rgb[m] = P['dark'][1]
        self.blob(c, knee[0] + f * 1.6, knee[1], 2.6, 2.6, P['dark'], dark - 0.2, spec=0.6)
        # sneaker: chunky upper, white sole, toe cap
        ax, ay = ank
        tx = ax + f * 8.5 * toe
        pts = [(ax - f * 4, ay - 4), (ax + f * 2, ay - 4.5), (tx, ay + 1.5), (tx + f * 0.5, ay + 4.5), (ax - f * 4.5, ay + 4.5)]
        self.shape(c, pts, P['dark'], dark - 0.1, bevel=2.0, spec=0.7)
        sole = poly(self.h, self.w, [(ax - f * 4.8, ay + 3), (tx + f * 1, ay + 3), (tx + f * 1, ay + 5.4), (ax - f * 4.8, ay + 5.4)])
        c.put(sole, PAL['shirt'][2], line=INK)
        lace = poly(self.h, self.w, [(ax, ay - 3), (ax + f * 4, ay - 1.5), (ax + f * 3.4, ay - 0.5), (ax - f * 0.6, ay - 2)])
        c.rgb[lace] = PAL['shirt'][1]

    def torso(self, c, p, f):
        """V-shaped bodybuilder torso: traps, bulging pecs, six-pack, narrow waist; open sleeveless white vest."""
        P = PAL
        bs, fs, bh, fh, nk = p['bsho'], p['fsho'], p['bhip'], p['fhip'], p['neck']
        ch = p['chest']
        pts = [(bs[0] - f * 4, bs[1] - 4), (nk[0], nk[1] - 1), (fs[0] + f * 3, fs[1] - 4.5), (fs[0] + f * 8, fs[1] + 4),   # traps, shoulders
               (fs[0] + f * 8.5, fs[1] + 10),                                                                        # pec front
               (lerp(fs, fh, 0.62)[0] + f * 4, lerp(fs, fh, 0.62)[1]), (fh[0] + f * 2, fh[1] - 1),                  # waist
               (bh[0] - f * 2, bh[1] - 1), (lerp(bs, bh, 0.55)[0] - f * 4, lerp(bs, bh, 0.55)[1]), (bs[0] - f * 8, bs[1] + 5)]
        m = poly(self.h, self.w, pts)
        # muscle relief as a height field: pecs, abs grid, lats
        hgt = np.zeros((self.h, self.w), np.float32)
        px, py = fs[0] + f * 3, fs[1] + 6
        for cx, w in ((px, 6.5), (px - f * 9, 5.5)):
            hgt += 3.2 * np.exp(-(((self.xx - cx) / w) ** 2 + ((self.yy - py) / 4.5) ** 2))
        ax0 = lerp(fs, fh, 0.45)
        for row in range(3):
            for col in (0, 1):
                cx = ax0[0] + f * (1.5 - col * 4.5)
                cy = ax0[1] - 2 + row * 4.4
                hgt += 1.6 * np.exp(-(((self.xx - cx) / 2.1) ** 2 + ((self.yy - cy) / 1.8) ** 2))
        d = np.zeros_like(hgt)
        _, base = inflate(m, 6)
        from art import normals_from_height
        nn = normals_from_height(hgt * m, 1.0)
        n = base + (nn - np.array([0, 0, 1.0])) * 1.2
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        self.part(c, m, n, P['skin'], 0.0, spec=0.5)
        # sternum line and pec underline
        line = poly(self.h, self.w, [(px - f * 4.5, py - 4), (px - f * 3.8, py - 4), (px - f * 3.6, py + 5), (px - f * 4.3, py + 5)])
        c.rgb[line & m] = P['skin'][1]
        under = m & (np.abs(self.yy - (py + 4.4 + np.abs(self.xx - px) * 0.15)) < 0.7) & (np.abs(self.xx - px) < 6)
        c.rgb[under] = P['skin'][0]
        # open sleeveless vest: two white panels down the sides, torn armholes
        side_b = poly(self.h, self.w, [(bs[0] - f * 8, bs[1] + 3), (bs[0] + f * 1, bs[1] - 3), (nk[0] - f * 1, nk[1] + 2),
                                       (lerp(nk, bh, 0.6)[0] - f * 1, lerp(nk, bh, 0.6)[1]), (bh[0] + f * 1, bh[1] + 5),
                                       (bh[0] - f * 4, bh[1] + 6), (lerp(bs, bh, 0.55)[0] - f * 4.5, lerp(bs, bh, 0.55)[1])])
        side_f = poly(self.h, self.w, [(fs[0] + f * 3.5, fs[1] - 3), (fs[0] + f * 9, fs[1] + 9), (lerp(fs, fh, 0.62)[0] + f * 4.5, lerp(fs, fh, 0.62)[1]),
                                       (fh[0] + f * 3, fh[1] + 5), (fh[0] + f * 0.5, fh[1] + 6), (lerp(fs, fh, 0.5)[0] + f * 4, lerp(fs, fh, 0.5)[1]),
                                       (fs[0] + f * 6, fs[1] + 4)])
        vest = (side_b | side_f) & ~(np.abs(self.xx - px) < 4.5) | (side_b & m)
        _, vn = inflate(vest, 4)
        v = lambert(vn, LIGHT, 0.32) + 0.25 * (np.clip(1 - vn[..., 2], 0, 1) ** 2) * (vn[..., 0] < -0.3)
        v = v + np.sin((self.yy * 1.1 + self.xx * 0.5)) * 0.06
        c.put(vest, toon(v, P['shirt'], 0.18), line=INK)
        # belt with buckle + gaffer tape roll
        by = (bh[1] + fh[1]) / 2 - 1
        belt = poly(self.h, self.w, [(bh[0] - f * 4, by - 2), (fh[0] + f * 3, by - 2), (fh[0] + f * 3, by + 2), (bh[0] - f * 4, by + 2)])
        c.put(belt, P['dark'][0], line=INK)
        buckle = rect_mask(self.h, self.w, int(fh[0] + f * 0.5 - 1.5), int(by - 1.5), 4, 3)
        c.rgb[buckle] = P['hair'][2]
        tx = bh[0] - f * 3
        self.blob(c, tx, by + 3.5, 3.4, 3.4, P['shirt'], 0.05, spec=0.6)
        hole, _ = ellipsoid(self.h, self.w, tx, by + 3.5, 1.2, 1.2)
        c.rgb[hole] = P['dark'][0]
        # traps: thick neck base
        self.blob(c, nk[0] - f * 0.5, nk[1] + 2, 6.5, 3.6, P['skin'], 0.05)
        return m

    def head(self, c, p, f):
        P = PAL
        hx, hy = p['head']
        nk = p['neck']
        sway = math.sin(math.radians(p['lean']) * 3) * 2 + p.get('sway', 0)
        # ponytail behind everything else of the head
        pt = [(hx - f * 5, hy - 3), (hx - f * 10, hy - 1 + sway * 0.5), (hx - f * 14, hy + 5 + sway), (hx - f * 15, hy + 11 + sway * 1.4)]
        m, n, _ = tube(self.h, self.w, pt, [3.0, 2.8, 2.2, 1.2])
        self.part(c, m, n, P['hair'], 0.05, spec=0.6)
        # neck
        self.muscle(c, (nk[0] - f * 0.5, nk[1] + 3), (hx - f * 0.5, hy + 4), 5.2, 5.0, 4.6, P['skin'], 0.05)
        # skull + square comic jaw
        skull, sn = ellipsoid(self.h, self.w, hx, hy, 6.2, 7.0)
        jaw = poly(self.h, self.w, [(hx - f * 5, hy + 1), (hx + f * 6.8, hy + 0.5), (hx + f * 7, hy + 6.5), (hx + f * 5, hy + 9.4),
                                    (hx - f * 1.5, hy + 9.4), (hx - f * 5.5, hy + 6)])
        _, jn = inflate(jaw, 3)
        mm = skull | jaw
        nn = np.where(skull[..., None], sn, jn)
        self.part(c, mm, nn, P['skin'])
        # nose
        nose = poly(self.h, self.w, [(hx + f * 6.2, hy - 1), (hx + f * 8.6, hy + 2.6), (hx + f * 6.4, hy + 3.4)])
        c.put(nose, P['skin'][2], line=INK)
        # ear
        self.blob(c, hx - f * 1.6, hy + 1.5, 1.9, 2.6, P['skin'], 0.1)
        # eye: angry brow, white, pupil
        ex, ey = int(round(hx + f * 3.6)), int(round(hy - 0.5))
        for k in range(-2, 3):
            c.rgb[ey - 2 + (1 if k * f > 0 else 0), ex + k] = INK
        c.rgb[ey, ex - 1:ex + 2] = P['shirt'][3]
        c.rgb[ey, ex + (1 if f > 0 else -1)] = INK
        c.rgb[ey + 1, ex - 1:ex + 2] = P['skin'][1]
        # mouth and chin cleft
        mx = int(round(hx + f * 4.5))
        c.rgb[int(hy + 5), min(mx, mx + 2 * f):max(mx, mx + 2 * f) + 1] = P['skin'][0]
        # hair: swept spiky fringe over the top
        hp = [(hx - f * 6.8, hy + 2), (hx - f * 7.6, hy - 5), (hx - f * 4, hy - 9.5), (hx + f * 1, hy - 10.5), (hx + f * 5, hy - 9),
              (hx + f * 8.4, hy - 7.5), (hx + f * 5.4, hy - 5.5), (hx + f * 6.6, hy - 3.2), (hx + f * 2.2, hy - 4.6),
              (hx - f * 0.5, hy - 3.6), (hx - f * 3, hy - 1.5), (hx - f * 4, hy + 3)]
        m = poly(self.h, self.w, hp)
        _, n = inflate(m, 3)
        self.part(c, m, n, P['hair'], 0.0, spec=0.9)
        strands = m & (((self.xx * 0.6 - self.yy * f) % 4) < 0.8)
        c.rgb[strands] = P['hair'][0]
        # headset: band over the hair, ear cup, boom mic to the mouth
        m, n, _ = tube(self.h, self.w, [(hx - f * 1.8, hy - 1), (hx - f * 0.8, hy - 8.5), (hx + f * 2.5, hy - 10.6)], [1.2, 1.2, 1.1])
        self.part(c, m, n, P['dark'], 0.0, spec=1.0)
        self.blob(c, hx - f * 1.6, hy + 1.2, 2.6, 3.4, P['dark'], 0.0, spec=1.0)
        m, n, _ = tube(self.h, self.w, [(hx - f * 0.5, hy + 3.5), (hx + f * 3.5, hy + 6.8), (hx + f * 6.2, hy + 6.4)], [0.6, 0.6, 0.6])
        c.put(m, P['shirt'][1])
        mm, _ = ellipsoid(self.h, self.w, hx + f * 6.6, hy + 6.3, 1.4, 1.3)
        c.put(mm, INK)

    def draw(self, name, cx=48.0, ground=86.0, flash=False):
        spec = POSES[name]
        p = fk(spec, LOOK, cx, ground)
        f = 1
        c = Canvas(self.w, self.h)
        if not spec.get('bfront'):
            self.arm(c, p['bsho'], p['belb'], p['bhan'], 0.16, p['bfist'])
        self.leg(c, p['bhip'], p['bkne'], p['bank'], p['btoe'], 0.16, f)
        self.torso(c, p, f)
        self.leg(c, p['fhip'], p['fkne'], p['fank'], p['ftoe'], 0.0, f)
        self.head(c, p, f)
        if spec.get('bfront'):
            self.arm(c, p['bsho'], p['belb'], p['bhan'], 0.08, p['bfist'])
        self.arm(c, p['fsho'], p['felb'], p['fhan'], 0.0, p['ffist'])
        c.outline(INK)
        return c
