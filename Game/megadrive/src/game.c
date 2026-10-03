#include <genesis.h>
#include "game.h"
#include "bg.h"
#include "text.h"
#include "hud.h"
#include "sound.h"
#include "sprites_res.h"
#include "gen_pages.h"

// «Саундчек мёртвых»: a stage technician fights through the panels of a comic book.

#define MAX_ENEMIES 3
#define MAX_FX 4
#define MAX_SHOTS 3
#define HERO_HP 20

enum { A_IDLE, A_WALK, A_JAB, A_CROSS, A_KICK, A_JUMP, A_JKICK, A_HURT, A_DOWN, A_CHEER };
enum { Z_SPAWN, Z_WALK, Z_WIND, Z_ATTACK, Z_HURT, Z_DOWN };
enum { S_SPAWN, S_IDLE, S_WALK, S_JUMP, S_ATTACK, S_WIND, S_HURT, S_STUN, S_DEAD };
enum { AT_JAB, AT_CROSS, AT_KICK, AT_JKICK };
enum { M_TITLE, M_PLAY, M_PAN, M_TURN, M_OVER, M_WIN, M_PAUSE };

typedef struct
{
    bool on;
    u8 kind;
    s32 x, y, vx, vy;           // panel-local, 24.8 fixed point; (x, y) = feet
    s8 face;
    s16 hp, maxhp;
    u8 st;
    s16 t;
    bool ground;
    s16 inv, cool, comboT;
    u8 combo, attack;
    bool hitDone;
    u16 anim;
    s16 sprAnim, sprFrame;
    Sprite *spr;
} Actor;

typedef struct { bool on; s16 x, y, life; Sprite *spr; } Fx;
typedef struct { bool on; s32 x, vx; s16 y, life, dmg; bool big; Sprite *spr; } Shot;
typedef struct { bool on, taken; u8 kind; s16 x, y; Sprite *spr; } Pickup;

static Actor hero;
static Actor foe[MAX_ENEMIES];
static Fx fx[MAX_FX];
static Shot shot[MAX_SHOTS];
static Pickup pick[2];
static u8 mode;
static u16 pageI, panelI;
static u8 inv[3];
static u8 cableHits;
static bool exitOpen;
static u16 frame;
static u16 joy, joyPrev, pressed;
static Spawn pending[6];
static u8 pendingN;
static s16 bubbleLife;
static const Platform *plats;
static u16 platN;
static s16 panX, panY, panSteps;        // pan direction / remaining tile steps
static s16 turnCol, turnPhase;
static u16 palette[64];
static u16 overT;
static s16 heroFlyX0, heroFlyX1;
static s16 flashT;
static Sprite *arrow;
static s16 arrowDir = -1;

static const SpriteDefinition *const zdef[4] = { &spr_loader, &spr_fan, &spr_singer, &spr_boss };
static const s16 zmaxhp[4] = { 5, 3, 6, 34 };
static const s32 zspeed[4] = { FIXF(0.6), FIXF(1.4), FIXF(0.47), FIXF(0.82) };   // px/frame
static const s16 zdamage[4] = { 2, 1, 2, 3 };

static const PanelDef *panel(void) { return &story[pageI].panel[panelI]; }
static s16 cellX(void) { return panel()->col * CELL_W; }
static s16 cellY(void) { return panel()->row * CELL_H; }

static u16 rnd(u16 n) { return random() % n; }

// ---------------------------------------------------------------------------- effects

static void burst(u16 word, s16 x, s16 y)
{
    for (u16 i = 0; i < MAX_FX; i++)
    {
        Fx *f = &fx[i];
        if (f->on) continue;
        f->on = TRUE;
        f->x = x;
        f->y = y;
        f->life = 28;
        f->spr = SPR_addSprite(&spr_burst, 0, 0, TILE_ATTR(PAL0, TRUE, FALSE, FALSE));
        if (f->spr) SPR_setAnim(f->spr, word);
        return;
    }
}

static void say(const char *s, s16 x, s16 headY, bool isHero)
{
    TXT_bubble(s, cellX() + x, cellY() + headY - 4, cellX() + PANEL_X0 + 2, cellX() + PANEL_X1 - 2, isHero);
    bubbleLife = 150;
}

static void clearFx(void)
{
    for (u16 i = 0; i < MAX_FX; i++)
        if (fx[i].on) { SPR_releaseSprite(fx[i].spr); fx[i].on = FALSE; }
    for (u16 i = 0; i < MAX_SHOTS; i++)
        if (shot[i].on) { SPR_releaseSprite(shot[i].spr); shot[i].on = FALSE; }
    TXT_clearBubble();
    bubbleLife = 0;
}

// ---------------------------------------------------------------------------- actors

static s16 heightOf(const Actor *a) { return a->kind == K_BOSS ? 104 : 80; }
static s16 halfW(const Actor *a) { return a->kind == K_BOSS ? 20 : 13; }

