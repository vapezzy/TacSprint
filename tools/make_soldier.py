"""Sculpts the operator figures seen in the world (soldier.gd): a head under a
balaclava with goggles, a high-cut helmet with night vision, headset and
counterweight, the combat shirt torso with a full plate carrier, the battle
belt, sleeved arms with shoulder patches, gloved hands, and a light copy of
the KR-4 rifle for them to carry.

    python tools/make_soldier.py [part ...]

Head frame: origin in the middle of the head between the ears, +Y up, -Z the
way the face looks, metres. Torso frame (legs.gd): origin in the middle of the
spine piece, +Y towards the chest, -Z the front. Pelvis frame: origin between
the hip joints. Arm frames as for the legs: origin in the middle of the bone,
+Y towards its far end (elbow, wrist), -Z the front.

Material zones (character.gdshader): 0 uniform camo, 1 nylon gear, 2 boot
leather, 3 polymer and rubber, 4 glove, 5 metal, 6 knitted balaclava, 7 lens.
"""
import os
import struct
import sys

import numpy as np

from sdf import OUT, ball, box, cut, cyl, groove, mesh, occlusion, save, seg, smin, split_by_zone, torus, union, v, wear, zones


def ellipsoid(p, c, r):
    q = (p - c) / np.asarray(r)
    k = np.linalg.norm(q, axis=1)
    return (k - 1.0) * min(r)


def shifted(p, dz):
    """p with each point moved along z by dz (an array): bends flat shapes
    round the body."""
    q = p.copy()
    q[:, 2] -= dz
    return q


def molle(d, p, x0, x1, ys, z, nz, depth=0.0035):
    """Rows of webbing on a face whose outward normal is nz along z, with the
    bar-tack slits between the loops."""
    for yy in ys:
        row = box(p, v((x0 + x1) / 2, yy, z + nz * depth / 2), ((x1 - x0) / 2, 0.0095, depth / 2 + 0.001), 0, 0.0015)
        for xx in np.arange(x0 + 0.02, x1 - 0.01, 0.038):
            row = cut(row, box(p, v(xx, yy, z + nz * depth), (0.0016, 0.012, depth), 0, 0.0006))
        d = np.minimum(d, row)
    return d


# --- head ---------------------------------------------------------------------

def head_masked(p):
    """The head under a knitted balaclava: skull, a defined brow, cheekbones,
    nose and chin showing through the cloth, the mouth only as a soft dip, and
    loose rolled folds round the neck."""
    skull = ellipsoid(p, v(0, 0.03, 0.012), (0.08, 0.091, 0.099))
    jaw = ellipsoid(p, v(0, -0.045, -0.022), (0.064, 0.048, 0.072))
    d = smin(skull, jaw, 0.034)
    d = smin(d, ball(p, v(0, -0.085, -0.066), 0.022), 0.024)                    # chin
    for sx in (-1.0, 1.0):
        d = smin(d, ball(p, v(sx * 0.046, 0.0, -0.062), 0.022), 0.022)          # cheekbones
        d = smin(d, ellipsoid(p, v(sx * 0.078, 0.004, 0.006), (0.012, 0.03, 0.02)), 0.012)   # ears under cloth
        d = -smin(-d, ball(p, v(sx * 0.031, 0.017, -0.103), 0.016), 0.012)    # eye sockets
    d = smin(d, seg(p, v(-0.042, 0.038, -0.084), v(0.042, 0.038, -0.084), 0.011), 0.018)   # brow
    nose = seg(p, v(0, 0.026, -0.094), v(0, -0.016, -0.111), 0.008, 0.012)
    nose = smin(nose, ball(p, v(0, -0.02, -0.107), 0.0135), 0.01)
    d = smin(d, nose, 0.014)
    d = -smin(-d, ellipsoid(p, v(0, -0.051, -0.112), (0.02, 0.006, 0.01)), 0.008)          # mouth
    d = smin(d, seg(p, v(0, -0.06, 0.02), v(0, -0.16, 0.03), 0.06, 0.068), 0.035)          # neck
    y = p[:, 1]
    ang = np.arctan2(p[:, 0], p[:, 2])
    neck = np.clip((-y - 0.075) / 0.04, 0, 1)
    d = d - 0.0032 * neck * np.sin(2 * np.pi * y / 0.026 + 2.5 * np.sin(3 * ang))
    # A seam over the top of the head and the knit's ribs.
    d = groove(d, np.abs(p[:, 0]) - 0.0012, 0.0008)
    return d


