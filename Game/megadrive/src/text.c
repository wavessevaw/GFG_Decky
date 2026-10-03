#include "text.h"
#include "gen_font.h"
#include "bg.h"

static u32 buf[TXT_MAX * 8];
static u16 bw, bh;              // buffer size in tiles
static s16 bubbleTX = -1, bubbleTY, bubbleW, bubbleH;
static s16 bannerRow = -1, bannerW, bannerX;

// --- UTF-8 -> glyph index

static u16 nextChar(const char **p)
{
    const u8 *s = (const u8 *) *p;
    u16 cp = s[0];
    if (cp < 0x80) { *p += 1; }
    else if ((cp & 0xE0) == 0xC0) { cp = ((cp & 0x1F) << 6) | (s[1] & 0x3F); *p += 2; }
    else { cp = ((cp & 0x0F) << 12) | ((s[1] & 0x3F) << 6) | (s[2] & 0x3F); *p += 3; }
    return cp;
}

static s16 glyph(u16 cp)
{
    if (cp >= 'a' && cp <= 'z') cp -= 32;
    if (cp >= 0x20 && cp < 0x60) return cp - 0x20;
    if (cp >= 0x430 && cp < 0x450) cp -= 0x20;
    if (cp >= 0x410 && cp < 0x430) return 64 + (cp - 0x410);
    switch (cp)
    {
        case 0x401: case 0x451: return 96;
        case 0x2026: return 97;
        case 0x2014: return 98;
        case 0xAB: return 99;
        case 0xBB: return 100;
        case 0xD7: return 101;
        case 0xB7: return 102;
        case 0x2665: return 103;
    }
    return 0;
}

u16 TXT_width(const char *s)
{
    u16 w = 0;
    while (*s)
    {
        s16 g = glyph(nextChar(&s));
        w += font_width[g] + 1;
    }
    return w ? w - 1 : 0;
}

// --- pixel buffer

static void clearBuf(u16 w, u16 h)
{
    bw = w; bh = h;
    memset(buf, 0, w * h * 32);
}

static inline void pset(s16 x, s16 y, u8 c)
{
    if (x < 0 || y < 0 || x >= bw * 8 || y >= bh * 8) return;
    u32 *row = &buf[((y >> 3) * bw + (x >> 3)) * 8 + (y & 7)];
    u16 sh = (7 - (x & 7)) * 4;
    *row = (*row & ~(0xFUL << sh)) | ((u32) c << sh);
}

static void fill(s16 x, s16 y, s16 w, s16 h, u8 c)
{
    for (s16 j = y; j < y + h; j++)
        for (s16 i = x; i < x + w; i++) pset(i, j, c);
}

static void print(s16 x, s16 y, const char *s, u8 c, u8 shadow)
{
    while (*s)
    {
        s16 g = glyph(nextChar(&s));
        const u8 *rows = &font_rows[g * 7];
        for (u16 r = 0; r < 7; r++)
        {
            u8 bits = rows[r];
            for (u16 i = 0; i < 5; i++)
                if (bits & (0x80 >> i))
                {
                    if (shadow) pset(x + i + 1, y + r + 1, shadow);
                    pset(x + i, y + r, c);
                }
        }
        x += font_width[g] + 1;
    }
}

// Word wrap into at most 5 lines; returns line count.
#define LINE_BYTES 96
static u16 wrap(const char *s, u16 maxw, char lines[5][LINE_BYTES])
{
    u16 n = 0, len = 0;
    lines[0][0] = 0;
    while (*s && n < 5)
    {
        const char *w = s;
        while (*s && *s != ' ') s++;
        u16 wl = s - w;
        char cand[LINE_BYTES * 2];
        if (wl > LINE_BYTES - 1) wl = LINE_BYTES - 1;
        if (len)
        {
            memcpy(cand, lines[n], len);
            cand[len] = ' ';
            memcpy(cand + len + 1, w, wl);
            cand[len + 1 + wl] = 0;
        }
        else
        {
            memcpy(cand, w, wl);
            cand[wl] = 0;
        }
        if (len && TXT_width(cand) > maxw)
        {
            n++;
            if (n >= 5) break;
            memcpy(lines[n], w, wl);
            lines[n][wl] = 0;
            len = wl;
        }
        else
        {
            u16 cl = strlen(cand);
            if (cl > LINE_BYTES - 1) cl = LINE_BYTES - 1;
            memcpy(lines[n], cand, cl);
            lines[n][cl] = 0;
            len = cl;
        }
        while (*s == ' ') s++;
    }
    return n + (len ? 1 : 0);
}

static void upload(u16 vram)
{
    VDP_loadTileData(buf, vram, bw * bh, CPU);
}

// --- bubbles

void TXT_clearBubble(void)
{
    if (bubbleTX < 0) return;
    for (s16 y = 0; y < bubbleH; y++)
        for (s16 x = 0; x < bubbleW; x++)
            VDP_setTileMapXY(BG_A, 0, (bubbleTX + x) & 63, (bubbleTY + y) & 31);
    bubbleTX = -1;
}

bool TXT_hasBubble(void) { return bubbleTX >= 0; }

