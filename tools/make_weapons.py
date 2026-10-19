"""Builds the other weapons of the class system: assault rifle, sniper rifle,
pistol and knife. (The submachine gun comes from make_gun.py.)

All of them are built around the same pistol grip, and the two long guns
around the same vertical foregrip and magazine position, so the hand models
fit every weapon without change.

The weapon points down -Z, +X is its right side.
Zones: 0 painted steel, 1 polymer, 2 bare steel, 3 dark glass / rubber.

Run: python tools/make_weapons.py
"""
import numpy as np

from make_gun import SIGHT_Y, mag_well, rear_sight
from sdf import (ball, box, cut, cyl, mesh, occlusion, save, seg, smin, split_by_zone, torus, union, v, wear, zones)

STEP = 0.0008


def grip(p, guard=True):
    """Trigger housing, pistol grip and trigger guard, shared by every firearm."""
    housing = box(p, v(0, -0.035, 0.03), (0.0182, 0.0165, 0.06), 0, 0.004)
    handle = box(p, v(0, -0.098, 0.072), (0.016, 0.05, 0.022), -14.0, 0.007)
    low = smin(housing, handle, 0.006)
    low = smin(low, box(p, v(0, -0.149, 0.0855), (0.0168, 0.0045, 0.0235), -14.0, 0.002), 0.002)
    low = smin(low, box(p, v(0, -0.058, 0.096), (0.013, 0.012, 0.008), 0, 0.006), 0.006)
    if not guard:
        return low
    loop = smin(box(p, v(0, -0.0835, 0.0135), (0.0062, 0.0022, 0.0335), 0, 0.0015),
                box(p, v(0, -0.0665, -0.0185), (0.0062, 0.0185, 0.0022), 0, 0.0015), 0.004)
    return np.minimum(low, loop)


def foregrip(p):
    d = box(p, v(0, -0.07, -0.185), (0.015, 0.04, 0.017), 6.0, 0.006)
    return smin(d, box(p, v(0, -0.027, -0.188), (0.0175, 0.006, 0.03), 0, 0.003), 0.006)


def trigger(p):
    return seg(p, v(0, -0.0535, 0.021), v(0, -0.0735, 0.0135), 0.0028)


def well_cut(d, p):
    return cut(d, box(p, v(0, -0.0535, -0.077), (0.0138, 0.0325, 0.0205), 0, 0.001))


# --- assault rifle --------------------------------------------------------------

AR_Y = 0.012


def ar_painted(p):
    upper = box(p, v(0, AR_Y, -0.02), (0.018, 0.03, 0.11), 0, 0.004)
    upper = cut(upper, box(p, v(0.019, 0.016, -0.03), (0.006, 0.008, 0.028), 0, 0.0015))       # ejection port
    upper = np.minimum(upper, cyl(p, v(0.018, 0.02, 0.03), v(0.024, 0.02, 0.03), 0.006, 0.001))   # forward assist
    rail = box(p, v(0, 0.046, -0.13), (0.0105, 0.004, 0.22), 0, 0.001)
    slot = np.abs(np.mod(p[:, 2] + 0.0025, 0.01) - 0.005) - 0.0024
    rail = cut(rail, np.maximum(slot, 0.0465 - p[:, 1]))
    guard = cyl(p, v(0, AR_Y, -0.36), v(0, AR_Y, -0.13), 0.0235, 0.003)
    for z in (-0.33, -0.28, -0.23, -0.18):
        for sx in (-1.0, 1.0):
            guard = cut(guard, box(p, v(sx * 0.024, AR_Y, z), (0.004, 0.0045, 0.016), 0, 0.002))
    front = box(p, v(0, 0.057, -0.33), (0.006, 0.008, 0.008), 0, 0.0015)
    hood = torus(p, v(0, SIGHT_Y, -0.33), v(0, 0, 1.0), 0.011, 0.002)
    tube = cyl(p, v(0, AR_Y, 0.09), v(0, AR_Y, 0.3), 0.0145, 0.002)
    body = union(upper, rail, guard, front, hood, tube, mag_well(p), rear_sight(p))
    return well_cut(body, p)