def goggles(p):
    """Wrap-around ballistic goggles: a curved lens across the eyes, a moulded
    frame round it, a vent strip on top and a wide strap round the head."""
    band = ellipsoid(p, v(0, 0.018, 0.004), (0.091, 0.102, 0.108))
    y = p[:, 1]
    z = p[:, 2]
    lens = np.maximum(np.abs(band) - 0.0035, np.abs(y - 0.016) - 0.016)
    lens = np.maximum(lens, z + 0.05)
    lens = cut(lens, ball(p, v(0, -0.005, -0.12), 0.014))           # nose cut-out
    return lens


def goggle_frame(p):
    band = ellipsoid(p, v(0, 0.018, 0.004), (0.091, 0.102, 0.108))
    y = p[:, 1]
    z = p[:, 2]
    frame = np.abs(band - 0.003) - 0.0065
    frame = np.maximum(frame, np.abs(np.abs(y - 0.016) - 0.018) - 0.0035)
    frame = np.maximum(frame, z + 0.035)
    frame = cut(frame, ball(p, v(0, -0.005, -0.12), 0.012))
    return frame


def goggle_strap(p):
    z = p[:, 2]
    y = p[:, 1]
    strap = np.abs(ellipsoid(p, v(0, 0.02, 0.008), (0.087, 0.098, 0.103))) - 0.003
    strap = np.maximum(strap, np.abs(y - 0.018) - 0.011)
    return np.maximum(strap, -(z + 0.035))


# --- helmet -------------------------------------------------------------------

def _shell_outer(p):
    d = ellipsoid(p, v(0, 0.034, 0.008), (0.099, 0.106, 0.115))
    # A flatter crown and a fuller back, like a high-cut shell.
    return np.maximum(d, p[:, 1] - 0.132)


def helmet_shell(p):
    """High-cut shell in a cloth cover: cut high over the ears, a short brim at
    the front, lower at the back, a rim round the edge."""
    outer = _shell_outer(p)
    inner = ellipsoid(p, v(0, 0.034, 0.008), (0.088, 0.095, 0.103))
    shell = np.maximum(outer, -inner)
    y = p[:, 1]
    z = p[:, 2]
    edge = 0.04 + 0.022 * np.clip(-z / 0.1, 0, 1) - 0.04 * np.clip(z / 0.1, 0, 1)
    edge = edge - 0.035 * np.exp(-(z / 0.05) ** 2)
    shell = np.maximum(shell, edge - y - 0.01)
    for sx in (-1.0, 1.0):
        shell = cut(shell, ball(p, v(sx * 0.115, -0.012, -0.004), 0.06))
    # Cover seams and loop panels on top and the sides.
    shell = groove(shell, np.abs(p[:, 0]) - 0.0012, 0.0012)
    shell = union(shell, box(p, v(0, 0.13, -0.01), (0.04, 0.004, 0.05), 0, 0.002))
    for sx in (-1.0, 1.0):
        patch = box(p, v(sx * 0.07, 0.085, 0.03), (0.018, 0.024, 0.035), 0, 0.003)
        shell = smin(shell, np.maximum(patch, outer - 0.004), 0.002)
    # Counterweight pouch at the back for the night vision.
    cw = box(p, v(0, 0.045, 0.12), (0.045, 0.028, 0.016), -18, 0.008)
    shell = union(shell, cw)
    return shell


