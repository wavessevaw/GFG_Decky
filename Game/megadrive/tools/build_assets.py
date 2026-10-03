"""Renders every graphic of the game and converts it into Mega Drive resources.

Outputs (all generated, do not edit):
  res/*.png + res/sprites.res  -> sprite sheets for rescomp (SGDK sprite engine)
  src/gen_pages.c / .h         -> comic pages: raw 4bpp tiles + per-tile palette + palettes
  src/gen_font.c / .h          -> proportional 5x7 font (Latin + Cyrillic) for the text renderer
"""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)

from art import md  # noqa: E402
from mdconv import quantize_tiles, pack_tile, to9, key, unkey, md_word, indexed_sheet, preview  # noqa: E402
import scenes  # noqa: E402
import chars  # noqa: E402

PAPER = md('#e8dcb4')
PAPER_DOT = md('#c8b48c')
# PAL0 colours every page must carry (UI, bubbles, bursts): index 1..6
UI_COLORS = ['#000000', '#ffffff', '#e8dcb4', '#c8b48c', '#fcd828', '#d82020']


def cell_image(scene_rgb):
    if scene_rgb.shape[:2] == (224, 320):
        return scene_rgb
    cell = np.zeros((224, 320, 3), np.float32)
    cell[:] = PAPER
    yy, xx = np.mgrid[0:224, 0:320]
    cell[(xx % 4 == 0) & (yy % 4 == 0)] = PAPER_DOT
    cell[6:218, 6:314] = 0
    cell[8:216, 8:312] = scene_rgb
    return cell


def page_image(cells):
    """cells: 2x2 list of scene canvases (or None for an empty paper cell)."""
    img = np.zeros((448, 640, 3), np.float32)
    for r in range(2):
        for c in range(2):
            sc = cells[r][c]
            if sc is None:
                cell = np.zeros((224, 320, 3), np.float32)
                cell[:] = PAPER
            else:
                cell = cell_image(sc.rgb)
            img[r * 224:(r + 1) * 224, c * 320:(c + 1) * 320] = cell
    return img


def c_array(name, ctype, values, per_line=12, fmt='0x{:04X}'):
    lines = []
    for i in range(0, len(values), per_line):
        lines.append('    ' + ', '.join(fmt.format(v) for v in values[i:i + per_line]) + ',')
    return f'const {ctype} {name}[{len(values)}] = {{\n' + '\n'.join(lines) + '\n};\n'


def build_pages(out_c, out_h, preview_dir):
    pages = [
        [[scenes.cover(), scenes.ending()], [None, None]],
        [[scenes.basement(), scenes.loading_dock()], [scenes.corridor(), scenes.dressing_room()]],
        [[scenes.wings(), scenes.stage()], [scenes.foh(), scenes.dancefloor()]],
    ]
    forced = [key(to9(md(h))) for h in UI_COLORS]
    src = ['#include <genesis.h>', '#include "gen_pages.h"', '']
    hdr = ['#pragma once', '#include <genesis.h>', '',
           '#define PAGE_TW 80', '#define PAGE_TH 56', f'#define PAGE_COUNT {len(pages)}', '',
           'typedef struct { const u32 *tiles; const u8 *pal; const u16 *colors; } PageData;',
           'extern const PageData pages[PAGE_COUNT];', '']
    for pi, cells in enumerate(pages):
        img = page_image(cells)
        assign, pals, idx = quantize_tiles(img, forced)
        preview(assign, pals, idx, os.path.join(preview_dir, f'page{pi + 1}.png'), 1)
        words = []
        for ty in range(56):
            for tx in range(80):
                words += pack_tile(idx[ty, tx])
        colors = []
        for p in pals:
            colors += [0] + [md_word(unkey(k)) for k in p] + [0] * (15 - len(p))
        src.append(c_array(f'page{pi + 1}_tiles', 'u32', words, 8, '0x{:08X}'))
        src.append(c_array(f'page{pi + 1}_pal', 'u8', assign.ravel().tolist(), 40, '{}'))
        src.append(c_array(f'page{pi + 1}_colors', 'u16', colors, 16))
    # Platforms (tops of road cases etc.) in cell coordinates.
    src.append('#include "game.h"')
    plat_cases = []
    for pi, cells in enumerate(pages):
        for r in range(2):
            for c in range(2):
                sc = cells[r][c]
                pl = getattr(sc, 'platforms', []) if sc is not None else []
                name = f'plat_{pi}_{c}_{r}'
                if pl:
                    src.append(f'static const Platform {name}[] = {{ ' + ', '.join(f'{{ {x + 8}, {y + 8}, {w} }}' for x, y, w in pl) + ' };')
                    plat_cases.append((pi, c, r, name, len(pl)))
    src.append('const Platform *platformsFor(u16 art, u16 col, u16 row, u16 *count)\n{')
    for pi, c, r, name, n in plat_cases:
        src.append(f'    if (art == {pi} && col == {c} && row == {r}) {{ *count = {n}; return {name}; }}')
    src.append('    *count = 0;\n    return NULL;\n}\n')
    src.append('const PageData pages[PAGE_COUNT] = {')
    for pi in range(len(pages)):
        src.append(f'    {{ page{pi + 1}_tiles, page{pi + 1}_pal, page{pi + 1}_colors }},')
    src.append('};')
    open(out_c, 'w').write('\n'.join(src) + '\n')
    open(out_h, 'w').write('\n'.join(hdr) + '\n')