def ar_polymer(p):
    stock = box(p, v(0, -0.004, 0.265), (0.016, 0.042, 0.05), 0, 0.008)
    stock = cut(stock, box(p, v(0, -0.02, 0.25), (0.02, 0.012, 0.02), 0, 0.004))
    charge = box(p, v(0, 0.043, 0.085), (0.014, 0.004, 0.012), 0, 0.002)
    return union(grip(p), foregrip(p), stock, charge)


def ar_steel(p):
    hider = cyl(p, v(0, AR_Y, -0.565), v(0, AR_Y, -0.52), 0.011, 0.001)
    for a in range(3):
        ang = a * np.pi / 3
        n = v(np.cos(ang), np.sin(ang), 0)
        q = p - v(0, AR_Y, -0.545)
        hider = cut(hider, np.maximum(np.abs(q @ n) - 0.0018, np.abs(q[:, 2]) - 0.014))
    parts = [
        cyl(p, v(0, AR_Y, -0.52), v(0, AR_Y, -0.35), 0.009, 0.0005),
        hider,
        box(p, v(0, AR_Y + 0.012, -0.4), (0.011, 0.016, 0.012), 0, 0.003),                 # gas block
        cyl(p, v(0, 0.018, -0.06), v(0, 0.018, 0.0), 0.0145, 0.001),                       # bolt
        box(p, v(0, SIGHT_Y - 0.0055, -0.33), (0.0011, 0.0055, 0.0014), 0, 0.0004),        # front post
        trigger(p),
        box(p, v(0, -0.058, -0.046), (0.0045, 0.011, 0.003), 12.0, 0.001),
    ]
    for y, z in [(-0.012, 0.075), (-0.012, -0.11), (-0.03, 0.062), (-0.03, 0.0)]:
        parts.append(cyl(p, v(-0.0193, y, z), v(0.0193, y, z), 0.0027, 0.0006))
    return union(*parts)


# --- sniper rifle ---------------------------------------------------------------
# A heavy .50 bolt-action: fluted barrel with a slotted muzzle brake, a slim
# chassis with lightening slots, a folded bipod, a long box magazine and a
# scope on two rings.

SCOPE_Y = 0.078
SN_Y = 0.016
MAG_Z = -0.078


def _slotted_rail(p, z0, z1):
    rail = box(p, v(0, 0.04, (z0 + z1) / 2), (0.0105, 0.0045, (z1 - z0) / 2), 0, 0.001)
    slot = np.abs(np.mod(p[:, 2] + 0.0025, 0.01) - 0.005) - 0.0024
    return cut(rail, np.maximum(slot, 0.0412 - p[:, 1]))


def sn_scope(p):
    tube = cyl(p, v(0, SCOPE_Y, -0.1), v(0, SCOPE_Y, 0.1), 0.0152, 0.002)
    bell = smin(cyl(p, v(0, SCOPE_Y, -0.245), v(0, SCOPE_Y, -0.125), 0.027, 0.003), tube, 0.014)
    eye = smin(cyl(p, v(0, SCOPE_Y, 0.1), v(0, SCOPE_Y, 0.17), 0.021, 0.003), tube, 0.008)
    eye = np.minimum(eye, cyl(p, v(0, SCOPE_Y, 0.118), v(0, SCOPE_Y, 0.132), 0.0225, 0.0015))     # zoom ring
    saddle = box(p, v(0, SCOPE_Y, 0.0), (0.019, 0.019, 0.017), 0, 0.006)
    turrets = union(cyl(p, v(0, SCOPE_Y, 0.0), v(0, SCOPE_Y + 0.04, 0.0), 0.012, 0.002),
                    cyl(p, v(0, SCOPE_Y, 0.0), v(0.04, SCOPE_Y, 0.0), 0.012, 0.002),
                    cyl(p, v(0, SCOPE_Y, 0.0), v(-0.03, SCOPE_Y, 0.0), 0.0105, 0.002))
    d = union(bell, eye, saddle, turrets)
    for z in (-0.07, 0.06):
        # Ring: a clamp round the tube on a foot that sits on the rail.
        ring = cyl(p, v(0, SCOPE_Y, z - 0.008), v(0, SCOPE_Y, z + 0.008), 0.0195, 0.002)
        foot = box(p, v(0, 0.052, z), (0.012, 0.012, 0.008), 0, 0.002)
        d = np.minimum(d, smin(ring, foot, 0.004))
    # Hollow ends so the lenses sit recessed.
    d = cut(d, cyl(p, v(0, SCOPE_Y, -0.26), v(0, SCOPE_Y, -0.232), 0.0235))
    return cut(d, cyl(p, v(0, SCOPE_Y, 0.16), v(0, SCOPE_Y, 0.18), 0.017))


