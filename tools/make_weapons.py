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
from sdf import (ball, box, cut, cyl, groove, mesh, occlusion, save, seg, smin, split_by_zone, torus, union, v, wear, zones)

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


# --- sniper rifle, AX-50 style (replaces the parts above) --------------------------
# A heavy .50 in a flat-sided aluminium chassis: square receiver with a full-
# length rail, a long free-float handguard with M-LOK slots and a folded
# bipod, a skeleton folding stock with an adjustable cheek riser, recoil pad
# spacers and a monopod, a fluted barrel with a big two-port muzzle brake, and
# a large tactical scope.

SN_STEP = 0.0007


def _mlok(d, p, z0, z1, x, y, half_h):
    """Rows of M-LOK slots cut into a flat side at x (or the bottom when x is None)."""
    for z in np.arange(z0, z1, 0.042):
        if x is None:
            d = cut(d, box(p, v(0, y, z), (0.0045, 0.006, 0.0135), 0, 0.0025))
        else:
            for dy in (-half_h, half_h):
                d = cut(d, box(p, v(x, y + dy, z), (0.006, 0.0045, 0.0135), 0, 0.0025))
    return d


def ax_receiver(p):
    rec = box(p, v(0, SN_Y + 0.002, -0.035), (0.0195, 0.0225, 0.135), 0, 0.0035)
    # Ejection port on the right, relief channels along both sides.
    rec = cut(rec, box(p, v(0.02, SN_Y + 0.005, -0.03), (0.007, 0.0095, 0.044), 0, 0.0015))
    for sx in (-1.0, 1.0):
        rec = groove(rec, np.maximum(np.abs(p[:, 1] - (SN_Y - 0.008)) - 0.0022, np.abs(p[:, 2] + 0.08) - 0.07), 0.0012)
    shroud = cyl(p, v(0, SN_Y, 0.1), v(0, SN_Y, 0.124), 0.0165, 0.002)
    lower = box(p, v(0, -0.014, -0.03), (0.0205, 0.0165, 0.122), 0, 0.003)
    well = box(p, v(0, -0.034, MAG_Z), (0.021, 0.014, 0.07), 0, 0.003)
    return union(rec, shroud, lower, well)


def ax_handguard(p):
    zc, half = -0.335, 0.187
    hg = box(p, v(0, SN_Y - 0.004, zc), (0.0245, 0.0265, half), 0, 0.007)
    # Bevelled top corners: the octagon-ish section of a modern chassis.
    for sx in (-1.0, 1.0):
        hg = cut(hg, box(p, v(sx * 0.031, SN_Y + 0.03, zc), (0.0125, 0.0125, half + 0.01), 0, 0.0015))
    hg = cut(hg, cyl(p, v(0, SN_Y, zc - half - 0.01), v(0, SN_Y, zc + half + 0.01), 0.0175))
    hg = _mlok(hg, p, -0.5, -0.17, 0.0245, SN_Y - 0.004, 0.009)
    hg = _mlok(hg, p, -0.5, -0.17, -0.0245, SN_Y - 0.004, 0.009)
    hg = _mlok(hg, p, -0.48, -0.2, None, SN_Y - 0.0305, 0)
    cap = cyl(p, v(0, SN_Y - 0.002, -0.528), v(0, SN_Y - 0.002, -0.52), 0.0225, 0.002)
    return union(hg, cap)


def ax_rail(p):
    rail = box(p, v(0, 0.0405, -0.205), (0.0105, 0.0045, 0.3), 0, 0.0008)
    slot = np.abs(np.mod(p[:, 2] + 0.0025, 0.01) - 0.005) - 0.0024
    rail = cut(rail, np.maximum(slot, 0.0418 - p[:, 1]))
    # Rail screws every few slots.
    for z in np.arange(-0.48, 0.08, 0.08):
        rail = cut(rail, cyl(p, v(0, 0.046, z), v(0, 0.041, z), 0.0028))
    return rail


def ax_bipod(p):
    """Bipod folded back along the handguard's underside."""
    mount = box(p, v(0, -0.019, -0.49), (0.016, 0.007, 0.018), 0, 0.003)
    yoke = box(p, v(0, -0.028, -0.49), (0.021, 0.006, 0.012), 0, 0.003)
    d = union(mount, yoke)
    for sx in (-1.0, 1.0):
        leg = seg(p, v(sx * 0.018, -0.031, -0.485), v(sx * 0.018, -0.031, -0.27), 0.0058)
        inner = seg(p, v(sx * 0.018, -0.031, -0.33), v(sx * 0.018, -0.031, -0.255), 0.0046)
        foot = ball(p, v(sx * 0.018, -0.031, -0.252), 0.0075)
        d = union(d, leg, inner, foot)
        # Locking collars on each leg.
        d = union(d, cyl(p, v(sx * 0.018, -0.031, -0.34), v(sx * 0.018, -0.031, -0.33), 0.0072, 0.001))
    return d