static void physics(Actor *a)
{
    const s32 oldY = a->y;
    a->vy += FIXF(0.36);                // gravity, px/frame²
    if (a->vy > FIX(9)) a->vy = FIX(9);
    a->x += a->vx;
    a->y += a->vy;
    a->ground = FALSE;
    if (a->y >= FIX(FLOOR_Y))
    {
        a->y = FIX(FLOOR_Y);
        a->vy = 0;
        a->ground = TRUE;
    }
    else if (a->vy >= 0)
    {
        const s16 x = UNFIX(a->x);
        for (u16 i = 0; i < platN; i++)
        {
            const Platform *p = &plats[i];
            if (x > p->x - 4 && x < p->x + p->w + 4 && oldY <= FIX(p->y) && a->y >= FIX(p->y))
            {
                a->y = FIX(p->y);
                a->vy = 0;
                a->ground = TRUE;
            }
        }
    }
    s16 minX = PANEL_X0 + 14, maxX = PANEL_X1 - 14;
    if (a->kind == K_HERO && exitOpen)
    {
        const u8 e = panel()->exit;
        if (e == EX_RIGHT || e == EX_PAGE) maxX = PANEL_X1 + 6;
        if (e == EX_LEFT) minX = PANEL_X0 - 6;
    }
    if (a->x < FIX(minX)) a->x = FIX(minX);
    if (a->x > FIX(maxX)) a->x = FIX(maxX);
}

static void setFrame(Actor *a, s16 anim, s16 fr)
{
    if (!a->spr) return;
    if (anim != a->sprAnim || fr != a->sprFrame)
    {
        SPR_setAnimAndFrame(a->spr, anim, fr);
        a->sprAnim = anim;
        a->sprFrame = fr;
    }
}

static void place(Actor *a)
{
    if (!a->spr) return;
    const s16 ax = a->kind == K_BOSS ? 56 : a->kind == K_HERO ? 48 : 40, ay = a->kind == K_BOSS ? 116 : 92;
    s16 sx = cellX() + UNFIX(a->x) - BG_camX() - ax;
    s16 sy = cellY() + UNFIX(a->y) - BG_camY() - ay;
    SPR_setPosition(a->spr, sx, sy);
    SPR_setHFlip(a->spr, a->face < 0);
    // Blink while invulnerable.
    bool hide = (a->inv > 0 && a->kind == K_HERO && (frame & 4)) || (a->st == S_DEAD && a->t < 24 && (frame & 2));
    SPR_setVisibility(a->spr, hide ? HIDDEN : VISIBLE);
}

static void hurtHero(s16 dmg, s16 fromX)
{
#ifdef GOD
    dmg = 0;
#endif
    if (hero.inv > 0 || hero.st == S_DEAD) return;
    hero.hp -= dmg;
    hero.inv = 70;
    hero.vx = (UNFIX(hero.x) < fromX) ? -FIX(3) : FIX(3);
    hero.vy = -FIX(3);
    hero.ground = FALSE;
    SND_play(SFX_HURT);
    if (hero.hp <= 0)
    {
        hero.hp = 0;
        hero.st = S_DEAD;
        hero.t = 110;
        say("НЕТ… ШОУ… ДОЛЖНО…", UNFIX(hero.x), UNFIX(hero.y) - 92, TRUE);
    }
    else
    {
        hero.st = S_HURT;
        hero.t = 18;
        burst(5, UNFIX(hero.x), UNFIX(hero.y) - 84);
    }
    HUD_health(hero.hp, HERO_HP);
}

static bool heroHits(void)
{
    const bool cable = cableHits > 0;
    const u8 at = hero.attack;
    s16 reach = at == AT_KICK ? 56 : at == AT_JKICK ? 52 : 46;
    if (cable) reach += 26;
    const s16 hx = UNFIX(hero.x), hy = UNFIX(hero.y);
    const s16 zx0 = hero.face > 0 ? hx : hx - reach, zx1 = hero.face > 0 ? hx + reach : hx;
    const s16 zy0 = hy - (at == AT_KICK ? 62 : 74), zy1 = hy - (at == AT_KICK ? 26 : 38);
    bool hit = FALSE;
    for (u16 i = 0; i < MAX_ENEMIES; i++)
    {
        Actor *e = &foe[i];
        if (!e->on || e->st == S_DEAD || e->st == S_SPAWN || e->inv) continue;
        const s16 ex = UNFIX(e->x), ey = UNFIX(e->y);
        if (ex + halfW(e) < zx0 || ex - halfW(e) > zx1 || ey < zy0 || ey - heightOf(e) > zy1) continue;
        s16 dmg = (at == AT_KICK || at == AT_JKICK) ? 2 : 1;
        if (at == AT_CROSS && hero.combo >= 2) { dmg = 3; hero.combo = 0; }
        if (cable) dmg += 2;
        e->hp -= dmg;
        e->inv = 12;
        const s16 push = (at == AT_KICK || dmg >= 3) ? 4 : 2;
        e->vx = hero.face * FIX(push) / (e->kind == K_BOSS ? 3 : 1);
        e->vy = (at == AT_KICK) ? -FIX(3) : -FIX(1);
        e->ground = FALSE;
        if (e->hp <= 0)
        {
            e->st = S_DEAD;
            e->t = 70;
            burst(2 + rnd(3), ex, ey - 76);
            SND_play(SFX_DOWN);
        }
        else
        {
            if (e->kind != K_BOSS || at == AT_KICK || dmg >= 3) { e->st = S_HURT; e->t = 20; }
            burst(dmg >= 3 ? 11 : (at == AT_KICK ? 1 : 0), ex, ey - 76);
            SND_play(dmg >= 3 ? SFX_BIGHIT : SFX_HIT);
        }
        hit = TRUE;
    }
    if (hit && cable) { cableHits--; HUD_cable(cableHits); }
    return hit;
}