def helmet_hard(p):
    """The hardware: side rails along the cut, the ear cups of the headset on
    their arms, the boom microphone and the night vision goggles flipped up."""
    d = np.full(len(p), 1.0)
    for sx in (-1.0, 1.0):
        rail = box(p, v(sx * 0.095, 0.048, 0.005), (0.006, 0.01, 0.062), 0, 0.002)
        for zz in (-0.035, 0.0, 0.035):
            rail = cut(rail, box(p, v(sx * 0.101, 0.048, zz), (0.004, 0.004, 0.009), 0, 0.001))
        d = union(d, rail)
        # Ear cups hung from the rails.
        cup = cyl(p, v(sx * 0.072, -0.012, 0.004), v(sx * 0.108, -0.012, 0.004), 0.043, 0.012)
        cup = smin(cup, cyl(p, v(sx * 0.1, -0.012, 0.004), v(sx * 0.113, -0.012, 0.004), 0.03, 0.006), 0.006)
        d = union(d, cup)
        d = union(d, seg(p, v(sx * 0.103, 0.03, 0.004), v(sx * 0.108, 0.04, 0.004), 0.007))
    # Boom mic from the right cup to the mouth.
    mic = seg(p, v(0.1, -0.03, -0.02), v(0.072, -0.07, -0.085), 0.004)
    mic = union(mic, seg(p, v(0.072, -0.07, -0.085), v(0.03, -0.078, -0.112), 0.0035))
    mic = union(mic, ball(p, v(0.026, -0.078, -0.114), 0.009))
    d = union(d, mic)
    # Night vision, flipped up over the brim: the housing and two tubes.
    nv = box(p, v(0, 0.124, -0.12), (0.036, 0.022, 0.022), 35, 0.008)
    for sx in (-1.0, 1.0):
        tube = cyl(p, v(sx * 0.024, 0.11, -0.1), v(sx * 0.024, 0.165, -0.142), 0.017, 0.004)
        nv = smin(nv, tube, 0.006)
    d = union(d, nv)
    return d


def helmet_metal(p):
    """The shroud on the front of the shell and the mount arm into it."""
    shroud = box(p, v(0, 0.084, -0.11), (0.022, 0.018, 0.009), -22, 0.004)
    arm = box(p, v(0, 0.104, -0.122), (0.012, 0.014, 0.008), 10, 0.003)
    return union(shroud, arm)


def helmet_lens(p):
    d = np.full(len(p), 1.0)
    for sx in (-1.0, 1.0):
        d = union(d, cyl(p, v(sx * 0.024, 0.163, -0.141), v(sx * 0.024, 0.168, -0.145), 0.014, 0.002))
    return d


# --- torso ----------------------------------------------------------------------

def torso_shirt(p):
    """Combat shirt over a real chest: narrower at the waist, filled out at
    the chest and the lats; folds where it bunches at the waist."""
    y = p[:, 1]
    q = p.copy()
    widen = 1.0 + 0.12 * np.clip((y + 0.1) / 0.25, 0, 1)
    q[:, 0] /= widen
    d = box(q, v(0, -0.01, 0.0), (0.152, 0.215, 0.1), 0, 0.085) * 0.95
    d = smin(d, seg(p, v(-0.13, 0.17, 0.005), v(0.13, 0.17, 0.005), 0.08), 0.06)
    ang = np.arctan2(p[:, 0], p[:, 2])
    waist = np.exp(-((y + 0.17) / 0.05) ** 2)
    return d - (0.0015 + 0.003 * waist) * np.sin(2 * np.pi * y / 0.04 + 2.0 * np.sin(2 * ang + 0.5))


def _plate(p, zsign):
    """A plate bag, curved round the chest (zsign -1 front, +1 back)."""
    x = p[:, 0]
    q = shifted(p, -zsign * 1.1 * x * x)
    return box(q, v(0, 0.035, zsign * 0.128), (0.128, 0.155, 0.027), 0, 0.02)


