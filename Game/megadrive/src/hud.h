#pragma once
#include <genesis.h>

// HUD in the fixed window plane (top 4 tile rows): item boxes, health bar, cable charges.
#define HUD_VRAM 2016

void HUD_init(void);
void HUD_show(bool on);
void HUD_health(s16 hp, s16 max);
void HUD_items(const u8 inv[3]);
void HUD_cable(u16 charges);
void HUD_page(u16 page, u16 panel);
