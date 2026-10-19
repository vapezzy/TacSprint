"""Builds the weapon and its magazine as detailed meshes.

A compact submachine gun with a suppressor, modelled from rounded solids:
stamped receiver with stiffening ribs, cocking tube with its slot and handle,
hooded front sight and drum rear sight, polymer trigger housing, pistol grip,
vertical foregrip with hand stop, pins, selector and a curved magazine with
two rounds showing. Edges come out as fine bevels, which is what catches the
light on a real weapon.

The gun points down -Z, +X is its right side. The sight line is at y = SIGHT_Y.
Zones: 0 painted steel, 1 polymer, 2 bare steel, 4 brass, 5 copper.

Run: python tools/make_gun.py
"""
import numpy as np

from sdf import (ball, box, cut, cyl, mesh, occlusion, save, seg, smin, split_by_zone, torus, union, v, wear, zones)

SIGHT_Y = 0.066
STEP = 0.0007


# --- painted steel ------------------------------------------------------------

def receiver(p):
    tube = cyl(p, v(0, 0.022, -0.142), v(0, 0.022, 0.108), 0.0212, 0.002)
    lower = box(p, v(0, 0.001, -0.017), (0.0198, 0.021, 0.123), 0, 0.003)
    d = np.minimum(tube, lower)
    for sx in (-1.0, 1.0):
        # Pressed stiffening ribs along both sides.
        d = np.minimum(d, box(p, v(sx * 0.0203, 0.009, -0.005), (0.0014, 0.0032, 0.062), 0, 0.0012))
        d = np.minimum(d, box(p, v(sx * 0.0203, -0.008, 0.022), (0.0014, 0.0028, 0.04), 0, 0.0012))
    # Top rib with the notches a sight mount claws into.
    rib = box(p, v(0, 0.0438, -0.005), (0.0062, 0.0026, 0.085), 0, 0.001)
    for z in (-0.06, -0.02, 0.03):
        rib = cut(rib, box(p, v(0, 0.0458, z), (0.008, 0.0022, 0.004), 0, 0.0005))
    d = np.minimum(d, rib)
    # Ejection port, cut deep enough to show the bolt.
    return cut(d, box(p, v(0.021, 0.016, -0.028), (0.007, 0.0085, 0.026), 0, 0.0015))


def rear_sight(p):
    d = cyl(p, v(0, 0.0415, 0.08), v(0, 0.054, 0.08), 0.0125, 0.0015)
    d = np.minimum(d, cyl(p, v(0, 0.054, 0.08), v(0, 0.0585, 0.08), 0.0105, 0.001))
    for sx in (-1.0, 1.0):
        d = np.minimum(d, box(p, v(sx * 0.0086, SIGHT_Y - 0.0025, 0.08), (0.0031, 0.0075, 0.0065), 0, 0.0012))
    return d


def cocking_tube(p):
    d = cyl(p, v(0, 0.036, -0.268), v(0, 0.036, -0.125), 0.0125, 0.002)
    return cut(d, box(p, v(-0.0115, 0.036, -0.2), (0.0045, 0.0032, 0.048), 0, 0.001))


def front_sight(p):
    tower = box(p, v(0, 0.0495, -0.25), (0.0055, 0.0075, 0.007), 0, 0.0015)
    hood = torus(p, v(0, SIGHT_Y, -0.25), v(0, 0, 1.0), 0.0122, 0.0021)
    return np.minimum(tower, hood)


def front_housing(p):
    d = box(p, v(0, 0.0, -0.183), (0.0205, 0.0235, 0.052), 0, 0.004)
    for sx in (-1.0, 1.0):
        # Shallow lightening pocket on each side.
        d = cut(d, box(p, v(sx * 0.0212, 0.004, -0.186), (0.0018, 0.0095, 0.03), 0, 0.0012))
    return d


def mag_well(p):
    return box(p, v(0, -0.036, -0.076), (0.0172, 0.016, 0.026), 0, 0.0025)