def torso_gear(p):
    """The plate carrier: front and back plate bags, padded shoulder straps,
    cummerbund with webbing, open-top triple magazine pouch with bungee pull
    tabs, an admin pouch, the radio pouch, a frag pouch, a tourniquet, a
    zip-on back panel with a drag handle."""
    front = _plate(p, -1.0)
    back = _plate(p, 1.0)
    d = np.minimum(front, back)
    y = p[:, 1]
    # Cummerbund: a band round the waist between the plates.
    ring = (np.linalg.norm((p[:, [0, 2]] - 0) / np.array([0.178, 0.138]), axis=1) - 1.0) * 0.138
    band = np.maximum(np.abs(ring) - 0.011, np.abs(y + 0.07) - 0.07)
    d = smin(d, band, 0.01)
    for sx in (-1.0, 1.0):
        # Padded shoulder straps over the top, flat and wide.
        strap = seg(p, v(sx * 0.1, 0.18, -0.13), v(sx * 0.105, 0.255, -0.02), 0.022)
        strap = smin(strap, seg(p, v(sx * 0.105, 0.255, -0.02), v(sx * 0.1, 0.18, 0.13), 0.022), 0.03)
        strap = np.maximum(strap, np.abs(p[:, 0] - sx * 0.102) - 0.035)
        d = smin(d, strap, 0.012)
    # Webbing rows on the cummerbund sides and on the front bag above the pouches.
    for sx in (-1.0, 1.0):
        for yy in (-0.035, -0.075, -0.115):
            r = np.maximum(np.abs(ring + 0.0) - 0.014, np.abs(y - yy) - 0.0095)
            r = np.maximum(r, -(sx * p[:, 0] - 0.13))
            r = np.maximum(r, np.abs(p[:, 2]) - 0.1)
            d = np.minimum(d, r)
    d = molle(d, shifted(p, 1.1 * p[:, 0] ** 2), -0.11, 0.11, (0.13, 0.165), -0.155, -1.0)
    # Triple magazine pouch, shingle style, open at the top.
    q = shifted(p, 1.1 * p[:, 0] ** 2)
    for x in (-0.074, 0.0, 0.074):
        pouch = box(q, v(x, -0.035, -0.178), (0.034, 0.06, 0.026), 0, 0.009)
        pouch = cut(pouch, box(q, v(x, 0.03, -0.178), (0.027, 0.02, 0.019), 0, 0.004))
        pouch = groove(pouch, np.abs(q[:, 1] + 0.005) - 0.0007, 0.0009)
        tab = box(q, v(x, 0.034, -0.198), (0.009, 0.014, 0.004), 0, 0.002)
        d = union(d, pouch, tab)
    # Admin pouch on the upper chest with a patch.
    adm = box(q, v(0, 0.098, -0.175), (0.072, 0.03, 0.02), 0, 0.009)
    d = union(d, adm)
    # Radio pouch on the left side of the back, a frag pouch on the right side.
    d = union(d, box(p, v(-0.165, 0.0, 0.085), (0.03, 0.075, 0.036), 0, 0.012))
    d = union(d, cyl(p, v(0.19, -0.13, -0.04), v(0.19, -0.02, -0.04), 0.03, 0.01))
    d = union(d, box(p, v(0.19, -0.015, -0.04), (0.032, 0.012, 0.03), 0, 0.006))
    # Tourniquet strapped to the left front.
    d = union(d, cyl(p, v(-0.15, 0.07, -0.13), v(-0.15, 0.17, -0.13), 0.017, 0.006))
    # Zip-on back panel with webbing and a drag handle.
    bp = box(shifted(p, -1.1 * p[:, 0] ** 2), v(0, 0.02, 0.175), (0.11, 0.135, 0.024), 0, 0.016)
    d = union(d, bp)
    d = molle(d, shifted(p, -1.1 * p[:, 0] ** 2), -0.095, 0.095, (-0.05, -0.012, 0.026, 0.064), 0.199, 1.0)
    d = union(d, torus(p, v(0, 0.2, 0.15), v(1.0, 0, 0), 0.03, 0.008))
    return d


def torso_poly(p):
    """Magazines standing in the pouches, the radio, the PTT and its cable,
    the frag and the tourniquet's windlass."""
    q = shifted(p, 1.1 * p[:, 0] ** 2)
    d = np.full(len(p), 1.0)
    for i, x in enumerate((-0.074, 0.0, 0.074)):
        mag = box(q, v(x, 0.035, -0.178 + 0.004 * i), (0.026, 0.034, 0.0125), 8, 0.004)
        mag = union(mag, box(q, v(x, 0.068, -0.18), (0.028, 0.005, 0.015), 8, 0.002))
        for zz in (-0.0125, 0.0125):
            mag = groove(mag, np.abs(q[:, 2] - (-0.178 + zz)) - 0.0008, 0.0008)
        d = union(d, mag)
    radio = box(p, v(-0.165, 0.09, 0.085), (0.026, 0.035, 0.03), 0, 0.006)
    radio = union(radio, cyl(p, v(-0.165, 0.12, 0.1), v(-0.165, 0.15, 0.1), 0.007))
    d = union(d, radio)
    # PTT on the left shoulder strap and its cable down the side.
    d = union(d, box(p, v(-0.1, 0.205, -0.13), (0.018, 0.018, 0.01), -30, 0.005))
    d = union(d, seg(p, v(-0.115, 0.19, -0.12), v(-0.17, 0.12, 0.0), 0.0035))
    d = union(d, seg(p, v(-0.17, 0.12, 0.0), v(-0.165, 0.13, 0.07), 0.0035))
    # Frag spoon and fuse sticking out of its pouch.
    d = union(d, ball(p, v(0.19, 0.0, -0.04), 0.022))
    d = union(d, box(p, v(0.19, 0.03, -0.04), (0.006, 0.014, 0.006), 0, 0.002))
    d = union(d, box(p, v(-0.15, 0.12, -0.152), (0.006, 0.03, 0.006), 0, 0.002))
    return d


