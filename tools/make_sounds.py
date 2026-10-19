"""Synthesises the sniper rifle and movement sounds (no recordings involved) into sounds/*.wav.

    python tools/make_sounds.py

Every sound is built from filtered noise and damped resonances: the shot is a
supersonic crack, a muzzle blast and a long echo off the containers; the bolt
and magazine noises are short metal-on-metal impacts and slides.
"""
import os
import wave

import numpy as np
from scipy import signal

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds")
rng = np.random.default_rng(46)


def t_axis(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def noise(seconds):
    return rng.standard_normal(int(seconds * RATE))


def band(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], "bandpass", fs=RATE, output="sos")
    return signal.sosfilt(sos, x)


def low(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, "lowpass", fs=RATE, output="sos"), x)


def high(x, hz, order=2):
    return signal.sosfilt(signal.butter(order, hz, "highpass", fs=RATE, output="sos"), x)


def ring(seconds, freqs, decay, amps=None):
    """Damped, slightly detuned resonances: a struck piece of steel."""
    t = t_axis(seconds)
    out = np.zeros_like(t)
    amps = amps or [1.0] * len(freqs)
    for f, a in zip(freqs, amps):
        f *= rng.uniform(0.985, 1.015)
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.3)) * np.exp(-t * decay * (f / 2000.0) ** 0.5)
    return out


def click(seconds, freqs, decay, sharp=1.0):
    """A metal click: a very short noise impulse into some resonances."""
    t = t_axis(seconds)
    hit = high(noise(seconds), 1500) * np.exp(-t * 900 / sharp)
    return hit * 0.8 + ring(seconds, freqs, decay) * 0.5


def slide(seconds, lo, hi, grit=40.0):
    """Steel sliding on steel: band-limited noise, roughened by the surface."""
    t = t_axis(seconds)
    env = np.sin(np.pi * np.clip(t / seconds, 0, 1)) ** 0.7
    rough = 1.0 + 0.6 * low(noise(seconds), grit, 1) * 30
    return band(noise(seconds), lo, hi) * env * np.clip(rough, 0.2, 2.5)


def place(total, *parts):
    """Mixes (start, sound, gain) into one buffer of `total` seconds."""
    out = np.zeros(int(total * RATE))
    for start, snd, gain in parts:
        i = int(start * RATE)
        n = min(len(snd), len(out) - i)
        out[i:i + n] += snd[:n] * gain
    return out


def reverb(x, seconds, damp, wet):
    """A rough late echo: convolution with decaying, darkening noise."""
    t = t_axis(seconds)
    tail = noise(seconds) * np.exp(-t * damp)
    tail = low(tail, 2500) * (t > 0.035)
    wet_sig = np.concatenate([signal.fftconvolve(x, tail), np.zeros(1)])[:len(x) + len(tail)]
    dry = np.concatenate([x, np.zeros(len(tail))])
    wet_sig = wet_sig / (np.max(np.abs(wet_sig)) + 1e-9) * np.max(np.abs(x))
    return dry + wet_sig[:len(dry)] * wet


def stereo(mono, width=0.0):
    """Two channels; `width` decorrelates them a little."""
    if width <= 0:
        return np.stack([mono, mono], 1)
    d = int(0.0007 * RATE)
    l = mono
    r = np.concatenate([np.zeros(d), mono[:-d]]) * (1 - width * 0.3) + mono * width * 0.3
    return np.stack([l, r], 1)


