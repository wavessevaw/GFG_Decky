"""Original chiptune soundtrack for the Mega Drive: a tiny tracker that writes VGM files
(YM2612 FM + SN76489 PSG register writes at 60 Hz), converted by SGDK's rescomp to XGM2.

Channels: FM1 bass, FM2/FM3 power-chord guitars, FM4 lead, FM5 FM kick drum, FM6 pad / harmony;
PSG 0-2 arpeggios and bells, PSG noise for snare and hi-hats.
"""
import math
import struct

YM_CLOCK = 7670453
PSG_CLOCK = 3579545
NOTE_NAMES = {'C': 0, 'C#': 1, 'DB': 1, 'D': 2, 'D#': 3, 'EB': 3, 'E': 4, 'F': 5, 'F#': 6, 'GB': 6, 'G': 7, 'G#': 8,
              'AB': 8, 'A': 9, 'A#': 10, 'BB': 10, 'B': 11}


def note_freq(name):
    """'E2', 'F#4', 'Bb3' -> Hz."""
    n = name.upper()
    octave = int(n[-1])
    pc = NOTE_NAMES[n[:-1]]
    midi = 12 * (octave + 1) + pc
    return 440.0 * 2 ** ((midi - 69) / 12)


# --- FM patches: alg, fb, ops [op1, op2, op3, op4] = (dt, mul, tl, rs, ar, d1r, d2r, sl, rr)
PATCHES = {
    'bass': (0, 5, [(0, 1, 30, 1, 31, 14, 2, 4, 8), (0, 2, 40, 1, 31, 10, 2, 3, 8),
                    (0, 1, 26, 1, 31, 12, 2, 3, 8), (0, 1, 2, 1, 31, 7, 3, 2, 10)]),
    'guitar': (0, 7, [(3, 1, 24, 1, 31, 6, 2, 2, 7), (0, 3, 30, 1, 31, 7, 2, 2, 7),
                      (0, 1, 22, 1, 31, 5, 2, 2, 7), (0, 1, 8, 1, 31, 3, 1, 1, 9)]),
    'lead': (4, 6, [(1, 1, 32, 1, 31, 6, 2, 3, 6), (0, 1, 10, 1, 28, 4, 1, 2, 7),
                    (2, 2, 36, 1, 31, 6, 2, 3, 6), (0, 1, 12, 1, 28, 4, 1, 2, 7)]),
    'kick': (7, 0, [(0, 1, 127, 0, 31, 0, 0, 0, 15), (0, 1, 127, 0, 31, 0, 0, 0, 15),
                    (0, 1, 127, 0, 31, 0, 0, 0, 15), (0, 1, 0, 0, 31, 18, 10, 6, 15)]),
    'pad': (5, 3, [(0, 1, 30, 0, 18, 2, 0, 1, 5), (0, 2, 20, 0, 16, 2, 0, 1, 5),
                   (3, 1, 22, 0, 16, 2, 0, 1, 5), (7, 1, 24, 0, 16, 2, 0, 1, 5)]),
    'bell': (4, 2, [(0, 7, 28, 1, 31, 10, 4, 4, 6), (0, 2, 14, 1, 31, 8, 3, 3, 6),
                    (0, 9, 34, 1, 31, 10, 4, 4, 6), (0, 1, 16, 1, 31, 8, 3, 3, 6)]),
}
SLOT_OFFSET = [0, 8, 4, 12]          # register offset for op1, op2, op3, op4
CARRIERS = {0: [3], 1: [3], 2: [3], 3: [3], 4: [1, 3], 5: [1, 2, 3], 6: [1, 2, 3], 7: [0, 1, 2, 3]}


class VGM:
    def __init__(self):
        self.data = bytearray()
        self.samples = 0
        self.loop_offset = None
        self.loop_samples = 0

    def ym(self, port, reg, val):
        self.data += bytes([0x52 + port, reg & 0xFF, val & 0xFF])

    def psg(self, val):
        self.data += bytes([0x50, val & 0xFF])

    def wait_frames(self, n):
        for _ in range(n):
            self.data += b'\x62'
            self.samples += 735

    def mark_loop(self):
        self.loop_offset = len(self.data)
        self.loop_start_samples = self.samples

    def bytes(self):
        body = bytes(self.data) + b'\x66'
        hdr = bytearray(0x40)
        hdr[0:4] = b'Vgm '
        struct.pack_into('<I', hdr, 0x04, 0x40 + len(body) - 4)
        struct.pack_into('<I', hdr, 0x08, 0x150)
        struct.pack_into('<I', hdr, 0x0C, PSG_CLOCK)
        struct.pack_into('<I', hdr, 0x18, self.samples)
        if self.loop_offset is not None:
            struct.pack_into('<I', hdr, 0x1C, 0x40 + self.loop_offset - 0x1C)
            struct.pack_into('<I', hdr, 0x20, self.samples - self.loop_start_samples)
        struct.pack_into('<I', hdr, 0x24, 60)
        struct.pack_into('<H', hdr, 0x28, 0x0009)
        hdr[0x2A] = 16
        struct.pack_into('<I', hdr, 0x2C, YM_CLOCK)
        struct.pack_into('<I', hdr, 0x34, 0x40 - 0x34)
        return bytes(hdr) + body