def torso_metal(p):
    """Buckles on the cummerbund and the radio's antenna, up past the shoulder."""
    d = np.full(len(p), 1.0)
    for sx in (-1.0, 1.0):
        d = union(d, box(p, v(sx * 0.125, -0.07, -0.14), (0.012, 0.016, 0.006), 0, 0.002))
    d = union(d, seg(p, v(-0.165, 0.15, 0.1), v(-0.175, 0.42, 0.12), 0.0035, 0.002))
    return d


def belt_gear(p):
    """Battle belt in the pelvis frame: a padded belt, a drop holster on the
    right thigh, a dump pouch at the back left, pistol mag pouches at the
    front left and a medical pouch at the back."""
    y = p[:, 1]
    ring = (np.linalg.norm(p[:, [0, 2]] / np.array([0.158, 0.128]), axis=1) - 1.0) * 0.128
    d = np.maximum(np.abs(ring) - 0.012, np.abs(y - 0.04) - 0.03)
    d = groove(d, np.abs(np.abs(y - 0.04) - 0.018) - 0.0008, 0.0008)
    # Holster on a drop leg platform.
    d = union(d, box(p, v(0.175, -0.04, 0.0), (0.012, 0.075, 0.03), 0, 0.006))
    d = union(d, box(p, v(0.188, -0.085, -0.005), (0.018, 0.075, 0.04), -8, 0.012))
    for yy in (-0.13, -0.19):
        d = union(d, np.maximum(np.abs((np.linalg.norm((p[:, [0, 2]] - np.array([0.11, 0.0])) / np.array([0.095, 0.09]), axis=1) - 1.0) * 0.09) - 0.004,
                                np.abs(y - yy) - 0.012))
    d = union(d, box(p, v(-0.13, -0.02, 0.09), (0.04, 0.06, 0.035), 20, 0.018))
    for x in (-0.085, -0.045):
        d = union(d, box(p, v(x, 0.02, -0.14), (0.018, 0.04, 0.014), 0, 0.005))
    d = union(d, box(p, v(0.04, 0.03, 0.14), (0.065, 0.04, 0.03), 0, 0.012))
    return d


def belt_hard(p):
    d = box(p, v(0, 0.04, -0.132), (0.032, 0.024, 0.008), 0, 0.004)                  # cobra buckle
    d = union(d, box(p, v(0.19, 0.0, -0.02), (0.016, 0.03, 0.02), -8, 0.006))         # pistol grip
    for x in (-0.085, -0.045):
        d = union(d, box(p, v(x, 0.065, -0.14), (0.012, 0.01, 0.009), 0, 0.003))
    return d


# --- shoulders and arms ---------------------------------------------------------

UPPER = 0.29
FORE = 0.28


def shoulders(p):
    """The top of the body in the shirt, in the aiming frame (soldier.gd: the
    upper body's pivot, +Y up, -Z forward): trapezius from the neck out to each
    shoulder, round deltoids, the upper chest, and a collar round the neck."""
    d = ellipsoid(p, v(0, -0.035, 0.0), (0.17, 0.085, 0.11))
    for sx in (-1.0, 1.0):
        trap = seg(p, v(sx * 0.045, 0.075, 0.02), v(sx * 0.165, 0.025, 0.0), 0.048, 0.056)
        d = smin(d, trap, 0.04)
        delt = ellipsoid(p, v(sx * 0.19, -0.005, -0.006), (0.064, 0.074, 0.07))
        d = smin(d, delt, 0.035)
    collar = ellipsoid(p, v(0, 0.065, 0.018), (0.074, 0.042, 0.068))
    d = smin(d, collar, 0.02)
    y = p[:, 1]
    ang = np.arctan2(p[:, 0], p[:, 2])
    return d - 0.0018 * np.sin(2 * np.pi * y / 0.045 + 2.0 * np.sin(2 * ang))