def sn_painted(p):
    """Receiver, chassis, rail, bipod and magazine well. Barrel and optic are separate parts."""
    action = cyl(p, v(0, SN_Y, -0.17), v(0, SN_Y, 0.1), 0.0195, 0.002)
    action = cut(action, box(p, v(0.016, SN_Y + 0.004, -0.04), (0.01, 0.008, 0.04), 0, 0.0015))
    chassis = box(p, v(0, -0.008, -0.15), (0.019, 0.017, 0.27), 0, 0.005)
    for z in np.arange(-0.39, -0.2, 0.045):
        for sx in (-1.0, 1.0):
            chassis = cut(chassis, box(p, v(sx * 0.02, -0.008, z), (0.004, 0.0055, 0.014), 0, 0.002))
    stock = cyl(p, v(0, SN_Y - 0.004, 0.1), v(0, SN_Y - 0.004, 0.3), 0.012, 0.002)
    # Bipod, folded forward under the fore-end.
    bipod = box(p, v(0, -0.03, -0.385), (0.017, 0.008, 0.016), 0, 0.003)
    for sx in (-1.0, 1.0):
        bipod = np.minimum(bipod, seg(p, v(sx * 0.016, -0.034, -0.39), v(sx * 0.021, -0.038, -0.6), 0.0058))
        bipod = np.minimum(bipod, seg(p, v(sx * 0.021, -0.038, -0.6), v(sx * 0.021, -0.038, -0.625), 0.0075))
    well = box(p, v(0, -0.03, MAG_Z), (0.0195, 0.012, 0.066), 0, 0.003)
    # Barrel nut where every barrel screws in.
    nut = cyl(p, v(0, SN_Y, -0.2), v(0, SN_Y, -0.165), 0.0175, 0.002)
    body = union(action, chassis, _slotted_rail(p, -0.17, 0.09), stock, bipod, well, nut)
    return cut(body, box(p, v(0, -0.06, MAG_Z), (0.0158, 0.04, 0.0615), 0, 0.001))


def _fluted(p, z0, z1, r, flute0, flute1):
    barrel = cyl(p, v(0, SN_Y, z0), v(0, SN_Y, z1), r, 0.001)
    for k in range(6):
        ang = k * np.pi / 3 + 0.5
        c = v(np.cos(ang) * (r + 0.0014), SN_Y + np.sin(ang) * (r + 0.0014), 0)
        barrel = cut(barrel, seg(p, c + v(0, 0, flute0), c + v(0, 0, flute1), 0.0042))
    return barrel


def _brake(p, z, half_w, half_h, half_l):
    brake = box(p, v(0, SN_Y, z), (half_w, half_h, half_l), 0, 0.004)
    for dz in (-0.5, 0.0, 0.5):
        brake = cut(brake, box(p, v(0, SN_Y, z + dz * half_l), (half_w * 1.6, half_h * 0.52, half_l * 0.125), 0, 0.001))
    return cut(brake, cyl(p, v(0, SN_Y, z - half_l * 1.4), v(0, SN_Y, z - half_l * 0.6), 0.0068))


def sn_barrel_standard(p):
    return union(_fluted(p, -0.78, -0.2, 0.0128, -0.72, -0.46), _brake(p, -0.815, 0.019, 0.0145, 0.04))


def sn_barrel_long(p):
    """Heavier, longer barrel with a bigger brake."""
    return union(_fluted(p, -0.92, -0.2, 0.0145, -0.86, -0.42), _brake(p, -0.962, 0.022, 0.0165, 0.046))