# ------------------------------------------------------------------ sprites

def frame_image(pup, pose):
    return pup.draw(pose).image()


def lying(img, ground):
    """Knocked-down frame: the hurt pose rotated onto its back, resting on the ground line."""
    w, h = img.size
    r = img.rotate(-84, resample=Image.NEAREST, center=(w / 2, ground - 30), expand=False)
    a = np.asarray(r)[..., 3]
    ys = np.where(a.any(1))[0]
    shift = int(ground + 4 - ys.max()) if len(ys) else 0
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    out.alpha_composite(r, (0, shift))
    return out


def sketch_frames(img):
    """Enemies are drawn into the panel: pencil outline top-down, then colour."""
    a = np.asarray(img).copy()
    alpha = a[..., 3] > 0
    ink = alpha & (a[..., :3].sum(-1) == 0)
    ys = np.where(alpha.any(1))[0]
    top, bot = ys.min(), ys.max()
    frames = []
    yy = np.mgrid[0:a.shape[0], 0:a.shape[1]][0]
    for k, (outline_to, colour_to) in enumerate([(0.5, 0), (1.0, 0), (1.0, 0.5), (1.0, 0.8)]):
        f = np.zeros_like(a)
        lim_o = top + (bot - top) * outline_to
        lim_c = top + (bot - top) * colour_to
        col = alpha & (yy <= lim_c)
        f[col] = a[col]
        sk = ink & (yy <= lim_o) & ~col
        f[sk] = list(md('#383844')) + [255]
        frames.append(Image.fromarray(f, 'RGBA'))
    return frames


def write_sheet(rows, fw, fh, name, res_dir, forced):
    width = max(len(r) for r in rows) * fw
    sheet = Image.new('RGBA', (width, len(rows) * fh), (0, 0, 0, 0))
    for ri, row in enumerate(rows):
        for fi, im in enumerate(row):
            sheet.alpha_composite(im, (fi * fw, ri * fh))
    im, pal, n = indexed_sheet(sheet, forced)
    im.save(os.path.join(res_dir, name + '.png'))
    print(f'{name}: {n} colours -> {len(pal)}')
    return pal