class FMChannel:
    def __init__(self, vgm, ch):
        self.v, self.ch = vgm, ch
        self.port, self.c = (0, ch) if ch < 3 else (1, ch - 3)
        self.patch = None
        self.vol = 0

    def set_patch(self, name, vol=0):
        alg, fb, ops = PATCHES[name]
        self.patch = (alg, fb, ops)
        self.vol = vol
        v, p, c = self.v, self.port, self.c
        v.ym(p, 0xB0 + c, (fb << 3) | alg)
        v.ym(p, 0xB4 + c, 0xC0)
        for i, (dt, mul, tl, rs, ar, d1r, d2r, sl, rr) in enumerate(ops):
            o = SLOT_OFFSET[i] + c
            if i in CARRIERS[alg]:
                tl = min(127, tl + vol)
            v.ym(p, 0x30 + o, (dt << 4) | mul)
            v.ym(p, 0x40 + o, tl)
            v.ym(p, 0x50 + o, (rs << 6) | ar)
            v.ym(p, 0x60 + o, d1r)
            v.ym(p, 0x70 + o, d2r)
            v.ym(p, 0x80 + o, (sl << 4) | rr)
            v.ym(p, 0x90 + o, 0)

    def freq(self, hz):
        block = 0
        fnum = hz * (1 << 20) / (YM_CLOCK / 144.0)
        while fnum > 0x7FF and block < 7:
            fnum /= 2
            block += 1
        fnum = int(fnum)
        self.v.ym(self.port, 0xA4 + self.c, (block << 3) | (fnum >> 8))
        self.v.ym(self.port, 0xA0 + self.c, fnum & 0xFF)

    def key(self, on):
        chbits = self.c + (4 if self.port else 0)
        self.v.ym(0, 0x28, (0xF0 if on else 0) | chbits)


class PSGChannel:
    def __init__(self, vgm, ch):
        self.v, self.ch = vgm, ch

    def tone(self, hz):
        n = max(1, min(1023, int(PSG_CLOCK / (32 * hz))))
        self.v.psg(0x80 | (self.ch << 5) | (n & 0xF))
        self.v.psg((n >> 4) & 0x3F)

    def volume(self, att):
        self.v.psg(0x90 | (self.ch << 5) | (att & 0xF))

    def noise(self, mode):
        self.v.psg(0xE0 | mode)


def parse(track):
    """'E2 . E2 - G2 ...' -> list of tokens per step."""
    return track.split()


