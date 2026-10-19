"""Attachments for the MP5 and the KR-4, and the bare weapon bodies they fit on.

    python tools/make_attachments.py            # everything
    python tools/make_attachments.py optics     # only names containing "optics"

Bodies keep their own coordinates (as in make_gun.py / make_weapons.py).
Muzzle devices are built on the bore axis starting at z = 0 and running down -Z;
optics stand on y = 0 (the top of the rail) centred on z = 0; the laser module
is centred on the origin. viewmodel.gd puts each part where its weapon wants it
(weapons.gd ATTACHMENTS).

Zones: 0 painted steel, 1 polymer, 2 bare steel, 3 dark glass / rubber,
4 brass, 5 copper.
"""
import sys

import numpy as np

import make_gun as mg
import make_weapons as mw
from sdf import (ball, box, cut, cyl, mesh, occlusion, save, seg, smin, split_by_zone, torus, union, v, wear, zones)

STEP = 0.0007


def build(name, groups, lo, hi, keep=0.3):
    if len(sys.argv) > 1 and not any(a in name for a in sys.argv[1:]):
        return
    print(name)
    field = lambda q: union(*[g(q) for _, g in groups])
    verts, normals, faces = mesh(field, lo, hi, STEP, keep)
    ao = occlusion(field, verts, normals)
    worn = wear(field, verts)
    src, faces, zone = split_by_zone(faces, zones(verts[faces].mean(axis=1), groups))
    save(name, verts[src], normals[src], faces, zone, ao[src], worn[src])


# --- bodies -------------------------------------------------------------------

def smg_painted(p):
    body = union(mg.receiver(p), mg.rear_sight(p), mg.cocking_tube(p), mg.front_sight(p), mg.front_housing(p), mg.mag_well(p))
    return cut(body, box(p, v(0, -0.0535, -0.077), (0.0138, 0.0325, 0.0205), 0, 0.001))


def smg_polymer(p):
    """mg.polymer without the moulded fore grip: that is an attachment now."""
    housing = box(p, v(0, -0.035, 0.03), (0.0182, 0.0165, 0.06), 0, 0.004)
    grip = box(p, v(0, -0.098, 0.072), (0.016, 0.05, 0.022), -14.0, 0.007)
    low = smin(housing, grip, 0.006)
    low = smin(low, box(p, v(0, -0.149, 0.0855), (0.0168, 0.0045, 0.0235), -14.0, 0.002), 0.002)
    low = smin(low, box(p, v(0, -0.058, 0.096), (0.013, 0.012, 0.008), 0, 0.006), 0.006)
    guard = smin(box(p, v(0, -0.0835, 0.0135), (0.0062, 0.0022, 0.0335), 0, 0.0015),
                 box(p, v(0, -0.0665, -0.0185), (0.0062, 0.0185, 0.0022), 0, 0.0015), 0.004)
    knob = seg(p, v(-0.052, 0.036, -0.176), v(-0.038, 0.036, -0.176), 0.0082)
    cap = box(p, v(0, 0.006, 0.119), (0.0215, 0.027, 0.008), 0, 0.004)
    cap = cut(cap, box(p, v(0, 0.007, 0.1278), (0.0135, 0.0175, 0.0022), 0, 0.0012))
    selector = np.minimum(cyl(p, v(-0.0238, -0.03, 0.05), v(-0.0182, -0.03, 0.05), 0.0068, 0.001),
                          box(p, v(-0.0222, -0.03, 0.038), (0.0018, 0.0032, 0.012), 0, 0.001))
    return union(low, guard, knob, cap, selector)


def ar_painted_body(p):
    body = mw.ar_painted(p)
    return body


def ar_polymer_body(p):
    charge = box(p, v(0, 0.043, 0.085), (0.014, 0.004, 0.012), 0, 0.002)
    return union(mw.grip(p), charge)


