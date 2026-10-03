#include "bg.h"
#include "gen_pages.h"

static const PageData *page;
static s16 camX, camY;

// Ring slots live in two VRAM ranges: tiles 16..1039 and the (unused) font area 1440..1535.
u16 BG_slotTile(u16 tx, u16 ty)
{
    u16 slot = (tx % VIEW_TW) + VIEW_TW * (ty % VIEW_TH);
    return slot < 1024 ? 16 + slot : 1440 + (slot - 1024);
}

static void putTile(u16 tx, u16 ty)
{
    const u16 i = ty * PAGE_TW + tx;
    const u16 vram = BG_slotTile(tx, ty);
    VDP_loadTileData(page->tiles + i * 8, vram, 1, DMA_QUEUE);
    VDP_setTileMapXY(BG_B, TILE_ATTR_FULL(page->pal[i], FALSE, FALSE, FALSE, vram), tx & 63, ty & 31);
}

void BG_init(void)
{
    VDP_setPlaneSize(64, 32, TRUE);
    VDP_setScrollingMode(HSCROLL_PLANE, VSCROLL_PLANE);
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
            const u16 i = ty * PAGE_TW + tx;
            const u16 vram = BG_slotTile(tx, ty);
            VDP_loadTileData(page->tiles + i * 8, vram, 1, CPU);
            VDP_setTileMapXY(BG_B, TILE_ATTR_FULL(page->pal[i], FALSE, FALSE, FALSE, vram), tx & 63, ty & 31);
        }
    }
    VDP_setHorizontalScroll(BG_B, -camX);
    VDP_setVerticalScroll(BG_B, camY);
    VDP_setHorizontalScroll(BG_A, -camX);
    VDP_setVerticalScroll(BG_A, camY);
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
    VDP_setHorizontalScroll(BG_B, -camX);
    VDP_setVerticalScroll(BG_B, camY);
    VDP_setHorizontalScroll(BG_A, -camX);
    VDP_setVerticalScroll(BG_A, camY);
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