def upper_arm(p, side):
    """Upper arm in the sleeve: round at the deltoid, biceps and triceps,
    narrowing to the elbow; soft folds, and a loop patch on the outside."""
    d = seg(p, v(0, -UPPER / 2 - 0.01, 0), v(0, UPPER / 2, 0), 0.058, 0.048)
    d = smin(d, ellipsoid(p, v(0, -0.01, 0.018), (0.043, 0.075, 0.04)), 0.02)
    d = smin(d, ellipsoid(p, v(0, -0.03, -0.016), (0.041, 0.08, 0.036)), 0.02)
    y = p[:, 1]
    ang = np.arctan2(p[:, 0], p[:, 2])
    folds = np.sin(2 * np.pi * y / 0.05 + 1.6 * np.sin(2 * ang)) * np.clip((y + 0.02) / 0.12, 0, 1)
    d = d - 0.0026 * folds
    # Elbow: the sleeve gathers in rings.
    d = d - 0.003 * np.exp(-((y - 0.13) / 0.025) ** 2) * np.sin(2 * np.pi * y / 0.016)
    # Pocket on the outside of the sleeve.
    pocket = box(p, v(side * 0.053, -0.055, 0.0), (0.009, 0.045, 0.034), 0, 0.007)
    return smin(d, pocket, 0.006)


def upper_patch(p, side):
    return box(p, v(side * 0.061, -0.065, 0.0), (0.004, 0.022, 0.026), 0, 0.002)


def forearm(p):
    d = seg(p, v(0, -FORE / 2 - 0.01, 0), v(0, FORE / 2 - 0.03, 0), 0.053, 0.042)
    y = p[:, 1]
    ang = np.arctan2(p[:, 0], p[:, 2])
    bunch = np.exp(-((y + 0.02) / 0.05) ** 2)
    d = d - (0.003 + 0.0045 * bunch) * np.sin(2 * np.pi * y / 0.035 + 2.0 * np.sin(3 * ang))
    # The cuff closes round the glove.
    return smin(d, seg(p, v(0, FORE / 2 - 0.07, 0), v(0, FORE / 2 - 0.04, 0), 0.046), 0.01)


def forearm_glove(p):
    return seg(p, v(0, FORE / 2 - 0.05, 0), v(0, FORE / 2 + 0.01, 0), 0.04, 0.039)


def hand(p):
    """A gloved hand closed round a grip, in the hand frame: -Z the way the
    rifle points, +Y up. Back of the hand outwards (+X), four fingers curled
    under the grip, the thumb wrapped over the top."""
    d = box(p, v(0.012, 0.0, 0.01), (0.016, 0.042, 0.038), 0, 0.014)
    for i in range(4):
        yy = 0.03 - i * 0.021
        r = 0.0105 - i * 0.0008
        finger = seg(p, v(0.02, yy, -0.022), v(-0.012, yy - 0.003, -0.036), r)
        finger = smin(finger, seg(p, v(-0.012, yy - 0.003, -0.036), v(-0.026, yy - 0.006, -0.012), r * 0.92), 0.004)
        d = smin(d, finger, 0.006)
    thumb = seg(p, v(0.0, 0.035, 0.03), v(-0.022, 0.05, -0.008), 0.0115, 0.0095)
    d = smin(d, thumb, 0.008)
    return smin(d, seg(p, v(0.01, 0.0, 0.03), v(0.01, 0.0, 0.07), 0.034, 0.038), 0.012)


def hand_guard(p):
    """Moulded knuckle guard on the back of the glove."""
    k = box(p, v(0.03, 0.0, -0.015), (0.006, 0.04, 0.012), 0, 0.005)
    return k


# --- building ----------------------------------------------------------------------

def build(name, parts, lo, hi, step, keep):
    print(name)
    whole = lambda q: union(*[fn(q) for _, fn in parts])
    verts, normals, faces = mesh(whole, lo, hi, step, keep)
    ao = occlusion(whole, verts, normals, (0.003, 0.008, 0.016))
    worn = wear(whole, verts, 0.0015, 40.0, 240.0)
    src, faces, zone = split_by_zone(faces, zones(verts[faces].mean(axis=1), parts))
    save(name, verts[src], normals[src], faces, zone, ao[src], worn[src])


def load(name):
    with open(os.path.join(OUT, name + ".bin"), "rb") as fh:
        b = fh.read()
    n, ni = struct.unpack("<II", b[4:12])
    o = 12
    pos = np.frombuffer(b, "<f4", n * 3, o).reshape(-1, 3); o += n * 12
    nor = np.frombuffer(b, "<f4", n * 3, o).reshape(-1, 3); o += n * 12
    uv = np.frombuffer(b, "<f4", n * 2, o).reshape(-1, 2); o += n * 8
    uv2 = np.frombuffer(b, "<f4", n * 2, o).reshape(-1, 2); o += n * 8
    idx = np.frombuffer(b, "<i4", ni, o).reshape(-1, 3)
    return pos, nor, uv, uv2, idx