static void useItem(u16 slot)
{
    if (slot >= 3 || !inv[slot] || hero.st == S_DEAD) return;
    const u8 k = inv[slot];
    for (u16 i = slot; i < 2; i++) inv[i] = inv[i + 1];
    inv[2] = IT_NONE;
    HUD_items(inv);
    switch (k)
    {
        case IT_TAPE:
            hero.hp = min(HERO_HP, hero.hp + 8);
            HUD_health(hero.hp, HERO_HP);
            burst(6, UNFIX(hero.x), UNFIX(hero.y) - 96);
            SND_play(SFX_HEAL);
            break;
        case IT_CABLE:
            cableHits = 8;
            HUD_cable(cableHits);
            SND_play(SFX_CABLE);
            say("ПОСЛУШАЙ, КАК ЗВУЧИТ ХОРОШАЯ КОММУТАЦИЯ!", UNFIX(hero.x), UNFIX(hero.y) - 92, TRUE);
            break;
        case IT_STROBE:
            SND_play(SFX_STROBE);
            for (u16 i = 0; i < MAX_ENEMIES; i++)
            {
                Actor *e = &foe[i];
                if (!e->on || e->st == S_DEAD || e->st == S_SPAWN) continue;
                e->st = S_STUN;
                e->t = e->kind == K_BOSS ? 100 : 220;
                e->vx = 0;
            }
            burst(10, 160, 90);
            flashT = 12;
            break;
    }
}

static void updateHero(void)
{
    Actor *h = &hero;
    if (h->inv > 0) h->inv--;
    if (h->comboT > 0) h->comboT--; else h->combo = 0;
    if (h->t > 0) h->t--;

    // Items: X / Y / Z on a 6-button pad, or DOWN + A / B / C.
    if (pressed & BUTTON_X) useItem(0);
    if (pressed & BUTTON_Y) useItem(1);
    if (pressed & BUTTON_Z) useItem(2);
    const bool down = joy & BUTTON_DOWN;
    if (down && (pressed & BUTTON_A)) useItem(0);
    if (down && (pressed & BUTTON_B)) useItem(1);
    if (down && (pressed & BUTTON_C)) useItem(2);

    switch (h->st)
    {
        case S_DEAD:
            h->vx = 0;
            break;
        case S_HURT:
            if (h->t <= 0) h->st = S_IDLE;
            break;
        case S_ATTACK:
        {
            const bool kick = h->attack == AT_KICK || h->attack == AT_JKICK;
            const s16 hitStart = kick ? 14 : 10, hitEnd = kick ? 7 : 5;
            if (!h->hitDone && h->t <= hitStart && h->t >= hitEnd && heroHits()) h->hitDone = TRUE;
            if (h->ground) h->vx = h->vx * 3 / 4;
            if (h->t <= 0) h->st = h->ground ? S_IDLE : S_JUMP;
            break;
        }
        default:
        {
            s16 dir = 0;
            if (!down)
            {
                if (joy & BUTTON_LEFT) dir = -1;
                if (joy & BUTTON_RIGHT) dir = 1;
            }
            if (dir) h->face = dir;
            h->vx = dir * FIX(2);
            if ((pressed & BUTTON_C) && !down && h->ground)
            {
                h->vy = -FIXF(7.25);
                h->ground = FALSE;
                SND_play(SFX_JUMP);
            }
            const bool punch = (pressed & BUTTON_B) && !down, kick = (pressed & BUTTON_A) && !down;
            if (punch || kick)
            {
                h->st = S_ATTACK;
                h->hitDone = FALSE;
                if (!h->ground) { h->attack = AT_JKICK; h->t = 22; }
                else if (kick) { h->attack = AT_KICK; h->t = 22; }
                else
                {
                    h->attack = (h->combo & 1) ? AT_CROSS : AT_JAB;
                    h->combo++;
                    h->comboT = 34;
                    h->t = 15;
                }
                SND_play(h->attack == AT_JAB || h->attack == AT_CROSS ? SFX_PUNCH : SFX_KICK);
            }
            else
                h->st = !h->ground ? S_JUMP : (dir ? S_WALK : S_IDLE);
        }
    }
    physics(h);
    if (!h->ground && h->st == S_IDLE) h->st = S_JUMP;
    if (h->st == S_WALK) { h->anim++; if ((h->anim & 15) == 0) SND_play(SFX_STEP); }

    // Animation frame.
    switch (h->st)
    {
        case S_WALK: setFrame(h, A_WALK, (h->anim >> 3) & 3); break;
        case S_JUMP: setFrame(h, A_JUMP, h->vy < 0 ? 0 : 1); break;
        case S_ATTACK:
        {
            const s16 total = (h->attack == AT_JAB || h->attack == AT_CROSS) ? 15 : 22;
            const s16 fr = (total - h->t) < 4 ? 0 : 1;
            if (h->attack == AT_JKICK) setFrame(h, A_JKICK, 0);
            else setFrame(h, h->attack == AT_JAB ? A_JAB : h->attack == AT_CROSS ? A_CROSS : A_KICK, h->t < 4 ? 0 : fr);
            break;
        }
        case S_HURT: setFrame(h, A_HURT, 0); break;
        case S_DEAD: setFrame(h, h->ground ? A_DOWN : A_HURT, 0); break;
        default: setFrame(h, A_IDLE, 0);
    }
}

