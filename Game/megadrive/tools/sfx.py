"""Sound effects synthesised as 8-bit PCM for the XGM2 driver (3 PCM channels mixed by the Z80)."""
import math
import os
import wave
import numpy as np

RATE = 13300


def t(sec):
    return np.arange(int(RATE * sec)) / RATE


def env(n, attack=0.002, decay=0.1, curve=2.0):
    x = np.arange(n) / RATE
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    d = np.exp(-x / max(decay, 1e-4) * curve)
    return a * d


def noise(n, seed=1):
    return np.random.default_rng(seed).uniform(-1, 1, n)


def lowpass(x, k):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += (v - acc) * k
        y[i] = acc
    return y


def sweep(f0, f1, sec, shape='sin'):
    tt = t(sec)
    f = f0 * (f1 / f0) ** (tt / sec)
    ph = np.cumsum(f) / RATE * 2 * math.pi
    if shape == 'sin':
        return np.sin(ph)
    if shape == 'square':
        return np.sign(np.sin(ph))
    return 2 * ((ph / (2 * math.pi)) % 1) - 1


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def crush(x, gain=1.0):
    x = np.tanh(x * gain)
    return x / max(1e-6, np.abs(x).max()) * 0.95


def punch():
    n = int(RATE * 0.14)
    body = sweep(180, 60, 0.14) * env(n, 0.001, 0.05)
    snap = lowpass(noise(n, 2), 0.5) * env(n, 0.0005, 0.02)
    return crush(body * 1.2 + snap * 0.9, 2.0)


def kick():
    n = int(RATE * 0.18)
    body = sweep(140, 45, 0.18) * env(n, 0.001, 0.08)
    whoosh = lowpass(noise(n, 3), 0.25) * env(n, 0.01, 0.06)
    return crush(body + whoosh * 0.7, 2.0)


def hit():
    n = int(RATE * 0.2)
    crack = noise(n, 4) * env(n, 0.0005, 0.04)
    thump = sweep(220, 50, 0.2) * env(n, 0.001, 0.07)
    return crush(crack * 0.8 + thump, 3.0)


def bighit():
    n = int(RATE * 0.35)
    crack = noise(n, 5) * env(n, 0.0005, 0.07)
    thump = sweep(160, 35, 0.35) * env(n, 0.001, 0.12)
    ring = sweep(900, 400, 0.35, 'square') * env(n, 0.001, 0.05) * 0.3
    return crush(crack + thump * 1.3 + ring, 3.5)


def hurt():
    n = int(RATE * 0.3)
    v = sweep(380, 140, 0.3, 'saw') * env(n, 0.005, 0.15)
    return crush(lowpass(v, 0.4) + noise(n, 6) * env(n, 0.001, 0.03) * 0.5, 2.5)


def down():
    n = int(RATE * 0.5)
    thud = sweep(90, 30, 0.5) * env(n, 0.001, 0.2)
    rub = lowpass(noise(n, 7), 0.15) * env(n, 0.02, 0.2)
    return crush(thud * 1.4 + rub, 2.0)


def jump():
    n = int(RATE * 0.16)
    return crush(lowpass(noise(n, 8), 0.3) * env(n, 0.02, 0.06) + sweep(200, 500, 0.16, 'square') * env(n, 0.001, 0.05) * 0.2)


def chime(freqs, step, dur, shape='square'):
    parts = []
    for i, f in enumerate(freqs):
        n = int(RATE * dur)
        tone = sweep(f, f, dur, shape) * env(n, 0.002, dur * 0.6)
        pad = np.zeros(int(RATE * step * i))
        parts.append(np.concatenate([pad, tone]))
    return crush(mix(*parts) * 0.6, 1.2)


def pickup():
    return chime([660, 880, 1320], 0.05, 0.12)


def heal():
    return chime([523, 659, 784, 1046], 0.06, 0.18, 'sin')


def cable():
    n = int(RATE * 0.35)
    zap = sweep(120, 1800, 0.35, 'saw') * env(n, 0.002, 0.25)
    hum = sweep(100, 100, 0.35, 'square') * env(n, 0.002, 0.3) * 0.4
    return crush(zap + hum, 2.0)


def strobe():
    n = int(RATE * 0.5)
    x = noise(n, 9) * (np.sin(t(0.5) * 2 * math.pi * 14) > 0.3) * env(n, 0.001, 0.3)
    return crush(x, 1.5)


def shout():
    """Zombie singer: a rough formant scream."""
    n = int(RATE * 0.45)
    base = sweep(260, 200, 0.45, 'saw')
    vib = np.sin(t(0.45) * 2 * math.pi * 7) * 0.3
    x = base * (1 + vib) + noise(n, 10) * 0.4
    x = lowpass(x, 0.35) * env(n, 0.03, 0.25)
    return crush(x, 3.0)


def roar():
    n = int(RATE * 0.8)
    base = sweep(90, 60, 0.8, 'saw') + sweep(93, 61, 0.8, 'saw')
    x = lowpass(base + noise(n, 11) * 0.6, 0.25) * env(n, 0.05, 0.45)
    fb = sweep(2400, 2900, 0.8, 'sin') * env(n, 0.2, 0.5) * 0.25          # feedback squeal
    return crush(x + fb, 3.0)


def clear():
    return chime([784, 988, 1175, 1568], 0.07, 0.2)


def slide():
    n = int(RATE * 0.45)
    x = lowpass(noise(n, 12), 0.12) * np.sin(np.linspace(0, math.pi, n))
    return crush(x, 2.0)


def page():
    n = int(RATE * 0.8)
    x = lowpass(noise(n, 13), 0.2) * np.sin(np.linspace(0, math.pi, n)) ** 0.7
    flap = lowpass(noise(n, 14), 0.5) * (np.abs(np.sin(t(0.8) * 2 * math.pi * 9)) > 0.9) * 0.6
    return crush(x + flap, 2.0)


def step():
    n = int(RATE * 0.05)
    return crush(lowpass(noise(n, 15), 0.3) * env(n, 0.001, 0.015)) * 0.35


def sketch():
    """Pencil scratching: the artist draws an enemy in."""
    n = int(RATE * 0.6)
    scr = noise(n, 16) * (np.abs(np.sin(t(0.6) * 2 * math.pi * 11)) ** 3)
    return crush(lowpass(scr, 0.6) * env(n, 0.01, 0.4), 1.5) * 0.6


def swing():
    n = int(RATE * 0.18)
    return crush(lowpass(noise(n, 17), 0.2) * np.sin(np.linspace(0, math.pi, n)), 2.0) * 0.7


SFX = ['jump', 'punch', 'kick', 'hit', 'bighit', 'hurt', 'down', 'pickup', 'heal', 'cable', 'strobe', 'shout', 'roar',
       'clear', 'slide', 'page', 'step', 'sketch', 'swing']


def write_wav(path, x):
    x = np.clip(x, -1, 1)
    data = (x * 32000).astype('<i2').tobytes()
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)


def build(out_dir):
    for name in SFX:
        write_wav(os.path.join(out_dir, f'sfx_{name}.wav'), globals()[name]())
    return SFX
