#include <genesis.h>
#include "bg.h"
#include "hud.h"
#include "sound.h"
#include "game.h"

int main(bool hard)
{
    VDP_setScreenWidth320();
    BG_init();
    DMA_setMaxQueueSize(160);
    DMA_setIgnoreOverCapacity(FALSE);
    DMA_setMaxTransferSize(0);
    SPR_initEx(400);
    HUD_init();
    SND_init();
    GAME_run();
    return 0;
}