def save(name, x, peak=0.92):
    if x.ndim == 1:
        x = stereo(x)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    # Short fades so nothing pops at either end.
    n = min(64, len(x) // 4)
    x[:n] *= np.linspace(0, 1, n)[:, None]
    x[-n * 8:] *= np.linspace(1, 0, n * 8)[:, None]
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((x * 32767).astype("<i2").tobytes())
    print(name, round(len(x) / RATE, 2), "s")


def j(x, spread=0.08):
    """Jitter a value by a few percent, so every variant comes out a little different."""
    return x * rng.uniform(1 - spread, 1 + spread)


def limiter(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


# --- sniper rifle ---------------------------------------------------------------

def shot(name, suppressed=False):
    """A heavy .50 report: a hard crack on top of a big, deep boom that rolls off
    between the containers. Highs and lows are shaped apart, so the bass can be
    huge without muddying the crack."""
    t = t_axis(0.9)
    # Crack: a sub-millisecond N-wave plus a very short bright burst.
    crack = np.zeros_like(t)
    n = int(j(0.0008, 0.15) * RATE)
    crack[:n] = np.linspace(1, -1, n)
    crack += high(noise(0.9), 4000) * np.exp(-t * j(1100)) * 0.5
    snap = band(noise(0.9), j(1100, 0.15), j(6500, 0.1), 3) * np.exp(-t * j(60)) * 1.9
    # Grit: a ragged, distorted mid burst - the 'Krawall' of the muzzle blast.
    grit = np.tanh(band(noise(0.9), 500, 3500, 2) * 4.0) * np.exp(-t * j(35)) * 0.9
    body = band(noise(0.9), 220, 1300, 2) * np.exp(-t * j(24)) * 1.1
    clack = ring(0.9, [j(2300), j(3900), j(5600)], 50) * np.exp(-t * 60) * 0.06
    if suppressed:
        crack *= 0.15
        snap = low(snap, 1800) * 0.5
        body *= 0.8
    if suppressed:
        grit *= 0.2
    highs = limiter(crack * 1.0 + snap + grit + body + clack, 1.8)
    # The boom: a punch falling from ~115 Hz into a long sub-bass note, with a low
    # noise blast under it for the pressure wave.
    f0, f1 = j(115), j(41)
    f = (f0 - f1) * np.exp(-t * 22) + f1
    attack = 1 - np.exp(-t * 1800)
    punch = np.sin(2 * np.pi * np.cumsum(f) / RATE) * attack * np.exp(-t * j(9))
    sub = np.sin(2 * np.pi * np.cumsum(f * 0.5 + 12) / RATE) * attack * np.exp(-t * j(4.5)) * 0.6
    blast = low(noise(0.9), 260, 4) * np.exp(-t * j(14)) * 2.5
    lows = punch * 1.4 + sub + blast
    if suppressed:
        lows = lows * np.exp(-t * 6) * 0.55
    dry = limiter(highs * 1.05 + limiter(lows, 1.2) * 1.1, 1.35)
    # Echo: a dark wash, one clear slap back off a container wall, and the boom rolling away.
    wet = reverb(low(dry, 3000), j(1.8), j(3.0), j(0.3, 0.15) * (0.4 if suppressed else 1.0))
    slap_at = int(rng.uniform(0.09, 0.15) * RATE)
    slap = np.zeros_like(wet)
    slap[slap_at:slap_at + len(dry)] = low(dry, 1500)[:len(slap) - slap_at] * j(0.38, 0.2) * (0.3 if suppressed else 1.0)
    tt = np.arange(len(wet)) / RATE
    roll = low(rng.standard_normal(len(wet)), 120, 4) * np.exp(-np.maximum(tt - 0.12, 0) * j(2.2)) * (tt > 0.12)
    roll = roll / (np.max(np.abs(roll)) + 1e-9) * (0.15 if suppressed else 0.42)
    out = limiter(wet + slap + roll, 1.05)
    save(name, stereo(out, j(0.6, 0.2)), 0.8 if suppressed else 0.95)


def tick(seconds, freqs, body_hz, sharp=1.0):
    """A dry, hard steel click: an instant transient, a few very short high
    partials and a short low 'thock' that gives it weight. No ringing tail."""
    t = t_axis(seconds)
    hit = high(noise(seconds), 2500) * np.exp(-t * 3000 / sharp)
    parts = np.zeros_like(t)
    for f in freqs:
        parts += np.sin(2 * np.pi * j(f, 0.03) * t + rng.uniform(0, 6.3)) * np.exp(-t * j(260))
    thock = band(noise(seconds), body_hz * 0.6, body_hz * 1.6, 2) * np.exp(-t * j(180))
    return hit + parts * 0.35 + thock * 0.9


def scrape(seconds, lo, hi):
    """Steel drawn over steel: thin, gritty, bright."""
    t = t_axis(seconds)
    env = np.sin(np.pi * np.clip(t / seconds, 0, 1)) ** 0.5
    grit = np.clip(1.0 + 40 * low(noise(seconds), 90, 1), 0.1, 3.0)
    return band(noise(seconds), lo, hi, 3) * env * grit


def bolt_open(name):
    # Handle snapped up, bolt ripped back, hard stop.
    lift = tick(0.06, [j(4200), j(6100), j(8300)], j(700), 0.8)
    pull = scrape(j(0.11), j(2200), j(8000))
    stop = tick(0.07, [j(3400), j(5200), j(7600)], j(480), 1.0)
    save(name, place(0.3, (0.0, lift, 0.9), (j(0.04), pull, 0.3), (j(0.15, 0.05), stop, 1.0)))


def bolt_close(name):
    # Bolt slammed home, handle locked down: two hard, dry hits.
    push = scrape(j(0.09), j(2000), j(7500))
    home = tick(0.08, [j(3000), j(4700), j(7000)], j(420), 1.2)
    lock = tick(0.06, [j(4500), j(6600), j(9000)], j(750), 0.8)
    save(name, place(0.32, (0.0, push, 0.28), (0.09, home, 1.0), (j(0.2, 0.05), lock, 0.85)))


def mag_out(name):
    rel = tick(0.05, [j(4800), j(7000)], j(900), 0.7)
    drop = scrape(0.08, 1500, 6000)
    save(name, place(0.2, (0.0, rel, 0.8), (0.03, drop, 0.35)))


def mag_in(name):
    slide_in = scrape(0.06, 1800, 7000)
    seat = tick(0.07, [j(3200), j(5000), j(7400)], j(450), 1.2)
    save(name, place(0.2, (0.0, slide_in, 0.3), (0.06, seat, 1.0)))


def shell(name):
    # The big .50 case landing: a hollow brass ring, twice.
    hit = lambda: click(0.25, [j(3900), j(6300), j(8700), j(11200)], j(18)) * np.exp(-t_axis(0.25) * 9)
    save(name, place(0.5, (0.0, hit(), 0.8), (j(0.17, 0.2), hit(), j(0.35, 0.3))), 0.6)


# --- movement -----------------------------------------------------------------

def cloth(seconds, lo=300, hi=3000):
    t = t_axis(seconds)
    env = np.sin(np.pi * np.clip(t / seconds, 0, 1)) ** 1.5
    flutter = np.clip(1.0 + 25 * low(noise(seconds), 30, 1), 0.2, 2.0)
    return band(noise(seconds), j(lo), j(hi), 2) * env * flutter


def gear(seconds, hits):
    """Kit on the vest knocking about: a few small, quick clicks."""
    parts = []
    for _ in range(hits):
        parts.append((rng.uniform(0.0, seconds * 0.7), tick(0.04, [j(2600), j(4100)], j(900), 0.6), rng.uniform(0.15, 0.4)))
    return place(seconds, *parts)


def thud(seconds, hz, decay):
    t = t_axis(seconds)
    return low(noise(seconds), hz, 3) * np.exp(-t * decay) * (1 - np.exp(-t * 900))


def jump(name):
    push = high(thud(0.12, j(900), j(55)), 250) * 0.4 + band(noise(0.12), 700, 3500) * np.exp(-t_axis(0.12) * 60) * 0.35
    save(name, place(0.4, (0.0, push, 1.0), (0.02, cloth(j(0.3)), 0.5), (0.03, gear(0.3, 3), 1.0)), 0.55)


def land(name):
    boom = thud(0.25, j(220), j(22)) * 1.4
    grit = band(noise(0.1), 800, 4000) * np.exp(-t_axis(0.1) * 45) * 0.35
    save(name, place(0.45, (0.0, boom, 1.0), (0.0, grit, 1.0), (0.01, gear(0.35, 4), 1.2), (0.0, cloth(0.25), 0.4)), 0.75)


def slide(name):
    dur = j(0.8, 0.06)
    t = t_axis(dur)
    env = np.minimum(t / 0.03, 1.0) * np.clip((dur - t) / 0.25, 0, 1)
    grit = np.clip(1.0 + 30 * low(noise(dur), 60, 1), 0.2, 2.5)
    rub = band(noise(dur), j(800), j(5500), 2) * grit * env
    rumble = band(noise(dur), j(250), j(600), 2) * env * 0.35
    start = high(thud(0.2, 700, 35), 200) * 0.5
    save(name, place(dur + 0.05, (0.0, start, 0.9), (0.0, rub, 0.7), (0.0, rumble, 1.0),
                     (0.0, cloth(dur * 0.7), 0.35), (0.05, gear(0.4, 3), 0.8)), 0.6)


def crouch(name):
    save(name, place(0.35, (0.0, cloth(j(0.25), 250, 2400), 1.0), (0.05, gear(0.25, 2), 0.8)), 0.4)


def prone(name):
    save(name, place(0.6, (0.0, cloth(j(0.35)), 0.8), (0.2, thud(0.25, 200, 20), 1.2), (0.22, gear(0.3, 4), 1.0)), 0.6)


# --- the other firearms ----------------------------------------------------------

# Per calibre: crack brightness, snap length, boom pitch and weight, echo.
GUNS = {
    # 9 mm sub-machine gun: light, quick, a tight pop.
    "smg": {"snap_lo": 1500, "snap_hi": 7500, "snap_decay": 120, "body_decay": 55, "f0": 170, "f1": 70,
            "boom_decay": 22, "boom": 0.8, "wet": 0.22, "slap": 0.18, "peak": 0.8},
    # 5.56 rifle: a hard, loud crack with real weight behind it.
    "ar": {"snap_lo": 1200, "snap_hi": 7000, "snap_decay": 85, "body_decay": 38, "f0": 135, "f1": 55,
           "boom_decay": 14, "boom": 1.1, "wet": 0.3, "slap": 0.28, "peak": 0.88},
    # 9 mm pistol: snappy and dry.
    "pistol": {"snap_lo": 1700, "snap_hi": 8000, "snap_decay": 140, "body_decay": 60, "f0": 190, "f1": 80,
               "boom_decay": 26, "boom": 0.7, "wet": 0.2, "slap": 0.16, "peak": 0.78},
}


def gun_shot(name, kind, suppressed=False):
    g = GUNS[kind]
    t = t_axis(0.6)
    crack = np.zeros_like(t)
    n = int(j(0.0005, 0.15) * RATE)
    crack[:n] = np.linspace(1, -1, n)
    crack += high(noise(0.6), 4500) * np.exp(-t * j(1400)) * 0.5
    snap = band(noise(0.6), j(g["snap_lo"], 0.12), j(g["snap_hi"], 0.08), 3) * np.exp(-t * j(g["snap_decay"])) * 1.6
    grit = np.tanh(band(noise(0.6), 600, 3800, 2) * 3.5) * np.exp(-t * j(g["body_decay"])) * 0.6
    body = band(noise(0.6), 250, 1400, 2) * np.exp(-t * j(g["body_decay"])) * 0.9
    f0, f1 = j(g["f0"]), j(g["f1"])
    f = (f0 - f1) * np.exp(-t * 30) + f1
    boom = np.sin(2 * np.pi * np.cumsum(f) / RATE) * (1 - np.exp(-t * 2000)) * np.exp(-t * j(g["boom_decay"])) * g["boom"]
    blast = low(noise(0.6), 320, 3) * np.exp(-t * j(g["boom_decay"] * 1.6)) * 1.4 * g["boom"]
    # The action cycling: always there, but only audible once the report is tamed.
    action = place(0.6, (j(0.012), tick(0.05, [j(3200), j(5100)], j(600), 1.0), 1.0),
                   (j(0.045, 0.15), tick(0.05, [j(2700), j(4300)], j(500), 1.0), 0.8))
    if suppressed:
        crack *= 0.08
        snap = low(snap, 1500) * 0.35
        grit *= 0.15
        body = low(body, 900) * 0.8
        boom *= 0.55
        blast *= 0.45
        dry = limiter(crack + snap + grit + body + boom + blast + action * 0.9, 1.2)
        wet = reverb(low(dry, 2200), j(0.7), j(6.0), 0.12)
        save(name, stereo(wet, 0.3), g["peak"] * 0.75)
        return
    highs = limiter(crack + snap + grit + body, 1.7)
    dry = limiter(highs + limiter(boom + blast, 1.2) + action * 0.12, 1.3)
    wet = reverb(low(dry, 3200), j(1.2), j(4.0), j(g["wet"], 0.15))
    slap_at = int(rng.uniform(0.08, 0.14) * RATE)
    slap = np.zeros_like(wet)
    slap[slap_at:slap_at + len(dry)] = low(dry, 1800)[:len(slap) - slap_at] * j(g["slap"], 0.2)
    save(name, stereo(limiter(wet + slap, 1.05), j(0.5, 0.2)), g["peak"])


def rifle_mag_out(name):
    rel = tick(0.05, [j(4200), j(6400)], j(800), 0.8)
    pull = scrape(0.09, 1400, 5500)
    save(name, place(0.22, (0.0, rel, 0.8), (0.025, pull, 0.4)))


def rifle_mag_in(name):
    slide_in = scrape(0.06, 1600, 6500)
    seat = tick(0.07, [j(2800), j(4500), j(6600)], j(420), 1.2)
    slap = thud(0.06, j(700), j(70)) * 0.5
    save(name, place(0.22, (0.0, slide_in, 0.3), (0.06, seat, 1.0), (0.06, slap, 0.8)))


def rifle_charge(name):
    # Charging handle back and released: the bolt slams forward.
    back = place(0.12, (0.0, tick(0.05, [j(3600), j(5600)], j(700), 0.8), 0.7), (0.01, scrape(0.07, 2000, 7000), 0.3))
    home = tick(0.08, [j(2500), j(4000), j(6200)], j(380), 1.3)
    save(name, place(0.35, (0.0, back, 1.0), (j(0.17), home, 1.0)))


def pistol_mag_out(name):
    save(name, place(0.18, (0.0, tick(0.04, [j(5200), j(7600)], j(1000), 0.7), 0.8), (0.02, scrape(0.06, 2000, 7000), 0.3)))


def pistol_mag_in(name):
    save(name, place(0.18, (0.0, scrape(0.04, 2200, 7500), 0.25), (0.04, tick(0.06, [j(3600), j(5800)], j(600), 1.0), 1.0)))


def pistol_slide(name):
    save(name, place(0.25, (0.0, scrape(0.05, 2500, 8000), 0.3), (0.06, tick(0.07, [j(3000), j(4900), j(7200)], j(520), 1.2), 1.0)))


def shell_small(name):
    # Small brass on concrete: bright, light, a couple of bounces.
    hit = lambda: click(0.12, [j(5200), j(7900), j(10400)], j(30)) * np.exp(-t_axis(0.12) * 25)
    save(name, place(0.35, (0.0, hit(), 0.7), (j(0.09, 0.3), hit(), j(0.3, 0.3)), (j(0.17, 0.3), hit(), j(0.12, 0.3))), 0.5)


def knife_swing(name):
    # A whoosh: noise sweeping up and down in pitch as the blade passes.
    dur = j(0.26, 0.1)
    t = t_axis(dur)
    sweep = np.sin(np.pi * t / dur)
    x = noise(dur)
    # Three bands cross-faded by the sweep: the pitch rises and falls with the blade.
    out = band(x, 400, 1200) * (1 - sweep) + band(x, 1200, 3000) * sweep + band(x, 3000, 6500) * sweep ** 3 * 0.6
    out = low(out, 6000) * sweep ** 1.5
    save(name, out, 0.45)


def knife_hit(name):
    thump = thud(0.15, j(500), j(40)) * 1.2
    slice_ = band(noise(0.12), 1500, 6000, 2) * np.exp(-t_axis(0.12) * 50) * 0.5
    save(name, place(0.2, (0.0, thump, 1.0), (0.0, slice_, 1.0)), 0.6)


# --- MP5 -----------------------------------------------------------------------------

def mp5_shot(name):
    """Open 9 mm: a hard, close crack with a fat punch behind it and a short room slap."""
    t = t_axis(0.6)
    crack = np.zeros_like(t)
    n = int(j(0.0005, 0.15) * RATE)
    crack[:n] = np.linspace(1, -1, n)
    crack += high(noise(0.6), 4000) * np.exp(-t * j(1300)) * 0.6
    snap = band(noise(0.6), j(1300, 0.1), j(7000, 0.08), 3) * np.exp(-t * j(95)) * 2.0
    grit = np.tanh(band(noise(0.6), 500, 3500, 2) * 4.5) * np.exp(-t * j(45)) * 0.8
    body = band(noise(0.6), 200, 1200, 2) * np.exp(-t * j(40)) * 1.0
    f0, f1 = j(190), j(72)
    f = (f0 - f1) * np.exp(-t * 32) + f1
    punch = np.sin(2 * np.pi * np.cumsum(f) / RATE) * (1 - np.exp(-t * 2200)) * np.exp(-t * j(17)) * 1.4
    blast = low(noise(0.6), 300, 3) * np.exp(-t * j(26)) * 1.8
    highs = limiter(crack + snap + grit + body, 1.9)
    dry = limiter(highs + limiter(punch + blast, 1.3) * 1.1, 1.4)
    wet = reverb(low(dry, 3500), j(1.0), j(5.0), j(0.26, 0.15))
    slap_at = int(rng.uniform(0.06, 0.11) * RATE)
    slap = np.zeros_like(wet)
    slap[slap_at:slap_at + len(dry)] = low(dry, 2000)[:len(slap) - slap_at] * j(0.24, 0.2)
    save(name, stereo(limiter(wet + slap, 1.05), j(0.5, 0.2)), 0.9)


def mp5_shot_sd(name):
    """Suppressed MP5: no boom, a quick high 'pfft' of gas, and the bolt's sharp
    metallic clack on top - higher and thinner than the open shot."""
    t = t_axis(0.4)
    gas = band(noise(0.4), j(1800, 0.1), j(5500, 0.1), 2) * np.exp(-t * j(70)) * 1.2
    hiss = high(noise(0.4), 5000) * np.exp(-t * j(140)) * 0.4
    thump = band(noise(0.4), 300, 900, 2) * np.exp(-t * j(60)) * 0.45
    pop = np.sin(2 * np.pi * j(420) * t) * np.exp(-t * 90) * 0.35
    # Bolt back and home: two bright clacks, the second a hair later.
    clack = place(0.4, (j(0.004, 0.3), tick(0.05, [j(4200), j(6500), j(8800)], j(1100), 0.7), 1.0),
                  (j(0.038, 0.12), tick(0.05, [j(3600), j(5600), j(7900)], j(900), 0.8), 0.75))
    dry = limiter(gas + hiss + thump + pop + clack * 0.9, 1.3)
    wet = reverb(dry, j(0.5), j(9.0), 0.08)
    save(name, stereo(wet, 0.25), 0.7)


def shell_ting(name):
    """The case leaving the port: a short, bright, glassy 'ting'."""
    t = t_axis(0.3)
    ting = np.zeros_like(t)
    base = j(5600, 0.06)
    for ratio, amp, decay in [(1.0, 1.0, 22), (1.53, 0.6, 30), (2.27, 0.35, 38), (2.94, 0.2, 45)]:
        ting += np.sin(2 * np.pi * base * ratio * t + rng.uniform(0, 6.3)) * np.exp(-t * j(decay)) * amp
    click = high(noise(0.3), 6000) * np.exp(-t * 2500) * 0.4
    save(name, ting * (1 - np.exp(-t * 3000)) + click, 0.45)


VARIANTS = 4

if __name__ == "__main__":
    for i in range(VARIANTS):
        shot("sniper_shot_%d" % i)
        shot("sniper_shot_sup_%d" % i, True)
        bolt_open("sniper_bolt_open_%d" % i)
        bolt_close("sniper_bolt_close_%d" % i)
        mag_out("sniper_mag_out_%d" % i)
        mag_in("sniper_mag_in_%d" % i)
        shell("sniper_shell_%d" % i)
        jump("move_jump_%d" % i)
        land("move_land_%d" % i)
        slide("move_slide_%d" % i)
        crouch("move_crouch_%d" % i)
        prone("move_prone_%d" % i)
        for kind in ("ar", "pistol"):
            gun_shot("%s_shot_%d" % (kind, i), kind)
            gun_shot("%s_shot_sup_%d" % (kind, i), kind, True)
        mp5_shot("smg_shot_%d" % i)
        mp5_shot_sd("smg_shot_sup_%d" % i)
        shell_ting("shell_ting_%d" % i)
        for kind in ("smg", "ar"):
            rifle_mag_out("%s_mag_out_%d" % (kind, i))
            rifle_mag_in("%s_mag_in_%d" % (kind, i))
            rifle_charge("%s_charge_%d" % (kind, i))
        pistol_mag_out("pistol_mag_out_%d" % i)
        pistol_mag_in("pistol_mag_in_%d" % i)
        pistol_slide("pistol_charge_%d" % i)
        shell_small("shell_small_%d" % i)
        knife_swing("knife_swing_%d" % i)
        knife_hit("knife_hit_%d" % i)
