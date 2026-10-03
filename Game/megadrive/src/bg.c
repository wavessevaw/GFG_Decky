#include "bg.h"
#include "gen_pages.h"

static const PageData *page;
static s16 camX, camY;
static s16 waterTop = -1, waterBottom = -1;
static s16 lineA[224], lineB[224];

// Horizontal scroll per scanline: plane A follows the camera; plane B too, except the water band of the
// current panel, whose lines sway by a pixel to make the reflections ripple.
static void applyScroll(u16 frame)
{
    static const s8 sway[32] = { 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, -1, -1, -1, -1, 0, 0,
                                 0, 1, 1, 0, 0, -1, -1, 0, 0, 1, 1, 1, 0, -1, -1, 0 };
    for (u16 y = 0; y < 224; y++)
    {
        lineA[y] = -camX;
        const s16 py = camY + y;
        lineB[y] = (py >= waterTop && py < waterBottom) ? -camX + sway[(py * 3 + (frame >> 2)) & 31] : -camX;
    }
    VDP_setHorizontalScrollLine(BG_A, 0, lineA, 224, DMA_QUEUE);
    VDP_setHorizontalScrollLine(BG_B, 0, lineB, 224, DMA_QUEUE);
}

void BG_setWater(s16 top, s16 bottom)
{
    waterTop = top;
    waterBottom = bottom;
}

void BG_animate(u16 frame) { applyScroll(frame); }

// Ring slots live in two VRAM ranges: tiles 16..1039 and the (unused) font area 1440..1535.
u16 BG_slotTile(u16 tx, u16 ty)
{
    u16 slot = (tx % VIEW_TW) + VIEW_TW * (ty % VIEW_TH);
    return slot < 1024 ? 16 + slot : 1440 + (slot - 1024);
}

static void putTile(u16 tx, u16 ty)
{
    const u16 i = ty * page->tw + tx;
    const u16 vram = BG_slotTile(tx, ty);
    VDP_loadTileData(page->tiles + i * 8, vram, 1, DMA_QUEUE);
    VDP_setTileMapXY(BG_B, TILE_ATTR_FULL(page->pal[i] & 3, page->pal[i] >> 7, FALSE, FALSE, vram), tx & 63, ty & 31);
}

void BG_init(void)
{
    VDP_setPlaneSize(64, 32, TRUE);
    VDP_setScrollingMode(HSCROLL_LINE, VSCROLL_PLANE);
}

void BG_loadPage(u16 p, s16 x, s16 y)
{
    page = &pages[p];
    camX = x;
    camY = y;
    const u16 tx0 = x >> 3, ty0 = y >> 3;
    for (u16 ty = ty0; ty < ty0 + VIEW_TH; ty++)
    {
        for (u16 tx = tx0; tx < tx0 + VIEW_TW; tx++)
        {
            const u16 i = ty * page->tw + tx;
            const u16 vram = BG_slotTile(tx, ty);
            VDP_loadTileData(page->tiles + i * 8, vram, 1, CPU);
            VDP_setTileMapXY(BG_B, TILE_ATTR_FULL(page->pal[i] & 3, page->pal[i] >> 7, FALSE, FALSE, vram), tx & 63, ty & 31);
        }
    }
    VDP_setVerticalScroll(BG_B, camY);
    VDP_setVerticalScroll(BG_A, camY);
    applyScroll(0);
}

void BG_step(s16 dx, s16 dy)
{
    const u16 tx0 = camX >> 3, ty0 = camY >> 3;
    if (dx > 0)
        for (u16 ty = ty0; ty < ty0 + VIEW_TH; ty++) putTile(tx0 + VIEW_TW, ty);
    else if (dx < 0)
        for (u16 ty = ty0; ty < ty0 + VIEW_TH; ty++) putTile(tx0 - 1, ty);
    if (dy > 0)
        for (u16 tx = tx0; tx < tx0 + VIEW_TW; tx++) putTile(tx, ty0 + VIEW_TH);
    else if (dy < 0)
        for (u16 tx = tx0; tx < tx0 + VIEW_TW; tx++) putTile(tx, ty0 - 1);
    camX += dx * 8;
    camY += dy * 8;
    VDP_setVerticalScroll(BG_B, camY);
    VDP_setVerticalScroll(BG_A, camY);
    applyScroll(0);
}

s16 BG_camX(void) { return camX; }
s16 BG_camY(void) { return camY; }
const u16 *BG_colors(void) { return page->colors; }

// --- page turn sheet on plane A (HUD tiles 22 = paper, 23 = curled edge)

#define PAPER_TILE (2016 + 22)

void BG_paperColumn(s16 col, bool edge)
{
    const u16 tx = ((camX >> 3) + col) & 63, ty0 = camY >> 3;
    const u16 attr = TILE_ATTR_FULL(PAL0, TRUE, FALSE, FALSE, PAPER_TILE + (edge ? 1 : 0));
    for (u16 y = 0; y < VIEW_TH; y++) VDP_setTileMapXY(BG_A, attr, tx, (ty0 + y) & 31);
    // The HUD window covers plane A in the top rows: the sheet covers it too.
    for (u16 y = 0; y < 4; y++) VDP_setTileMapXY(WINDOW, attr, col, y);
}

void BG_paperClearColumn(s16 col)
{
    const u16 tx = ((camX >> 3) + col) & 63, ty0 = camY >> 3;
    for (u16 y = 0; y < VIEW_TH; y++) VDP_setTileMapXY(BG_A, 0, tx, (ty0 + y) & 31);
    for (u16 y = 0; y < 4; y++) VDP_setTileMapXY(WINDOW, 0, col, y);
}

void BG_paperAll(void)
{
    for (s16 c = 0; c < VIEW_TW; c++) BG_paperColumn(c, FALSE);
}