def suppressor(p):
    d = cyl(p, v(0, 0, -0.47), v(0, 0, -0.305), 0.0185, 0.003)
    radial = np.sqrt(p[:, 0] ** 2 + p[:, 1] ** 2)
    # Knurled band near the mount, then two wrench flats' worth of rings further out.
    for z in list(np.arange(-0.345, -0.3179, 0.0045)) + [-0.43, -0.4345]:
        ring = np.maximum(np.abs(p[:, 2] - z) - 0.0009, (0.0185 - 0.0009) - radial)
        d = cut(d, ring)
    return cut(d, cyl(p, v(0, 0, -0.49), v(0, 0, -0.44), 0.0046))


def painted(p):
    body = union(receiver(p), rear_sight(p), cocking_tube(p), front_sight(p), front_housing(p), mag_well(p))
    # The magazine cavity, open at the bottom.
    body = cut(body, box(p, v(0, -0.0535, -0.077), (0.0138, 0.0325, 0.0205), 0, 0.001))
    return np.minimum(body, suppressor(p))


# --- polymer ------------------------------------------------------------------

def polymer(p):
    housing = box(p, v(0, -0.035, 0.03), (0.0182, 0.0165, 0.06), 0, 0.004)
    grip = box(p, v(0, -0.098, 0.072), (0.016, 0.05, 0.022), -14.0, 0.007)
    low = smin(housing, grip, 0.006)
    low = smin(low, box(p, v(0, -0.149, 0.0855), (0.0168, 0.0045, 0.0235), -14.0, 0.002), 0.002)
    low = smin(low, box(p, v(0, -0.058, 0.096), (0.013, 0.012, 0.008), 0, 0.006), 0.006)       # beavertail
    guard = smin(box(p, v(0, -0.0835, 0.0135), (0.0062, 0.0022, 0.0335), 0, 0.0015),
                 box(p, v(0, -0.0665, -0.0185), (0.0062, 0.0185, 0.0022), 0, 0.0015), 0.004)
    fore = box(p, v(0, -0.07, -0.185), (0.015, 0.04, 0.017), 6.0, 0.006)
    fore = smin(fore, box(p, v(0, -0.027, -0.188), (0.0195, 0.007, 0.046), 0, 0.003), 0.006)
    fore = smin(fore, box(p, v(0, -0.046, -0.2365), (0.0148, 0.0155, 0.006), 0, 0.0035), 0.006)
    knob = seg(p, v(-0.052, 0.036, -0.176), v(-0.038, 0.036, -0.176), 0.0082)
    cap = box(p, v(0, 0.006, 0.119), (0.0215, 0.027, 0.008), 0, 0.004)
    # Recessed panel on the rear face, and a slot for the sling on the left edge.
    cap = cut(cap, box(p, v(0, 0.007, 0.1278), (0.0135, 0.0175, 0.0022), 0, 0.0012))
    cap = cut(cap, box(p, v(-0.0205, 0.012, 0.119), (0.003, 0.009, 0.0028), 0, 0.001))
    selector = np.minimum(cyl(p, v(-0.0238, -0.03, 0.05), v(-0.0182, -0.03, 0.05), 0.0068, 0.001),
                          box(p, v(-0.0222, -0.03, 0.038), (0.0018, 0.0032, 0.012), 0, 0.001))
    return union(low, guard, fore, knob, cap, selector)


# --- bare steel -----------------------------------------------------------------

