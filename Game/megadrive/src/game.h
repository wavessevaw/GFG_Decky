#pragma once
#include <genesis.h>
#include "gen_pages.h"

// 16.16 fixed point. (The integer part sits in the high word, so narrowing it to s16 reads an aligned
// word: GCC's m68k back end may load the middle word of a 24.8 value, which faults on a real 68000.)
#define FIX(x) ((s32)(x) << 16)
#define FIXF(f) ((s32)((f) * 65536.0))
#define UNFIX(x) ((s16)((x) >> 16))

typedef enum { K_LOADER, K_FAN, K_SINGER, K_BOSS, K_HERO } Kind;
typedef enum { IT_NONE, IT_TAPE, IT_CABLE, IT_STROBE } ItemKind;
typedef enum { EX_RIGHT, EX_DOWN, EX_LEFT, EX_PAGE, EX_END } Exit;

typedef struct { u8 kind; s16 x; u16 delay; } Spawn;
typedef struct { u8 kind; s16 x, y; } ItemDef;

typedef struct
{
    u8 exit;
    const char *caption;
    const char *line;
    u8 spawns;
    Spawn spawn[6];
    u8 items;
    ItemDef item[2];
} PanelDef;

typedef struct
{
    u16 art;            // index into gen_pages
    u8 panels;
    PanelDef panel[6];
} PageDef;

#define STORY_PAGES 2
extern const PageDef story[STORY_PAGES];


void GAME_run(void);
