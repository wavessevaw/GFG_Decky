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
static s16 panTX, panTY, panTotal, panDone;   // camera target, steps
static s16 turnCol, turnPhase;
static u16 palette[64];
static u16 overT;
static s16 flyX0, flyY0, flyX1, flyY1;        // hero leap across the gutter, page coordinates
static s16 flashT;
static bool cycling;
// A new game is a fresh run: page order, start panel, enemies, items and obstacles are rolled each time.
static u8 order[STORY_PAGES], runStep;
typedef struct { bool on; u8 kind; s16 x, w, top, hp; Sprite *spr; } Prop;   // kind 0 road case, 1 oil drum
#define MAX_PROPS 2
static Prop prop[MAX_PROPS];
static Spawn rolled[6];
static u8 rolledN;
static ItemDef rolledItem;
static bool rolledHasItem;                    // page palette has running-water / chase-light colours
static Sprite *arrow;
static s16 arrowDir = -1;

static const SpriteDefinition *const zdef[4] = { &spr_loader, &spr_fan, &spr_singer, &spr_boss };
static const s16 zmaxhp[4] = { 5, 3, 6, 34 };
static const s32 zspeed[4] = { FIXF(0.6), FIXF(1.4), FIXF(0.47), FIXF(0.82) };   // px/frame
static const s16 zdamage[4] = { 2, 1, 2, 3 };

static const PanelDef *panel(void) { return &story[pageI].panel[panelI]; }
static bool lastPanel(void) { return panelI == story[pageI].panels - 1; }
static bool bossPanel(void) { return runStep == STORY_PAGES - 1 && lastPanel(); }
static u8 exitOf(void) { return lastPanel() ? (bossPanel() ? EX_END : EX_PAGE) : exitOf(); }
static const PanelRect *rect(void) { return &pages[story[pageI].art].panel[panelI]; }
static s16 cellX(void) { return rect()->x; }
static s16 cellY(void) { return rect()->y; }
static s16 panelW(void) { return rect()->w; }
static s16 floorY(void) { return rect()->floor; }

// Camera for a panel: centred on it (a little low: the HUD sits over the top rows), inside the page.
static void camFor(const PageData *pg, const PanelRect *r, s16 *cx, s16 *cy)
{
    s16 x = r->x + r->w / 2 - 160, y = r->y + r->h / 2 - 124;
    const s16 mx = pg->tw * 8 - 320, my = pg->th * 8 - 224;
    if (x > mx) x = mx;
    if (y > my) y = my;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    *cx = x & ~7;
    *cy = y & ~7;
}

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
    TXT_bubble(s, cellX() + x, cellY() + headY - 4, cellX() + 2, cellX() + panelW() - 2, isHero);
    bubbleLife = 150;
}


// Release a sprite exactly once: a double release corrupts SGDK's sprite pool (two objects end up sharing one slot).
static void dropSpr(Sprite **s)
{
    if (*s) SPR_releaseSprite(*s);
    *s = NULL;
}

static void clearFx(void)
{
    for (u16 i = 0; i < MAX_FX; i++)
        if (fx[i].on) { dropSpr(&fx[i].spr); fx[i].on = FALSE; }
    for (u16 i = 0; i < MAX_SHOTS; i++)
        if (shot[i].on) { dropSpr(&shot[i].spr); shot[i].on = FALSE; }
    TXT_clearBubble();
    bubbleLife = 0;
}

// ---------------------------------------------------------------------------- actors

static s16 heightOf(const Actor *a) { return a->kind == K_BOSS ? 104 : 80; }
static s16 halfW(const Actor *a) { return a->kind == K_BOSS ? 20 : 13; }

