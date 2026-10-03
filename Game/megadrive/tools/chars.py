"""Characters as lit puppets: a skeleton pose plus body parts shaded with the art engine."""
import math
import numpy as np
from art import Canvas, tube, ellipsoid, poly, inflate, ramp, rect_mask, normals_from_height, distance_in, LIGHT

INK = np.array([0, 0, 0], np.float32)

HERO_PAL = {
    'skin': ramp('#583020', '#a85c3c', '#e09870', '#ffd4a8'),
    'tee': ramp('#0a0a12', '#24242e', '#50505e'),
    'pants': ramp('#24301a', '#4a5c28', '#86983c'),
    'brown': ramp('#2c1608', '#6c3c18'),
    'metal': ramp('#7c7c90', '#e0e0f0'),
}


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


class Puppet:
    """Draws one figure into a canvas. `pose` maps joint names to (x, y); `face` is +1 (right) or -1."""

    def __init__(self, w, h, pal, look):
        self.w, self.h, self.pal, self.look = w, h, pal, look

    def limb(self, c, pts, radii, rmp, dark=0.0, line=None):
        m, n, _ = tube(self.h, self.w, pts, radii)
        return c.shaded((m, n), rmp, ambient=0.30 - dark, line=line if line is not None else rmp[0], extra=-dark)

    def draw(self, pose, flash=False):
        c = Canvas(self.w, self.h)
        P, L = self.pal, self.look
        p = pose
        # Back arm and leg are a touch darker (further from the light).
        self.arm(c, p['bsho'], p['belb'], p['bhan'], dark=0.12, fist=p.get('bfist', True))
        self.leg(c, p['bhip'], p['bkne'], p['bank'], p.get('btoe', 1), dark=0.12)
        self.torso(c, p)
        self.leg(c, p['fhip'], p['fkne'], p['fank'], p.get('ftoe', 1), dark=0.0)
        self.head(c, p)
        self.arm(c, p['fsho'], p['felb'], p['fhan'], dark=0.0, fist=p.get('ffist', True))
        c.outline(INK)
        if flash:
            c.rgb[c.alpha] = np.array([252, 252, 252]) * (c.rgb[c.alpha].sum(-1, keepdims=True) > 60)
        return c

    def arm(self, c, s, e, h, dark, fist):
        P, L = self.pal, self.look
        sleeve = L['sleeve']
        # Upper arm (skin or sleeve), forearm, hand.
        mid = lerp(s, e, 0.55)
        self.limb(c, [s, e], [L['arm'] + 0.8, L['arm']], P['skin'], dark)
        if sleeve:
            self.limb(c, [s, mid], [L['arm'] + 1.6, L['arm'] + 1.3], P[sleeve], dark)
        self.limb(c, [e, h], [L['arm'] - 0.2, L['arm'] - 0.7], P['skin'], dark)
        if L.get('glove'):
            self.limb(c, [lerp(e, h, 0.6), h], [L['arm'] - 0.1, L['arm'] - 0.4], P[L['glove']], dark)
        r = L['arm'] + (1.4 if fist else 0.9)
        m, n = ellipsoid(self.h, self.w, h[0], h[1], r, r * 0.9)
        c.shaded((m, n), P[L.get('glove') or 'skin'], ambient=0.3 - dark, extra=-dark, line=P['skin'][0])

    def leg(self, c, hip, knee, ank, toe, dark):
        P, L = self.pal, self.look
        self.limb(c, [hip, knee], [L['thigh'], L['thigh'] - 0.8], P[L['legs']], dark)
        self.limb(c, [knee, ank], [L['thigh'] - 1.0, L['thigh'] - 2.0], P[L['legs']], dark)
        if L.get('pocket'):
            k = lerp(hip, knee, 0.55)
            m = rect_mask(self.h, self.w, int(k[0] - 3), int(k[1] - 3), 6, 6)
            m &= c.part > 0
            c.rgb[m & (c.part == c.parts)] = P[L['legs']][0]
        # Boot: a chunky ellipsoid pointing forward.
        f = self.look['face']
        bx = ank[0] + f * toe * 2.5
        m, n = ellipsoid(self.h, self.w, bx, ank[1] + 1.5, L['boot'], L['boot'] * 0.62)
        m &= self.grid_y() < ank[1] + 5
        c.shaded((m, n), P[L['shoes']], ambient=0.35 - dark, spec=0.9, line=P[L['shoes']][0])

    def grid_y(self):
        return np.mgrid[0:self.h, 0:self.w][0] + 0.5

    def torso(self, c, p):
        P, L = self.pal, self.look
        bs, fs, bh, fh = p['bsho'], p['fsho'], p['bhip'], p['fhip']
        f = L['face']
        wd = L['chest']
        # Silhouette: shoulders wider than waist, slightly V shaped.
        pts = [(bs[0] - f * 3.5, bs[1] - 1.5), (fs[0] + f * 3.5, fs[1] - 1.5), (fs[0] + f * 3, fs[1] + 7),
               (fh[0] + f * (1 + L.get('belly', 0)), (fs[1] + fh[1]) / 2 + 6), (fh[0] + f * 1, fh[1] + 1),
               (bh[0] - f * 1.5, bh[1] + 1), (bs[0] - f * 4, bs[1] + 7)]
        m = poly(self.h, self.w, pts)
        m, n = inflate(m, wd)
        pid = c.shaded((m, n), P[L['shirt']], ambient=0.25, line=P[L['shirt']][0])
        # Belt / waistband.
        yy = self.grid_y()
        belt_y = (bh[1] + fh[1]) / 2 - 2
        bm = m & (yy > belt_y) & (yy < belt_y + 3)
        if L.get('belt'):
            c.rgb[bm] = P['brown'][0]
            # gaffer tape roll on the hip
            tx = fh[0] + f * 1
            mm, nn = ellipsoid(self.h, self.w, tx, belt_y + 3, 3.6, 3.4)
            c.shaded((mm, nn), P['metal'], ambient=0.35, line=INK)
            hole, _ = ellipsoid(self.h, self.w, tx, belt_y + 3, 1.3, 1.2)
            c.rgb[hole] = P['tee'][0]
        if L.get('print'):
            L['print'](c, m, p)

    def head(self, c, p):
        P, L = self.pal, self.look
        hx, hy = p['head']
        f = L['face']
        nk = p['neck']
        self.limb(c, [(nk[0], nk[1]), (hx - f, hy + 5)], [L['neck'], L['neck']], P['skin'], -0.1)
        rx, ry = L['headw'], L['headh']
        m, n = ellipsoid(self.h, self.w, hx, hy, rx, ry)
        # Jaw: extend down-forward for a square comic chin.
        jaw = poly(self.h, self.w, [(hx - f * rx * 0.6, hy), (hx + f * rx * 1.05, hy + 1), (hx + f * rx * 0.9, hy + ry + 1),
                                     (hx - f * rx * 0.1, hy + ry + 2), (hx - f * rx * 0.7, hy + ry * 0.6)])
        jm, jn = inflate(jaw, 3)
        mm = m | jm
        nn = np.where(m[..., None], n, jn)
        c.shaded((mm, nn), P['skin'], ambient=0.32, line=P['skin'][0])
        L['features'](c, hx, hy, f, P, self)


