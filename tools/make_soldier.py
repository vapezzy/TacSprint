"""Sculpts the parts of the soldier figures (soldier.gd) that used to be plain
spheres and capsules: a head with a real face, the eyes, a high-cut helmet
and sleeved arms.

    python tools/make_soldier.py

Head frame: origin in the middle of the head between the ears, +Y up, -Z the
way the face looks, metres. Arm frames as for the legs: origin in the middle of
the bone, +Y towards its far end (elbow, wrist), -Z the front.
Zones in the models: 0 sleeve cloth (camo), 3 rubber/hard gear, 6 skin, 7 eyes.
"""
import numpy as np

from sdf import ball, box, cut, mesh, occlusion, save, seg, smin, split_by_zone, union, v, wear, zones


def ellipsoid(p, c, r):
    q = (p - c) / np.asarray(r)
    k = np.linalg.norm(q, axis=1)
    return (k - 1.0) * min(r)


# --- head and face ------------------------------------------------------------

def head_skin(p):
    skull = ellipsoid(p, v(0, 0.03, 0.012), (0.079, 0.09, 0.097))
    jaw = ellipsoid(p, v(0, -0.045, -0.02), (0.063, 0.046, 0.07))
    d = smin(skull, jaw, 0.03)
    d = smin(d, ball(p, v(0, -0.086, -0.068), 0.021), 0.02)                 # chin
    for sx in (-1.0, 1.0):
        d = smin(d, ball(p, v(sx * 0.047, 0.002, -0.06), 0.021), 0.02)    # cheekbones
        d = smin(d, ellipsoid(p, v(sx * 0.077, 0.005, 0.004), (0.011, 0.029, 0.019)), 0.006)   # ears
    # Brow ridge over the eyes, the eye sockets under it.
    d = smin(d, seg(p, v(-0.04, 0.036, -0.083), v(0.04, 0.036, -0.083), 0.011), 0.016)
    for sx in (-1.0, 1.0):
        socket = ball(p, v(sx * 0.031, 0.017, -0.097), 0.017)
        d = -smin(-d, socket, 0.008)
        # Eyelids: the upper one covers the top of the eye, the lower one is a thin rim.
        d = smin(d, seg(p, v(sx * 0.021, 0.0235, -0.088), v(sx * 0.041, 0.0215, -0.085), 0.0068), 0.004)
        d = smin(d, seg(p, v(sx * 0.022, 0.0075, -0.087), v(sx * 0.04, 0.0085, -0.084), 0.0042), 0.003)
    # Nose: bridge, tip and the wings of the nostrils.
    nose = seg(p, v(0, 0.026, -0.093), v(0, -0.016, -0.111), 0.007, 0.012)
    nose = smin(nose, ball(p, v(0, -0.02, -0.108), 0.0135), 0.008)
    for sx in (-1.0, 1.0):
        nose = smin(nose, ball(p, v(sx * 0.0125, -0.025, -0.098), 0.0085), 0.006)
    d = smin(d, nose, 0.01)
    # Lips and the line between them.
    lips = seg(p, v(-0.021, -0.046, -0.094), v(0.021, -0.046, -0.094), 0.0065)
    lips = smin(lips, seg(p, v(-0.019, -0.057, -0.092), v(0.019, -0.057, -0.092), 0.0072), 0.004)
    d = smin(d, lips, 0.008)
    d = cut(d, box(p, v(0, -0.0515, -0.105), (0.022, 0.0009, 0.02), 0, 0.0005))
    # Neck.
    d = smin(d, seg(p, v(0, -0.06, 0.02), v(0, -0.15, 0.03), 0.058, 0.064), 0.035)
    return d


def head_eyes(p):
    return np.minimum(ball(p, v(-0.031, 0.0155, -0.079), 0.0115), ball(p, v(0.031, 0.0155, -0.079), 0.0115))


# --- helmet ------------------------------------------------------------------