def sn_barrel_sup(p):
    """Short barrel inside a full-length suppressor."""
    barrel = cyl(p, v(0, SN_Y, -0.56), v(0, SN_Y, -0.2), 0.0128, 0.001)
    can = cyl(p, v(0, SN_Y, -0.8), v(0, SN_Y, -0.53), 0.0235, 0.004)
    for z in np.arange(-0.77, -0.55, 0.03):
        can = cut(can, torus(p, v(0, SN_Y, z), v(0, 0, 1.0), 0.0245, 0.0018))
    can = cut(can, cyl(p, v(0, SN_Y, -0.81), v(0, SN_Y, -0.79), 0.0062))
    collar = cyl(p, v(0, SN_Y, -0.54), v(0, SN_Y, -0.52), 0.0255, 0.002)
    return union(barrel, can, collar)


def sn_scope_compact(p):
    """Short low-power scope: quicker to the eye, less magnification."""
    tube = cyl(p, v(0, SCOPE_Y, -0.09), v(0, SCOPE_Y, 0.06), 0.0142, 0.002)
    bell = smin(cyl(p, v(0, SCOPE_Y, -0.165), v(0, SCOPE_Y, -0.1), 0.0205, 0.003), tube, 0.01)
    eye = smin(cyl(p, v(0, SCOPE_Y, 0.06), v(0, SCOPE_Y, 0.12), 0.0185, 0.003), tube, 0.007)
    saddle = box(p, v(0, SCOPE_Y, -0.01), (0.016, 0.016, 0.014), 0, 0.005)
    turrets = union(cyl(p, v(0, SCOPE_Y, -0.01), v(0, SCOPE_Y + 0.028, -0.01), 0.0095, 0.002),
                    cyl(p, v(0, SCOPE_Y, -0.01), v(0.028, SCOPE_Y, -0.01), 0.0095, 0.002))
    d = union(bell, eye, saddle, turrets)
    for z in (-0.06, 0.04):
        ring = cyl(p, v(0, SCOPE_Y, z - 0.007), v(0, SCOPE_Y, z + 0.007), 0.018, 0.002)
        foot = box(p, v(0, 0.052, z), (0.012, 0.012, 0.007), 0, 0.002)
        d = np.minimum(d, smin(ring, foot, 0.004))
    d = cut(d, cyl(p, v(0, SCOPE_Y, -0.18), v(0, SCOPE_Y, -0.152), 0.0175))
    return cut(d, cyl(p, v(0, SCOPE_Y, 0.11), v(0, SCOPE_Y, 0.13), 0.015))


def sn_glass_compact(p):
    return union(cyl(p, v(0, SCOPE_Y, -0.156), v(0, SCOPE_Y, -0.152), 0.0175),
                 cyl(p, v(0, SCOPE_Y, 0.108), v(0, SCOPE_Y, 0.112), 0.015))


DOT_Y = 0.066


def sn_dot(p):
    """Open reflex sight: a base on the rail and a hood round the window."""
    base = box(p, v(0, 0.049, -0.03), (0.013, 0.006, 0.026), 0, 0.002)
    hood = box(p, v(0, DOT_Y, -0.04), (0.0175, 0.019, 0.011), 0, 0.004)
    hood = cut(hood, box(p, v(0, DOT_Y, -0.04), (0.0135, 0.0145, 0.03), 0, 0.003))
    housing = box(p, v(0, 0.056, -0.012), (0.011, 0.006, 0.014), 0, 0.002)
    knob = cyl(p, v(0.011, 0.056, -0.012), v(0.017, 0.056, -0.012), 0.005, 0.001)
    return union(base, hood, housing, knob)


def sn_stock(p):
    butt = box(p, v(0, -0.004, 0.275), (0.017, 0.048, 0.045), 0, 0.01)
    butt = cut(butt, box(p, v(0, -0.012, 0.262), (0.03, 0.02, 0.018), 0, 0.006))
    return np.minimum(butt, box(p, v(0, 0.03, 0.22), (0.014, 0.008, 0.05), 0, 0.006))


def sn_polymer(p):
    return union(grip(p), foregrip(p), sn_stock(p))


