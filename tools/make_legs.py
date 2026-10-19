"""Builds the leg parts the player sees when looking down.

Three rigid pieces per leg, each in the frame of its bone: thigh (hip to
knee), shin (knee to ankle) and boot. The game moves them with the knee
solver in legs.gd. Trousers get folds, a side seam and a cargo pocket; the
shin carries a strapped knee pad; the boot has a treaded sole, a toe cap,
a padded collar and laces.

Bone frame for thigh and shin: origin at the middle of the bone, +Y towards
its far end (knee, ankle), +Z the front of the leg, +X the wearer's right.
Boot frame: origin at the ankle, +Y up, -Z towards the toes.
Zones: 0 trouser cloth, 2 boot leather, 3 rubber (sole, knee pad, straps).

Run: python tools/make_legs.py
"""
import sys

import numpy as np

from sdf import ball, box, cut, groove, mesh, occlusion, save, seg, smin, split_by_zone, torus, union, v, wear, zones

THIGH = 0.44
SHIN = 0.45


def _around(p):
    return np.arctan2(p[:, 0], p[:, 2])


# --- thigh --------------------------------------------------------------------

def thigh_cloth(p, side):
    """Trousers over a real thigh: full at the hip, the quadriceps bulging at the
    front, the hamstrings behind, narrowing to the knee. Folds only where cloth
    really bunches: in the hip crease and behind the knee."""
    y = p[:, 1]
    ang = _around(p)
    s = (y + THIGH / 2) / THIGH                      # 0 at the hip, 1 at the knee
    d = seg(p, v(0, -THIGH / 2, 0), v(0, THIGH / 2, 0), 0.088, 0.062)
    quad = seg(p, v(0, -THIGH / 2 + 0.06, 0.03), v(0, THIGH / 2 - 0.09, 0.022), 0.07, 0.052)
    ham = seg(p, v(0, -THIGH / 2 + 0.05, -0.025), v(0, THIGH / 2 - 0.12, -0.018), 0.07, 0.05)
    d = smin(d, smin(quad, ham, 0.03), 0.03)
    # Hip crease: a few soft rolls across the front at the top.
    crease = np.exp(-(s / 0.12) ** 2) * np.clip(np.cos(ang), 0.0, 1.0)
    d = d - 0.0022 * crease * np.sin(2 * np.pi * y / 0.024 + 1.5 * np.sin(ang * 2.0))
    # Behind the knee the cloth gathers in a few deep, slanted folds.
    back = np.exp(-((1.0 - s) / 0.14) ** 2) * np.clip(-np.cos(ang), 0.0, 1.0)
    d = d - 0.0035 * back * np.sin(2 * np.pi * (y + 0.2 * p[:, 0]) / 0.03)
    # Long gentle draping down the leg, much calmer than before.
    d = d - 0.0012 * np.sin(2 * np.pi * y / 0.11 + 2.0 * ang + 0.4)
    # Out- and inseam.
    for a_seam in (side * np.pi / 2, -side * np.pi / 2):
        seam = np.abs(np.angle(np.exp(1j * (ang - a_seam)))) * 0.075
        d = groove(d, seam - 0.0009, 0.0007)
    # Cargo pocket on the outside: a flat panel with a flap, stitched round the edge.
    out = v(side, 0, 0)
    c = v(side * 0.072, 0.03, 0.006)
    panel = box(p, c, (0.01, 0.07, 0.056), 0, 0.012)
    d = smin(d, panel, 0.01)
    flap = box(p, c + v(side * 0.004, -0.06, 0.0), (0.008, 0.018, 0.06), 0, 0.006)
    d = smin(d, flap, 0.003)
    stitch = np.abs(box(p, c + v(side * 0.006, 0.0, 0.0), (0.02, 0.064, 0.05), 0, 0.01)) - 0.0005
    d = groove(d, np.maximum(stitch, -(p @ out) + 0.07), 0.0006)
    return d


# --- shin ---------------------------------------------------------------------

