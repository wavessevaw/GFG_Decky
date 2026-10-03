"""Pixel-art engine for the Mega Drive game.

Everything is built from lit shapes (tubes, ellipsoids, inflated polygons, height fields), shaded
into hand-picked colour ramps with ordered dithering, outlined in ink, and finally snapped to the
console's 9-bit colour space (3 bits per channel). The output respects the hardware: 8x8 tiles,
16-colour palettes with colour 0 transparent.
"""
import numpy as np
from PIL import Image, ImageDraw

BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0
LIGHT = np.array([0.45, -0.7, 0.55])
LIGHT = LIGHT / np.linalg.norm(LIGHT)


def md(hexstr):
    """'#rrggbb' snapped to the Mega Drive's 3 bits per channel, returned as an (r, g, b) 0..255 tuple."""
    h = hexstr.lstrip('#')
    c = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    return tuple(min(7, int(round(v / 255 * 7))) * 36 for v in c)


def ramp(*hexes):
    return np.array([md(h) for h in hexes], dtype=np.float32)


def bayer(h, w, ox=0, oy=0):
    yy, xx = np.mgrid[0:h, 0:w]
    return BAYER4[(yy + oy) % 4, (xx + ox) % 4]


def grid(h, w):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    return yy + 0.5, xx + 0.5


