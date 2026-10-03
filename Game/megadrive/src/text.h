#pragma once
#include <genesis.h>

// Software text renderer: proportional 5x7 font (Latin + Cyrillic, UTF-8 strings) drawn into a RAM
// tile buffer, then uploaded to VRAM. Used for comic speech bubbles, captions and screen titles.

#define C_INK 1
#define C_WHITE 2
#define C_PAPER 3
#define C_DOT 4
#define C_YELLOW 5
#define C_RED 6

// Bubble / screen text area on plane A: VRAM tiles 1680..1791.
#define TXT_VRAM 1680
#define TXT_MAX 112
// Caption area in the HUD window: VRAM tiles 1972..2015.
#define CAP_VRAM 1972
#define CAP_MAX 44

u16 TXT_width(const char *s);
// Speech bubble anchored at world point (ax, ay) = the speaker's head; tail points down to it.
void TXT_bubble(const char *s, s16 ax, s16 ay, s16 minX, s16 maxX, bool hero);
void TXT_clearBubble(void);
bool TXT_hasBubble(void);
// Caption box (yellow, like comic narration) at the top-left of the screen, in the fixed window plane.
void TXT_caption(const char *s);
void TXT_clearCaption(void);
// Centered text line drawn on plane A at screen-tile row `row` (screens: title, game over).
void TXT_banner(const char *s, u16 row, u8 color, u8 shadow, bool box);
void TXT_clearBanner(void);