def build_sprites(res_dir):
    res = []
    ink = [key(to9(md('#000000')))]
    # Hero: 80x96 frames (10x12 tiles), feet at y 92, x 40.
    pup = chars.Puppet(80, 96, chars.HERO_PAL, chars.HERO_LOOK)
    H = lambda n: frame_image(pup, chars.hero_pose(n))  # noqa: E731
    rows = [
        [H('guard')],
        [H('step1'), H('step2'), H('step3'), H('step4')],
        [H('jab0'), H('jab1')],
        [H('jab0'), H('cross1')],
        [H('kick0'), H('kick1')],
        [H('jump'), H('fall')],
        [H('jkick')],
        [H('hurt')],
        [lying(H('hurt'), 92)],
        [H('cheer')],
    ]
    write_sheet(rows, 80, 96, 'hero', res_dir, ink)
    res.append('SPRITE spr_hero "hero.png" 10 12 FAST 0 NONE BALANCED')
    # Zombies share one palette: write them in one sheet set with the same forced colour order.
    zpal = None
    for name, look in (('loader', chars.LOADER), ('fan', chars.FAN), ('singer', chars.SINGER), ('boss', chars.BOSS)):
        big = look is chars.BOSS
        fw, fh, cx, g = (112, 120, 56.0, 112.0) if big else (80, 96, 40.0, 88.0)
        pup = chars.Puppet(fw, fh, chars.ZOMBIE_PAL, look)
        Z = lambda n: frame_image(pup, chars.zombie_pose(n, look, cx, g))  # noqa: E731
        walk = [Z('shamble0'), Z('shamble1'), Z('shamble2'), Z('shamble3')]
        attack = Z('shout') if name in ('singer', 'boss') else Z('strike')
        rows = [sketch_frames(walk[0]), walk, [Z('wind')], [attack], [Z('hurt')], [lying(Z('hurt'), g + 4)]]
        zpal = all_zombie_palette() if zpal is None else zpal
        write_sheet(rows, fw, fh, 'z_' + name, res_dir, zpal)
        res.append(f'SPRITE spr_{name} "z_{name}.png" {fw // 8} {fh // 8} FAST 0 NONE BALANCED')
    build_fx(res_dir, res)
    open(os.path.join(res_dir, 'sprites.res'), 'w').write('\n'.join(res) + '\n')


def all_zombie_palette():
    """Fixed colour order for the shared zombie palette (PAL3), so every zombie sheet indexes it identically."""
    cols = ['#000000']
    for r in chars.ZOMBIE_PAL.values():
        cols += [tuple(int(v) for v in c) for c in r]
    out = []
    for c in cols:
        k = key(to9(md(c) if isinstance(c, str) else c))
        if k not in out:
            out.append(k)
    assert len(out) <= 15, len(out)
    return out


# ------------------------------------------------------------------ effects, items, HUD (PAL0 colours)

UI = {n: np.array(md(h), np.float32) for n, h in zip(('ink', 'white', 'paper', 'dot', 'yellow', 'red'), UI_COLORS)}
UI_FORCED = [key(to9(md(h))) for h in UI_COLORS]


def glyph_bitmap(text, scale=2):
    order, glyphs = font_table()
    cols = []
    for ch in text:
        g = glyphs.get(ch.upper(), ['...'] * 7) if ch != ' ' else ['...'] * 7
        for x in range(len(g[0])):
            cols.append([g[y][x] == '#' for y in range(7)])
        cols.append([False] * 7)
    m = np.array(cols, bool).T if cols else np.zeros((7, 1), bool)
    return np.kron(m, np.ones((scale, scale), bool))


def burst_image(text, w=64, h=40, seed=0):
    """Comic onomatopoeia: jagged red star, yellow core, black outlined lettering."""
    from art import poly
    import math
    rng = np.random.default_rng(seed)
    img = np.zeros((h, w, 4), np.uint8)
    cx, cy = w / 2, h / 2
    pts = []
    n = 14
    for k in range(n * 2):
        a = k / (n * 2) * 2 * math.pi
        r = (1.0 if k % 2 == 0 else 0.62) * rng.uniform(0.85, 1.0)
        pts.append((cx + math.cos(a) * r * (w / 2 - 1), cy + math.sin(a) * r * (h / 2 - 1)))
    outer = poly(h, w, pts)
    inner = poly(h, w, [(cx + (x - cx) * 0.78, cy + (y - cy) * 0.74) for x, y in pts])
    img[outer] = list(UI['ink']) + [255]
    p = np.pad(outer, 1)
    core = outer & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    img[core] = list(UI['red']) + [255]
    img[inner] = list(UI['yellow']) + [255]
    t = glyph_bitmap(text, 2 if len(text) <= 6 else 1)
    t = t[:, :w - 2]
    th, tw = t.shape
    ox, oy = int(cx - tw / 2), int(cy - th / 2)
    tm = np.zeros((h, w), bool)
    tm[max(0, oy):oy + th, max(0, ox):ox + tw] = t[:min(th, h - oy), :min(tw, w - ox)]
    # outline + drop shadow
    for dx, dy in ((1, 1), (2, 2), (-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1)):
        sh = np.roll(np.roll(tm, dy, 0), dx, 1)
        img[sh & ~tm] = list(UI['ink']) + [255]
    img[tm] = list(UI['white']) + [255]
    return Image.fromarray(img, 'RGBA')