void TXT_bubble(const char *s, s16 ax, s16 ay, s16 minX, s16 maxX, bool hero)
{
    TXT_clearBubble();
    char lines[5][LINE_BYTES];
    u16 n = wrap(s, 112, lines);
    u16 tw = 0;
    for (u16 i = 0; i < n; i++) { u16 w = TXT_width(lines[i]); if (w > tw) tw = w; }
    u16 wpx = tw + 12, hpx = n * 9 + 8;
    u16 wt = (wpx + 7) >> 3, ht = (hpx + 6 + 7) >> 3;
    while (wt * ht > TXT_MAX) ht--;
    clearBuf(wt, ht);
    wpx = wt * 8;
    // Rounded box with ink border.
    fill(1, 0, wpx - 2, hpx, C_INK);
    fill(0, 1, wpx, hpx - 2, C_INK);
    fill(2, 1, wpx - 4, hpx - 2, hero ? C_WHITE : C_PAPER);
    fill(1, 2, wpx - 2, hpx - 4, hero ? C_WHITE : C_PAPER);
    for (u16 i = 0; i < n; i++)
    {
        u16 lw = TXT_width(lines[i]);
        print((wpx - lw) / 2, 4 + i * 9, lines[i], C_INK, 0);
    }
    // Placement: centered over the speaker, clamped to the panel.
    s16 px = ax - wpx / 2;
    if (px < minX) px = minX;
    if (px + (s16) wpx > maxX) px = maxX - wpx;
    px &= ~7;
    s16 py = (ay - (s16) ht * 8) & ~7;
    // Tail: a small wedge from the box bottom toward the speaker.
    s16 tx = ax - px;
    if (tx < 8) tx = 8;
    if (tx > (s16) wpx - 10) tx = wpx - 10;
    for (u16 i = 0; i < 6 && hpx + i < ht * 8; i++)
    {
        s16 w = 6 - i;
        fill(tx - 1 + i / 2, hpx - 1 + i, w + 2, 1, C_INK);
        if (w > 1) fill(tx + i / 2, hpx - 1 + i, w, 1, hero ? C_WHITE : C_PAPER);
    }
    upload(TXT_VRAM);
    bubbleTX = px >> 3;
    bubbleTY = py >> 3;
    bubbleW = wt;
    bubbleH = ht;
    for (u16 y = 0; y < ht; y++)
        for (u16 x = 0; x < wt; x++)
            VDP_setTileMapXY(BG_A, TILE_ATTR_FULL(PAL0, TRUE, FALSE, FALSE, TXT_VRAM + y * wt + x),
                             (bubbleTX + x) & 63, (bubbleTY + y) & 31);
}

// --- caption (window plane, fixed on screen)

void TXT_caption(const char *s)
{
    TXT_clearCaption();
    u16 w = TXT_width(s) + 10;
    u16 wt = (w + 7) >> 3;
    if (wt > CAP_MAX / 2) wt = CAP_MAX / 2;
    clearBuf(wt, 2);
    fill(0, 0, wt * 8, 14, C_INK);
    fill(1, 1, wt * 8 - 2, 12, C_YELLOW);
    print(5, 4, s, C_INK, 0);
    upload(CAP_VRAM);
    for (u16 y = 0; y < 2; y++)
        for (u16 x = 0; x < wt; x++)
            VDP_setTileMapXY(WINDOW, TILE_ATTR_FULL(PAL0, TRUE, FALSE, FALSE, CAP_VRAM + y * wt + x), 2 + x, 2 + y);
}

void TXT_clearCaption(void)
{
    for (u16 y = 2; y < 4; y++)
        for (u16 x = 2; x < 2 + CAP_MAX / 2; x++)
            VDP_setTileMapXY(WINDOW, 0, x, y);
}

// --- banners (screen texts)

void TXT_banner(const char *s, u16 row, u8 color, u8 shadow, bool box)
{
    TXT_clearBanner();
    u16 w = TXT_width(s) + (box ? 14 : 4);
    u16 wt = (w + 7) >> 3;
    if (wt > TXT_MAX / 2) wt = TXT_MAX / 2;
    clearBuf(wt, 2);
    if (box)
    {
        fill(0, 1, wt * 8, 14, C_INK);
        fill(1, 2, wt * 8 - 2, 12, C_WHITE);
    }
    print((wt * 8 - TXT_width(s)) / 2, 5, s, color, shadow);
    upload(TXT_VRAM);
    bannerX = (40 - wt) / 2;
    bannerW = wt;
    bannerRow = row;
    const s16 cx = BG_camX() >> 3, cy = BG_camY() >> 3;
    for (u16 y = 0; y < 2; y++)
        for (u16 x = 0; x < wt; x++)
            VDP_setTileMapXY(BG_A, TILE_ATTR_FULL(PAL0, TRUE, FALSE, FALSE, TXT_VRAM + y * wt + x),
                             (cx + bannerX + x) & 63, (cy + row + y) & 31);
}

void TXT_clearBanner(void)
{
    if (bannerRow < 0) return;
    const s16 cx = BG_camX() >> 3, cy = BG_camY() >> 3;
    for (u16 y = 0; y < 2; y++)
        for (u16 x = 0; x < bannerW; x++)
            VDP_setTileMapXY(BG_A, 0, (cx + bannerX + x) & 63, (cy + bannerRow + y) & 31);
    bannerRow = -1;
}
