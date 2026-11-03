"""More synthesised sounds, built with the helpers in make_sounds.py:

    python tools/make_sounds2.py

- step_*:     boots on concrete (heel, roll, a little grit and kit)
- slide_*:    the reworked slide: a short drop, then trousers and grit scraping
              over concrete, fading as the slide slows (replaces move_slide_*)
- stim_*:     the stim: cap flicked off, the needle punched in, the hiss of the
              injector, a sharp breath through the teeth
- breath_*:   a deep breath while health comes back: slow inhale, a pause, a
              long exhale
"""
import numpy as np

from make_sounds import (RATE, band, click, cloth, gear, high, j, low, noise, place, rng, save, t_axis, thud, tick)

VARIANTS = 4


def step(name):
    heel = thud(0.09, j(520), j(70)) * 1.0
    roll = band(noise(0.12), j(900), j(3800)) * np.exp(-t_axis(0.12) * j(38)) * 0.32
    grit = high(noise(0.08), 3000) * np.exp(-t_axis(0.08) * 60) * 0.12
    save(name, place(0.26, (0.0, heel, 1.0), (0.012, roll, 1.0), (0.02, grit, 1.0), (0.03, gear(0.2, 1), 0.5)), 0.5)


def slide_new(name):
    dur = j(0.85, 0.05)
    t = t_axis(dur)
    # Fast at first, slowing down: loud and bright, then quieter and darker.
    speed = np.clip(1.0 - t / dur, 0.0, 1.0) ** 0.8
    env = np.minimum(t / 0.02, 1.0) * speed
    grit = np.clip(1.0 + 26 * low(noise(dur), j(45), 1), 0.25, 2.2)
    scrape = band(noise(dur), j(1400), j(6500), 2) * grit * env
    fabric = band(noise(dur), j(500), j(2400), 2) * env * np.clip(1.0 + 18 * low(noise(dur), 22, 1), 0.3, 1.8)
    # Little stones skittering out of the way.
    pebbles = []
    for _ in range(int(rng.integers(6, 11))):
        pebbles.append((rng.uniform(0.0, dur * 0.7), tick(0.03, [j(3200), j(5200)], j(1400), 0.4), rng.uniform(0.08, 0.22)))
    drop = high(thud(0.12, j(800), j(50)), 300) * 0.45
    save(name, place(dur + 0.08, (0.0, drop, 1.0), (0.0, scrape, 0.5), (0.0, fabric, 0.55),
                     (0.0, place(dur, *pebbles), 1.0), (0.04, gear(0.35, 2), 0.6)), 0.55)


def stim(name):
    cap = click(0.06, [j(2400), j(3900)], j(700), 0.7) * 0.7
    punch = thud(0.08, j(1200), j(80)) * 0.6 + high(noise(0.08), 2500) * np.exp(-t_axis(0.08) * 200) * 0.4
    d = j(0.45)
    t = t_axis(d)
    hiss = band(noise(d), j(2500), j(9000), 2) * np.exp(-t * 4.5) * np.minimum(t / 0.01, 1.0) * 0.45
    teeth = band(noise(0.35), j(1800), j(5000), 2) * np.sin(np.pi * np.clip(t_axis(0.35) / 0.35, 0, 1)) ** 2 * 0.3
    save(name, place(1.1, (0.0, cap, 1.0), (0.22, punch, 1.0), (0.24, hiss, 1.0), (0.45, teeth, 1.0)), 0.6)


def _air(seconds, lo, hi, shape):
    """Breath: noise through two moving formants, shaped by an envelope."""
    t = t_axis(seconds)
    x = noise(seconds)
    a = band(x, lo, hi, 2)
    b = band(x, lo * 2.2, hi * 1.6, 2) * 0.4
    return (a + b) * shape(t / seconds)


def breath(name):
    inhale = _air(j(1.05), j(420), j(2200), lambda u: np.sin(np.pi * np.clip(u, 0, 1)) ** 1.3 * (0.6 + 0.4 * u))
    exhale = _air(j(1.5), j(260), j(1500), lambda u: np.sin(np.pi * np.clip(u, 0, 1) ** 0.6) ** 1.2 * (1.0 - 0.5 * u))
    save(name, place(3.0, (0.0, inhale, 0.8), (1.35, low(exhale, 1800), 1.0)), 0.45)


if __name__ == "__main__":
    for i in range(VARIANTS):
        step("step_%d" % i)
        slide_new("move_slide_%d" % i)
        stim("stim_%d" % i)
        breath("breath_%d" % i)