BURSTS = ['БАЦ!', 'БУМ!', 'ХРЯСЬ!', 'БАБАХ!', 'ШМЯК!', 'АЙ!', '+8', 'СКОТЧ!', 'КАБЕЛЬ!', 'СТРОБ!', 'ВСПЫШКА!', 'ВЖУХ!']


def item_icon(kind, size=16, box=False):
    """16x16 icons of the three items, drawn in PAL0 colours (tape, XLR cable, strobe)."""
    from art import ellipsoid, tube, poly
    import math
    img = np.zeros((size, size, 4), np.uint8)
    put = lambda m, c: img.__setitem__(m, list(UI[c]) + [255])  # noqa: E731
    if box:
        img[:, :] = list(UI['ink']) + [255]
        img[1:-1, 1:-1] = list(UI['yellow']) + [255]
    c = size / 2
    if kind == 'tape':
        o, _ = ellipsoid(size, size, c, c, 6.5, 6.5)
        i2, _ = ellipsoid(size, size, c, c, 5.5, 5.5)
        h1, _ = ellipsoid(size, size, c, c, 3, 3)
        h2, _ = ellipsoid(size, size, c, c, 2, 2)
        put(o, 'ink'); put(i2, 'dot'); put(i2 & (np.mgrid[0:size, 0:size][0] < c - 1), 'white'); put(h1, 'ink'); put(h2, 'paper' if not box else 'yellow')
    elif kind == 'cable':
        for r in (6, 4.5):
            pts = [(c + math.cos(a) * r, c + 1 + math.sin(a) * r * 0.7) for a in np.linspace(0, 6.1, 18)]
            m, _, _ = tube(size, size, pts, [1.0] * len(pts))
            put(m, 'ink')
        m = np.zeros((size, size), bool); m[2:6, 10:14] = True
        put(m, 'ink'); m2 = np.zeros((size, size), bool); m2[3:5, 11:13] = True; put(m2, 'red')
    else:
        m = np.zeros((size, size), bool); m[5:12, 3:13] = True
        put(m, 'ink'); m2 = np.zeros((size, size), bool); m2[6:11, 4:12] = True; put(m2, 'white')
        m3 = np.zeros((size, size), bool); m3[7:10, 5:11] = True; put(m3, 'yellow')
        for (y, x) in ((2, 2), (3, 3), (2, 13), (3, 12), (1, 8), (2, 8), (13, 3), (13, 12)):
            img[y, x] = list(UI['yellow']) + [255]
    return Image.fromarray(img, 'RGBA')


