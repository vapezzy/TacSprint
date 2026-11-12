"""SR-8: a second bolt-action sniper rifle, a slim modern precision chassis.

    python tools/make_sniper2.py

Built on the same layout as the FJ50 (make_weapons.py) so the hands, the bolt
(sniper_bolt.bin), the magazine (sniper_mag.bin), the barrels and the optics all
fit it unchanged: same bore height SN_Y, same magazine well at MAG_Z, same
pistol grip. What is its own:
  - a round action with a flat top and a full-length top rail
  - a long, slim handguard reaching far forward, with a row of long slots
    high on each side and short slots below, and no vertical grip (the support
    hand cups it from below)
  - a skeleton stock: a top bar with a long cheek riser, a straight lower bar,
    and a tall butt plate with a window and a thick pad
Writes models/sniper2.bin.
"""
import numpy as np

import make_weapons as mw
from make_weapons import MAG_Z, SN_Y, build_hi, grip, trigger
from sdf import ball, box, cut, cyl, groove, seg, smin, union, v


def _side_slots(d, p, z0, z1, step, half_len, y, x, half_h):
    for z in np.arange(z0, z1, step):
        for sx in (-1.0, 1.0):
            d = cut(d, box(p, v(sx * x, y, z), (0.006, half_h, half_len), 0, 0.0022))
    return d


def s2_receiver(p):
    action = cyl(p, v(0, SN_Y, -0.175), v(0, SN_Y, 0.102), 0.0188, 0.002)
    flat = box(p, v(0, SN_Y + 0.012, -0.035), (0.0155, 0.012, 0.137), 0, 0.003)
    rec = smin(action, flat, 0.004)
    rec = cut(rec, box(p, v(0.019, SN_Y + 0.005, -0.03), (0.007, 0.0095, 0.044), 0, 0.0015))    # ejection port
    # Bolt handle slot at the back on the right.
    rec = cut(rec, box(p, v(0.018, SN_Y - 0.004, 0.08), (0.006, 0.006, 0.02), 0, 0.001))
    shroud = cyl(p, v(0, SN_Y, 0.1), v(0, SN_Y, 0.122), 0.016, 0.002)
    # Chassis under the action: flat sides with a long relief, the magazine well.
    lower = box(p, v(0, -0.013, -0.04), (0.02, 0.0155, 0.13), 0, 0.0035)
    lower = groove(lower, np.maximum(np.abs(p[:, 1] + 0.012) - 0.004, np.abs(p[:, 2] + 0.06) - 0.06), 0.0011)
    well = box(p, v(0, -0.033, MAG_Z), (0.0205, 0.013, 0.069), 0, 0.003)
    flare = box(p, v(0, -0.044, MAG_Z), (0.0225, 0.004, 0.073), 0, 0.002)
    return union(rec, shroud, lower, well, flare)


def s2_handguard(p):
    """Long and slim: a rounded-octagon section from the receiver out to z = -0.66."""
    z0, z1 = -0.66, -0.17
    zc, half = (z0 + z1) / 2, (z1 - z0) / 2
    hg = box(p, v(0, SN_Y - 0.003, zc), (0.0215, 0.0235, half), 0, 0.006)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            hg = cut(hg, box(p, v(sx * 0.028, SN_Y - 0.003 + sy * 0.03, zc), (0.0115, 0.0115, half + 0.01), 0, 0.0015))
    hg = cut(hg, cyl(p, v(0, SN_Y, z0 - 0.01), v(0, SN_Y, z1 + 0.01), 0.0158))
    # A long row of slots high on each side, short ones lower down, a row underneath.
    hg = _side_slots(hg, p, -0.63, -0.21, 0.034, 0.0125, SN_Y + 0.006, 0.0215, 0.0036)
    hg = _side_slots(hg, p, -0.6, -0.24, 0.06, 0.009, SN_Y - 0.013, 0.0215, 0.0032)
    for z in np.arange(-0.62, -0.25, 0.045):
        hg = cut(hg, box(p, v(0, SN_Y - 0.0265, z), (0.004, 0.006, 0.012), 0, 0.002))
    # Front end cap with a lip, and the barrel nut ring behind it.
    cap = cyl(p, v(0, SN_Y - 0.002, -0.668), v(0, SN_Y - 0.002, -0.656), 0.0215, 0.002)
    cap = cut(cap, cyl(p, v(0, SN_Y, -0.68), v(0, SN_Y, -0.64), 0.0152))
    return union(hg, cap)


