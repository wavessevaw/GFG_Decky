#pragma once
#include <genesis.h>

enum { SFX_JUMP, SFX_PUNCH, SFX_KICK, SFX_HIT, SFX_BIGHIT, SFX_HURT, SFX_DOWN, SFX_PICKUP, SFX_HEAL, SFX_CABLE,
       SFX_STROBE, SFX_SHOUT, SFX_ROAR, SFX_CLEAR, SFX_SLIDE, SFX_PAGE, SFX_STEP, SFX_SKETCH, SFX_SWING, SFX_COUNT };
enum { MUS_TITLE, MUS_GAME, MUS_OVER, MUS_WIN };

void SND_init(void);
void SND_play(u16 sfx);
void SND_music(u16 track);
void SND_pause(bool on);