def render(song, frames_per_step):
    """song: dict(sections=[...], loop_from=i). Each section: dict(steps, channels={name: tokens}, repeat)."""
    v = VGM()
    fm = [FMChannel(v, i) for i in range(6)]
    psg = [PSGChannel(v, i) for i in range(4)]
    v.ym(0, 0x22, 0)     # LFO off
    v.ym(0, 0x27, 0)     # ch3 normal mode
    v.ym(0, 0x2B, 0)     # DAC off
    for i in range(6):
        fm[i].key(False)
    for i in range(4):
        psg[i].volume(15)
    patches = song['patches']
    for i, (name, vol) in patches.items():
        fm[i].set_patch(name, vol)
    kick_t = -1
    noise_t, noise_kind = -1, None
    psg_env = [99, 99, 99]
    for si, sec in enumerate(song['sections']):
        if si == song.get('loop_from', 0):
            v.mark_loop()
        steps = sec['steps']
        for _ in range(sec.get('repeat', 1)):
            for st in range(steps):
                for f in range(frames_per_step):
                    if f == 0:
                        for key, toks in sec['channels'].items():
                            tok = toks[st % len(toks)]
                            if key.startswith('fm'):
                                chs = [int(x) for x in key[2:].split('+')]
                                for ci, c in enumerate(chs):
                                    ch = fm[c]
                                    if tok == '.':
                                        ch.key(False)
                                    elif tok != '-':
                                        notes = tok.split('/')
                                        n = notes[ci % len(notes)]
                                        ch.key(False)
                                        ch.freq(note_freq(n))
                                        ch.key(True)
                            elif key == 'kick':
                                if tok == 'x':
                                    kick_t = 0
                                    fm[4].key(False)
                                    fm[4].key(True)
                            elif key == 'noise':
                                if tok in ('s', 'h', 'o', 'c'):
                                    noise_t, noise_kind = 0, tok
                            elif key.startswith('psg'):
                                c = int(key[3:])
                                if tok == '.':
                                    psg[c].volume(15)
                                    psg_env[c] = 99
                                elif tok != '-':
                                    psg[c].tone(note_freq(tok))
                                    psg_env[c] = 0
                    # Per-frame envelopes: FM kick pitch drop, noise drums, PSG plucks.
                    if kick_t >= 0:
                        fm[4].freq(max(40, 160 * math.exp(-kick_t * 0.55)))
                        kick_t += 1
                        if kick_t > 8:
                            fm[4].key(False)
                            kick_t = -1
                    if noise_t >= 0:
                        if noise_kind == 's':
                            if noise_t == 0:
                                psg[3].noise(4 | 1)
                            att = min(15, 1 + noise_t * 2)
                        elif noise_kind == 'c':
                            if noise_t == 0:
                                psg[3].noise(4 | 0)
                            att = min(15, 2 + noise_t)
                        else:
                            if noise_t == 0:
                                psg[3].noise(4 | 0)
                            att = min(15, 5 + noise_t * (5 if noise_kind == 'h' else 2))
                        psg[3].volume(att)
                        noise_t += 1
                        if att >= 15:
                            noise_t = -1
                    for c in range(3):
                        if psg_env[c] < 99:
                            att = min(15, 3 + psg_env[c] // 2)
                            psg[c].volume(att)
                            psg_env[c] += 1
                    v.wait_frames(1)
    if not song.get('loop', True):
        for i in range(6):
            fm[i].key(False)
        for i in range(4):
            psg[i].volume(15)
        v.wait_frames(30)
        v.loop_offset = None
    return v.bytes()


def rep(pattern, n):
    return (pattern + ' ') * n


# ------------------------------------------------------------------ songs (all original)

# Main theme "Саундчек мёртвых": E minor chug riff, 150 BPM, 16th = 6 frames.
RIFF_A = 'E2 E2 . E2 E2 . G2 . E2 E2 . A2 . G2 . F#2'
RIFF_B = 'E2 E2 . E2 E2 . G2 . A#2 - A2 - G2 . F#2 .'
GTR_A = 'E3/B3 E3/B3 . E3/B3 E3/B3 . G3/D4 . E3/B3 E3/B3 . A3/E4 . G3/D4 . F#3/C#4'
GTR_B = 'E3/B3 E3/B3 . E3/B3 E3/B3 . G3/D4 . A#3/F4 - A3/E4 - G3/D4 . F#3/C#4 .'
DR_A = 'x . . x x . . . x . . x x . . .'
SN_A = 'c h h h s h h h c h h h s h h h'
SN_FILL = 'c h s h s h s s s s s s s s s s'
LEAD_B1 = 'B4 - - - A4 - G4 - F#4 - - - E4 - - - G4 - A4 - B4 - D5 - C5 - - - B4 - - -'
LEAD_B2 = 'E5 - - - D5 - B4 - C5 - - - B4 - A4 - G4 - - - F#4 - G4 - E4 - - - - - . .'
BASS_B = 'C2 C2 . C2 C2 . C2 C2 D2 D2 . D2 D2 . D2 D2 E2 E2 . E2 E2 . E2 E2 B1 B1 . B1 B1 . B1 B1'
GTR_B2 = 'C3/G3 - - C3/G3 - - C3/G3 - D3/A3 - - D3/A3 - - D3/A3 - E3/B3 - - E3/B3 - - E3/B3 - B2/F#3 - - B2/F#3 - - B2/F#3 -'
ARP = 'E5 B4 G4 B4 E5 B4 G4 B4 E5 C5 G4 C5 E5 C5 G4 C5'

GAME = dict(
    patches={0: ('bass', 0), 1: ('guitar', 4), 2: ('guitar', 6), 3: ('lead', 2), 4: ('kick', 0), 5: ('pad', 10)},
    sections=[
        dict(steps=16, repeat=2, channels={'fm0': parse(RIFF_A), 'kick': parse(DR_A), 'noise': parse('h . h . h . h . h . h . h . h .')}),
        dict(steps=32, repeat=2, channels={'fm0': parse(RIFF_A + ' ' + RIFF_B), 'fm1+2': parse(GTR_A + ' ' + GTR_B),
                                           'kick': parse(DR_A), 'noise': parse(SN_A)}),
        dict(steps=32, repeat=2, channels={'fm0': parse(BASS_B), 'fm1+2': parse(GTR_B2), 'fm3': parse(LEAD_B1 if True else ''),
                                           'kick': parse('x . . . x . . . x . . . x . . .'), 'noise': parse(SN_A),
                                           'psg0': parse(ARP)}),
        dict(steps=32, repeat=1, channels={'fm0': parse(BASS_B), 'fm1+2': parse(GTR_B2), 'fm3': parse(LEAD_B2),
                                           'kick': parse('x . . . x . . . x . . . x . x .'), 'noise': parse(SN_A + ' ' + SN_FILL),
                                           'psg0': parse(ARP)}),
    ],
    loop_from=1,
)

TITLE = dict(
    patches={0: ('bass', 4), 1: ('pad', 2), 2: ('pad', 4), 3: ('bell', 6), 4: ('kick', 4), 5: ('pad', 8)},
    sections=[
        dict(steps=64, repeat=2, channels={
            'fm1+2+5': parse('E3/G3/B3 - - - - - - - - - - - - - - - C3/E3/G3 - - - - - - - - - - - - - - - '
                             'A2/C3/E3 - - - - - - - - - - - - - - - B2/D#3/F#3 - - - - - - - - - - - - - - -'),
            'fm0': parse('E2 - - - - - - - . . . . E2 - D2 - C2 - - - - - - - . . . . C2 - B1 - '
                         'A1 - - - - - - - . . . . A1 - B1 - B1 - - - - - - - . . . . B1 - D#2 -'),
            'fm3': parse('E5 . . . B4 . . . G4 . . . B4 . . . E5 . . . C5 . . . G4 . . . C5 . . . '
                         'E5 . . . C5 . . . A4 . . . C5 . . . F#5 . . . D#5 . . . B4 . . . D#5 . . .'),
            'kick': parse('x . . . . . . . . . . . . . . . x . . . . . . . . . . . . . . . '),
            'noise': parse('. . . . . . . . s . . . . . . . . . . . . . . . s . . . . . h h'),
        }),
    ],
    loop_from=0,
)

OVER = dict(
    patches={0: ('bass', 0), 1: ('lead', 2), 2: ('pad', 6), 3: ('lead', 6), 4: ('kick', 0), 5: ('pad', 10)},
    sections=[dict(steps=24, channels={
        'fm1': parse('E4 - - B3 - - G3 - - E3 - - - - - - - - - - - - . .'),
        'fm0': parse('E2 - - - - - C2 - - - - - B1 - - - - - E1 - - - - .'),
        'fm2': parse('E3/G3 - - - - - C3/E3 - - - - - B2/D#3 - - - - - E2/B2 - - - - .'),
        'kick': parse('x . . . . . x . . . . . x . . . . . x . . . . .'),
    })],
    loop=False,
)

WIN = dict(
    patches={0: ('bass', 0), 1: ('guitar', 4), 2: ('guitar', 6), 3: ('lead', 0), 4: ('kick', 0), 5: ('bell', 6)},
    sections=[dict(steps=32, channels={
        'fm3': parse('E4 G#4 B4 E5 - - B4 E5 F#5 - - - E5 - - - A4 C#5 E5 A5 - - E5 A5 B5 - - - - - - .'),
        'fm1+2': parse('E3/B3 - - - - - - - D3/A3 - - - - - - - A2/E3 - - - - - - - B2/F#3 - - - - - - .'),
        'fm0': parse('E2 - E2 - E2 - E2 - D2 - D2 - D2 - D2 - A1 - A1 - A1 - A1 - B1 - B1 - B1 - - .'),
        'kick': parse('x . . . x . . . x . . . x . . . x . . . x . . . x . x . x . . .'),
        'noise': parse('c h s h c h s h c h s h c h s h c h s h c h s h c s s s s s c .'),
        'fm5': parse('E6 . B5 . E6 . B5 . D6 . A5 . D6 . A5 . E6 . C#6 . E6 . A5 . F#6 . D#6 . B5 . . .'),
    })],
    loop=False,
)

SONGS = {'mus_game': (GAME, 6), 'mus_title': (TITLE, 8), 'mus_over': (OVER, 8), 'mus_win': (WIN, 6)}


def build(out_dir):
    import os
    names = []
    for name, (song, fps) in SONGS.items():
        data = render(song, fps)
        open(os.path.join(out_dir, name + '.vgm'), 'wb').write(data)
        names.append(name)
    return names