def steel(p):
    parts = [
        cyl(p, v(0, 0, -0.306), v(0, 0, -0.232), 0.0085, 0.0005),            # barrel
        cyl(p, v(0, 0, -0.297), v(0, 0, -0.289), 0.0105, 0.001),             # lugs
        cyl(p, v(0, 0, -0.243), v(0, 0, -0.233), 0.014, 0.001),              # barrel nut
        cyl(p, v(0, 0.036, -0.2745), v(0, 0.036, -0.2625), 0.0137, 0.0015),  # cocking tube cap
        cyl(p, v(0, 0, -0.3125), v(0, 0, -0.3005), 0.0196, 0.001),           # suppressor mount ring
        cyl(p, v(0, 0.02, -0.06), v(0, 0.02, 0.004), 0.0168, 0.001),         # bolt, seen through the port
        box(p, v(0, SIGHT_Y - 0.0065, -0.25), (0.0011, 0.0065, 0.0014), 0, 0.0004),   # front sight post
        seg(p, v(0, -0.0535, 0.021), v(0, -0.0735, 0.0135), 0.0028),         # trigger
        cyl(p, v(-0.04, 0.036, -0.176), v(-0.008, 0.036, -0.176), 0.0042, 0.0005),    # cocking handle stem
        box(p, v(0, -0.058, -0.046), (0.0045, 0.011, 0.003), 12.0, 0.001),   # magazine release paddle
        torus(p, v(-0.026, 0.012, 0.119), v(0, 0, 1.0), 0.0062, 0.0016),     # sling loop
        cyl(p, v(0, 0.007, 0.1235), v(0, 0.007, 0.1268), 0.0042, 0.0008),    # end cap screw
    ]
    # Cross pins, standing just proud of the surface they pass through.
    for half, y, z in [(0.0209, -0.012, 0.088), (0.0209, -0.013, -0.122), (0.0193, -0.03, 0.062),
                       (0.0193, -0.03, 0.0), (0.0216, -0.014, -0.215), (0.0216, 0.014, -0.146)]:
        parts.append(cyl(p, v(-half, y, z), v(half, y, z), 0.0027, 0.0006))
    return union(*parts)


def gun(p):
    return union(painted(p), polymer(p), steel(p))


# --- magazine -------------------------------------------------------------------

def _curve(t):
    """Centre and lean of the magazine body at distance t below the feed end."""
    bend = max(t, 0.0)
    y = -0.068 - t
    z = -0.077 - 1.6 * bend * bend
    lean = np.degrees(np.arctan(3.2 * bend)) + 2.0
    return y, z, lean


def mag_body(p):
    d = None
    grooves = None
    for t in np.arange(-0.012, 0.1201, 0.012):
        y, z, lean = _curve(t)
        part = box(p, v(0, y, z), (0.0128, 0.0085, 0.0195), lean, 0.0022)
        d = part if d is None else smin(d, part, 0.004)
        a = np.radians(lean)
        for sx in (-1.0, 1.0):
            for off in (-0.0075, 0.006):
                c = v(sx * 0.0131, y - np.sin(a) * off, z + np.cos(a) * off)
                g = box(p, c, (0.001, 0.0085, 0.0028), lean, 0.0008)
                grooves = g if grooves is None else np.minimum(grooves, g)
    d = cut(d, grooves)
    for sx in (-1.0, 1.0):
        d = np.minimum(d, box(p, v(sx * 0.0105, -0.0435, -0.072), (0.0014, 0.006, 0.016), 0, 0.0007))   # feed lips
    return d


def mag_plate(p):
    y, z, lean = _curve(0.129)
    return box(p, v(0, y, z), (0.0146, 0.003, 0.0215), lean, 0.0015)


ROUNDS = [(-0.0042, -0.0445), (0.0042, -0.0385)]


def mag_brass(p):
    return union(*[cyl(p, v(x, y, -0.083), v(x, y, -0.062), 0.0048, 0.0006) for x, y in ROUNDS])


def mag_copper(p):
    return union(*[seg(p, v(x, y, -0.085), v(x, y, -0.0925), 0.0045, 0.0024) for x, y in ROUNDS])


def magazine(p):
    return union(mag_body(p), mag_plate(p), mag_brass(p), mag_copper(p))


def build(name, field, groups, lo, hi, shade, keep):
    print(name)
    verts, normals, faces = mesh(field, lo, hi, STEP, keep)
    ao = occlusion(shade, verts, normals)
    worn = wear(field, verts)
    # Each triangle takes the material of the part its centre lies on.
    src, faces, zone = split_by_zone(faces, zones(verts[faces].mean(axis=1), groups))
    save(name, verts[src], normals[src], faces, zone, ao[src], worn[src])


if __name__ == "__main__":
    together = lambda q: np.minimum(gun(q), magazine(q))
    build("gun", gun, [(0, painted), (1, polymer), (2, steel)],
          (-0.066, -0.162, -0.48), (0.033, 0.083, 0.134), together, 0.24)
    build("mag", magazine, [(0, mag_body), (1, mag_plate), (4, mag_brass), (5, mag_copper)],
          (-0.02, -0.215, -0.135), (0.02, -0.028, -0.048), magazine, 0.35)
