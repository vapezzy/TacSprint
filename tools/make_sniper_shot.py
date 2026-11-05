"""The FJ50 (.50 bolt rifle) report, rebuilt like a game gunshot is layered:

    python tools/make_sniper_shot.py

  1. transient  - a few milliseconds of hard, clipped broadband pop
  2. crack      - the supersonic bullet: a bright snap that dies in ~20 ms
  3. blast      - the muzzle blast: a kick-drum-like drop from ~170 Hz to ~45 Hz,
                  driven into saturation so it has weight on small speakers too
  4. body       - a short mid-range burst that gives the bang its 'bark'
  5. mechanics  - a quiet steel ring of the action
  6. tail       - outdoors: discrete slap-back echoes off walls, each darker and
                  quieter than the last, then a long rolling rumble, no hiss

The suppressed version keeps the crack (a .50 is supersonic either way), loses
most of the blast and nearly all of the tail, and the action gets louder.
Writes sounds/sniper_shot_0..3.wav and sounds/sniper_shot_sup_0..3.wav.
"""
import os
import wave

import numpy as np
from scipy import signal

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds")
rng = np.random.default_rng(1950)


def n_of(seconds):
    return int(seconds * RATE)


def t_axis(seconds):
    return np.arange(n_of(seconds)) / RATE


def noise(seconds):
    return rng.standard_normal(n_of(seconds))


def sos(kind, hz, order=2):
    return signal.butter(order, hz, kind, fs=RATE, output="sos")


def low(x, hz, order=2):
    return signal.sosfilt(sos("lowpass", hz, order), x)


def high(x, hz, order=2):
    return signal.sosfilt(sos("highpass", hz, order), x)


def band(x, lo, hi, order=2):
    return signal.sosfilt(sos("bandpass", [lo, hi], order), x)


def j(x, spread=0.06):
    return x * rng.uniform(1 - spread, 1 + spread)