static void spawnEnemy(u8 kind, s16 x)
{
    for (u16 i = 0; i < MAX_ENEMIES; i++)
    {
        Actor *e = &foe[i];
        if (e->on) continue;
        memset(e, 0, sizeof(Actor));
        e->on = TRUE;
        e->kind = kind;
        e->x = FIX(x);
        e->y = FIX(FLOOR_Y);
        e->ground = TRUE;
        e->face = x > UNFIX(hero.x) ? -1 : 1;
        e->hp = e->maxhp = zmaxhp[kind];
        e->st = S_SPAWN;
        e->t = 48;
        e->sprAnim = -1;
        e->spr = SPR_addSprite(zdef[kind], 0, 0, TILE_ATTR(PAL3, FALSE, FALSE, FALSE));
        if (kind == K_BOSS)
        {
            SND_play(SFX_ROAR);
            say("ФИДБЭК: ТЕСТ… РАЗ… ДВА… ВЫ УВОЛЕНЫ!", x, FLOOR_Y - 116, FALSE);
        }
        else SND_play(SFX_SKETCH);
        return;
    }
}

static bool freeSlot(void)
{
    for (u16 i = 0; i < MAX_ENEMIES; i++) if (!foe[i].on) return TRUE;
    return FALSE;
}

static void fire(Actor *e)
{
    for (u16 i = 0; i < MAX_SHOTS; i++)
    {
        Shot *s = &shot[i];
        if (s->on) continue;
        s->on = TRUE;
        s->big = e->kind == K_BOSS;
        s->x = e->x + e->face * FIX(s->big ? 28 : 20);
        s->y = UNFIX(e->y) - (s->big ? 78 : 66);
        s->vx = e->face * (s->big ? FIXF(3.5) : FIXF(2.6));
        s->life = 150;
        s->dmg = zdamage[e->kind];
        s->spr = SPR_addSprite(&spr_wave, 0, 0, TILE_ATTR(PAL3, TRUE, FALSE, FALSE));
        if (s->spr) { SPR_setAnim(s->spr, s->big ? 1 : 0); SPR_setHFlip(s->spr, e->face < 0); }
        SND_play(s->big ? SFX_ROAR : SFX_SHOUT);
        return;
    }
}

static void updateEnemy(Actor *e)
{
    const u8 k = e->kind;
    if (e->inv > 0) e->inv--;
    if (e->cool > 0) e->cool--;
    if (e->t > 0) e->t--;
    const s16 dx = UNFIX(hero.x) - UNFIX(e->x);
    const s16 adx = abs(dx);
    switch (e->st)
    {
        case S_SPAWN:
            if (e->t <= 0) { e->st = S_IDLE; e->cool = 30; }
            break;
        case S_DEAD:
            e->vx = e->vx * 7 / 8;
            break;
        case S_HURT:
        case S_STUN:
            if (e->t <= 0) e->st = S_IDLE;
            if (e->st == S_STUN) e->vx = 0;
            break;
        case S_WIND:
            e->vx = 0;
            if (e->t == (k == K_BOSS ? 14 : 10))
            {
                if (k == K_SINGER || (k == K_BOSS && rnd(2)))
                {
                    fire(e);
                    if (rnd(4) == 0) say(k == K_BOSS ? "FEEDBACK!!!" : "А-А-А-А-А!", UNFIX(e->x), UNFIX(e->y) - (k == K_BOSS ? 118 : 94), FALSE);
                }
                else if (adx < (k == K_BOSS ? 56 : 44) && abs(UNFIX(hero.y) - UNFIX(e->y)) < 30)
                    hurtHero(zdamage[k], UNFIX(e->x));
                else SND_play(SFX_SWING);
            }
            if (e->t <= 0) { e->st = S_IDLE; e->cool = k == K_BOSS ? 46 : (k == K_FAN ? 40 : 66); }
            break;
        default:
        {
            e->face = dx >= 0 ? 1 : -1;
            const bool ranged = k == K_SINGER || (k == K_BOSS && adx > 90);
            const s16 range = ranged ? 200 : (k == K_BOSS ? 46 : 34);
            if (hero.st == S_DEAD) { e->vx = 0; e->st = S_IDLE; }
            else if (adx > range)
            {
                s32 sp = zspeed[k];
                if (k == K_BOSS && adx > 150) sp *= 2;
                e->vx = e->face * sp;
                e->st = S_WALK;
                e->anim++;
            }
            else
            {
                e->vx = 0;
                e->st = S_IDLE;
                if (e->cool == 0) { e->st = S_WIND; e->t = k == K_BOSS ? 34 : 28; }
            }
            if (k == K_SINGER && adx < 80 && e->st != S_WIND) { e->vx = -e->face * zspeed[k]; e->st = S_WALK; e->anim++; }
        }
    }
    physics(e);
    switch (e->st)
    {
        case S_SPAWN: setFrame(e, Z_SPAWN, min(3, (48 - e->t) / 12)); break;
        case S_WALK: setFrame(e, Z_WALK, (e->anim >> 3) & 3); break;
        case S_WIND: setFrame(e, e->t > (k == K_BOSS ? 14 : 10) ? Z_WIND : Z_ATTACK, 0); break;
        case S_HURT: setFrame(e, Z_HURT, 0); break;
        case S_STUN: setFrame(e, Z_HURT, 0); break;
        case S_DEAD: setFrame(e, e->ground ? Z_DOWN : Z_HURT, 0); break;
        default: setFrame(e, Z_WALK, 0);
    }
    if (e->st == S_DEAD && e->t <= 0)
    {
        SPR_releaseSprite(e->spr);
        e->spr = NULL;
        e->on = FALSE;
    }
}

