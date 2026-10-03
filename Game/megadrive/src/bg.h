#pragma once
#include <genesis.h>

// Comic page background on plane B, streamed through a 40x28 ring of VRAM tiles so that every
// panel can be fully unique art (no tile budget) while the camera pans across the page.

#define VIEW_TW 40
#define VIEW_TH 28

void BG_init(void);
// Shows the page with the camera at (x, y) pixels (multiples of 8). Call with the display off/faded.
void BG_loadPage(u16 page, s16 camX, s16 camY);
// Moves the camera one tile (8 px) in the given direction, streaming in the new column / row.
void BG_step(s16 dx, s16 dy);
s16 BG_camX(void);
s16 BG_camY(void);
const u16 *BG_colors(void);
// VRAM tile index of the ring slot for page tile (tx, ty).
u16 BG_slotTile(u16 tx, u16 ty);
// Page-coordinate band whose reflections ripple (-1 = none); BG_animate runs the line scroll every frame.
void BG_setWater(s16 top, s16 bottom);
void BG_animate(u16 frame);
void BG_paperColumn(s16 col, bool edge);
void BG_paperClearColumn(s16 col);
void BG_paperAll(void);