def ax_stock_frame(p):
    hinge = box(p, v(0, 0.0, 0.135), (0.0195, 0.022, 0.012), 0, 0.003)
    top = box(p, v(0, 0.02, 0.2), (0.0105, 0.009, 0.06), 0, 0.003)
    low = box(p, v(0, -0.026, 0.198), (0.009, 0.0075, 0.068), -9.0, 0.003)
    upright = box(p, v(0, -0.004, 0.262), (0.0125, 0.052, 0.009), 0, 0.003)
    d = union(hinge, top, low, upright)
    # Lightening window in the hinge block, cheek riser posts, the monopod.
    d = cut(d, box(p, v(0, 0.0, 0.135), (0.03, 0.009, 0.005), 0, 0.002))
    for z in (0.17, 0.235):
        d = union(d, cyl(p, v(0, 0.028, z), v(0, 0.036, z), 0.0042, 0.0008))
    d = union(d, cyl(p, v(0, -0.034, 0.245), v(0, -0.09, 0.245), 0.0058, 0.001))
    d = union(d, cyl(p, v(0, -0.09, 0.245), v(0, -0.1, 0.245), 0.0085, 0.002))
    d = union(d, cyl(p, v(0, -0.06, 0.245), v(0, -0.052, 0.245), 0.0095, 0.001))   # adjuster wheel
    return d


def ax_stock_soft(p):
    """Cheek riser and the thick rubber recoil pad with its ribs."""
    cheek = box(p, v(0, 0.044, 0.205), (0.0145, 0.0105, 0.056), 0, 0.007)
    pad = box(p, v(0, -0.004, 0.287), (0.0175, 0.056, 0.0115), 0, 0.007)
    for y in np.arange(-0.05, 0.05, 0.012):
        pad = groove(pad, np.abs(p[:, 1] - y) - 0.0012, 0.0012)
    return union(cheek, pad)


def ax_stock_spacers(p):
    return box(p, v(0, -0.004, 0.2735), (0.0135, 0.05, 0.0025), 0, 0.0008)


def sn_painted(p):
    """Receiver, chassis, handguard, rail, bipod and stock frame (barrel and optic are separate)."""
    body = union(ax_receiver(p), ax_handguard(p), ax_rail(p), ax_bipod(p), ax_stock_frame(p))
    return cut(body, box(p, v(0, -0.06, MAG_Z), (0.0158, 0.04, 0.0615), 0, 0.001))


def sn_stock(p):
    return ax_stock_soft(p)


def sn_steel(p):
    return union(trigger(p), box(p, v(0, -0.05, -0.008), (0.004, 0.012, 0.003), 12.0, 0.001), ax_stock_spacers(p))


def _brake(p, z, half_w, half_h, half_l):
    """The big .50 brake: a round body with two large side ports each side and
    a flat front face."""
    r = max(half_w, half_h) * 1.12
    brake = cyl(p, v(0, SN_Y, z - half_l), v(0, SN_Y, z + half_l), r, 0.003)
    for dz in (-0.45, 0.12):
        brake = cut(brake, box(p, v(0, SN_Y, z + dz * half_l), (r * 1.6, r * 0.62, half_l * 0.22), 0, 0.002))
    # Small gas ports on top.
    for dz in (-0.75, 0.55):
        brake = cut(brake, cyl(p, v(0, SN_Y + r * 1.3, z + dz * half_l), v(0, SN_Y, z + dz * half_l), 0.0028))
    return cut(brake, cyl(p, v(0, SN_Y, z - half_l * 1.4), v(0, SN_Y, z - half_l * 0.6), 0.0072))


