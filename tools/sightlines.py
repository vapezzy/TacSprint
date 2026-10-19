"""Quick plan-view check of the arena layout in arena.gd.

Reads the ground-level containers, then reports the longest clear lines at
eye height and the narrowest gaps between neighbouring containers, so the
layout can be tuned without starting the game.

Run: python tools/sightlines.py
"""
import math
import os
import re

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = open(os.path.join(HERE, "..", "arena.gd"), encoding="utf-8").read()
L = {"L20": 6.058, "L40": 12.192}
W = 2.438
X0, X1, Z0, Z1 = -18.05, 18.05, -16.05, 16.05


def rows(name):
    block = SRC[SRC.index("const %s := [" % name):]
    block = block[:block.index("\n]")]
    return re.findall(r"\[(L20|L40), ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+), (\w+|[-\d.]+)\]", block)


boxes = []   # (cx, cz, half length, half width, yaw, open)
for r in rows("LAYOUT"):
    if float(r[4]) == 0:
        boxes.append((float(r[1]), float(r[2]), L[r[0]] / 2, W / 2, math.radians(float(r[3])), r[6] == "true"))
for r in rows("WALLS"):
    boxes.append((float(r[1]), float(r[2]), L[r[0]] / 2, W / 2, math.radians(float(r[3])), False))


def local(px, pz, b):
    """World point to container-local coordinates (length along local x)."""
    cx, cz, hl, hw, yaw, _ = b
    dx, dz = px - cx, pz - cz
    # Godot yaw about +Y: local x maps to (cos, -sin) in (x, z).
    return dx * math.cos(yaw) - dz * math.sin(yaw), dx * math.sin(yaw) + dz * math.cos(yaw)


def blocked(px, pz, margin=0.0):
    for b in boxes:
        lx, lz = local(px, pz, b)
        if b[5]:
            # Walk-through: only the two long walls are solid.
            if abs(lx) <= b[2] + margin and b[3] - 0.09 - margin <= abs(lz) <= b[3] + margin:
                return True
        elif abs(lx) <= b[2] + margin and abs(lz) <= b[3] + margin:
            return True
    return False


def ray(px, pz, ang, step=0.2, limit=60.0):
    dx, dz = math.cos(ang), math.sin(ang)
    d = 0.0
    while d < limit:
        d += step
        x, z = px + dx * d, pz + dz * d
        if x < X0 - 1 or x > X1 + 1 or z < Z0 - 1 or z > Z1 + 1 or blocked(x, z):
            return d
    return limit


def main():
    lines = []
    for px in np.arange(X0 + 0.55, X1, 1.5):
        for pz in np.arange(Z0 + 0.55, Z1, 1.5):
            if blocked(px, pz, 0.35):
                continue
            for k in range(72):
                ang = math.tau * k / 72
                d = ray(px, pz, ang)
                lines.append((d, px, pz, px + math.cos(ang) * d, pz + math.sin(ang) * d))
    lines.sort(reverse=True)
    print("longest clear lines (m): from -> to")
    shown = []
    for d, ax, az, bx, bz in lines:
        # Skip lines that are nearly the same corridor as one already listed.
        if any(abs(ax - s[0]) + abs(az - s[1]) < 5 and abs(bx - s[2]) + abs(bz - s[3]) < 5 or
               abs(ax - s[2]) + abs(az - s[3]) < 5 and abs(bx - s[0]) + abs(bz - s[1]) < 5 for s in shown):
            continue
        shown.append((ax, az, bx, bz))
        print("  %5.1f  (%6.1f, %6.1f) -> (%6.1f, %6.1f)" % (d, ax, az, bx, bz))
        if len(shown) >= 10:
            break
    per_spot = {}
    for d, ax, az, _, _ in lines:
        per_spot[(ax, az)] = max(per_spot.get((ax, az), 0.0), d)
    vals = sorted(per_spot.values())
    print("median of each spot's longest view: %.1f m" % vals[len(vals) // 2])

    # Text plan: '#' solid, '.' free. North is up, one character per metre.
    print()
    for pz in np.arange(Z0 + 0.5, Z1, 1.0):
        print("".join("#" if blocked(px, pz) else "." for px in np.arange(X0 + 0.5, X1, 0.5)))


if __name__ == "__main__":
    main()