def sat(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def norm(x, peak=1.0):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def pad(x, length):
    out = np.zeros(length)
    out[:min(len(x), length)] = x[:length]
    return out


def dry_shot(suppressed):
    """The first ~0.35 s: everything that arrives straight from the rifle."""
    d = 0.35
    t = t_axis(d)
    # 1. transient: an N-wave of under a millisecond and a clipped click.
    tr = np.zeros_like(t)
    k = n_of(j(0.0007, 0.2))
    tr[:k] = np.linspace(1.0, -1.0, k)
    tr += noise(d) * np.exp(-t * 2600) * 0.9
    tr = sat(tr, 3.0)
    # 2. crack: bright snap.
    crack = high(noise(d), 2800, 2) * np.exp(-t * j(170)) * 0.9
    crack += band(noise(d), j(1400), j(5200), 2) * np.exp(-t * j(90)) * 0.7
    # 3. blast: the falling low note plus a low noise thump.
    f_hi, f_lo = j(170), j(46)
    f = (f_hi - f_lo) * np.exp(-t * j(30)) + f_lo
    attack = 1 - np.exp(-t * 2500)
    tone = np.sin(2 * np.pi * np.cumsum(f) / RATE) * attack * np.exp(-t * j(16))
    thump = band(noise(d), 60, 700, 2) * np.exp(-t * j(38)) * 1.6
    blast = high(sat(tone * 1.2 + thump, 1.8), 55, 2)
    # The kick: what you feel in the chest. A drum-like hit dropping from ~130 Hz
    # to ~52 Hz in a few tens of ms, a sub note that holds a little longer, and
    # a short low-mid 'punch' around 100-200 Hz that small speakers can show.
    kf = (j(130) - 52) * np.exp(-t * 45) + 52
    kick = np.sin(2 * np.pi * np.cumsum(kf) / RATE) * (1 - np.exp(-t * 3000)) * np.exp(-t * j(15))
    subn = np.sin(2 * np.pi * np.cumsum(kf * 0.0 + j(48, 0.03)) / RATE) * (1 - np.exp(-t * 400)) * np.exp(-t * j(10))
    punch = band(noise(d), 90, 230, 2) * np.exp(-t * j(26)) * 2.2
    kick = sat(kick * 1.0 + subn * 0.45 + punch, 1.3)
    # 4. body: short mid bark.
    body = band(noise(d), 280, 1600, 2) * np.exp(-t * j(42)) * 1.4
    body = sat(body, 2.0)
    # 5. mechanics.
    mech = np.zeros_like(t)
    for fr, a in ((j(2450), 1.0), (j(3720), 0.7), (j(5480), 0.5), (j(1180), 0.6)):
        mech += a * np.sin(2 * np.pi * fr * t + rng.uniform(0, 6.3)) * np.exp(-t * j(38))
    mech *= (1 - np.exp(-t * 900))
    if suppressed:
        tr *= 0.25
        crack *= 0.7
        blast = low(blast, 380) * 0.45
        body = low(body, 900) * 0.35
        mech *= 2.6
    # The bang: a loud, hard-clipped mid/high explosion over the first ~40 ms,
    # the part of the report that cuts through everything.
    bang = band(noise(d), j(500), j(5200), 2) * np.exp(-t * j(38))
    bang = sat(bang * 7.0, 3.5) * np.exp(-t * 14)
    # Explosion body: a big low/mid noise blast like a detonation, ~0.25 s.
    boom = sat(band(noise(d), 40, 450, 2) * np.exp(-t * j(13)) * 5.0, 2.5)
    if suppressed:
        kick *= 0.12
        bang *= 0.1
        boom *= 0.08
    mix = tr * 1.8 + crack * 2.3 + bang * 2.2 + boom * 1.1 + blast * 1.35 + kick * 2.2 + body * 1.3 + mech * 0.06
    return sat(high(mix, 38, 2), 1.7)


def tail(dry, total, suppressed):
    """Outdoor echoes: discrete slap-backs, a dark diffuse wash, a rolling rumble."""
    L = n_of(total)
    left, right = np.zeros(L), np.zeros(L)
    # Slap-backs off walls at varied distances: later ones darker and quieter.
    taps = sorted(rng.uniform(0.07, 0.62, 6))
    for i, at in enumerate(taps):
        cutoff = 2600 * (0.68 ** i)
        g = 0.42 * (0.72 ** i) * j(1.0, 0.25)
        echo = low(dry, max(cutoff, 350), 2) * g
        s = n_of(at)
        n = min(len(echo), L - s)
        pan = 0.65 if i % 2 == 0 else -0.65
        left[s:s + n] += echo[:n] * (1 - max(pan, 0) * 0.6)
        right[s:s + n] += echo[:n] * (1 + min(pan, 0) * 0.6)
    # Dark diffuse wash: short, under the echoes.
    ir_t = t_axis(1.3)
    ir = low(noise(1.3), 1100, 2) * np.exp(-ir_t * 3.4) * (ir_t > 0.03)
    for ch, off in ((left, 0), (right, 1)):
        irc = np.roll(ir, off * 37)
        wash = signal.fftconvolve(dry, irc)[:L]
        ch[:len(wash)] += norm(wash, 0.22)
    # Rumble: deep, slowly swelling and falling, like distant thunder.
    tt = np.arange(L) / RATE
    swell = 1 + 0.55 * low(rng.standard_normal(L), 5, 2) * 60
    swell = np.clip(swell, 0.25, 1.9)
    env = (1 - np.exp(-tt * 9)) * np.exp(-tt * j(1.35))
    rumble_l = band(rng.standard_normal(L), 40, 220, 2) * swell * env
    rumble_r = band(rng.standard_normal(L), 40, 220, 2) * swell * env
    left += norm(rumble_l, 0.22)
    right += norm(rumble_r, 0.22)
    scale = 0.18 if suppressed else 1.0
    return left * scale, right * scale


def save(name, l, r, peak):
    x = np.stack([l, r], 1)
    x = norm(x, peak)
    fade = n_of(0.25)
    x[-fade:] *= np.linspace(1, 0, fade)[:, None] ** 2
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((x * 32767).astype("<i2").tobytes())
    print(name, round(len(x) / RATE, 2), "s")


def shot(name, suppressed=False):
    total = 1.4 if suppressed else 2.8
    dry = dry_shot(suppressed)
    tl, tr = tail(dry, total, suppressed)
    d = pad(dry, n_of(total))
    # A hair of width on the dry part, so it fills the head without smearing the hit.
    dl = d
    dr = np.concatenate([np.zeros(12), d[:-12]]) * 0.97
    left = sat(dl + tl * 1.3, 1.1)
    right = sat(dr + tr * 1.3, 1.1)
    save(name, left, right, 0.8 if suppressed else 0.97)


if __name__ == "__main__":
    for i in range(4):
        shot("sniper_shot_%d" % i)
        shot("sniper_shot_sup_%d" % i, True)