static void updateShots(void)
{
    for (u16 i = 0; i < MAX_SHOTS; i++)
    {
        Shot *s = &shot[i];
        if (!s->on) continue;
        s->x += s->vx;
        s->life--;
        const s16 x = UNFIX(s->x);
        const s16 hx = UNFIX(hero.x), hy = UNFIX(hero.y);
        if (abs(x - hx) < (s->big ? 22 : 16) && s->y > hy - 84 && s->y < hy - 10 && hero.inv == 0 && hero.st != S_DEAD)
        {
            hurtHero(s->dmg, x - (s->vx > 0 ? 10 : -10));
            s->life = 0;
        }
        if (s->life <= 0 || x < PANEL_X0 - 20 || x > PANEL_X1 + 20)
        {
            SPR_releaseSprite(s->spr);
            s->on = FALSE;
            continue;
        }
        if (s->spr)
        {
            SPR_setPosition(s->spr, cellX() + x - BG_camX() - 20, cellY() + s->y - BG_camY() - 16);
            SPR_setFrame(s->spr, (frame >> 2) & 1);
        }
    }
}

static void updateFx(void)
{
    for (u16 i = 0; i < MAX_FX; i++)
    {
        Fx *f = &fx[i];
        if (!f->on) continue;
        if (--f->life <= 0 || !f->spr)
        {
            if (f->spr) SPR_releaseSprite(f->spr);
            f->on = FALSE;
            continue;
        }
        const s16 rise = (28 - f->life) / 4;
        SPR_setPosition(f->spr, cellX() + f->x - BG_camX() - 40, cellY() + f->y - rise - BG_camY() - 20);
    }
    if (bubbleLife > 0 && --bubbleLife == 0) TXT_clearBubble();
}

static void updatePickups(void)
{
    for (u16 i = 0; i < 2; i++)
    {
        Pickup *p = &pick[i];
        if (!p->on) continue;
        const s16 bob = (frame >> 4) & 1;
        if (p->spr) SPR_setPosition(p->spr, cellX() + p->x - 8 - BG_camX(), cellY() + p->y - 18 - bob - BG_camY());
        if (!p->taken && abs(p->x - UNFIX(hero.x)) < 18 && abs(p->y - UNFIX(hero.y)) < 30)
        {
            u16 slot = 3;
            for (u16 s = 0; s < 3; s++) if (!inv[s]) { slot = s; break; }
            if (slot == 3) continue;
            inv[slot] = p->kind;
            HUD_items(inv);
            p->taken = TRUE;
            p->on = FALSE;
            SPR_releaseSprite(p->spr);
            p->spr = NULL;
            SND_play(SFX_PICKUP);
            burst(p->kind == IT_TAPE ? 7 : p->kind == IT_CABLE ? 8 : 9, p->x, p->y - 30);
        }
    }
}

// ---------------------------------------------------------------------------- panels

// Blinking exit arrow (right / down / left) once a panel is cleared.
static void showArrow(s16 dir)
{
    if (arrow) { SPR_releaseSprite(arrow); arrow = NULL; }
    arrowDir = dir;
    if (dir < 0 || dir == EX_END) { arrowDir = -1; return; }
    arrow = SPR_addSprite(&spr_arrow, 0, 0, TILE_ATTR(PAL0, TRUE, FALSE, FALSE));
    if (!arrow) return;
    SPR_setAnim(arrow, dir == EX_DOWN ? 1 : 0);
    SPR_setHFlip(arrow, dir == EX_LEFT);
}

static void updateArrow(void)
{
    if (!arrow) return;
    s16 x = arrowDir == EX_LEFT ? 20 : arrowDir == EX_DOWN ? 144 : 268;
    s16 y = arrowDir == EX_DOWN ? 120 + ((frame >> 3) & 3) : 100;
    if (arrowDir != EX_DOWN) x += ((frame >> 3) & 3) * (arrowDir == EX_LEFT ? -1 : 1);
    SPR_setPosition(arrow, cellX() + x - BG_camX(), cellY() + y - BG_camY());
    SPR_setVisibility(arrow, (frame & 16) ? VISIBLE : HIDDEN);
}

static void releaseAll(void)
{
    for (u16 i = 0; i < MAX_ENEMIES; i++)
        if (foe[i].on) { if (foe[i].spr) SPR_releaseSprite(foe[i].spr); foe[i].on = FALSE; }
    for (u16 i = 0; i < 2; i++)
        if (pick[i].spr) { SPR_releaseSprite(pick[i].spr); pick[i].spr = NULL; pick[i].on = FALSE; }
    clearFx();
}