def shin_cloth(p, side):
    y = p[:, 1]
    ang = _around(p)
    d = seg(p, v(0, -SHIN / 2, 0), v(0, SHIN / 2 - 0.05, 0), 0.068, 0.058)
    s = (y + SHIN / 2) / SHIN
    # The trouser leg is bloused into the boot, so it bunches up near the bottom.
    amp = 0.0008 + 0.0035 * np.exp(-((s - 0.8) / 0.1) ** 2)
    folds = np.sin(2 * np.pi * y / 0.042 + 2.0 * np.sin(2 * ang + 1.1) + 1.3 * np.sin(3 * ang + 0.3))
    seam = np.exp(-((np.abs(ang - side * np.pi / 2) * 0.06) / 0.0025) ** 2)
    blouse = 0.008 * np.exp(-((s - 0.8) / 0.08) ** 2)
    return d - amp * folds - 0.0012 * seam - blouse


def shin_pad(p, side):
    """Hard-shell knee pad: a domed cap with a moulded rim and a ridge, on a soft
    backing, held by two straps round the leg."""
    k = v(0, -SHIN / 2 + 0.03, 0.05)
    shell = ball(p, k, 0.058)
    shell = np.maximum(shell, -(p[:, 2] - 0.035))             # only the front half
    shell = np.maximum(shell, np.abs(p[:, 1] - k[1]) - 0.07)
    rim = np.abs(ball(p, k, 0.06)) - 0.0025
    rim = np.maximum(rim, np.maximum(-(p[:, 2] - 0.033), np.abs(p[:, 1] - k[1]) - 0.071))
    ridge = box(p, k + v(0, 0, 0.055), (0.02, 0.05, 0.004), 0, 0.003)
    straps = union(torus(p, v(0, -SHIN / 2 - 0.012, 0.004), v(0, 1.0, 0), 0.066, 0.0055),
                   torus(p, v(0, -SHIN / 2 + 0.085, 0.003), v(0, 1.0, 0), 0.062, 0.0055))
    buckle = box(p, v(side * 0.062, -SHIN / 2 + 0.085, 0.01), (0.006, 0.01, 0.012), 0, 0.002)
    return union(smin(shell, ridge, 0.004), rim, straps, buckle)


# --- boot ---------------------------------------------------------------------

def boot_sole(p, side):
    d = box(p, v(0, -0.079, -0.068), (0.05, 0.011, 0.142), 0, 0.006)
    heel = box(p, v(0, -0.084, 0.04), (0.046, 0.008, 0.04), 0, 0.004)
    d = np.minimum(d, heel)
    # Tread: grooves across the sole.
    z = p[:, 2]
    for zg in np.arange(-0.19, 0.07, 0.022):
        groove = np.maximum(np.abs(z - zg) - 0.0035, p[:, 1] + 0.083)
        d = cut(d, groove)
    return d


def boot_upper(p, side):
    foot = seg(p, v(0, -0.036, 0.045), v(0, -0.043, -0.165), 0.046, 0.04)
    foot = np.maximum(foot, -(p[:, 1] + 0.072))                 # flat underside on the sole
    shaft = seg(p, v(0, -0.02, 0.012), v(0, 0.13, 0.004), 0.05, 0.052)
    d = smin(foot, shaft, 0.03)
    # Padded collar, toe cap seam and heel counter.
    d = smin(d, torus(p, v(0, 0.128, 0.004), v(0, 1.0, 0), 0.05, 0.009), 0.006)
    toe_seam = np.maximum(np.abs(p[:, 2] + 0.118) - 0.0012, -(p[:, 1] + 0.062))
    d = groove(d, toe_seam, 0.0012)
    # Laces: bars across the instep and up the shaft.
    for i in range(7):
        t = i / 6.0
        y = -0.012 + 0.125 * t
        zc = -0.075 * (1.0 - t) ** 1.6 - 0.046 - 0.006 * t
        d = smin(d, seg(p, v(-0.022, y, zc), v(0.022, y, zc), 0.0032), 0.002)
    return d


# --- torso ---------------------------------------------------------------------
# Frame: origin at the middle of the spine piece, +Y up towards the chest,
# -Z the front of the body.

def torso_shirt(p, side):
    core = box(p, v(0, 0.0, 0.0), (0.165, 0.2, 0.098), 0, 0.075)
    # Shoulders slope away instead of ending in a flat cut.
    core = smin(core, seg(p, v(-0.13, 0.17, 0.0), v(0.13, 0.17, 0.0), 0.075), 0.05)
    y = p[:, 1]
    ang = np.arctan2(p[:, 0], p[:, 2])
    folds = np.sin(2 * np.pi * y / 0.06 + 2.0 * np.sin(2 * ang + 0.5))
    return core - 0.0022 * folds