def ar_steel_body(p):
    parts = [
        cyl(p, v(0, mw.AR_Y, -0.525), v(0, mw.AR_Y, -0.35), 0.009, 0.0005),
        cyl(p, v(0, mw.AR_Y, -0.528), v(0, mw.AR_Y, -0.518), 0.0105, 0.0008),     # thread shoulder
        box(p, v(0, mw.AR_Y + 0.012, -0.4), (0.011, 0.016, 0.012), 0, 0.003),
        cyl(p, v(0, 0.018, -0.06), v(0, 0.018, 0.0), 0.0145, 0.001),
        box(p, v(0, mg.SIGHT_Y - 0.0055, -0.33), (0.0011, 0.0055, 0.0014), 0, 0.0004),
        mw.trigger(p),
        box(p, v(0, -0.058, -0.046), (0.0045, 0.011, 0.003), 12.0, 0.001),
    ]
    for y, z in [(-0.012, 0.075), (-0.012, -0.11), (-0.03, 0.062), (-0.03, 0.0)]:
        parts.append(cyl(p, v(-0.0193, y, z), v(0.0193, y, z), 0.0027, 0.0006))
    return union(*parts)


def smg_steel_body(p):
    parts = [
        cyl(p, v(0, 0, -0.318), v(0, 0, -0.232), 0.0085, 0.0005),            # barrel, threaded at the end
        cyl(p, v(0, 0, -0.297), v(0, 0, -0.289), 0.0105, 0.001),
        cyl(p, v(0, 0, -0.243), v(0, 0, -0.233), 0.014, 0.001),
        cyl(p, v(0, 0.036, -0.2745), v(0, 0.036, -0.2625), 0.0137, 0.0015),
        cyl(p, v(0, 0.02, -0.06), v(0, 0.02, 0.004), 0.0168, 0.001),
        box(p, v(0, mg.SIGHT_Y - 0.0065, -0.25), (0.0011, 0.0065, 0.0014), 0, 0.0004),
        seg(p, v(0, -0.0535, 0.021), v(0, -0.0735, 0.0135), 0.0028),
        cyl(p, v(-0.04, 0.036, -0.176), v(-0.008, 0.036, -0.176), 0.0042, 0.0005),
        box(p, v(0, -0.058, -0.046), (0.0045, 0.011, 0.003), 12.0, 0.001),
        torus(p, v(-0.026, 0.012, 0.119), v(0, 0, 1.0), 0.0062, 0.0016),
        cyl(p, v(0, 0.007, 0.1235), v(0, 0.007, 0.1268), 0.0042, 0.0008),
    ]
    for half, y, z in [(0.0209, -0.012, 0.088), (0.0209, -0.013, -0.122), (0.0193, -0.03, 0.062),
                       (0.0193, -0.03, 0.0), (0.0216, -0.014, -0.215), (0.0216, 0.014, -0.146)]:
        parts.append(cyl(p, v(-half, y, z), v(half, y, z), 0.0027, 0.0006))
    return union(*parts)


# --- muzzle devices (bore on the z axis, from z = 0 forward) -------------------------

def _rings(d, p, radius, zs):
    radial = np.sqrt(p[:, 0] ** 2 + p[:, 1] ** 2)
    for z in zs:
        d = cut(d, np.maximum(np.abs(p[:, 2] - z) - 0.0009, (radius - 0.0009) - radial))
    return d


def muz_sup_small(p):
    d = cyl(p, v(0, 0, -0.165), v(0, 0, 0.0), 0.0185, 0.003)
    d = _rings(d, p, 0.0185, list(np.arange(-0.04, -0.0121, 0.0045)) + [-0.125, -0.1295])
    return cut(d, cyl(p, v(0, 0, -0.18), v(0, 0, -0.14), 0.0046))


def muz_sup_large(p):
    d = cyl(p, v(0, 0, -0.2), v(0, 0, 0.0), 0.0215, 0.004)
    d = np.minimum(d, cyl(p, v(0, 0, -0.03), v(0, 0, 0.0), 0.0225, 0.002))
    d = _rings(d, p, 0.0215, list(np.arange(-0.17, -0.05, 0.02)))
    return cut(d, cyl(p, v(0, 0, -0.215), v(0, 0, -0.18), 0.0052))