static void startPanel(void)
{
    const PanelDef *p = panel();
    releaseAll();
    plats = platformsFor(story[pageI].art, p->col, p->row, &platN);
#ifdef NOENEMY
    pendingN = 0;
#else
    pendingN = p->spawns;
#endif
    memcpy(pending, p->spawn, sizeof(Spawn) * p->spawns);
    exitOpen = FALSE;
    for (u16 i = 0; i < p->items; i++)
    {
        Pickup *k = &pick[i];
        k->on = TRUE;
        k->taken = FALSE;
        k->kind = p->item[i].kind;
        if (p->item[i].x == 0 && platN)
        {
            // On top of the highest platform (reward for climbing).
            u16 best = 0;
            for (u16 j = 1; j < platN; j++) if (plats[j].y < plats[best].y) best = j;
            k->x = plats[best].x + plats[best].w / 2;
            k->y = plats[best].y;
        }
        else
        {
            k->x = p->item[i].x ? p->item[i].x : 160;
            k->y = p->item[i].y ? p->item[i].y : FLOOR_Y;
        }
        k->spr = SPR_addSprite(&spr_item, 0, 0, TILE_ATTR(PAL0, FALSE, FALSE, FALSE));
        if (k->spr) SPR_setAnim(k->spr, k->kind - 1);
    }
    hero.vx = 0;
    hero.vy = 0;
    if (hero.st != S_DEAD) hero.st = S_IDLE;
    TXT_caption(p->caption);
    say(p->line, UNFIX(hero.x), UNFIX(hero.y) - 92, TRUE);
    HUD_page(pageI, panelI);
}

static void loadPagePalette(void)
{
    memcpy(palette, BG_colors(), 32 * 2);
    memcpy(palette + 32, spr_hero.palette->data, 16 * 2);
    memcpy(palette + 48, spr_loader.palette->data, 16 * 2);
}

static void enterPage(u16 p, bool fade)
{
    pageI = p;
#ifdef START_PANEL
    panelI = START_PANEL;
#else
    panelI = 0;
#endif
    if (fade) PAL_fadeOutAll(16, FALSE);
    SYS_disableInts();
    BG_loadPage(story[p].art, cellX(), cellY());
    SYS_enableInts();
    loadPagePalette();
    if (fade) PAL_fadeInAll(palette, 16, TRUE);
    else PAL_setColors(0, palette, 64, CPU);
}

static void newGame(void)
{
    memset(&hero, 0, sizeof(hero));
    hero.on = TRUE;
    hero.kind = K_HERO;
    hero.x = FIX(60);
    hero.y = FIX(FLOOR_Y);
    hero.face = 1;
    hero.hp = hero.maxhp = HERO_HP;
    hero.st = S_IDLE;
    hero.sprAnim = -1;
    if (!hero.spr) hero.spr = SPR_addSprite(&spr_hero, 0, 0, TILE_ATTR(PAL2, FALSE, FALSE, FALSE));
    SPR_setVisibility(hero.spr, VISIBLE);
    memset(inv, 0, sizeof(inv));
    cableHits = 0;
    TXT_clearBanner();
    HUD_show(TRUE);
    HUD_items(inv);
    HUD_cable(0);
    HUD_health(hero.hp, HERO_HP);
#ifdef START_PAGE
    enterPage(START_PAGE, TRUE);
#else
    enterPage(0, TRUE);
#endif
    mode = M_PLAY;
    startPanel();
    SND_music(MUS_GAME);
}

static void restartPanel(void)
{
    hero.hp = HERO_HP;
    hero.st = S_IDLE;
    hero.inv = 90;
    hero.x = FIX(60);
    hero.y = FIX(FLOOR_Y);
    TXT_clearBanner();
    PAL_fadeInAll(palette, 20, TRUE);
    HUD_health(hero.hp, HERO_HP);
    mode = M_PLAY;
    startPanel();
}

static void checkExit(void)
{
    const PanelDef *p = panel();
    const s16 x = UNFIX(hero.x);
    bool leave = FALSE;
    switch (p->exit)
    {
        case EX_RIGHT: case EX_PAGE: leave = x >= PANEL_X1 + 2; break;
        case EX_LEFT: leave = x <= PANEL_X0 - 2; break;
        case EX_DOWN: leave = abs(x - 160) < 70 && hero.ground && UNFIX(hero.y) == FLOOR_Y && (joy & BUTTON_DOWN); break;
    }
    if (!leave) return;
    releaseAll();
    showArrow(-1);
    TXT_clearCaption();
    if (p->exit == EX_PAGE)
    {
        mode = M_TURN;
        turnCol = 40;
        turnPhase = 0;
        HUD_show(FALSE);
        SPR_setVisibility(hero.spr, HIDDEN);
        SND_play(SFX_PAGE);
        return;
    }
    const u16 from = panelI;
    panelI++;
    const PanelDef *n = panel();
    panX = n->col - story[pageI].panel[from].col;
    panY = n->row - story[pageI].panel[from].row;
    panSteps = panX ? 40 : 28;
    heroFlyX0 = x;
    heroFlyX1 = p->exit == EX_RIGHT ? 30 : p->exit == EX_LEFT ? 290 : x;
    mode = M_PAN;
    SND_play(SFX_SLIDE);
}