static void physics(Actor *a)
{
    const s32 oldY = a->y, oldX = a->x;
    a->vy += FIXF(0.36);                // gravity, px/frame²
    if (a->vy > FIX(9)) a->vy = FIX(9);
    a->x += a->vx;
    a->y += a->vy;
    a->ground = FALSE;
    if (a->y >= FIX(floorY()))
    {
        a->y = FIX(floorY());
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
    // Obstacles: the hero stands on top of them and cannot walk through them.
    if (a->kind == K_HERO)
    {
        const s16 x = UNFIX(a->x);
        for (u16 i = 0; i < MAX_PROPS; i++)
        {
            const Prop *o = &prop[i];
            if (!o->on) continue;
            const s16 x0 = o->x - o->w / 2, x1 = o->x + o->w / 2;
            if (a->vy >= 0 && x > x0 - 4 && x < x1 + 4 && oldY <= FIX(o->top) && a->y >= FIX(o->top))
            {
                a->y = FIX(o->top);
                a->vy = 0;
                a->ground = TRUE;
            }
            else if (a->y > FIX(o->top + 2) && x > x0 - 10 && x < x1 + 10)
            {
                a->x = UNFIX(oldX) < o->x ? FIX(x0 - 10) : FIX(x1 + 10);
                a->vx = 0;
            }
        }
    }
    s16 minX = 14, maxX = panelW() - 14;
    if (a->kind == K_HERO && exitOpen)
    {
        const u8 e = exitOf();
        if (e == EX_RIGHT || e == EX_PAGE) maxX = panelW() + 6;
        if (e == EX_LEFT) minX = -6;
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
    // A well-timed punch knocks a singer's sound wave out of the air (the boss's feedback is too big to stop).
    for (u16 i = 0; i < MAX_SHOTS; i++)
    {
        Shot *s = &shot[i];
        const s16 sx = UNFIX(s->x);
        if (!s->on || s->big || sx + 12 < zx0 || sx - 12 > zx1 || s->y < zy0 - 12 || s->y > zy1 + 12) continue;
        s->life = 0;
        burst(1, sx, s->y);
        hit = TRUE;
    }
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
    // Oil drums break after a few blows and may leave an item behind.
    for (u16 i = 0; i < MAX_PROPS; i++)
    {
        Prop *o = &prop[i];
        if (!o->on || o->kind != 1 || o->x + 13 < zx0 || o->x - 13 > zx1 || o->top > zy1) continue;
        o->hp--;
        hit = TRUE;
        burst(o->hp ? 1 : 2, o->x, o->top - 10);
        SND_play(o->hp ? SFX_HIT : SFX_BIGHIT);
        if (o->hp <= 0)
        {
            dropSpr(&o->spr);
            o->on = FALSE;
            for (u16 k = 0; k < 2; k++)
            {
                Pickup *p = &pick[k];
                if (p->on || rnd(3) == 0) continue;
                p->on = TRUE;
                p->taken = FALSE;
                p->kind = 1 + rnd(3);
                p->x = o->x;
                p->y = floorY();
                p->spr = SPR_addSprite(&spr_item, 0, 0, TILE_ATTR(PAL0, FALSE, FALSE, FALSE));
                if (p->spr) SPR_setAnim(p->spr, p->kind - 1);
                break;
            }
        }
        break;
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
        if (x == 0) x = 22;
        if (x >= 999) x = panelW() - 22;
        e->x = FIX(x);
        e->y = FIX(floorY());
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
            say("ФИДБЭК: ТЕСТ… РАЗ… ДВА… ВЫ УВОЛЕНЫ!", x, floorY() - 116, FALSE);
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
            // Singers back off only right after a shot, so they can be cornered.
            if (k == K_SINGER && adx < 80 && e->st != S_WIND && e->cool > 30) { e->vx = -e->face * zspeed[k]; e->st = S_WALK; e->anim++; }
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
        dropSpr(&e->spr);
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
        if (s->life <= 0 || x < -20 || x > panelW() + 20)
        {
            dropSpr(&s->spr);
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
            if (f->spr) dropSpr(&f->spr);
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
            dropSpr(&p->spr);
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
    if (arrow) { dropSpr(&arrow); arrow = NULL; }
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
    s16 x = arrowDir == EX_LEFT ? 12 : arrowDir == EX_DOWN ? panelW() / 2 - 16 : panelW() - 44;
    s16 y = (arrowDir == EX_DOWN ? floorY() - 64 + ((frame >> 3) & 3) : floorY() - 84);
    if (arrowDir != EX_DOWN) x += ((frame >> 3) & 3) * (arrowDir == EX_LEFT ? -1 : 1);
    SPR_setPosition(arrow, cellX() + x - BG_camX(), cellY() + y - BG_camY());
    SPR_setVisibility(arrow, (frame & 16) ? VISIBLE : HIDDEN);
}

static void releaseAll(void)
{
    for (u16 i = 0; i < MAX_PROPS; i++)
        if (prop[i].on) { dropSpr(&prop[i].spr); prop[i].on = FALSE; }
    for (u16 i = 0; i < MAX_ENEMIES; i++)
        if (foe[i].on) { if (foe[i].spr) dropSpr(&foe[i].spr); foe[i].on = FALSE; }
    for (u16 i = 0; i < 2; i++)
        if (pick[i].spr) { dropSpr(&pick[i].spr); pick[i].spr = NULL; pick[i].on = FALSE; }
    clearFx();
}

// Enemies, an item and obstacles are rolled for every panel of a run.
static void rollPanel(void)
{
    if (bossPanel())
    {
        rolled[0] = (Spawn) { K_BOSS, 999, 60 };
        rolledN = 1;
        if (rnd(2)) { rolled[1] = (Spawn) { K_FAN, 0, 200 }; rolledN = 2; }
    }
    else
    {
        rolledN = 2 + rnd(2) + runStep + (panelI > 2 ? 1 : 0);
        if (rolledN > 5) rolledN = 5;
        u16 t = 30 + rnd(40);
        for (u16 i = 0; i < rolledN; i++)
        {
            const u16 r = rnd(10);
            const u8 k = r < 4 ? K_FAN : r < 7 ? K_LOADER : K_SINGER;
            rolled[i] = (Spawn) { k, rnd(2) ? 999 : 0, t };
            t += 70 + rnd(90);
        }
    }
    rolledHasItem = rnd(10) < 7;
    rolledItem = (ItemDef) { 1 + rnd(3), 0, 0 };
    if (rolledItem.kind != IT_TAPE && rnd(2)) rolledItem.kind = IT_TAPE;
}

static void placeProps(void)
{
    for (u16 i = 0; i < MAX_PROPS; i++) prop[i].on = FALSE;
    const u16 n = panelW() >= 260 ? rnd(3) : rnd(2);
    s16 used = -999;
    for (u16 i = 0; i < n; i++)
    {
        Prop *o = &prop[i];
        o->kind = rnd(3) == 0 ? 0 : 1;
        o->w = o->kind == 0 ? 56 : 26;
        s16 x = 80 + rnd(panelW() - 170);
        if (abs(x - used) < 80) x = used + (x > used ? 90 : -90);
        if (x < 70 || x > panelW() - 80) continue;
        used = x;
        o->x = x;
        o->top = floorY() - (o->kind == 0 ? 36 : 34);
        o->hp = 3;
        o->spr = SPR_addSprite(&spr_prop, 0, 0, TILE_ATTR(PAL2, FALSE, FALSE, FALSE));
        if (!o->spr) continue;
        SPR_setAnim(o->spr, o->kind);
        SPR_setDepth(o->spr, 100);
        o->on = TRUE;
    }
}

static void updateProps(void)
{
    for (u16 i = 0; i < MAX_PROPS; i++)
        if (prop[i].on)
            SPR_setPosition(prop[i].spr, cellX() + prop[i].x - 32 - BG_camX(), cellY() + floorY() - 46 - BG_camY());
}

static void startPanel(void)
{
    const PanelDef *p = panel();
    releaseAll();
    plats = rect()->plat;
    platN = rect()->nplat;
    rollPanel();
#ifdef NOENEMY
    pendingN = 0;
#else
    pendingN = rolledN;
#endif
    memcpy(pending, rolled, sizeof(Spawn) * rolledN);
    exitOpen = FALSE;
    placeProps();
    for (u16 i = 0; i < (rolledHasItem ? 1 : 0); i++)
    {
        Pickup *k = &pick[i];
        k->on = TRUE;
        k->taken = FALSE;
        k->kind = rolledItem.kind;
        if (platN)
        {
            // On top of the highest platform (reward for climbing).
            u16 best = 0;
            for (u16 j = 1; j < platN; j++) if (plats[j].y < plats[best].y) best = j;
            k->x = plats[best].x + plats[best].w / 2;
            k->y = plats[best].y;
        }
        else
        {
            k->x = panelW() / 2;
            k->y = floorY();
        }
        k->spr = SPR_addSprite(&spr_item, 0, 0, TILE_ATTR(PAL0, FALSE, FALSE, FALSE));
        if (k->spr) SPR_setAnim(k->spr, k->kind - 1);
    }
    hero.vx = 0;
    hero.vy = 0;
    if (hero.st != S_DEAD) hero.st = S_IDLE;
    BG_setWater(rect()->water ? cellY() + rect()->water : -1, cellY() + rect()->h);
    TXT_caption(p->caption);
    if (bossPanel() && story[pageI].panel[panelI].exit != EX_END)
        say("ФИДБЭК ИДЁТ ЗА МНОЙ… ПУЛЬТ У НЕГО!", UNFIX(hero.x), UNFIX(hero.y) - 92, TRUE);
    else
        say(p->line, UNFIX(hero.x), UNFIX(hero.y) - 92, TRUE);
    HUD_page(pageI, panelI);
}

static void loadPagePalette(void)
{
    cycling = TRUE;
    memcpy(palette, BG_colors(), 32 * 2);
    memcpy(palette + 32, spr_hero.palette->data, 16 * 2);
    memcpy(palette + 48, spr_loader.palette->data, 16 * 2);
}

static void enterPage(u16 p, u16 startAt, bool fade)
{
    pageI = p;
#ifdef START_PANEL
    panelI = START_PANEL;
#else
    panelI = startAt;
#endif
    if (fade) PAL_fadeOutAll(16, FALSE);
    SYS_disableInts();
    s16 cx, cy;
    camFor(&pages[story[p].art], rect(), &cx, &cy);
    BG_loadPage(story[p].art, cx, cy);
    SYS_enableInts();
    loadPagePalette();
    if (fade) PAL_fadeInAll(palette, 16, TRUE);
    else PAL_setColors(0, palette, 64, CPU);
}

static void newGame(void)
{
    Sprite *keep = hero.spr;   // the hero's sprite lives for the whole session; re-adding it would leak one per game
    memset(&hero, 0, sizeof(hero));
    hero.spr = keep;
    hero.on = TRUE;
    hero.kind = K_HERO;
    hero.x = FIX(60);
    hero.y = FIX(floorY());
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
    // Roll the run: which location comes first, and where in it the hero lands.
    setRandomSeed(frame ^ GET_HVCOUNTER ^ (joy << 3));
    order[0] = rnd(STORY_PAGES);
    for (u16 i = 1; i < STORY_PAGES; i++) order[i] = (order[0] + i) % STORY_PAGES;
    runStep = 0;
#ifdef START_PAGE
    order[0] = START_PAGE;
    order[1] = 1 - START_PAGE;
#endif
    enterPage(order[0], rnd(3), TRUE);
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
    hero.y = FIX(floorY());
    TXT_clearBanner();
    PAL_fadeInAll(palette, 20, TRUE);
    HUD_health(hero.hp, HERO_HP);
    mode = M_PLAY;
    startPanel();
}

static void checkExit(void)
{
    const s16 x = UNFIX(hero.x);
    bool leave = FALSE;
    const u8 ex = exitOf();
    switch (ex)
    {
        case EX_RIGHT: case EX_PAGE: leave = x >= panelW() + 2; break;
        case EX_LEFT: leave = x <= -2; break;
        case EX_DOWN: leave = abs(x - panelW() / 2) < 70 && hero.ground && UNFIX(hero.y) == floorY() && (joy & BUTTON_DOWN); break;
    }
    if (!leave) return;
    releaseAll();
    showArrow(-1);
    TXT_clearCaption();
    if (ex == EX_PAGE)
    {
        mode = M_TURN;
        turnCol = 40;
        turnPhase = 0;
        HUD_show(FALSE);
        SPR_setVisibility(hero.spr, HIDDEN);
        SND_play(SFX_PAGE);
        return;
    }
    // Leap from the exit point of this panel to the entry point of the next one.
    flyX0 = cellX() + x;
    flyY0 = cellY() + UNFIX(hero.y);
    panelI++;
    s16 entry = ex == EX_RIGHT ? 30 : ex == EX_LEFT ? panelW() - 30 : flyX0 - cellX();
    if (entry < 30) entry = 30;
    if (entry > panelW() - 30) entry = panelW() - 30;
    flyX1 = cellX() + entry;
    flyY1 = cellY() + floorY();
    camFor(&pages[story[pageI].art], rect(), &panTX, &panTY);
    panTotal = (abs(panTX - BG_camX()) + abs(panTY - BG_camY())) >> 3;
    if (panTotal == 0) panTotal = 1;
    panDone = 0;
    BG_setWater(-1, -1);
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
        if (exitOf() == EX_END)
        {
            mode = M_WIN;
            overT = 0;
            say("ПУЛЬТ СПАСЁН. ШОУ ДОЛЖНО ПРОДОЛЖАТЬСЯ!", UNFIX(hero.x), UNFIX(hero.y) - 92, TRUE);
            SND_music(MUS_WIN);
            return;
        }
        static const char *const lines[] = { "ЧИСТО. ДАЛЬШЕ!", "ЛИНИЯ СВОБОДНА.", "САУНДЧЕК ПРОЙДЕН.", "СЛЕДУЮЩИЙ!" };
        say(lines[rnd(4)], UNFIX(hero.x), UNFIX(hero.y) - 92, TRUE);
        showArrow(exitOf());
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
    // Camera glides one tile per frame: across first, then up or down.
    if (BG_camX() != panTX) BG_step(panTX > BG_camX() ? 1 : -1, 0);
    else if (BG_camY() != panTY) BG_step(0, panTY > BG_camY() ? 1 : -1);
    panDone++;
    const s16 t = min(panDone, panTotal);
    const s16 px = flyX0 + (s32) (flyX1 - flyX0) * t / panTotal;
    const s16 arc = (s32) t * (panTotal - t) * 6 / panTotal;
    const s16 py = flyY0 + (s32) (flyY1 - flyY0) * t / panTotal - arc;
    setFrame(&hero, A_JUMP, t < panTotal / 2 ? 0 : 1);
    if (hero.spr) SPR_setPosition(hero.spr, px - BG_camX() - 48, py - BG_camY() - 92);
    if (BG_camX() == panTX && BG_camY() == panTY && panDone >= panTotal)
    {
        hero.x = FIX(flyX1 - cellX());
        hero.y = FIX(floorY());
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
            runStep++;
            pageI = order[runStep];
            panelI = 0;
            SYS_disableInts();
            s16 cx, cy;
            camFor(&pages[story[pageI].art], rect(), &cx, &cy);
            BG_loadPage(story[pageI].art, cx, cy);
            // The camera jumped: wipe the whole sheet layer, then cover the new view again.
            VDP_clearPlane(BG_A, TRUE);
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
            hero.y = FIX(floorY());
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
    static s16 lastX, stuck, dropDir;
    const s16 cx = UNFIX(hero.x);
    stuck = (cx == lastX) ? stuck + 1 : 0;
    lastX = cx;
    const u16 hop = stuck > 6 ? BUTTON_C : 0;
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
        if (UNFIX(hero.y) < UNFIX(foe[best].y) - 20)   // on a platform: walk off towards the foe, or the other way if blocked
        {
            if (dropDir == 0 || stuck > 6) dropDir = (stuck > 6) ? -dropDir : (dx > 0 ? 1 : -1);
            if (dropDir == 0) dropDir = 1;
            return dropDir > 0 ? BUTTON_RIGHT : BUTTON_LEFT;
        }
        dropDir = 0;
        for (u16 i = 0; i < MAX_SHOTS; i++)   // a sound wave incoming: punch it away
            if (shot[i].on && !shot[i].big && abs(UNFIX(shot[i].x) - hx) < 44 && ((shot[i].vx > 0) == (UNFIX(shot[i].x) < hx)))
            {
                const bool right = UNFIX(shot[i].x) > hx;
                if (right != (hero.face > 0)) return right ? BUTTON_RIGHT : BUTTON_LEFT;
                return (frame & 3) == 0 ? BUTTON_A : 0;
            }
        for (u16 i = 0; i < MAX_PROPS; i++)   // an oil drum in the way: smash it
            if (prop[i].on && prop[i].kind == 1 && ((prop[i].x - hx) > 0) == (dx > 0) && abs(prop[i].x - hx) < 40 && abs(prop[i].x - hx) < abs(dx))
            {
                if ((dx > 0) != (hero.face > 0)) return dx > 0 ? BUTTON_RIGHT : BUTTON_LEFT;
                return (frame & 7) == 0 ? BUTTON_A : 0;
            }
        if (abs(dx) > 40) j |= (dx > 0 ? BUTTON_RIGHT : BUTTON_LEFT) | hop | (abs(dx) < 120 && (frame & 31) == 0 ? BUTTON_C : 0);
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
    switch (exitOf())
    {
        case EX_RIGHT: case EX_PAGE: return BUTTON_RIGHT | hop;
        case EX_LEFT: return BUTTON_LEFT | hop;
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
    cycling = FALSE;
    BG_setWater(-1, -1);
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
                    BG_loadPage(0, pages[0].panel[1].x, 0);
                    SYS_enableInts();
                    memcpy(palette, BG_colors(), 64);
                    cycling = FALSE;
                    BG_setWater(-1, -1);
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
            updateProps();
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
            sprintf(dbg, "M%d V%ld X%d Y%d P%d E%d", (int) mode, (long) hero.spr->visibility, UNFIX(hero.x), UNFIX(hero.y), (int) panelI, (int) exitOpen);
            TXT_banner(dbg, 14, C_WHITE, C_INK, FALSE);
        }
#endif
        BG_animate(frame);
        // Running water and chasing lights: rotate the three cycling colours of palette 1 (13..15).
        if (cycling && (frame % 6) == 0 && !PAL_isDoingFade() && flashT == 0)
        {
            const u16 t = palette[29];
            palette[29] = palette[30];
            palette[30] = palette[31];
            palette[31] = t;
            PAL_setColors(29, &palette[29], 3, DMA_QUEUE);
        }
        SPR_update();
        SYS_doVBlankProcess();
    }
}