def muz_hider(p):
    d = cyl(p, v(0, 0, -0.045), v(0, 0, 0.0), 0.011, 0.001)
    for a in range(3):
        ang = a * np.pi / 3
        n = v(np.cos(ang), np.sin(ang), 0)
        q = p - v(0, 0, -0.03)
        d = cut(d, np.maximum(np.abs(q @ n) - 0.0018, np.abs(q[:, 2]) - 0.016))
    return cut(d, cyl(p, v(0, 0, -0.05), v(0, 0, -0.035), 0.0055))


def muz_comp(p):
    """Compensator: ports on top push the muzzle down."""
    d = cyl(p, v(0, 0, -0.05), v(0, 0, 0.0), 0.0128, 0.0015)
    for z in (-0.012, -0.024, -0.036):
        d = cut(d, cyl(p, v(0, 0.004, z), v(0, 0.02, z), 0.0034))
    d = cut(d, box(p, v(0, 0.0, -0.05), (0.004, 0.004, 0.006), 0, 0.001))
    return cut(d, cyl(p, v(0, 0, -0.06), v(0, 0, -0.042), 0.006))


def muz_brake(p):
    """Muzzle brake: big side ports, a wide flat body."""
    d = box(p, v(0, 0, -0.032), (0.0165, 0.0125, 0.032), 0, 0.003)
    for z in (-0.016, -0.032, -0.048):
        d = cut(d, box(p, v(0, 0, z), (0.03, 0.0062, 0.0042), 0, 0.001))
    return cut(d, cyl(p, v(0, 0, -0.07), v(0, 0, -0.055), 0.0062))


# --- fore grips (weapon coordinates, at the shared foregrip spot) -----------------------

def _grip_mount(p, top):
    """Rail clamp from the bottom of the handguard down to the grip."""
    return box(p, v(0, (top - 0.03) / 2.0, -0.188), (0.0175, (top + 0.03) / 2.0 + 0.002, 0.03), 0, 0.003)


def grip_vertical(top):
    def f(p):
        d = box(p, v(0, -0.07, -0.185), (0.015, 0.04, 0.017), 6.0, 0.006)
        return smin(d, _grip_mount(p, top), 0.006)
    return f


def grip_tactical(top):
    """Thicker, ribbed grip with a flared foot."""
    def f(p):
        d = box(p, v(0, -0.07, -0.185), (0.016, 0.04, 0.018), 6.0, 0.007)
        for y in np.arange(-0.095, -0.045, 0.01):
            d = cut(d, box(p, v(0, y, -0.204), (0.02, 0.0015, 0.004), 6.0, 0.0008))
        foot = box(p, v(0, -0.111, -0.181), (0.019, 0.004, 0.021), 6.0, 0.003)
        return union(smin(d, _grip_mount(p, top), 0.006), foot)
    return f


# --- laser module (centred on the origin, beam out of -Z) ------------------------------

def laser_body(p):
    d = box(p, v(0, 0, 0), (0.009, 0.011, 0.026), 0, 0.003)
    d = cut(d, cyl(p, v(0, 0.004, -0.03), v(0, 0.004, -0.022), 0.0036))
    d = cut(d, cyl(p, v(0, -0.004, -0.03), v(0, -0.004, -0.022), 0.0026))
    clamp = box(p, v(-0.008, 0, 0.004), (0.004, 0.008, 0.014), 0, 0.001)
    button = cyl(p, v(0, 0.011, 0.012), v(0, 0.014, 0.012), 0.003, 0.001)
    return union(d, clamp, button)


def laser_glass(p):
    return union(cyl(p, v(0, 0.004, -0.0235), v(0, 0.004, -0.0225), 0.0036),
                 cyl(p, v(0, -0.004, -0.0235), v(0, -0.004, -0.0225), 0.0026))