static void play(void)
{
    // Enemies are drawn into the panel one by one (at most 3 at a time).
    for (u16 i = 0; i < pendingN; i++)
    {
        if (pending[i].delay > 0) pending[i].delay--;
        if (pending[i].delay == 0 && freeSlot())
        {
            spawnEnemy(pending[i].kind, pending[i].x);
            pending[i] = pending[pendingN - 1];
            pendingN--;
            break;
        }
    }
    updateHero();
    for (u16 i = 0; i < MAX_ENEMIES; i++) if (foe[i].on) updateEnemy(&foe[i]);
    updateShots();
    updatePickups();
    bool alive = FALSE;
    for (u16 i = 0; i < MAX_ENEMIES; i++) if (foe[i].on && foe[i].st != S_DEAD) alive = TRUE;
    if (!exitOpen && pendingN == 0 && !alive)
    {
        exitOpen = TRUE;
        SND_play(SFX_CLEAR);
        if (panel()->exit == EX_END)
        {
            mode = M_WIN;
            overT = 0;
            say("ПУЛЬТ СПАСЁН. ШОУ ДОЛЖНО ПРОДОЛЖАТЬСЯ!", UNFIX(hero.x), UNFIX(hero.y) - 92, TRUE);
            SND_music(MUS_WIN);
            return;
        }
        static const char *const lines[] = { "ЧИСТО. ДАЛЬШЕ!", "ЛИНИЯ СВОБОДНА.", "САУНДЧЕК ПРОЙДЕН.", "СЛЕДУЮЩИЙ!" };
        say(lines[rnd(4)], UNFIX(hero.x), UNFIX(hero.y) - 92, TRUE);
        showArrow(panel()->exit);
    }
    if (exitOpen) checkExit();
    if (hero.st == S_DEAD && hero.t <= 0 && mode == M_PLAY)
    {
        mode = M_OVER;
        overT = 0;
        SND_music(MUS_OVER);
    }
}

static void stepPan(void)
{
    BG_step(panX, panY);
    panSteps--;
    // The hero leaps across the gutter into the next panel.
    const s16 total = panX ? 40 : 28, done = total - panSteps;
    hero.x = FIX(heroFlyX0 + (heroFlyX1 - heroFlyX0) * done / total);
    const s16 arc = (done * (total - done)) * 4 / total;
    const s16 wx = (panX ? (panX > 0 ? -CELL_W : CELL_W) * (total - done) / total : 0);
    const s16 wy = (panY ? -CELL_H * (total - done) / total : 0);
    hero.y = FIX(FLOOR_Y - arc);
    setFrame(&hero, A_JUMP, done < total / 2 ? 0 : 1);
    if (hero.spr)
        SPR_setPosition(hero.spr, cellX() + UNFIX(hero.x) + wx - BG_camX() - 48, cellY() + UNFIX(hero.y) + wy - BG_camY() - 92);
    if (panSteps == 0)
    {
        hero.y = FIX(FLOOR_Y);
        mode = M_PLAY;
        showArrow(-1);
        startPanel();
    }
}

static void stepTurn(void)
{
    // Page turn: a paper sheet sweeps over the page from the right, the next page loads underneath,
    // then the sheet keeps sweeping off to the left.
    if (turnPhase == 0)
    {
        turnCol--;
        BG_paperColumn(turnCol, TRUE);
        if (turnCol < 39) BG_paperColumn(turnCol + 1, FALSE);
        if (turnCol == 0)
        {
            BG_paperColumn(0, FALSE);
            turnPhase = 1;
            pageI++;
            panelI = 0;
            SYS_disableInts();
            BG_loadPage(story[pageI].art, cellX(), cellY());
            BG_paperAll();
            SYS_enableInts();
            loadPagePalette();
            PAL_setColors(0, palette, 64, DMA_QUEUE);
            turnCol = 40;
        }
    }
    else
    {
        turnCol--;
        BG_paperClearColumn(turnCol);
        if (turnCol > 0) BG_paperColumn(turnCol - 1, TRUE);
        if (turnCol == 0)
        {
            mode = M_PLAY;
            hero.x = FIX(40);
            hero.y = FIX(FLOOR_Y);
            SPR_setVisibility(hero.spr, VISIBLE);
            HUD_show(TRUE);
            startPanel();
        }
    }
}

#ifdef AUTOPLAY
// Test bot: walks to the nearest zombie and fights, then heads for the exit.
static u16 autopilot(void)
{
    if (mode == M_TITLE || mode == M_OVER || mode == M_WIN) return (frame & 32) ? BUTTON_START : 0;
    if (mode != M_PLAY) return 0;
    const s16 hx = UNFIX(hero.x);
    s16 best = -1, bd = 999;
    for (u16 i = 0; i < MAX_ENEMIES; i++)
        if (foe[i].on && foe[i].st != S_DEAD && foe[i].st != S_SPAWN && abs(UNFIX(foe[i].x) - hx) < bd) { bd = abs(UNFIX(foe[i].x) - hx); best = i; }
    if (best >= 0)
    {
        const s16 dx = UNFIX(foe[best].x) - hx;
        u16 j = 0;
        if (abs(dx) > 40) j |= dx > 0 ? BUTTON_RIGHT : BUTTON_LEFT;
        else
        {
            if ((dx > 0) != (hero.face > 0)) j |= dx > 0 ? BUTTON_RIGHT : BUTTON_LEFT;
            if ((frame & 7) == 0) j |= (frame & 32) ? BUTTON_A : BUTTON_B;
        }
        if (hero.hp < 8 && inv[0] && (frame & 63) == 0) j |= BUTTON_X;
        return j;
    }
    if (!exitOpen)
    {
        for (u16 i = 0; i < 2; i++) if (pick[i].on) return pick[i].x > hx ? BUTTON_RIGHT : BUTTON_LEFT;
        return 0;
    }
    switch (panel()->exit)
    {
        case EX_RIGHT: case EX_PAGE: return BUTTON_RIGHT;
        case EX_LEFT: return BUTTON_LEFT;
        case EX_DOWN: return abs(hx - 160) > 20 ? (hx < 160 ? BUTTON_RIGHT : BUTTON_LEFT) : BUTTON_DOWN;
    }
    return 0;
}
#endif

