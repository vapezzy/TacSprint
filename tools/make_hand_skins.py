"""Finger bones for the first-person gloves.

    python tools/make_hand_skins.py

Every hand pose built by make_arms.py gets a skeleton: one palm bone at the
wrist and three bones per digit (four fingers and the thumb), pivoting at the
knuckle and at each finger joint. Each vertex of the already built hand mesh
(models/<pose>_hand.bin) is weighted to the bones it lies nearest to, softly
across the joints, and the result goes to models/<pose>_hand.skin:

    "SKN1", bone count, vertex count
    per bone:   parent (i32), pivot xyz (f32), hinge axis xyz (f32)
    per vertex: 4 bone indices (i32), 4 weights (f32)

The hinge is the axis a digit curls about (positive angle = curl further);
viewmodel.gd turns the bones about it to bring the fingers to life.
The meshes themselves are not touched.
"""
import os
import struct

import numpy as np

import make_arms as ma

MODELS = os.path.join(os.path.dirname(__file__), "..", "models")


def load_verts(name):
    with open(os.path.join(MODELS, name + "_hand.bin"), "rb") as fh:
        assert fh.read(4) == b"ARM2"
        n, _ = struct.unpack("<II", fh.read(8))
        return np.frombuffer(fh.read(n * 12), dtype="<f4").reshape(n, 3).astype(np.float64)


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def unit(x):
    return x / (np.linalg.norm(x) + 1e-12)


def skin(name, hand):
    verts = load_verts(name)
    digits = [np.array(pts) for pts, _ in hand.fingers] + [np.array(hand.thumb)]
    parents, pivots, hinges = [-1], [hand.wrist], [np.array([1.0, 0.0, 0.0])]
    dist = []
    # Palm: the wrist out to every knuckle and to the thumb's root.
    palm = np.min([seg_dist(verts, hand.wrist, d[0]) for d in digits] +
                  [seg_dist(verts, hand.wrist, hand.wrist + hand.dir * 0.05)], axis=0)
    dist.append(palm)
    for di, d in enumerate(digits):
        a, b, c = d[1] - d[0], d[2] - d[1], d[3] - d[2]
        h = np.cross(a, b) + np.cross(b, c)
        if np.linalg.norm(h) < 1e-7:
            h = np.cross(a, -hand.out)
        h = unit(h)
        for k in range(3):
            parents.append(0 if k == 0 else len(parents) - 1)
            pivots.append(d[k])
            hinges.append(h)
            dist.append(seg_dist(verts, d[k], d[k + 1]))
    dist = np.stack(dist, 1)                       # vertices x bones
    # Soft weights: the nearest bones within a few millimetres share the vertex.
    near = dist.min(axis=1, keepdims=True)
    w = np.where(dist < near + 0.006, 1.0 / (dist + 0.0015) ** 4, 0.0)
    order = np.argsort(-w, axis=1)[:, :4]
    top = np.take_along_axis(w, order, 1)
    top = top / top.sum(axis=1, keepdims=True)
    with open(os.path.join(MODELS, name + "_hand.skin"), "wb") as fh:
        fh.write(b"SKN1")
        fh.write(struct.pack("<II", len(parents), len(verts)))
        for par, piv, hin in zip(parents, pivots, hinges):
            fh.write(struct.pack("<i3f3f", par, *map(float, piv), *map(float, hin)))
        fh.write(order.astype("<i4").tobytes())
        fh.write(top.astype("<f4").tobytes())
    print(f"{name}: {len(parents)} bones, {len(verts)} vertices")


def capture():
    """Runs make_arms' pose functions with build() swapped for skin()."""
    made = []
    real_build = ma.build
    ma.build = lambda name, hand, scene: made.append((name, hand))
    try:
        ma.right_hand()
        ma.left_hand()
        ma.left_hold()
        ma.right_bolt()
        ma.right_bolt_hook()
        import make_gun as mg
        import make_weapons as mw
        ma.left_mag("left_mag_rifle", mg.magazine)
        ma.left_mag("left_mag_sniper", lambda p: np.minimum(mw.sn_mag(p), mw.sn_mag_brass(p)))
        ma.left_open()
    finally:
        ma.build = real_build
    return made


if __name__ == "__main__":
    for name, hand in capture():
        if os.path.exists(os.path.join(MODELS, name + "_hand.bin")):
            skin(name, hand)