def light_body(p):
    """Laser with a weapon light underneath: a bigger module with a bezel."""
    d = union(laser_body(p), cyl(p, v(0, -0.02, -0.035), v(0, -0.02, 0.02), 0.0105, 0.002),
              box(p, v(0, -0.011, -0.005), (0.007, 0.006, 0.014), 0, 0.002))
    return cut(d, cyl(p, v(0, -0.02, -0.04), v(0, -0.02, -0.03), 0.0085))


def light_glass(p):
    return union(laser_glass(p), cyl(p, v(0, -0.02, -0.0315), v(0, -0.02, -0.0305), 0.0085))


# --- magazines ---------------------------------------------------------------------------

def _mag(length, loop=False):
    def body(p):
        d = None
        for t in np.arange(-0.012, length + 0.0001, 0.012):
            y, z, lean = mg._curve(t)
            part = box(p, v(0, y, z), (0.0128, 0.0085, 0.0195), lean, 0.0022)
            d = part if d is None else smin(d, part, 0.004)
        for sx in (-1.0, 1.0):
            d = np.minimum(d, box(p, v(sx * 0.0105, -0.0435, -0.072), (0.0014, 0.006, 0.016), 0, 0.0007))
        return d

    def plate(p):
        y, z, lean = mg._curve(length + 0.009)
        d = box(p, v(0, y, z), (0.0146, 0.003, 0.0215), lean, 0.0015)
        if loop:
            # Pull tab under the floor plate for a fast change.
            a = np.radians(lean)
            c = v(0, y - np.cos(a) * 0.016, z - np.sin(a) * 0.016)
            d = np.minimum(d, torus(p, c, v(1.0, 0, 0), 0.011, 0.0028))
        return d
    return body, plate


mag_ext_body, mag_ext_plate = _mag(0.18)
mag_fast_body, mag_fast_plate = _mag(0.12, True)


# --- stocks --------------------------------------------------------------------------------

def smg_stock_fold(p):
    """Folding stock, swung out: two struts and a butt plate."""
    d = None
    for sx in (-1.0, 1.0):
        top = seg(p, v(sx * 0.016, 0.018, 0.126), v(sx * 0.016, 0.012, 0.33), 0.0042)
        low = seg(p, v(sx * 0.016, -0.012, 0.126), v(sx * 0.016, -0.03, 0.33), 0.0042)
        d = union(top, low) if d is None else union(d, top, low)
    hinge = cyl(p, v(-0.02, 0.003, 0.127), v(0.02, 0.003, 0.127), 0.007, 0.001)
    pad = box(p, v(0, -0.01, 0.335), (0.019, 0.05, 0.008), 0, 0.004)
    return union(d, hinge, pad)


def smg_stock_fixed(p):
    d = box(p, v(0, -0.004, 0.225), (0.018, 0.035, 0.1), 0, 0.01)
    d = smin(d, box(p, v(0, -0.02, 0.31), (0.019, 0.05, 0.02), 0, 0.008), 0.02)
    return cut(d, box(p, v(0, -0.02, 0.24), (0.03, 0.012, 0.045), 0, 0.006))


def ar_stock_std(p):
    stock = box(p, v(0, -0.004, 0.265), (0.016, 0.042, 0.05), 0, 0.008)
    return cut(stock, box(p, v(0, -0.02, 0.25), (0.02, 0.012, 0.02), 0, 0.004))


def ar_stock_skel(p):
    """Skeleton stock: a frame instead of a solid block."""
    frame = box(p, v(0, -0.004, 0.265), (0.008, 0.042, 0.05), 0, 0.004)
    frame = cut(frame, box(p, v(0, -0.004, 0.258), (0.02, 0.03, 0.036), 0, 0.006))
    pad = box(p, v(0, -0.004, 0.317), (0.015, 0.045, 0.005), 0, 0.003)
    collar = cyl(p, v(0, mw.AR_Y, 0.2), v(0, mw.AR_Y, 0.235), 0.017, 0.002)
    return union(frame, pad, collar)