// ---------------------------------------------------------------------------- screens

static void title(void)
{
    releaseAll();
    if (hero.spr) SPR_setVisibility(hero.spr, HIDDEN);
    HUD_show(FALSE);
    TXT_clearCaption();
    TXT_clearBanner();
    pageI = 0;
    mode = M_TITLE;
    PAL_fadeOutAll(16, FALSE);
    SYS_disableInts();
    BG_loadPage(0, 0, 0);
    SYS_enableInts();
    memcpy(palette, BG_colors(), 32 * 2);
    memcpy(palette + 32, spr_hero.palette->data, 32);
    memcpy(palette + 48, spr_loader.palette->data, 32);
    PAL_fadeInAll(palette, 20, TRUE);
    SND_music(MUS_TITLE);
}

void GAME_run(void)
{
    JOY_init();
    title();
    while (TRUE)
    {
        joyPrev = joy;
        joy = JOY_readJoypad(JOY_1);
#ifdef AUTOPLAY
        joy = autopilot();
#endif
        pressed = joy & ~joyPrev;
        frame++;
        switch (mode)
        {
            case M_TITLE:
                if ((frame & 63) == 0) TXT_banner("НАЖМИ START", 22, C_WHITE, C_INK, FALSE);
                if ((frame & 63) == 44) TXT_clearBanner();
                if (pressed & (BUTTON_START | BUTTON_A | BUTTON_B | BUTTON_C)) { TXT_clearBanner(); newGame(); }
                break;
            case M_PLAY:
                if (pressed & BUTTON_START)
                {
                    mode = M_PAUSE;
                    TXT_banner("ПАУЗА", 12, C_INK, 0, TRUE);
                    SND_pause(TRUE);
                    break;
                }
                play();
                break;
            case M_PAUSE:
                if (pressed & BUTTON_START) { mode = M_PLAY; TXT_clearBanner(); SND_pause(FALSE); }
                break;
            case M_PAN:
                stepPan();
                break;
            case M_TURN:
                stepTurn();
                break;
            case M_OVER:
                overT++;
                if (overT == 30)
                {
                    u16 dim[64];
                    for (u16 i = 0; i < 64; i++) dim[i] = (palette[i] >> 1) & 0x0EEE;
                    PAL_fadeTo(0, 63, dim, 30, TRUE);
                    TXT_banner("ЗАНАВЕС", 10, C_RED, C_INK, TRUE);
                }
                if (overT > 60 && (pressed & (BUTTON_START | BUTTON_B))) { SND_music(MUS_GAME); restartPanel(); }
                break;
            case M_WIN:
                overT++;
                // The boss finishes falling while the hero celebrates.
                for (u16 i = 0; i < MAX_ENEMIES; i++) if (foe[i].on) updateEnemy(&foe[i]);
                if (hero.ground) setFrame(&hero, A_CHEER, 0);
                if (overT == 220)
                {
                    releaseAll();
                    SPR_setVisibility(hero.spr, HIDDEN);
                    HUD_show(FALSE);
                    TXT_clearCaption();
                    PAL_fadeOutAll(20, FALSE);
                    SYS_disableInts();
                    BG_loadPage(0, CELL_W, 0);
                    SYS_enableInts();
                    memcpy(palette, BG_colors(), 64);
                    PAL_fadeInAll(palette, 20, TRUE);
                }
                if (overT == 260) TXT_banner("ПУЛЬТ СПАСЁН. ШОУ ДОЛЖНО ПРОДОЛЖАТЬСЯ!", 18, C_YELLOW, C_INK, FALSE);
                if (overT > 280 && (pressed & BUTTON_START)) title();
                break;
        }
        if (mode == M_PLAY || mode == M_OVER || (mode == M_WIN && overT < 220))
        {
            place(&hero);
            for (u16 i = 0; i < MAX_ENEMIES; i++) if (foe[i].on) place(&foe[i]);
            updateFx();
            updateArrow();
        }
        if (flashT > 0)
        {
            flashT--;
            if (flashT & 2)
            {
                u16 w[64];
                for (u16 i = 0; i < 64; i++) w[i] = (palette[i] | 0x0888) & 0x0EEE;
                PAL_setColors(0, w, 64, DMA_QUEUE);
            }
            else PAL_setColors(0, palette, 64, DMA_QUEUE);
        }
#ifdef DEBUG_HUD
        if (mode != M_TITLE && (frame & 15) == 0)
        {
            char dbg[48];
            sprintf(dbg, "V%ld X%ld Y%ld A%ld T%ld", (long) hero.spr->visibility, (long) hero.spr->x, (long) hero.spr->y, (long) hero.spr->animInd, (long) hero.spr->attribut);
            TXT_banner(dbg, 14, C_WHITE, C_INK, FALSE);
        }
#endif
        SPR_update();
        SYS_doVBlankProcess();
    }
}