def pad_to(im, w, h):
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    out.alpha_composite(im, ((w - im.width) // 2, (h - im.height) // 2))
    return out


def arrow_image(down):
    from art import poly
    pts = [(2, 10), (16, 10), (16, 3), (30, 16), (16, 29), (16, 22), (2, 22)]
    if down:
        pts = [(y, x) for x, y in pts]
    m = poly(32, 32, pts)
    img = np.zeros((32, 32, 4), np.uint8)
    p = np.pad(m, 1)
    ring = ~m & (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])
    img[m] = list(UI['yellow']) + [255]
    img[ring] = list(UI['ink']) + [255]
    inner = m & np.roll(np.roll(m, 2, 0), 2, 1)
    img[m & ~inner] = list(UI['red']) + [255]
    return Image.fromarray(img, 'RGBA')


def wave_image(big, phase):
    """Sound wave projectile (zombie shout / feedback): concentric arcs."""
    import math
    w, h = (40, 32) if big else (32, 24)
    img = np.zeros((h, w, 4), np.uint8)
    yy, xx = np.mgrid[0:h, 0:w] + 0.5
    cols = [chars.ZOMBIE_PAL['purple'][1], chars.ZOMBIE_PAL['white'][0], chars.ZOMBIE_PAL['purple'][0]]
    for k in range(3 if big else 2):
        r = 6 + k * 6 + phase * 3
        d = np.hypot(xx - 2, (yy - h / 2) * 1.1)
        ang = np.abs(np.arctan2(yy - h / 2, xx - 2)) < 1.0
        ring = (np.abs(d - r) < 1.6) & ang
        img[ring] = list(cols[k % 3]) + [255]
    return Image.fromarray(img, 'RGBA')


def build_fx(res_dir, res):
    rows = [[burst_image(t, 80, 40, i)] for i, t in enumerate(BURSTS)]
    write_sheet(rows, 80, 40, 'bursts', res_dir, UI_FORCED)
    res.append('SPRITE spr_burst "bursts.png" 10 5 FAST 0 NONE BALANCED')
    rows = [[arrow_image(False)], [arrow_image(True)]]
    write_sheet(rows, 32, 32, 'arrow', res_dir, UI_FORCED)
    res.append('SPRITE spr_arrow "arrow.png" 4 4 FAST 0 NONE BALANCED')
    rows = [[pad_to(item_icon(k), 16, 16)] for k in ('tape', 'cable', 'strobe')]
    write_sheet(rows, 16, 16, 'items', res_dir, UI_FORCED)
    res.append('SPRITE spr_item "items.png" 2 2 FAST 0 NONE BALANCED')
    rows = [[pad_to(wave_image(False, p), 40, 32) for p in (0, 1)], [pad_to(wave_image(True, p), 40, 32) for p in (0, 1)]]
    write_sheet(rows, 40, 32, 'wave', res_dir, all_zombie_palette())
    res.append('SPRITE spr_wave "wave.png" 5 4 FAST 0 NONE BALANCED')


def build_hud(out_c, out_h):
    """HUD tiles (window plane, PAL0): item boxes 2x2 for empty/tape/cable/strobe, health segments."""
    tiles = []

    def add_image(im):
        a = np.asarray(im)
        alpha = a[..., 3] > 0
        lv = to9(a[..., :3])
        k = lv[..., 0] * 64 + lv[..., 1] * 8 + lv[..., 2]
        idx = np.zeros(k.shape, np.uint8)
        for n, f in enumerate(UI_FORCED):
            idx[(k == f) & alpha] = n + 1
        th, tw = idx.shape[0] // 8, idx.shape[1] // 8
        for ty in range(th):
            for tx in range(tw):
                tiles.append(idx[ty * 8:ty * 8 + 8, tx * 8:tx * 8 + 8].ravel())

    empty = np.zeros((16, 16, 4), np.uint8)
    empty[:, :] = list(UI['ink']) + [255]
    empty[1:-1, 1:-1] = list(UI['yellow']) + [255]
    add_image(Image.fromarray(empty, 'RGBA'))
    for k in ('tape', 'cable', 'strobe'):
        add_image(item_icon(k, 16, box=True))
    # Health: 8px tiles holding two 3px segments; full / half / empty, normal (yellow) and low (red).
    for col in ('yellow', 'red'):
        for fill in (2, 1, 0):
            t = np.zeros((8, 8, 4), np.uint8)
            t[1:7, :] = list(UI['ink']) + [255]
            for s in range(2):
                c = col if s < fill else 'dot'
                t[2:6, s * 4:s * 4 + 3] = list(UI[c]) + [255]
            add_image(Image.fromarray(t, 'RGBA'))
    # Page-turn sheet: plain paper with halftone dots, and the curled leading edge.
    t = np.zeros((8, 8, 4), np.uint8)
    t[:, :] = list(UI['paper']) + [255]
    t[0::4, 0::4] = list(UI['dot']) + [255]
    add_image(Image.fromarray(t, 'RGBA'))
    t = np.zeros((8, 8, 4), np.uint8)
    t[:, :] = list(UI['white']) + [255]
    t[:, 0] = list(UI['ink']) + [255]
    t[:, 1:3] = list(UI['dot']) + [255]
    t[:, 6:] = list(UI['paper']) + [255]
    add_image(Image.fromarray(t, 'RGBA'))
    words = []
    for t in tiles:
        words += pack_tile(t)
    open(out_c, 'w').write('#include <genesis.h>\n#include "gen_hud.h"\n\n' + c_array('hud_tiles', 'u32', words, 8, '0x{:08X}'))
    open(out_h, 'w').write('#pragma once\n#include <genesis.h>\n\n// 0..3 empty box, 4..7 tape, 8..11 cable, 12..15 strobe (2x2 each, row-major);\n'
                           '// 16..18 health full/half/empty, 19..21 low-health variants, 22 paper, 23 paper edge\n#define HUD_TILES %d\nextern const u32 hud_tiles[HUD_TILES * 8];\n' % len(tiles))


# ------------------------------------------------------------------ font

FONT_SWIFT = os.path.join(ROOT, '..', '..', 'Packages', 'SSMTCore', 'Sources', 'SSMTCore', 'Game', 'PixelFont.swift')


def font_table():
    """Glyphs of the SSMT 5x7 pixel font, indexed for the ROM's text renderer."""
    import re
    txt = open(FONT_SWIFT, encoding='utf-8').read() if os.path.exists(FONT_SWIFT) else open(os.path.join(HERE, 'pixelfont.txt'), encoding='utf-8').read()
    glyphs = {}
    for m in re.finditer(r'"(\\?.)": \[([^\]]*)\]', txt):
        ch = m.group(1).replace('\\', '')
        rows = re.findall(r'"([.#]+)"', m.group(2))
        if len(rows) == 7:
            glyphs[ch] = rows
    alias = {'А': 'A', 'В': 'B', 'Е': 'E', 'К': 'K', 'М': 'M', 'Н': 'H', 'О': 'O', 'Р': 'P', 'С': 'C', 'Т': 'T', 'Х': 'X', 'Ё': 'Ë'}
    for k, v in alias.items():
        glyphs[k] = glyphs[v]
    order = [chr(c) for c in range(0x20, 0x60)]
    order += [chr(c) for c in range(0x410, 0x430)]
    order += ['Ё', '…', '—', '«', '»', '×', '·', '♥']
    return order, glyphs


def build_font(out_c, out_h):
    order, glyphs = font_table()
    widths, rows = [], []
    for ch in order:
        g = glyphs.get(ch)
        if ch == ' ':
            g = ['...'] * 7
        if g is None:
            g = ['.'] * 7
            widths.append(0)
        else:
            widths.append(len(g[0]))
        for r in g:
            v = 0
            for i, p in enumerate(r):
                if p == '#':
                    v |= 0x80 >> i
            rows.append(v)
    src = ['#include <genesis.h>', '#include "gen_font.h"', '',
           c_array('font_width', 'u8', widths, 32, '{}'), c_array('font_rows', 'u8', rows, 14, '0x{:02X}')]
    open(out_c, 'w').write('\n'.join(src))
    open(out_h, 'w').write('#pragma once\n#include <genesis.h>\n\n#define FONT_GLYPHS %d\n'
                           'extern const u8 font_width[FONT_GLYPHS];\nextern const u8 font_rows[FONT_GLYPHS * 7];\n' % len(order))


def build_sound(res_dir):
    import music
    import sfx
    lines = []
    for name in music.build(res_dir):
        lines.append(f'XGM2 {name} "{name}.vgm"')
    for name in sfx.build(res_dir):
        lines.append(f'WAV sfx_{name} "sfx_{name}.wav" XGM2')
    open(os.path.join(res_dir, 'sound.res'), 'w').write('\n'.join(lines) + '\n')


def main():
    res_dir = os.path.join(ROOT, 'res')
    src_dir = os.path.join(ROOT, 'src')
    prev = os.path.join(ROOT, 'out', 'preview')
    os.makedirs(prev, exist_ok=True)
    build_sprites(res_dir)
    build_sound(res_dir)
    build_font(os.path.join(src_dir, 'gen_font.c'), os.path.join(src_dir, 'gen_font.h'))
    build_hud(os.path.join(src_dir, 'gen_hud.c'), os.path.join(src_dir, 'gen_hud.h'))
    build_pages(os.path.join(src_dir, 'gen_pages.c'), os.path.join(src_dir, 'gen_pages.h'), prev)


if __name__ == '__main__':
    main()