def hero_features(c, hx, hy, f, P, pup):
    h, w = pup.h, pup.w
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    # Hair: a spiky cap on top/back of the head.
    pts = [(hx - f * 7, hy + 3), (hx - f * 8.5, hy - 4), (hx - f * 5, hy - 9), (hx - f * 1, hy - 10.5), (hx + f * 4, hy - 9.5),
           (hx + f * 7, hy - 6.5), (hx + f * 6.5, hy - 4), (hx + f * 2, hy - 5.5), (hx - f * 1, hy - 3), (hx - f * 3, hy + 1)]
    m = poly(h, w, pts)
    m, n = inflate(m, 3)
    c.shaded((m, n), P['brown'], ambient=0.4, line=INK)
    # Ear.
    em, en = ellipsoid(h, w, hx - f * 2, hy + 1, 1.8, 2.4)
    c.shaded((em, en), P['skin'], ambient=0.3, line=P['skin'][0])
    # Eye: white with pupil, heavy brow.
    ex, ey = int(hx + f * 4), int(hy)
    c.rgb[ey - 2, ex - 2:ex + 3] = INK
    c.rgb[ey - 1, ex - 1:ex + 2] = P['skin'][1]
    c.rgb[ey, ex - 1:ex + 2] = P['metal'][1]
    c.rgb[ey, ex + (1 if f > 0 else -1)] = INK
    c.rgb[ey + 1, ex - 1:ex + 2] = P['skin'][1]
    # Nose and mouth.
    c.rgb[ey + 2, int(hx + f * 7)] = P['skin'][1]
    c.rgb[ey + 5, int(hx + f * 4):int(hx + f * 4) + 3 if f > 0 else int(hx + f * 4) + 1] = P['skin'][0]
    # Stubble: dither on the jaw.
    st = (yy > hy + 3) & (yy < hy + 8.5) & (((xx + yy) % 2) == 0) & ((xx - hx) * f > -2) & c.alpha
    st &= np.all(c.rgb >= P['skin'][2] - 1, -1)
    c.rgb[st] = P['skin'][1]
    # Headset: band over the head, ear cup, boom mic to the mouth.
    m, n, _ = tube(h, w, [(hx - f * 2.5, hy - 1), (hx - f * 1.5, hy - 8), (hx + f * 2, hy - 10.5)], [1.0, 1.0, 1.0])
    c.shaded((m, n), P['tee'], ambient=0.5, spec=1, spec_col=P['metal'][1], line=INK)
    m, n = ellipsoid(h, w, hx - f * 2.2, hy + 1, 2.4, 3.2)
    c.shaded((m, n), P['tee'], ambient=0.45, spec=1.0, spec_col=P['metal'][0], line=INK)
    m, n, _ = tube(h, w, [(hx - f * 1, hy + 3), (hx + f * 3, hy + 6.5), (hx + f * 5.5, hy + 6)], [0.6, 0.6, 0.6])
    c.put(m, P['metal'][0])
    mm, nn = ellipsoid(h, w, hx + f * 6, hy + 6, 1.4, 1.2)
    c.put(mm, INK)


