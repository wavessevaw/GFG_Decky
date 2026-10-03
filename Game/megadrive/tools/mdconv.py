"""Conversion of rendered art into Mega Drive data: palettes, 4bpp tiles, tile palette choice."""
import numpy as np
from PIL import Image


def to9(rgb):
    """0..255 colour(s) -> 3-bit levels (0..7)."""
    return np.clip(np.round(np.asarray(rgb, np.float32) / 36.0), 0, 7).astype(np.int32)


def md_word(level3):
    r, g, b = [int(v) for v in level3]
    return (b << 9) | (g << 5) | (r << 1)


def key(levels):
    return int(levels[0]) * 64 + int(levels[1]) * 8 + int(levels[2])


def unkey(k):
    return np.array([k // 64, (k // 8) % 8, k % 8])


def dist(a, b):
    d = (np.asarray(a, np.float32) - np.asarray(b, np.float32))
    # weight green a bit more (perceptual-ish)
    return d[..., 0] ** 2 * 3 + d[..., 1] ** 2 * 4 + d[..., 2] ** 2 * 2


def build_palette(keys_counts, size, forced=()):
    """Pick `size` colours: forced first, then by frequency with merging of near duplicates."""
    pal = list(dict.fromkeys(forced))
    items = sorted(keys_counts.items(), key=lambda kv: -kv[1])
    cand = [k for k, _ in items if k not in pal]
    # k-means-ish: start with most frequent, then greedily add colours that reduce the error most.
    while len(pal) < size and cand:
        best, best_gain = None, -1
        P = np.array([unkey(k) for k in pal]) if pal else np.zeros((0, 3))
        for k in cand[:64]:
            c = unkey(k)
            gain = 0.0
            for k2, n in items[:96]:
                c2 = unkey(k2)
                cur = dist(P, c2).min() if len(P) else 1e9
                new = dist(c, c2)
                if new < cur:
                    gain += (min(cur, 400) - new) * n
            if gain > best_gain:
                best, best_gain = k, gain
        pal.append(best)
        cand.remove(best)
    return pal


def quantize_tiles(img_rgb, forced0=(), npal=2, iters=4):
    """img (H, W, 3) 0..255 -> (tile palette ids, palettes [npal][15 keys], index image).
    Each 8x8 tile uses one palette; colour 0 of every palette stays unused (transparent)."""
    H, W, _ = img_rgb.shape
    lv = to9(img_rgb)
    keys = lv[..., 0] * 64 + lv[..., 1] * 8 + lv[..., 2]
    th, tw = H // 8, W // 8
    tkeys = keys.reshape(th, 8, tw, 8).transpose(0, 2, 1, 3).reshape(th, tw, 64)
    # initial split: by average hue / dominant colours
    flat = tkeys.reshape(-1, 64)
    allk, allc = np.unique(keys, return_counts=True)
    counts = dict(zip(allk.tolist(), allc.tolist()))
    pal0 = build_palette(counts, 15, forced0)
    assign = np.zeros(len(flat), np.int32)
    pals = [pal0] + [pal0[:] for _ in range(npal - 1)]
    if npal > 1:
        # tiles poorly served by pal0 go to the other palette(s)
        err = tile_errors(flat, pal0)
        order = np.argsort(-err)
        assign[order[: len(order) // 3]] = 1
    for _ in range(iters):
        pals = []
        for p in range(npal):
            sel = flat[assign == p]
            if len(sel) == 0:
                pals.append(pal0[:])
                continue
            k, c = np.unique(sel, return_counts=True)
            pals.append(build_palette(dict(zip(k.tolist(), c.tolist())), 15, forced0 if p == 0 else (forced0[:1] if forced0 else ())))
        errs = np.stack([tile_errors(flat, p) for p in pals], -1)
        assign = errs.argmin(-1)
    # index image with ordered remap (nearest colour within the tile's palette)
    idx = np.zeros((th * tw, 64), np.uint8)
    for t in range(len(flat)):
        P = np.array([unkey(k) for k in pals[assign[t]]])
        cols = np.array([unkey(k) for k in flat[t]])
        d = dist(cols[:, None, :], P[None, :, :])
        idx[t] = d.argmin(-1) + 1
    return assign.reshape(th, tw), pals, idx.reshape(th, tw, 64)


def tile_errors(flat, pal):
    P = np.array([unkey(k) for k in pal])
    uk = np.unique(flat)
    cols = np.array([unkey(k) for k in uk])
    e = dist(cols[:, None, :], P[None, :, :]).min(-1)
    lut = dict(zip(uk.tolist(), e.tolist()))
    f = np.vectorize(lut.get)(flat)
    return f.sum(-1)


def pack_tile(idx64):
    """64 palette indices (row-major) -> 8 u32 words (4bpp, leftmost pixel in the high nibble)."""
    words = []
    for r in range(8):
        v = 0
        for c in range(8):
            v = (v << 4) | int(idx64[r * 8 + c])
        words.append(v)
    return words


def palette_words(keys16):
    return [md_word(unkey(k)) if k is not None else 0 for k in keys16]


def preview(assign, pals, idx, path, scale=2):
    th, tw = assign.shape
    out = np.zeros((th * 8, tw * 8, 3), np.uint8)
    for ty in range(th):
        for tx in range(tw):
            P = [np.zeros(3)] + [unkey(k) * 36 for k in pals[assign[ty, tx]]]
            t = idx[ty, tx].reshape(8, 8)
            out[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8] = np.array(P)[t]
    Image.fromarray(out).resize((tw * 8 * scale, th * 8 * scale), Image.NEAREST).save(path)
    return out


def indexed_sheet(rgba, forced=()):
    """RGBA sprite sheet -> 16-colour indexed PIL image (index 0 transparent) for rescomp."""
    a = np.asarray(rgba)
    alpha = a[..., 3] > 0
    lv = to9(a[..., :3])
    keys = lv[..., 0] * 64 + lv[..., 1] * 8 + lv[..., 2]
    k, c = np.unique(keys[alpha], return_counts=True)
    pal = build_palette(dict(zip(k.tolist(), c.tolist())), 15, forced)
    P = np.array([unkey(x) for x in pal])
    uk = np.unique(keys[alpha])
    lut = {}
    for x in uk.tolist():
        lut[x] = int(dist(unkey(x)[None, :], P).argmin()) + 1
    idx = np.zeros(keys.shape, np.uint8)
    flatk = keys[alpha]
    idx[alpha] = np.array([lut[x] for x in flatk.tolist()], np.uint8)
    im = Image.fromarray(idx, 'P')
    flatpal = [255, 0, 255]
    for x in pal:
        flatpal += [int(v) * 36 for v in unkey(x)]
    flatpal += [0, 0, 0] * (256 - len(flatpal) // 3)
    im.putpalette(flatpal)
    return im, pal, len(uk)