# --- optics (standing on the rail top at y = 0, centred on z = 0) ---------------------------

DOT_LINE = 0.022
HOLO_LINE = 0.026
ACOG_LINE = 0.032


def opt_dot(p):
    base = box(p, v(0, 0.004, 0.0), (0.012, 0.004, 0.022), 0, 0.0015)
    hood = box(p, v(0, DOT_LINE, -0.01), (0.0155, 0.0165, 0.009), 0, 0.0035)
    hood = cut(hood, box(p, v(0, DOT_LINE, -0.01), (0.0118, 0.0125, 0.03), 0, 0.003))
    housing = box(p, v(0, 0.012, 0.012), (0.01, 0.006, 0.012), 0, 0.002)
    knob = cyl(p, v(0.01, 0.012, 0.012), v(0.016, 0.012, 0.012), 0.0045, 0.001)
    return union(base, hood, housing, knob)


def opt_holo(p):
    base = box(p, v(0, 0.005, 0.0), (0.016, 0.005, 0.035), 0, 0.002)
    frame = box(p, v(0, HOLO_LINE - 0.002, -0.012), (0.019, 0.019, 0.022), 0, 0.004)
    frame = cut(frame, box(p, v(0, HOLO_LINE, -0.012), (0.0145, 0.0115, 0.04), 0, 0.002))
    hood = box(p, v(0, HOLO_LINE + 0.016, -0.012), (0.019, 0.003, 0.024), 0, 0.002)
    buttons = union(*[cyl(p, v(0.005 * k, 0.011, 0.03), v(0.005 * k, 0.014, 0.03), 0.0022, 0.0006) for k in (-1, 1)])
    return union(base, frame, hood, buttons)


def opt_acog(p):
    base = box(p, v(0, 0.006, 0.0), (0.013, 0.006, 0.03), 0, 0.002)
    tube = cyl(p, v(0, ACOG_LINE, -0.045), v(0, ACOG_LINE, 0.05), 0.0115, 0.002)
    bell = smin(cyl(p, v(0, ACOG_LINE, -0.075), v(0, ACOG_LINE, -0.05), 0.0145, 0.002), tube, 0.008)
    eye = smin(cyl(p, v(0, ACOG_LINE, 0.05), v(0, ACOG_LINE, 0.072), 0.0128, 0.002), tube, 0.006)
    body = smin(box(p, v(0, 0.02, -0.005), (0.012, 0.012, 0.03), 0, 0.004), tube, 0.006)
    fiber = box(p, v(0, ACOG_LINE + 0.013, -0.01), (0.0035, 0.0025, 0.03), 0, 0.001)
    d = union(base, bell, eye, body, fiber)
    d = cut(d, cyl(p, v(0, ACOG_LINE, -0.085), v(0, ACOG_LINE, -0.068), 0.0122))
    return cut(d, cyl(p, v(0, ACOG_LINE, 0.068), v(0, ACOG_LINE, 0.08), 0.0105))


def opt_acog_glass(p):
    return union(cyl(p, v(0, ACOG_LINE, -0.0705), v(0, ACOG_LINE, -0.0685), 0.0122),
                 cyl(p, v(0, ACOG_LINE, 0.0675), v(0, ACOG_LINE, 0.0695), 0.0105))


def smg_mount(p):
    """Claw mount on the MP5's top rib, with a short rail on top (top at y = 0.058)."""
    body = box(p, v(0, 0.0505, -0.02), (0.0105, 0.0055, 0.052), 0, 0.0015)
    claws = union(*[box(p, v(sx * 0.009, 0.044, z), (0.0025, 0.006, 0.006), 0, 0.001)
                    for sx in (-1.0, 1.0) for z in (-0.06, 0.03)])
    rail = box(p, v(0, 0.0555, -0.02), (0.0105, 0.0025, 0.05), 0, 0.001)
    slot = np.abs(np.mod(p[:, 2] + 0.0025, 0.01) - 0.005) - 0.0024
    rail = cut(rail, np.maximum(slot, 0.057 - p[:, 1]))
    levers = union(*[cyl(p, v(0.012, 0.049, z), v(0.02, 0.049, z), 0.003, 0.0008) for z in (-0.06, 0.03)])
    return union(body, claws, rail, levers)