def s2_rail(p):
    rail = box(p, v(0, 0.0405, -0.27), (0.0098, 0.0045, 0.39), 0, 0.0008)
    slot = np.abs(np.mod(p[:, 2] + 0.0025, 0.01) - 0.005) - 0.0024
    rail = cut(rail, np.maximum(slot, 0.0418 - p[:, 1]))
    # A few numbers' worth of index marks along the left side of the rail.
    for z in np.arange(-0.62, 0.1, 0.05):
        rail = cut(rail, box(p, v(-0.0098, 0.04, z), (0.0006, 0.002, 0.0006), 0, 0.0001))
    return rail


def s2_stock_frame(p):
    """Skeleton stock: hinge block, top bar, straight lower bar, tall butt plate."""
    hinge = box(p, v(0, 0.0, 0.135), (0.0185, 0.021, 0.012), 0, 0.003)
    top = box(p, v(0, 0.024, 0.205), (0.0095, 0.0085, 0.066), 0, 0.003)
    low = box(p, v(0, -0.045, 0.21), (0.0085, 0.0075, 0.065), -4.0, 0.003)
    # The lower bar meets the grip area through a sloped strut.
    strut = seg(p, v(0, -0.02, 0.145), v(0, -0.044, 0.152), 0.008)
    butt = box(p, v(0, -0.01, 0.272), (0.0125, 0.06, 0.009), 0, 0.003)
    butt = cut(butt, box(p, v(0, -0.012, 0.272), (0.03, 0.024, 0.0055), 0, 0.003))   # the window
    d = union(hinge, top, low, strut, butt)
    d = cut(d, box(p, v(0, 0.0, 0.135), (0.03, 0.008, 0.005), 0, 0.002))
    # Cheek riser posts and the length-of-pull adjuster.
    for z in (0.175, 0.24):
        d = union(d, cyl(p, v(0, 0.031, z), v(0, 0.038, z), 0.004, 0.0008))
    d = union(d, cyl(p, v(-0.011, -0.045, 0.235), v(0.011, -0.045, 0.235), 0.007, 0.001))
    return d


def s2_soft(p):
    cheek = box(p, v(0, 0.045, 0.21), (0.013, 0.0095, 0.062), 0, 0.007)
    pad = box(p, v(0, -0.01, 0.289), (0.016, 0.064, 0.01), 0, 0.007)
    for y in np.arange(-0.06, 0.05, 0.011):
        pad = groove(pad, np.abs(p[:, 1] - y) - 0.0011, 0.0011)
    return union(cheek, pad)


def s2_painted(p):
    body = union(s2_receiver(p), s2_handguard(p), s2_rail(p), s2_stock_frame(p))
    # Side screws on the chassis and handguard.
    for sx in (-1.0, 1.0):
        for z in (-0.15, -0.1, 0.02, 0.07):
            body = cut(body, cyl(p, v(sx * 0.0215, -0.012, z), v(sx * 0.018, -0.012, z), 0.0026))
    return cut(body, box(p, v(0, -0.06, MAG_Z), (0.0158, 0.04, 0.0615), 0, 0.001))


def s2_polymer(p):
    return union(grip(p), s2_soft(p))


def s2_steel(p):
    parts = [trigger(p), box(p, v(0, -0.05, -0.008), (0.004, 0.012, 0.003), 12.0, 0.001)]
    for sx in (-1.0, 1.0):
        for z in (-0.15, -0.1, 0.02, 0.07):
            parts.append(cyl(p, v(sx * 0.0215, -0.012, z), v(sx * 0.0195, -0.012, z), 0.0022, 0.0004))
        parts.append(cyl(p, v(sx * 0.0185, 0.0, 0.135), v(sx * 0.0215, 0.0, 0.135), 0.0055, 0.001))   # hinge pin heads
    parts.append(cyl(p, v(-0.0185, 0.0, 0.135), v(0.0185, 0.0, 0.135), 0.004, 0.0008))
    # Safety lever on the right and a magazine release paddle in front of the guard.
    parts.append(box(p, v(0.0225, SN_Y - 0.008, 0.088), (0.0024, 0.0045, 0.011), 0, 0.001))
    parts.append(box(p, v(0, -0.05, MAG_Z + 0.074), (0.007, 0.007, 0.003), 0, 0.0012))
    return union(*parts)


if __name__ == "__main__":
    lo, hi = (-0.045, -0.165, -0.69), (0.065, 0.075, 0.31)
    build_hi("sniper2", [(0, s2_painted), (1, s2_polymer), (2, s2_steel)], lo, hi, 0.4)