def torso_gear(p, side):
    """Plate carrier: front and back plates in their bags, shoulder straps,
    cummerbund, a triple magazine pouch with flaps, and MOLLE webbing rows."""
    front = box(p, v(0, 0.02, -0.095), (0.13, 0.15, 0.028), 0, 0.022)
    back = box(p, v(0, 0.02, 0.095), (0.13, 0.15, 0.028), 0, 0.022)
    d = np.minimum(front, back)
    for sx in (-1.0, 1.0):
        d = smin(d, seg(p, v(sx * 0.092, 0.16, -0.088), v(sx * 0.092, 0.215, 0.0), 0.023), 0.012)
        d = smin(d, seg(p, v(sx * 0.092, 0.215, 0.0), v(sx * 0.092, 0.16, 0.088), 0.023), 0.012)
        d = smin(d, box(p, v(sx * 0.148, -0.06, 0.0), (0.02, 0.055, 0.092), 0, 0.012), 0.01)
    # MOLLE: rows of webbing with bar tacks, on the plate bag.
    for yy in (0.05, 0.085, 0.12):
        row = box(p, v(0, yy, -0.124), (0.118, 0.0095, 0.0035), 0, 0.002)
        for xx in np.arange(-0.1, 0.101, 0.038):
            row = cut(row, box(p, v(xx, yy, -0.128), (0.0018, 0.012, 0.004), 0, 0.0008))
        d = np.minimum(d, row)
    for x in (-0.088, 0.0, 0.088):
        pouch = box(p, v(x, -0.075, -0.136), (0.036, 0.058, 0.02), 0, 0.01)
        flap = box(p, v(x, -0.025, -0.142), (0.038, 0.018, 0.021), 0, 0.008)
        pouch = smin(pouch, flap, 0.004)
        pouch = groove(pouch, np.abs(p[:, 1] + 0.043) - 0.0006, 0.0008)
        d = np.minimum(d, pouch)
    return d


def torso_hard(p, side):
    # Radio on the left side with its antenna stub, buckle in the middle.
    radio = box(p, v(-0.105, 0.09, -0.14), (0.026, 0.05, 0.018), 0, 0.006)
    radio = np.minimum(radio, seg(p, v(-0.12, 0.14, -0.14), v(-0.12, 0.2, -0.14), 0.005))
    return np.minimum(radio, box(p, v(0.0, 0.165, -0.125), (0.022, 0.014, 0.008), 0, 0.004))


def build(name, parts, lo, hi, step, keep, side):
    print(name)
    fields = [(zone, (lambda q, fn=fn: fn(q, side))) for zone, fn in parts]
    whole = lambda q: union(*[fn(q) for _, fn in fields])
    verts, normals, faces = mesh(whole, lo, hi, step, keep)
    ao = occlusion(whole, verts, normals, (0.004, 0.01, 0.02))
    worn = wear(whole, verts, 0.002, 40.0, 240.0)
    src, faces, zone = split_by_zone(faces, zones(verts[faces].mean(axis=1), fields))
    save(name, verts[src], normals[src], faces, zone, ao[src], worn[src])


if __name__ == "__main__":
    build("torso", [(1, torso_shirt), (0, torso_gear), (3, torso_hard)], (-0.25, -0.3, -0.2), (0.25, 0.3, 0.2), 0.002, 0.2, 1.0)
    if "--torso" in sys.argv:
        sys.exit(0)
    for tag, side in (("r", 1.0), ("l", -1.0)):
        build("thigh_" + tag, [(0, thigh_cloth)], (-0.13, -0.33, -0.13), (0.13, 0.31, 0.13), 0.002, 0.14, side)
        build("shin_" + tag, [(0, shin_cloth), (3, shin_pad)], (-0.1, -0.3, -0.1), (0.1, 0.25, 0.12), 0.002, 0.16, side)
        build("boot_" + tag, [(2, boot_upper), (3, boot_sole)], (-0.07, -0.1, -0.23), (0.07, 0.16, 0.1), 0.0015, 0.16, side)