def noise(h, w, scale, seed, octaves=3):
    """Smooth value noise in 0..1."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(1, int(scale / (2 ** o)))
        gh, gw = h // s + 2, w // s + 2
        g = rng.random((gh, gw)).astype(np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((gw * s, gh * s), Image.BICUBIC)
        out += np.asarray(im, np.float32)[:h, :w] / 255 * amp
        tot += amp
        amp *= 0.5
    return out / tot


# ---------------------------------------------------------------- shapes (mask + normal)

def tube(h, w, pts, radii):
    """Capsule chain along pts with per-point radii. Returns (mask, normal, t along chain 0..1)."""
    yy, xx = grid(h, w)
    best = np.full((h, w), 1e9, np.float32)
    nx = np.zeros((h, w), np.float32)
    ny = np.zeros((h, w), np.float32)
    rr = np.zeros((h, w), np.float32)
    tt = np.zeros((h, w), np.float32)
    n = len(pts) - 1
    for i in range(n):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        r0, r1 = radii[i], radii[i + 1]
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy or 1e-6
        t = np.clip(((xx - x0) * dx + (yy - y0) * dy) / L2, 0, 1)
        cx, cy = x0 + t * dx, y0 + t * dy
        r = r0 + (r1 - r0) * t
        d = np.hypot(xx - cx, yy - cy)
        score = d - r
        sel = score < best
        best = np.where(sel, score, best)
        nx = np.where(sel, (xx - cx) / np.maximum(r, 1e-3), nx)
        ny = np.where(sel, (yy - cy) / np.maximum(r, 1e-3), ny)
        rr = np.where(sel, r, rr)
        tt = np.where(sel, (i + t) / n, tt)
    mask = best < 0
    q = np.clip(nx * nx + ny * ny, 0, 1)
    nz = np.sqrt(1 - q)
    return mask, np.stack([nx, ny, nz], -1), tt


def ellipsoid(h, w, cx, cy, rx, ry):
    yy, xx = grid(h, w)
    ex, ey = (xx - cx) / rx, (yy - cy) / ry
    q = ex * ex + ey * ey
    mask = q < 1
    nz = np.sqrt(np.clip(1 - q, 0, 1))
    return mask, np.stack([ex, ey, nz], -1)


def poly(h, w, pts, ss=4):
    im = Image.new('L', (w * ss, h * ss), 0)
    ImageDraw.Draw(im).polygon([(x * ss, y * ss) for x, y in pts], fill=255)
    im = im.resize((w, h), Image.BOX)
    return np.asarray(im) >= 128


def rect_mask(h, w, x, y, rw, rh):
    m = np.zeros((h, w), bool)
    m[max(0, y):max(0, y + rh), max(0, x):max(0, x + rw)] = True
    return m


def distance_in(mask, limit=12):
    """Chessboard-ish distance from the outside, up to limit (cheap erosion steps)."""
    d = np.zeros(mask.shape, np.float32)
    cur = mask.copy()
    for i in range(limit):
        d += cur
        p = np.pad(cur, 1)
        cur = cur & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
        if not cur.any():
            break
    return d


def inflate(mask, radius=6.0, profile='round'):
    """Pillow-shaped normals for a flat mask (soft cloth, bodies, bevelled panels)."""
    d = distance_in(mask, int(radius) + 2)
    d = np.minimum(d, radius) / radius
    if profile == 'round':
        hgt = np.sqrt(np.clip(1 - (1 - d) ** 2, 0, 1)) * radius
    else:  # bevel
        hgt = d * radius
    hgt = smooth(hgt)
    return mask, normals_from_height(hgt, 1.0)


def smooth(a, k=1):
    for _ in range(k):
        p = np.pad(a, 1, mode='edge')
        a = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:] + 2 * a) / 6
    return a


def normals_from_height(hgt, strength=1.0):
    gy, gx = np.gradient(hgt.astype(np.float32))
    n = np.stack([-gx * strength, -gy * strength, np.ones_like(hgt)], -1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


# ---------------------------------------------------------------- shading

def lambert(normal, light=LIGHT, ambient=0.28, wrap=0.15):
    d = (normal @ light + wrap) / (1 + wrap)
    return ambient + (1 - ambient) * np.clip(d, 0, 1)


def specular(normal, power=18, light=LIGHT):
    h = light + np.array([0, 0, 1.0])
    h = h / np.linalg.norm(h)
    return np.clip(normal @ h, 0, 1) ** power


def toon(value, rmp, dither=1.0, ox=0, oy=0):
    """Map 0..1 brightness into ramp colours with ordered dithering between neighbouring tones."""
    hgt, wid = value.shape
    n = len(rmp)
    v = np.clip(value, 0, 1) * (n - 1)
    b = bayer(hgt, wid, ox, oy)
    frac = v - np.floor(v)
    # Only dither in a band around the boundary so most surfaces stay clean cel tones.
    band = 0.5 + (frac - 0.5) * (1.0 / max(dither, 1e-3))
    idx = np.floor(v).astype(int) + (np.clip(band, 0, 1) > b)
    return rmp[np.clip(idx, 0, n - 1)]


class Canvas:
    def __init__(self, w, h, bg=None):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.float32)
        if bg is not None:
            self.rgb[:] = bg
        self.alpha = np.zeros((h, w), bool) if bg is None else np.ones((h, w), bool)
        self.part = np.zeros((h, w), np.int32)
        self.parts = 0

    def put(self, mask, colors, line=None, inner=True):
        """Composite a part; line = colour for its visible contour against other parts."""
        self.parts += 1
        pid = self.parts
        m = mask
        colors = np.asarray(colors, np.float32)
        if colors.ndim == 1:
            self.rgb[m] = colors
        else:
            self.rgb[m] = colors[m]
        if line is not None and inner:
            p = np.pad(m, 1)
            edge = m & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
            # only where it borders already drawn pixels of other parts (inner contour)
            pa = np.pad(self.alpha, 1)
            touch = pa[:-2, 1:-1] | pa[2:, 1:-1] | pa[1:-1, :-2] | pa[1:-1, 2:]
            e = edge & touch
            self.rgb[e] = line
        self.alpha |= m
        self.part[m] = pid
        return pid

    def shaded(self, shape, rmp, light=LIGHT, ambient=0.28, spec=0.0, spec_col=None, line=None, dither=1.0,
               extra=None, rim=0.0):
        dither = min(dither, 0.35)
        mask, normal = shape[0], shape[1]
        v = lambert(normal, light, ambient)
        if extra is not None:
            v = v + extra
        if rim:
            v = v + rim * np.clip(1 - normal[..., 2], 0, 1) ** 3 * (normal[..., 0] > 0.2)
        col = toon(v, rmp, dither)
        if spec:
            s = specular(normal) * spec
            hl = spec_col if spec_col is not None else rmp[-1]
            col = np.where((s > 0.5)[..., None], hl, col)
        return self.put(mask, col, line=line)

    def outline(self, ink):
        """Ink silhouette outside the drawn area (sprites)."""
        a = self.alpha
        p = np.pad(a, 1)
        ring = ~a & (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])
        self.rgb[ring] = ink
        self.alpha = a | ring

    def image(self, scale=1):
        rgba = np.zeros((self.h, self.w, 4), np.uint8)
        rgba[..., :3] = np.clip(self.rgb, 0, 255).astype(np.uint8)
        rgba[..., 3] = self.alpha * 255
        im = Image.fromarray(rgba, 'RGBA')
        if scale != 1:
            im = im.resize((self.w * scale, self.h * scale), Image.NEAREST)
        return im


def snap(rgb):
    """Snap an RGB array to the console's colour levels."""
    return np.clip(np.round(rgb / 36.0), 0, 7) * 36