def crew_print(c, m, p):
    """Small 'CREW' logo stripe on the chest."""
    f = p['face']
    sx = int((p['fsho'][0] + p['bsho'][0]) / 2 + f * 1)
    sy = int(p['fsho'][1] + 6)
    letters = ["###", "#..", "###"]
    for dy, row in enumerate(letters):
        for dx, ch in enumerate(row):
            if ch == '#':
                x, y = sx + dx * f, sy + dy
                if m[y, x]:
                    c.rgb[y, x] = HERO_PAL['metal'][0]


HERO_LOOK = dict(face=1, arm=3.3, thigh=5.4, boot=5.6, chest=7, neck=2.8, headw=6.8, headh=8.0,
                 legs='pants', shoes='brown', shirt='tee', sleeve='tee', belt=True, pocket=True,
                 features=hero_features, print=crew_print)


def fk(spec, look, cx=34.0, ground=88.0):
    """Forward kinematics. Angles in degrees from straight down; positive = towards the facing side.
    spec: lean, headtilt, fl/bl = (thigh, shin) leg angles, fa/ba = (upper, fore) arm angles,
    optional hipy (absolute) or lift (raise above the ground), dx (shift)."""
    S, C = math.sin, math.cos
    r = math.radians
    T, TH, SH, UA, FA = look['torso'], look['thighlen'], look['shinlen'], look['ualen'], look['falen']

    def leg(a):
        t, sh = r(a[0]), r(a[1])
        k = (TH * S(t), TH * C(t))
        an = (k[0] + SH * S(sh), k[1] + SH * C(sh))
        return k, an

    fk_, fa_ = leg(spec['fl'])
    bk_, ba_ = leg(spec['bl'])
    hx = cx + spec.get('dx', 0)
    if 'hipy' in spec:
        hy = spec['hipy']
    else:
        hy = ground - max(fa_[1], ba_[1]) - spec.get('lift', 0)
    lean = r(spec.get('lean', 0))
    chest = (hx + T * S(lean), hy - T * C(lean))

    def rot(px, py):
        return (chest[0] + px * C(lean) - py * S(lean), chest[1] + px * S(lean) + py * C(lean))

    sw = look.get('shoulders', 5)
    fsho, bsho = rot(sw * 0.8, 2), rot(-sw, 1)
    neck = rot(1.2, -3)
    tilt = r(spec.get('head', 0))
    hl = look.get('headlen', 7.5)
    head = (neck[0] + hl * S(lean + tilt) + look.get('headfwd', 1), neck[1] - hl * C(lean + tilt))

    def arm(sho, a):
        u, f = r(a[0]), r(a[1])
        e = (sho[0] + UA * S(u), sho[1] + UA * C(u))
        h = (e[0] + FA * S(f), e[1] + FA * C(f))
        return e, h

    fe, fh = arm(fsho, spec['fa'])
    be, bh = arm(bsho, spec['ba'])
    return dict(face=1, head=head, neck=neck, fsho=fsho, bsho=bsho, lean=spec.get('lean', 0), chest=chest, hip=(hx, hy),
                fhip=(hx + 3, hy), bhip=(hx - 3, hy),
                fkne=(hx + 3 + fk_[0], hy + fk_[1]), fank=(hx + 3 + fa_[0], hy + fa_[1]),
                bkne=(hx - 3 + bk_[0], hy + bk_[1]), bank=(hx - 3 + ba_[0], hy + ba_[1]),
                felb=fe, fhan=fh, belb=be, bhan=bh,
                ffist=spec.get('ffist', True), bfist=spec.get('bfist', True),
                ftoe=spec.get('ftoe', 1), btoe=spec.get('btoe', 1))