def sn_polymer_plain(p):
    return union(grip(p), sn_stock(p))


def sn_steel(p):
    return union(trigger(p), box(p, v(0, -0.05, -0.008), (0.004, 0.012, 0.003), 12.0, 0.001))


def sn_bolt(p):
    """Bolt with its handle: a separate part, so it can be worked after every shot."""
    handle = cyl(p, v(0.015, SN_Y, 0.065), v(0.05, SN_Y - 0.014, 0.078), 0.0042, 0.0005)
    body = cyl(p, v(0, SN_Y, -0.09), v(0, SN_Y, 0.075), 0.0138, 0.001)
    shroud = cyl(p, v(0, SN_Y, 0.075), v(0, SN_Y, 0.098), 0.0155, 0.003)
    return union(handle, ball(p, v(0.054, SN_Y - 0.016, 0.079), 0.0105), body, shroud)


def sn_glass(p):
    return union(cyl(p, v(0, SCOPE_Y, -0.236), v(0, SCOPE_Y, -0.232), 0.0235),
                 cyl(p, v(0, SCOPE_Y, 0.158), v(0, SCOPE_Y, 0.162), 0.017))


def sn_mag(p):
    body = box(p, v(0, -0.092, MAG_Z), (0.0148, 0.052, 0.06), 2.0, 0.003)
    for sx in (-1.0, 1.0):
        for z in (-0.03, 0.0, 0.03):
            body = cut(body, box(p, v(sx * 0.0152, -0.1, MAG_Z + z), (0.001, 0.034, 0.008), 2.0, 0.0008))
    body = cut(body, box(p, v(0, -0.036, MAG_Z), (0.011, 0.012, 0.056), 0, 0.001))      # open top
    return np.minimum(body, box(p, v(0, -0.147, MAG_Z - 0.002), (0.0162, 0.0035, 0.0625), 2.0, 0.0018))


def sn_mag_brass(p):
    return cyl(p, v(0, -0.0445, MAG_Z + 0.05), v(0, -0.0445, MAG_Z - 0.03), 0.0078, 0.001)


def sn_mag_copper(p):
    return seg(p, v(0, -0.0445, MAG_Z - 0.03), v(0, -0.0445, MAG_Z - 0.052), 0.0062, 0.002)


# --- pistol ---------------------------------------------------------------------

PISTOL_SIGHT = 0.017


def pi_painted(p):
    slide = box(p, v(0, -0.004, 0.015), (0.0135, 0.014, 0.095), 0, 0.003)
    for z in np.arange(0.07, 0.1, 0.006):
        for sx in (-1.0, 1.0):
            slide = cut(slide, box(p, v(sx * 0.0142, -0.004, z), (0.0012, 0.011, 0.0014), 0, 0.0004))
    slide = cut(slide, box(p, v(0.01, 0.004, 0.0), (0.008, 0.008, 0.02), 0, 0.0015))
    front = box(p, v(0, PISTOL_SIGHT - 0.004, -0.07), (0.0016, 0.004, 0.004), 0, 0.0006)
    rear = None
    for sx in (-1.0, 1.0):
        w = box(p, v(sx * 0.0048, PISTOL_SIGHT - 0.004, 0.1), (0.0028, 0.004, 0.004), 0, 0.0008)
        rear = w if rear is None else np.minimum(rear, w)
    return union(slide, front, rear)


def pi_polymer(p):
    cover = box(p, v(0, -0.026, -0.05), (0.0125, 0.0085, 0.032), 0, 0.003)
    return np.minimum(grip(p), cover)


def pi_steel(p):
    return union(cyl(p, v(0, -0.002, -0.086), v(0, -0.002, -0.06), 0.0062, 0.0006),
                 cyl(p, v(0, 0.0, -0.02), v(0, 0.0, 0.025), 0.0085, 0.001), trigger(p),
                 cyl(p, v(-0.0193, -0.03, 0.0), v(0.0193, -0.03, 0.0), 0.0026, 0.0006))


# --- knife ----------------------------------------------------------------------

