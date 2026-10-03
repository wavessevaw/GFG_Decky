# «Саундчек мёртвых» — Sega Mega Drive / Genesis

The hidden fourth function of SSMT: a real 16-bit cartridge image. A stage technician fights
through the pages of a comic during a zombie apocalypse; the FOH engineer “Feedback” is the boss.

## Build

```sh
sudo apt install gcc-m68k-linux-gnu binutils-m68k-linux-gnu default-jre-headless python3-numpy python3-pil
./build.sh               # -> out/soundcheck.bin (fetches SGDK at a pinned commit into .sgdk/)
INSTALL=1 ./build.sh     # also copies the ROM into App/SSMT/Resources/Game/
```

`m68k-elf-gcc` works too. With `m68k-linux-gnu-gcc` the script rebuilds SGDK's `libmd.a` from source
(pointer return registers differ between the two ABIs) and checks our objects for word accesses at odd
addresses, which a 68000 does not allow.

Debug builds: `EXTRA_CFLAGS="-DSTART_PAGE=1 -DSTART_PANEL=3 -DGOD"` (start on a panel, invulnerable),
`-DNOENEMY`, `-DAUTOPLAY` (a bot plays the whole game), `-DDEBUG_HUD`.

## Layout

| Path | What |
|---|---|
| `src/game.c` | modes, hero, zombies, boss, items, panel pans, page turns |
| `src/bg.c` | comic page on plane B streamed through a 40×28 ring of VRAM tiles |
| `src/text.c` | proportional Cyrillic text renderer for bubbles, captions, banners |
| `src/hud.c`, `src/sound.c`, `src/story.c` | HUD in the window plane, XGM2 music/PCM, the story |
| `tools/art.py`, `chars.py`, `scenes.py` | lit pixel-art pipeline: puppets and panel scenes |
| `tools/mdconv.py` | 9-bit colour, per-tile palettes, 4bpp tiles |
| `tools/music.py`, `sfx.py` | original FM/PSG soundtrack (VGM) and PCM effects |
| `tools/build_assets.py` | renders everything into `res/` and `src/gen_*` |

## Controls

D-pad walk · B punch (repeat for a combo) · A kick (flying kick in the air) · C jump ·
X/Y/Z or ↓+A/B/C use item 1–3 · ↓ at a downward exit · START pause.