HERO_LOOK.update(torso=24, thighlen=17, shinlen=17, ualen=12, falen=11, shoulders=7.5)

# Hero animation keyframes (degrees).
HERO_POSES = {
    'guard': dict(lean=6, fl=(18, 4), bl=(-16, -6), fa=(30, 150), ba=(10, 140)),
    'step1': dict(lean=8, fl=(30, 8), bl=(-24, -10), fa=(10, 140), ba=(30, 150)),
    'step2': dict(lean=8, fl=(10, -20), bl=(-6, 4), fa=(20, 150), ba=(20, 150), lift=1),
    'step3': dict(lean=8, fl=(-22, -12), bl=(28, 6), fa=(30, 150), ba=(10, 140)),
    'step4': dict(lean=8, fl=(-4, 6), bl=(12, -20), fa=(20, 150), ba=(20, 150), lift=1),
    'jab0': dict(lean=4, fl=(20, 4), bl=(-18, -6), fa=(-20, 160), ba=(10, 140), dx=-2),
    'jab1': dict(lean=14, fl=(24, 6), bl=(-22, -8), fa=(88, 92), ba=(0, 150), dx=4),
    'cross1': dict(lean=18, fl=(26, 6), bl=(-26, -10), fa=(20, 160), ba=(86, 90), dx=6),
    'kick0': dict(lean=-6, fl=(70, -40), bl=(-4, -4), fa=(30, 150), ba=(-20, 150)),
    'kick1': dict(lean=-16, fl=(92, 90), bl=(-6, -2), fa=(40, 160), ba=(-40, 100), ftoe=1.4),
    'jump': dict(lean=4, fl=(60, -10), bl=(20, -30), fa=(150, 170), ba=(-30, 120), hipy=46),
    'fall': dict(lean=8, fl=(30, 10), bl=(-10, -20), fa=(110, 140), ba=(-60, 60), hipy=46),
    'jkick': dict(lean=-10, fl=(100, 96), bl=(40, -40), fa=(40, 170), ba=(-60, 60), hipy=44, ftoe=1.4),
    'hurt': dict(lean=-18, head=-14, fl=(16, 6), bl=(-14, -6), fa=(140, 170), ba=(-40, 130), dx=-3, ffist=False, bfist=False),
    'down': dict(lean=-70, head=-10, fl=(-60, -80), bl=(-50, -90), fa=(-150, -120), ba=(-120, -100), hipy=80, dx=10),
    'cheer': dict(lean=0, fl=(14, 4), bl=(-14, -4), fa=(170, 190), ba=(-30, 30)),
}