if __name__ == "__main__":
    build("smg_body", [(0, smg_painted), (1, smg_polymer), (2, smg_steel_body)], (-0.066, -0.162, -0.33), (0.033, 0.083, 0.134), 0.24)
    build("ar_body", [(0, ar_painted_body), (1, ar_polymer_body), (2, ar_steel_body)], (-0.035, -0.162, -0.535), (0.035, 0.085, 0.32), 0.22)
    m_lo, m_hi = (-0.03, -0.03, -0.23), (0.03, 0.03, 0.005)
    build("muz_sup_small", [(0, muz_sup_small)], m_lo, m_hi)
    build("muz_sup_large", [(0, muz_sup_large)], m_lo, m_hi)
    build("muz_hider", [(2, muz_hider)], m_lo, m_hi)
    build("muz_comp", [(2, muz_comp)], m_lo, m_hi)
    build("muz_brake", [(0, muz_brake)], m_lo, m_hi)
    g_lo, g_hi = (-0.03, -0.125, -0.23), (0.03, 0.0, -0.14)
    build("grip_vertical_smg", [(1, grip_vertical(-0.0235))], g_lo, g_hi)
    build("grip_tactical_smg", [(1, grip_tactical(-0.0235))], g_lo, g_hi)
    build("grip_vertical_ar", [(1, grip_vertical(-0.0115))], g_lo, (0.03, 0.01, -0.14))
    build("grip_tactical_ar", [(1, grip_tactical(-0.0115))], g_lo, (0.03, 0.01, -0.14))
    l_lo, l_hi = (-0.02, -0.035, -0.045), (0.02, 0.02, 0.035)
    build("laser", [(0, laser_body), (3, laser_glass)], l_lo, l_hi, 0.4)
    build("laser_light", [(0, light_body), (3, light_glass)], l_lo, l_hi, 0.4)
    mag_lo = (-0.02, -0.29, -0.2)
    build("mag_ext", [(0, mag_ext_body), (1, mag_ext_plate), (4, mg.mag_brass), (5, mg.mag_copper)], mag_lo, (0.02, -0.028, -0.048), 0.35)
    build("mag_fast", [(0, mag_fast_body), (1, mag_fast_plate), (4, mg.mag_brass), (5, mg.mag_copper)], mag_lo, (0.02, -0.028, -0.048), 0.35)
    build("smg_stock_fold", [(2, smg_stock_fold)], (-0.03, -0.07, 0.1), (0.03, 0.045, 0.35))
    build("smg_stock_fixed", [(1, smg_stock_fixed)], (-0.03, -0.08, 0.1), (0.03, 0.045, 0.35))
    build("ar_stock_std", [(1, ar_stock_std)], (-0.03, -0.06, 0.19), (0.03, 0.05, 0.33))
    build("ar_stock_skel", [(1, ar_stock_skel)], (-0.03, -0.06, 0.19), (0.03, 0.05, 0.33))
    o_lo, o_hi = (-0.03, -0.002, -0.095), (0.03, 0.05, 0.09)
    build("opt_dot", [(0, opt_dot)], o_lo, o_hi, 0.4)
    build("opt_holo", [(0, opt_holo)], o_lo, o_hi, 0.4)
    build("opt_acog", [(0, opt_acog), (3, opt_acog_glass)], o_lo, o_hi, 0.4)
    build("smg_mount", [(0, smg_mount)], (-0.03, 0.035, -0.08), (0.03, 0.062, 0.04), 0.4)