def light_rifle(name, sources, keep):
    """A light copy of a weapon for the figures: the parts merged, each
    material decimated on its own, the weapon zones mapped to the figure's
    (painted and bare steel -> metal, polymer -> polymer, glass -> lens)."""
    import fast_simplification
    remap = {0: 5, 1: 3, 2: 5, 3: 7}
    P, N, Z, A, W, F = [], [], [], [], [], []
    count = 0
    for src, offset in sources:
        pos, nor, uv, uv2, idx = load(src)
        pos = pos + np.asarray(offset)
        zone = np.rint(uv[:, 0] * 7.0).astype(int)
        for z in np.unique(zone):
            fz = idx[(zone[idx[:, 0]] == z)]
            used, inv = np.unique(fz, return_inverse=True)
            vv = pos[used].astype(np.float32)
            ff = inv.reshape(-1, 3).astype(np.int32)
            if len(ff) > 200:
                vv, ff = fast_simplification.simplify(vv, ff, target_reduction=1.0 - keep, agg=5)
            # Nearest source vertex for normals, occlusion and wear.
            from scipy.spatial import cKDTree
            near = cKDTree(pos[used]).query(vv)[1]
            P.append(vv)
            N.append(nor[used][near])
            Z.append(np.full(len(vv), remap.get(int(z), 3)))
            A.append(uv[used][near][:, 1])
            W.append(uv2[used][near])
            F.append(ff + count)
            count += len(vv)
    P, N, Z, A, W, F = map(np.concatenate, (P, N, Z, A, W, F))
    # Faces keep their winding from the source meshes.
    save(name, P, N, F, Z, A, W)


PARTS = {
    "head": lambda: build("soldier_head_masked", [(6, head_masked)], (-0.1, -0.2, -0.13), (0.1, 0.14, 0.12), 0.0016, 0.14),
    "goggles": lambda: build("soldier_goggles", [(7, goggles), (3, goggle_frame), (1, goggle_strap)], (-0.11, -0.02, -0.125), (0.11, 0.06, 0.12), 0.0011, 0.08),
    "helmet": lambda: build("soldier_helmet", [(1, helmet_shell), (3, helmet_hard), (5, helmet_metal), (7, helmet_lens)],
                            (-0.13, -0.1, -0.17), (0.13, 0.18, 0.15), 0.0016, 0.12),
    "torso": lambda: build("soldier_torso", [(0, torso_shirt), (1, torso_gear), (3, torso_poly), (5, torso_metal)],
                           (-0.25, -0.24, -0.23), (0.25, 0.44, 0.24), 0.0022, 0.12),
    "belt": lambda: build("soldier_belt", [(1, belt_gear), (3, belt_hard)], (-0.22, -0.23, -0.18), (0.23, 0.09, 0.18), 0.002, 0.14),
    "shoulders": lambda: build("soldier_shoulders", [(0, shoulders)], (-0.29, -0.13, -0.13), (0.29, 0.14, 0.13), 0.0022, 0.1),
    "hand": lambda: build("soldier_hand", [(4, hand), (3, hand_guard)], (-0.05, -0.06, -0.06), (0.06, 0.08, 0.09), 0.0012, 0.2),
    "arms": lambda: [build("soldier_upper_arm_" + t, [(0, lambda q, s=s: upper_arm(q, s)), (1, lambda q, s=s: upper_patch(q, s))],
                           (-0.09, -0.24, -0.09), (0.09, 0.2, 0.09), 0.002, 0.1) for t, s in (("r", 1.0), ("l", -1.0))],
    "forearm": lambda: build("soldier_forearm", [(0, forearm), (4, forearm_glove)], (-0.07, -0.18, -0.07), (0.07, 0.17, 0.07), 0.002, 0.1),
    "rifle": lambda: light_rifle("soldier_rifle", [("ar_body", (0, 0, 0)), ("mag", (0, 0, 0)), ("opt_holo", (0, 0.055, -0.02))], 0.07),
}


if __name__ == "__main__":
    wanted = sys.argv[1:] or list(PARTS)
    for key in wanted:
        PARTS[key]()
