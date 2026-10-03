#include "sound.h"
#include "sound_res.h"

// Music: FM + PSG tracks (XGM2). Effects: PCM samples mixed on the free XGM2 PCM channels.

static const u8 *const sfxData[SFX_COUNT] = {
    sfx_jump, sfx_punch, sfx_kick, sfx_hit, sfx_bighit, sfx_hurt, sfx_down, sfx_pickup, sfx_heal, sfx_cable,
    sfx_strobe, sfx_shout, sfx_roar, sfx_clear, sfx_slide, sfx_page, sfx_step, sfx_sketch, sfx_swing
};
static const u32 sfxLen[SFX_COUNT] = {
    sizeof(sfx_jump), sizeof(sfx_punch), sizeof(sfx_kick), sizeof(sfx_hit), sizeof(sfx_bighit), sizeof(sfx_hurt),
    sizeof(sfx_down), sizeof(sfx_pickup), sizeof(sfx_heal), sizeof(sfx_cable), sizeof(sfx_strobe), sizeof(sfx_shout),
    sizeof(sfx_roar), sizeof(sfx_clear), sizeof(sfx_slide), sizeof(sfx_page), sizeof(sfx_step), sizeof(sfx_sketch),
    sizeof(sfx_swing)
};
// Priority: big impacts and voices win over steps and swishes.
static const u8 sfxPrio[SFX_COUNT] = { 4, 6, 6, 9, 12, 10, 11, 8, 8, 8, 9, 7, 12, 10, 5, 6, 1, 6, 3 };

static s16 current = -1;

void SND_init(void)
{
    XGM2_loadDriver(TRUE);
}

void SND_play(u16 sfx)
{
    if (sfx >= SFX_COUNT) return;
    // Channel 1 is free (the tracks use no PCM); let the driver pick by priority.
    XGM2_playPCMEx(sfxData[sfx], sfxLen[sfx] & ~0xFF, SOUND_PCM_CH_AUTO, sfxPrio[sfx], FALSE, FALSE);
}

void SND_music(u16 track)
{
    if ((s16) track == current) return;
    current = track;
    switch (track)
    {
        case MUS_TITLE: XGM2_play(mus_title); break;
        case MUS_GAME: XGM2_play(mus_game); break;
        case MUS_OVER: XGM2_play(mus_over); break;
        case MUS_WIN: XGM2_play(mus_win); break;
    }
}

void SND_pause(bool on)
{
    if (on) XGM2_pause(); else XGM2_resume();
}