def hero_pose(name, cx=40.0, ground=88.0):
    return fk(HERO_POSES[name], HERO_LOOK, cx, ground)


# ------------------------------------------------------------------ zombies (one shared palette)

ZOMBIE_PAL = {
    'skin': ramp('#2c4428', '#5c7c48', '#9cb47c'),
    'vest': ramp('#a04400', '#fc9020'),
    'jeans': ramp('#1c2848', '#3c5890'),
    'red': ramp('#600c10', '#b42024'),
    'purple': ramp('#3c1c5c', '#8040a8'),
    'dark': ramp('#101014', '#383844'),
    'white': ramp('#e8ecd8', '#e8ecd8'),
}


def zombie_features(c, hx, hy, f, P, pup):
    h, w = pup.h, pup.w
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    L = pup.look
    # Stringy hair.
    hair = L.get('hair', 'dark')
    pts = [(hx - f * 7, hy + 4), (hx - f * 8, hy - 4), (hx - f * 4, hy - 9), (hx + f * 2, hy - 9.5), (hx + f * 6.5, hy - 5),
           (hx + f * 3, hy - 4.5), (hx - f * 2, hy - 2), (hx - f * 4, hy + 6)]
    if L.get('longhair'):
        pts = pts[:-1] + [(hx - f * 5, hy + 14), (hx - f * 8, hy + 12)]
    m = poly(h, w, pts)
    m, n = inflate(m, 2.5)
    c.shaded((m, n), P[hair], ambient=0.45, line=INK)
    # Sunken glowing eye, rotten cheek, open jaw with teeth.
    ex, ey = int(hx + f * 4), int(hy)
    c.rgb[ey - 1, ex - 2:ex + 3] = P['skin'][0]
    c.rgb[ey, ex - 1:ex + 2] = P['white'][1]
    c.rgb[ey, ex] = P['red'][1]
    c.rgb[ey + 1, ex - 1:ex + 2] = P['skin'][0]
    mx = int(hx + f * 4)
    for dy in range(4, 8):
        for dx in range(-1, 3):
            x = mx + dx * f
            if 0 <= x < w:
                c.rgb[ey + dy, x] = INK if 4 < dy < 7 else P['white'][1] if (dx + dy) % 2 == 0 else INK
    rot = (noise_mask(h, w, int(hx * 7 + hy)) & c.alpha & ((xx - hx) ** 2 + (yy - hy) ** 2 < 36))
    c.rgb[rot] = P['skin'][0]
    if L.get('headphones'):
        m, n, _ = tube(h, w, [(hx - f * 3.5, hy), (hx - f * 2, hy - 9), (hx + f * 3, hy - 10.5)], [1.4, 1.4, 1.4])
        c.shaded((m, n), P['dark'], ambient=0.5, line=INK)
        m, n = ellipsoid(h, w, hx - f * 3, hy + 1, 3.2, 4.2)
        c.shaded((m, n), P['dark'], ambient=0.5, spec=1, spec_col=P['white'][1], line=INK)


def noise_mask(h, w, seed, p=0.25):
    from art import noise
    return noise(h, w, 4, seed) > (1 - p)


