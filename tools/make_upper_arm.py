"""The upper arm sleeve for the first-person arms.

    python tools/make_upper_arm.py

A sleeve from the elbow (origin) to the shoulder (+Z, UPPER_ARM long) with the
same cloth folds as the forearm sleeves, and a rounded elbow so it closes the
joint with the forearm. viewmodel.gd keeps its far end in the shoulder socket
and points it at the elbow it solves for every frame.
"""
import numpy as np

from sdf import mesh, occlusion, save, seg, smin, v, wear

UPPER_ARM = 0.33


def field(p):
    a, b = v(0, 0, 0), v(0, 0, UPPER_ARM)
    s = np.clip(p[:, 2], 0.0, UPPER_ARM)
    ang = np.arctan2(p[:, 1], p[:, 0])
    base = seg(p, a, b, 0.056, 0.066)
    amp = 0.0016 + 0.0028 * np.exp(-s / 0.06) + 0.0022 * np.exp(-(UPPER_ARM - s) / 0.08)
    folds = np.sin(2 * np.pi * s / 0.041 + 2.0 * np.sin(2 * ang + 0.3) + 1.2 * np.sin(3 * ang + 1.4))
    twist = np.sin(2 * np.pi * s / 0.1 + 2.0 * ang) * np.sin(np.pi * s / UPPER_ARM)
    fine = np.sin(2 * np.pi * s / 0.0145 + 4.0 * ang + 2.0 * np.sin(ang * 5.0))
    seam = np.exp(-((np.abs(ang - 0.6) * 0.05) / 0.0022) ** 2)
    out = base - amp * folds - 0.0016 * twist - 0.0006 * fine - 0.0012 * seam
    # The elbow: a rounded cap a touch fuller than the sleeve.
    return smin(out, seg(p, a, a + v(0, 0, 0.01), 0.058), 0.006)


if __name__ == "__main__":
    lo, hi = np.array([-0.09, -0.09, -0.08]), np.array([0.09, 0.09, UPPER_ARM + 0.09])
    verts, normals, faces = mesh(field, lo, hi, 0.0016, 0.3)
    save("upper_sleeve", verts, normals, faces, np.zeros(len(verts)), occlusion(field, verts, normals),
         wear(field, verts, 0.002, 40.0, 220.0))