def helmet(p):
    """A high-cut helmet: shell cut high over the ears, side rails, a night
    vision shroud at the front and a rim round the edge."""
    outer = ellipsoid(p, v(0, 0.036, 0.008), (0.097, 0.104, 0.112))
    inner = ellipsoid(p, v(0, 0.036, 0.008), (0.085, 0.093, 0.1))
    shell = np.maximum(outer, -inner)
    y = p[:, 1]
    z = p[:, 2]
    # The lower edge: over the brow at the front, high over the ears, lower at the back.
    edge = 0.045 + 0.02 * np.clip(-z / 0.1, 0, 1) - 0.035 * np.clip(z / 0.1, 0, 1)
    edge = edge - 0.035 * np.exp(-((z - 0.0) / 0.05) ** 2)
    shell = np.maximum(shell, edge - y - 0.01)
    for sx in (-1.0, 1.0):
        shell = cut(shell, ball(p, v(sx * 0.11, -0.01, 0.0), 0.055))
        shell = union(shell, box(p, v(sx * 0.093, 0.05, 0.0), (0.006, 0.009, 0.06), 0, 0.002))
    shell = union(shell, box(p, v(0, 0.075, -0.107), (0.022, 0.017, 0.01), -20, 0.004))
    return shell


# --- arms --------------------------------------------------------------------

UPPER = 0.29
FORE = 0.28


def upper_arm(p):
    d = seg(p, v(0, -UPPER / 2 - 0.02, 0), v(0, UPPER / 2, 0), 0.066, 0.054)
    d = smin(d, ball(p, v(0, -UPPER / 2 + 0.01, -0.005), 0.07), 0.03)      # the shoulder
    y = p[:, 1]
    ang = np.arctan2(p[:, 0], p[:, 2])
    folds = np.sin(2 * np.pi * y / 0.05 + 1.6 * np.sin(2 * ang)) * np.clip((y + 0.02) / 0.12, 0, 1)
    d = d - 0.0025 * folds
    # A pocket on the outside of the sleeve.
    return smin(d, box(p, v(0.058, -0.03, 0.0), (0.008, 0.035, 0.03), 0, 0.006), 0.006)


def forearm(p):
    d = seg(p, v(0, -FORE / 2 - 0.01, 0), v(0, FORE / 2 - 0.03, 0), 0.054, 0.043)
    y = p[:, 1]
    ang = np.arctan2(p[:, 0], p[:, 2])
    # Sleeve pushed up: deep bunched folds round the middle of the forearm.
    bunch = np.exp(-((y + 0.02) / 0.05) ** 2)
    d = d - (0.003 + 0.004 * bunch) * np.sin(2 * np.pi * y / 0.035 + 2.0 * np.sin(3 * ang))
    return d


def glove(p):
    cuff = seg(p, v(0, FORE / 2 - 0.05, 0), v(0, FORE / 2 + 0.005, 0), 0.044, 0.042)
    return cuff


def build(name, parts, lo, hi, step, keep):
    print(name)
    whole = lambda q: union(*[fn(q) for _, fn in parts])
    verts, normals, faces = mesh(whole, lo, hi, step, keep)
    ao = occlusion(whole, verts, normals, (0.003, 0.008, 0.016))
    worn = wear(whole, verts, 0.0015, 40.0, 240.0)
    src, faces, zone = split_by_zone(faces, zones(verts[faces].mean(axis=1), parts))
    save(name, verts[src], normals[src], faces, zone, ao[src], worn[src])


if __name__ == "__main__":
    build("soldier_head", [(6, head_skin)], (-0.1, -0.2, -0.13), (0.1, 0.14, 0.12), 0.0016, 0.25)
    build("soldier_eyes", [(7, head_eyes)], (-0.05, 0.0, -0.1), (0.05, 0.032, -0.06), 0.0014, 0.4)
    build("soldier_helmet", [(3, helmet)], (-0.12, -0.03, -0.13), (0.12, 0.15, 0.13), 0.0018, 0.1)
    build("soldier_upper_arm", [(0, upper_arm)], (-0.09, -0.24, -0.09), (0.09, 0.2, 0.09), 0.002, 0.1)
    build("soldier_forearm", [(0, forearm), (3, glove)], (-0.07, -0.18, -0.07), (0.07, 0.17, 0.07), 0.002, 0.1)