def zombie_torn(c, m, p):
    """Torn shirt: ragged hem holes and blood."""
    rng = np.random.default_rng(int(p['fhip'][0] * 13 + p['fhip'][1]))
    hy = (p['fhip'][1] + p['bhip'][1]) / 2
    for _ in range(5):
        x = int(rng.uniform(p['bhip'][0] - 3, p['fhip'][0] + 4))
        y = int(hy - rng.uniform(1, 6))
        if 0 <= y < c.h and 0 <= x < c.w and m[y, x]:
            c.rgb[y, x] = ZOMBIE_PAL['skin'][1]
            c.rgb[y + 1, x] = ZOMBIE_PAL['skin'][0]
    for _ in range(3):
        x = int(rng.uniform(p['bsho'][0], p['fsho'][0] + 2))
        y = int(rng.uniform(p['fsho'][1] + 3, hy - 4))
        if m[y, x]:
            c.rgb[y, x] = ZOMBIE_PAL['red'][1]
            if m[y + 1, x]:
                c.rgb[y + 1, x] = ZOMBIE_PAL['red'][0]


def loader_print(c, m, p):
    zombie_torn(c, m, p)
    # Hi-vis vest reflective stripes.
    yy = np.mgrid[0:c.h, 0:c.w][0] + 0.5
    for off in (8, 14):
        s = m & (np.abs(yy - (p['fsho'][1] + off)) < 1.0)
        c.rgb[s & np.all(c.rgb != INK, -1)] = ZOMBIE_PAL['white'][0]


ZLOOK = dict(face=1, arm=2.8, thigh=4.8, boot=5.0, chest=6, neck=2.4, headw=6.2, headh=7.6,
             legs='jeans', shoes='dark', shirt='vest', sleeve=None, belt=False, pocket=False,
             features=zombie_features, print=loader_print,
             torso=24, thighlen=16, shinlen=16, ualen=12, falen=11, shoulders=7)

LOADER = dict(ZLOOK, arm=3.6, thigh=5.8, chest=9, shoulders=9, headw=7, sleeve='dark', belly=4)
FAN = dict(ZLOOK, shirt='red', sleeve='red', arm=2.5, thigh=4.4, chest=5.5, print=zombie_torn, hair='vest')
SINGER = dict(ZLOOK, shirt='purple', sleeve='purple', legs='dark', print=zombie_torn, longhair=True)
BOSS = dict(ZLOOK, shirt='dark', sleeve='dark', arm=5.0, thigh=7.4, boot=7.0, chest=12, shoulders=13, belly=8, headw=8, headh=9,
            neck=3.4, torso=30, thighlen=21, shinlen=20, ualen=15, falen=14, print=zombie_torn, hair='white',
            headphones=True, longhair=True)

ZOMBIE_POSES = {
    'shamble0': dict(lean=16, head=10, fl=(14, 4), bl=(-18, -8), fa=(70, 84), ba=(60, 76)),
    'shamble1': dict(lean=18, head=14, fl=(4, -8), bl=(-6, 2), fa=(76, 90), ba=(56, 70), lift=1),
    'shamble2': dict(lean=16, head=10, fl=(-14, -6), bl=(18, 6), fa=(66, 80), ba=(64, 80)),
    'shamble3': dict(lean=18, head=14, fl=(-2, 4), bl=(6, -10), fa=(74, 88), ba=(58, 72), lift=1),
    'wind': dict(lean=-4, head=-6, fl=(16, 4), bl=(-20, -8), fa=(150, 190), ba=(130, 170), bfist=False, ffist=False),
    'strike': dict(lean=30, head=16, fl=(28, 8), bl=(-28, -12), fa=(96, 110), ba=(86, 100), dx=4, bfist=False, ffist=False),
    'shout': dict(lean=-10, head=-20, fl=(14, 4), bl=(-16, -6), fa=(40, 150), ba=(-30, 40), ffist=False),
    'hurt': dict(lean=-20, head=-18, fl=(14, 6), bl=(-14, -6), fa=(30, 60), ba=(-40, -10), dx=-3, ffist=False, bfist=False),
}


def zombie_pose(name, look, cx=40.0, ground=88.0):
    return fk(ZOMBIE_POSES[name], look, cx, ground)