def sn_scope(p):
    """A big 5-25x56 tactical scope: objective bell with a sunshade, elevation and
    windage turrets with knurled caps, a parallax knob on the left, a throw
    lever on the zoom ring, and two rings with clamp screws."""
    tube = cyl(p, v(0, SCOPE_Y, -0.11), v(0, SCOPE_Y, 0.1), 0.0165, 0.002)
    bell = smin(cyl(p, v(0, SCOPE_Y, -0.245), v(0, SCOPE_Y, -0.13), 0.0295, 0.003), tube, 0.016)
    shade = cyl(p, v(0, SCOPE_Y, -0.27), v(0, SCOPE_Y, -0.24), 0.0292, 0.002)
    eye = smin(cyl(p, v(0, SCOPE_Y, 0.1), v(0, SCOPE_Y, 0.172), 0.0215, 0.003), tube, 0.008)
    zoom = cyl(p, v(0, SCOPE_Y, 0.116), v(0, SCOPE_Y, 0.136), 0.0232, 0.0015)
    for k in range(24):
        a = k * np.pi / 12
        zoom = cut(zoom, box(p, v(np.cos(a) * 0.0236, SCOPE_Y + np.sin(a) * 0.0236, 0.126), (0.0016, 0.0016, 0.012), 0, 0.0005))
    lever = box(p, v(0.026, SCOPE_Y + 0.008, 0.126), (0.009, 0.004, 0.006), 0, 0.002)
    saddle = box(p, v(0, SCOPE_Y, 0.0), (0.021, 0.021, 0.022), 0, 0.006)
    def turret(axis, length, radius):
        a = v(0, SCOPE_Y, 0.0)
        b = a + axis * length
        t = cyl(p, a, b, radius, 0.002)
        cap = cyl(p, a + axis * (length - 0.016), b, radius * 1.18, 0.002)
        n = 28
        for k in range(n):
            ang = k * 2 * np.pi / n
            # Knurling: little grooves round the cap.
            if axis[1] > 0.5:
                off = v(np.cos(ang) * radius * 1.2, length - 0.008, np.sin(ang) * radius * 1.2)
            elif axis[0] > 0.5:
                off = v(length - 0.008, np.cos(ang) * radius * 1.2, np.sin(ang) * radius * 1.2)
            else:
                off = v(-(length - 0.008), np.cos(ang) * radius * 1.2, np.sin(ang) * radius * 1.2)
            cap = cut(cap, ball(p, a + off, 0.0016))
        return union(t, cap)
    turrets = union(turret(v(0, 1, 0), 0.046, 0.0125), turret(v(1, 0, 0), 0.042, 0.0115), turret(v(-1, 0, 0), 0.038, 0.0135))
    d = union(bell, shade, eye, zoom, lever, saddle, turrets)
    for z in (-0.075, 0.062):
        ring = cyl(p, v(0, SCOPE_Y, z - 0.009), v(0, SCOPE_Y, z + 0.009), 0.0205, 0.002)
        foot = box(p, v(0, 0.053, z), (0.0125, 0.0125, 0.009), 0, 0.002)
        ring = smin(ring, foot, 0.004)
        for sx in (-1.0, 1.0):
            ring = union(ring, cyl(p, v(sx * 0.014, SCOPE_Y + 0.012, z), v(sx * 0.0215, SCOPE_Y + 0.012, z), 0.0032, 0.0006))
        ring = union(ring, cyl(p, v(0.01, 0.05, z), v(0.017, 0.05, z), 0.004, 0.0008))       # clamp nut
        d = np.minimum(d, ring)
    d = cut(d, cyl(p, v(0, SCOPE_Y, -0.28), v(0, SCOPE_Y, -0.236), 0.025))
    return cut(d, cyl(p, v(0, SCOPE_Y, 0.162), v(0, SCOPE_Y, 0.18), 0.0175))


def sn_mag(p):
    """A short five-round box magazine, as on the AX-50."""
    body = box(p, v(0, -0.074, MAG_Z), (0.0152, 0.034, 0.06), 0, 0.003)
    for sx in (-1.0, 1.0):
        for z in (-0.03, 0.0, 0.03):
            body = cut(body, box(p, v(sx * 0.0156, -0.08, MAG_Z + z), (0.0012, 0.018, 0.009), 0, 0.0008))
    body = cut(body, box(p, v(0, -0.036, MAG_Z), (0.011, 0.012, 0.056), 0, 0.001))
    return np.minimum(body, box(p, v(0, -0.11, MAG_Z), (0.0168, 0.004, 0.0625), 0, 0.002))


def build_hi(name, groups, lo, hi, keep):
    print(name)
    field = lambda q: union(*[g(q) for _, g in groups])
    verts, normals, faces = mesh(field, lo, hi, SN_STEP, keep)
    ao = occlusion(field, verts, normals)
    worn = wear(field, verts)
    src, faces, zone = split_by_zone(faces, zones(verts[faces].mean(axis=1), groups))
    save(name, verts[src], normals[src], faces, zone, ao[src], worn[src])


def sniper_set():
    box_lo, box_hi = (-0.045, -0.165, -0.66), (0.065, 0.075, 0.33)
    build_hi("sniper", [(0, sn_painted), (1, sn_polymer), (2, sn_steel)], box_lo, box_hi, 0.4)
    build_hi("sniper_nogrip", [(0, sn_painted), (1, sn_polymer_plain), (2, sn_steel)], box_lo, box_hi, 0.4)
    build_hi("sniper_mag", [(0, sn_mag), (4, sn_mag_brass), (5, sn_mag_copper)], (-0.022, -0.12, -0.148), (0.022, -0.03, -0.008), 0.6)
    build_hi("sniper_bolt", [(2, sn_bolt)], (-0.02, -0.01, -0.1), (0.07, 0.04, 0.11), 0.6)
    attachments()


def attachments():
    """The sniper rifle's swappable barrels and optics."""
    b_lo, b_hi = (-0.035, -0.02, -1.02), (0.035, 0.05, -0.15)
    build_hi("sniper_barrel_standard", [(0, sn_barrel_standard)], b_lo, b_hi, 0.45)
    build_hi("sniper_barrel_long", [(0, sn_barrel_long)], b_lo, b_hi, 0.45)
    build_hi("sniper_barrel_sup", [(0, sn_barrel_sup)], b_lo, b_hi, 0.45)
    o_lo, o_hi = (-0.055, 0.035, -0.285), (0.06, 0.14, 0.19)
    build_hi("sniper_optic_scope", [(0, sn_scope), (3, sn_glass)], o_lo, o_hi, 0.45)
    build_hi("sniper_optic_compact", [(0, sn_scope_compact), (3, sn_glass_compact)], o_lo, o_hi, 0.45)
    build_hi("sniper_optic_dot", [(0, sn_dot)], o_lo, o_hi, 0.5)


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