def kn_polymer(p):
    handle = box(p, v(0, -0.098, 0.072), (0.0125, 0.05, 0.017), -14.0, 0.008)
    a = np.radians(-14.0)
    for off in np.arange(-0.03, 0.031, 0.012):
        c = v(0, -0.098 + np.cos(a) * off, 0.072 + np.sin(a) * off)
        handle = cut(handle, torus(p, c, v(0, np.cos(a), np.sin(a)), 0.0205, 0.0022))
    pommel = box(p, v(0, -0.151, 0.0855), (0.014, 0.004, 0.019), -14.0, 0.003)
    return np.minimum(handle, pommel)


def kn_steel(p):
    guard = box(p, v(0, -0.047, 0.0595), (0.0065, 0.0035, 0.03), -14.0, 0.002)
    blade = box(p, v(0, 0.042, 0.0375), (0.0016, 0.09, 0.016), -14.0, 0.0012)
    # Round the spine down into a point.
    a = np.radians(-14.0)
    up = v(0, np.cos(a), np.sin(a))
    back = v(0, -np.sin(a), np.cos(a))
    blade = np.maximum(blade, ball(p, v(0, 0.042, 0.0375) - up * 0.062 + back * 0.016, 0.153))
    return np.minimum(guard, blade)


def build(name, groups, lo, hi, keep):
    print(name)
    field = lambda q: union(*[g(q) for _, g in groups])
    verts, normals, faces = mesh(field, lo, hi, STEP, keep)
    ao = occlusion(field, verts, normals)
    worn = wear(field, verts)
    src, faces, zone = split_by_zone(faces, zones(verts[faces].mean(axis=1), groups))
    save(name, verts[src], normals[src], faces, zone, ao[src], worn[src])


def sniper_set():
    box_lo, box_hi = (-0.045, -0.165, -0.66), (0.065, 0.06, 0.33)
    build("sniper", [(0, sn_painted), (1, sn_polymer), (2, sn_steel)], box_lo, box_hi, 0.2)
    build("sniper_nogrip", [(0, sn_painted), (1, sn_polymer_plain), (2, sn_steel)], box_lo, box_hi, 0.2)
    build("sniper_mag", [(0, sn_mag), (4, sn_mag_brass), (5, sn_mag_copper)], (-0.022, -0.158, -0.148), (0.022, -0.03, -0.008), 0.4)
    build("sniper_bolt", [(2, sn_bolt)], (-0.02, -0.01, -0.1), (0.07, 0.04, 0.11), 0.4)
    attachments()


def attachments():
    """The sniper rifle's swappable barrels and optics."""
    b_lo, b_hi = (-0.03, -0.012, -1.02), (0.03, 0.045, -0.15)
    build("sniper_barrel_standard", [(0, sn_barrel_standard)], b_lo, b_hi, 0.3)
    build("sniper_barrel_long", [(0, sn_barrel_long)], b_lo, b_hi, 0.3)
    build("sniper_barrel_sup", [(0, sn_barrel_sup)], b_lo, b_hi, 0.3)
    o_lo, o_hi = (-0.04, 0.035, -0.275), (0.05, 0.13, 0.19)
    build("sniper_optic_scope", [(0, sn_scope), (3, sn_glass)], o_lo, o_hi, 0.3)
    build("sniper_optic_compact", [(0, sn_scope_compact), (3, sn_glass_compact)], o_lo, o_hi, 0.3)
    build("sniper_optic_dot", [(0, sn_dot)], o_lo, o_hi, 0.4)


if __name__ == "__main__":
    import sys
    if "--sniper" in sys.argv:
        sniper_set()
        sys.exit(0)
    if "--attachments" in sys.argv:
        attachments()
        sys.exit(0)
    build("ar", [(0, ar_painted), (1, ar_polymer), (2, ar_steel)], (-0.035, -0.162, -0.575), (0.035, 0.085, 0.325), 0.22)
    sniper_set()
    build("pistol", [(0, pi_painted), (1, pi_polymer), (2, pi_steel)], (-0.03, -0.162, -0.095), (0.03, 0.03, 0.12), 0.3)
    build("knife", [(1, kn_polymer), (2, kn_steel)], (-0.03, -0.165, -0.02), (0.03, 0.14, 0.12), 0.35)
