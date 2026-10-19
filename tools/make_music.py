"""Synthesises the menu music: a slow, dark orchestral loop in the manner of a
big film score - low string pads, a pulsing string ostinato, brass swells,
deep drums and a high shimmer, in D minor at 60 bpm (i - VI - III - VII),
16 bars = 64 seconds, written so the end runs straight back into the start.

    python tools/make_music.py      ->  sounds/music_menu.wav
"""
import os
import wave

import numpy as np
from scipy import signal

RATE = 22050
BPM = 60.0
BEAT = 60.0 / BPM
BARS = 16
LENGTH = BARS * 4 * BEAT
OUT = os.path.join(os.path.dirname(__file__), "..", "sounds", "music_menu.wav")
rng = np.random.default_rng(7)

# Chords per bar (MIDI notes): Dm, Bb, F, C - twice, then the same with more weight.
CHORDS = [[38, 50, 53, 57], [34, 50, 53, 58], [41, 53, 57, 60], [36, 52, 55, 60]] * 4


def hz(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)


def t_axis(sec):
    return np.arange(int(sec * RATE)) / RATE


def saw(f, t, phase=0.0):
    return 2.0 * ((f * t + phase) % 1.0) - 1.0


def low(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, "lowpass", fs=RATE, output="sos"), x)


def band(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, hi], "bandpass", fs=RATE, output="sos"), x)


def env(n, attack, release, total):
    t = np.arange(n) / RATE
    a = np.clip(t / max(attack, 1e-3), 0, 1)
    r = np.clip((total - t) / max(release, 1e-3), 0, 1)
    return np.minimum(a, r) ** 1.5


def ensemble(note, sec, voices=7, detune=0.12, bright=1400.0):
    """A section of strings on one note: detuned saws, gentle vibrato, filtered."""
    t = t_axis(sec)
    out = np.zeros_like(t)
    for v in range(voices):
        cents = (v - (voices - 1) / 2) / ((voices - 1) / 2) * detune
        f = hz(note) * 2 ** (cents / 12.0)
        vib = 1.0 + 0.0025 * np.sin(2 * np.pi * rng.uniform(4.5, 5.5) * t + rng.uniform(0, 6))
        out += saw(f * vib, t, rng.uniform(0, 1))
    return low(out / voices, bright, 2)


def place(buf, start, x, gain=1.0):
    i = int(start * RATE) % len(buf)
    n = len(x)
    end = i + n
    if end <= len(buf):
        buf[i:end] += x * gain
    else:                                    # wrap round: the loop has no seam
        cut = len(buf) - i
        buf[i:] += x[:cut] * gain
        buf[:n - cut] += x[cut:] * gain


def build():
    n = int(LENGTH * RATE)
    left = np.zeros(n)
    right = np.zeros(n)
    bar = 4 * BEAT
    for b, chord in enumerate(CHORDS):
        start = b * bar
        lift = 0.6 if b < 8 else 1.0
        # Low strings: basses and cellos hold the chord across the bar, overlapping.
        for k, note in enumerate(chord):
            sec = bar + 1.5
            x = ensemble(note, sec, bright=900.0 + 400.0 * lift) * env(int(sec * RATE), 1.2, 1.4, sec)
            pan = (k - 1.5) / 3.0
            g = (0.32 if k == 0 else 0.2) * lift
            place(left, start, x, g * (1.0 - 0.4 * pan))
            place(right, start, x, g * (1.0 + 0.4 * pan))
        # Ostinato: short low string strokes in eighths, from bar 5.
        if b >= 4:
            root = chord[0] + 12
            for e in range(8):
                note = root + (0 if e % 4 != 3 else 7)
                sec = BEAT * 0.45
                x = ensemble(note, sec, voices=4, bright=1800.0) * env(int(sec * RATE), 0.01, 0.2, sec)
                accent = 1.0 if e % 2 == 0 else 0.6
                place(left, start + e * BEAT / 2, x, 0.12 * accent * lift)
                place(right, start + e * BEAT / 2, x, 0.1 * accent * lift)
        # Brass swell ("braaam") on bars 9 and 13: low, opening up.
        if b in (8, 12):
            sec = bar * 1.2
            t = t_axis(sec)
            brass = np.zeros_like(t)
            for note in (chord[0] - 12, chord[0], chord[0] + 7):
                for v in range(3):
                    brass += saw(hz(note) * 2 ** ((v - 1) * 0.08 / 12), t, rng.uniform(0, 1))
            cutoff = 200.0 + 1600.0 * np.clip(t / (sec * 0.6), 0, 1) ** 2
            # A sweeping low-pass, done in short blocks.
            out = np.zeros_like(brass)
            block = 1024
            for i in range(0, len(t), block):
                out[i:i + block] = low(brass[i:i + block + 256], float(cutoff[i]), 2)[:len(out[i:i + block])]
            out *= env(len(t), 2.5, 1.5, sec) * 0.09
            place(left, start, out)
            place(right, start, out)
        # Drums: a deep boom on every bar, a second hit later on.
        for hit_beat, g in ([(0.0, 1.0)] + ([(2.5, 0.55)] if b >= 8 else [])):
            sec = 2.0
            t = t_axis(sec)
            f = 85.0 * np.exp(-t * 5) + 42.0
            boom = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 3.2)
            skin = low(rng.standard_normal(len(t)), 500.0) * np.exp(-t * 18) * 0.5
            x = (boom + skin) * 0.5 * g * (0.7 + 0.3 * lift)
            place(left, start + hit_beat * BEAT, x)
            place(right, start + hit_beat * BEAT, x)
        # Shimmer: a slow high organ figure from bar 9.
        if b >= 8:
            figure = [chord[1] + 24, chord[2] + 24, chord[3] + 24, chord[2] + 24]
            for i, note in enumerate(figure):
                sec = BEAT * 1.4
                t = t_axis(sec)
                x = (np.sin(2 * np.pi * hz(note) * t) + 0.3 * np.sin(4 * np.pi * hz(note) * t)) \
                    * env(len(t), 0.3, 0.8, sec) * 0.045
                place(left if i % 2 == 0 else right, start + i * BEAT, x)
                place(right if i % 2 == 0 else left, start + i * BEAT + 0.12, x, 0.6)
    return left, right


def reverb(x, sec=4.0, seed=1):
    r = np.random.default_rng(seed)
    t = t_axis(sec)
    tail = r.standard_normal(len(t)) * np.exp(-t * 1.6)
    tail = low(tail, 3000.0) * (t > 0.03)
    tail /= np.sqrt(np.sum(tail ** 2))
    # Circular convolution keeps the loop seamless.
    n = len(x)
    pad = np.zeros(n)
    pad[:len(tail)] = tail[:n]
    return np.real(np.fft.ifft(np.fft.fft(x) * np.fft.fft(pad)))


def main():
    left, right = build()
    wet_l, wet_r = reverb(left, seed=1), reverb(right, seed=2)
    left = left * 0.55 + wet_l * 0.9
    right = right * 0.55 + wet_r * 0.9
    # Gentle bus compression and a ceiling.
    peak = max(np.max(np.abs(left)), np.max(np.abs(right)))
    left, right = np.tanh(left / peak * 1.4) / np.tanh(1.4), np.tanh(right / peak * 1.4) / np.tanh(1.4)
    data = np.stack([left, right], 1) * 0.85
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with wave.open(OUT, "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes((data * 32767).astype("<i2").tobytes())
    print("music", round(len(left) / RATE, 1), "s", round(os.path.getsize(OUT) / 1e6, 1), "MB")


if __name__ == "__main__":
    main()
