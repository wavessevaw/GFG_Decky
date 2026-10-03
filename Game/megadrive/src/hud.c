#include "hud.h"
#include "gen_hud.h"

static bool shown;
static u8 items[3];
static s16 health = 20, healthMax = 20;

void HUD_init(void)
{
    VDP_loadTileData(hud_tiles, HUD_VRAM, HUD_TILES, CPU);
    VDP_setWindowHPos(FALSE, 0);
    VDP_setWindowVPos(FALSE, 4);
}

static void drawItems(void)
{
    for (u16 s = 0; s < 3; s++)
    {
        const u16 base = HUD_VRAM + (shown ? items[s] * 4 : 0);
        const u16 x = 31 + s * 3;
        for (u16 i = 0; i < 4; i++)
            VDP_setTileMapXY(WINDOW, shown ? TILE_ATTR_FULL(PAL0, TRUE, FALSE, FALSE, base + i) : 0, x + (i & 1), 1 + (i >> 1));
    }
}

static void drawHealth(void)
{
    const bool low = health * 10 <= healthMax * 3;
    for (u16 i = 0; i < 10; i++)
    {
        const s16 seg = health - i * 2;
        const u16 t = 16 + (low ? 3 : 0) + (seg >= 2 ? 0 : seg == 1 ? 1 : 2);
        VDP_setTileMapXY(WINDOW, shown ? TILE_ATTR_FULL(PAL0, TRUE, FALSE, FALSE, HUD_VRAM + t) : 0, 29 + i, 3);
    }
}

void HUD_show(bool on)
{
    shown = on;
    drawItems();
    drawHealth();
}

void HUD_health(s16 hp, s16 max)
{
    health = hp;
    healthMax = max;
    drawHealth();
}

void HUD_items(const u8 inv[3])
{
    memcpy(items, inv, 3);
    drawItems();
}

void HUD_cable(u16 charges) { (void) charges; }

void HUD_page(u16 page, u16 panel) { (void) page; (void) panel; }
