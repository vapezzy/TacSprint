"""Shared helpers for the model generators.

Shapes are signed distance fields: a function that says, for any point, how
far it is from the surface (negative inside). Shapes are combined with min/max
or smooth blends, sampled on a fine grid and turned into a mesh with marching
cubes. Only grid blocks near the surface are sampled in full, which keeps a
sub-millimetre grid affordable.

Mesh file (models/*.bin, format ARM2):
  positions, normals, uv = (zone / 7, ambient occlusion), uv2 = (edge, cavity), indices.
"""
import os
import struct

import numpy as np
from skimage import measure

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models")


def v(*xyz):
    return np.array(xyz, dtype=np.float64)


# --- shapes ------------------------------------------------------------------

def seg(p, a, b, ra, rb=None):
    """Rounded segment (capsule) whose radius goes from ra to rb."""
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0.0, 1.0)
    d = np.linalg.norm(p - (a + t[:, None] * ab), axis=1)
    return d - (ra if rb is None else ra + (rb - ra) * t)


def ball(p, c, r):
    return np.linalg.norm(p - c, axis=1) - r


def box(p, center, half, rot_x_deg=0.0, rounding=0.002):
    """Box rotated about the X axis, with rounded edges."""
    q = p - center
    a = np.radians(-rot_x_deg)
    y = q[:, 1] * np.cos(a) - q[:, 2] * np.sin(a)
    z = q[:, 1] * np.sin(a) + q[:, 2] * np.cos(a)
    q = np.abs(np.stack([q[:, 0], y, z], axis=1)) - (np.asarray(half) - rounding)
    return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - rounding


def cyl(p, a, b, r, rounding=0.0):
    """Capped cylinder from a to b, with rounded rims."""
    ab = b - a
    length = np.linalg.norm(ab)
    axis = ab / length
    q = p - a
    along = q @ axis
    radial = np.linalg.norm(q - along[:, None] * axis, axis=1)
    dx = radial - (r - rounding)
    dy = np.abs(along - length / 2.0) - (length / 2.0 - rounding)
    outside = np.sqrt(np.maximum(dx, 0.0) ** 2 + np.maximum(dy, 0.0) ** 2)
    return outside + np.minimum(np.maximum(dx, dy), 0.0) - rounding


def torus(p, center, axis, big, small):
    q = p - center
    along = q @ axis
    radial = np.linalg.norm(q - along[:, None] * axis, axis=1)
    return np.sqrt((radial - big) ** 2 + along ** 2) - small


def smin(a, b, k):
    """Union with a soft fillet of size k."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def cut(d, tool):
    """d with the tool shape removed."""
    return np.maximum(d, -tool)


def groove(d, slab, depth):
    """A shallow channel: removes the outer `depth` of d wherever slab < 0."""
    return np.maximum(d, np.minimum(-slab, d + depth))


def union(*parts):
    out = parts[0]
    for part in parts[1:]:
        out = np.minimum(out, part)
    return out


# --- sampling and meshing ----------------------------------------------------

def chunked(f, p, size=300_000):
    if len(p) <= size:
        return f(p)
    return np.concatenate([f(p[i:i + size]) for i in range(0, len(p), size)])


def volume(f, lo, hi, step, block=8, slack=0.004):
    """Samples f on a grid, in full only for blocks that can contain surface."""
    lo = np.asarray(lo, dtype=np.float64)
    n = np.ceil((np.asarray(hi) - lo) / step).astype(int) + 1
    nb = np.ceil(n / block).astype(int)
    bi = np.stack(np.meshgrid(*[np.arange(k) for k in nb], indexing="ij"), axis=-1).reshape(-1, 3)
    centres = lo + (bi * block + (block - 1) / 2.0) * step
    dc = chunked(f, centres)
    reach = block * step * np.sqrt(3.0) / 2.0 + slack
    # Far blocks keep their centre value: the sign is right and no surface passes through.
    vol = np.repeat(np.repeat(np.repeat(dc.astype(np.float32).reshape(nb), block, 0), block, 1), block, 2)
    vol = np.ascontiguousarray(vol[:n[0], :n[1], :n[2]]).astype(np.float32)
    near = bi[np.abs(dc) < reach]
    offs = np.stack(np.meshgrid(*[np.arange(block)] * 3, indexing="ij"), axis=-1).reshape(-1, 3)
    per = max(1, 300_000 // len(offs))
    for i in range(0, len(near), per):
        ijk = (near[i:i + per, None, :] * block + offs[None, :, :]).reshape(-1, 3)
        ijk = ijk[(ijk < n).all(axis=1)]
        vol[ijk[:, 0], ijk[:, 1], ijk[:, 2]] = f(lo + ijk * step)
    print(f"  grid {tuple(n)}, {len(near)} of {len(bi)} blocks sampled in full")
    return vol


def grad(f, p, eps=0.0005):
    g = np.zeros_like(p)
    for i in range(3):
        e = np.zeros(3)
        e[i] = eps
        g[:, i] = chunked(f, p + e) - chunked(f, p - e)
    length = np.linalg.norm(g, axis=1, keepdims=True)
    return g / np.maximum(length, 1e-12)


def simplify(f, verts, faces, keep):
    """Drops triangles where the surface is flat and keeps them where it bends.

    Marching cubes makes every triangle the size of a grid cell, which wastes
    most of them on flat faces. Quadric simplification removes those first.
    Afterwards each vertex is pulled back onto the true surface.
    """
    import fast_simplification
    out_v, out_f = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int32),
                                                target_reduction=1.0 - keep, agg=4)
    out_v = out_v.astype(np.float64)
    for _ in range(2):
        out_v -= chunked(f, out_v)[:, None] * grad(f, out_v)
    return out_v, out_f.astype(np.int64)


def mesh(f, lo, hi, step, keep=1.0):
    vol = volume(f, lo, hi, step)
    verts, faces, _, _ = measure.marching_cubes(vol, level=0.0, spacing=(step, step, step))
    del vol
    verts = verts + np.asarray(lo)
    if keep < 1.0:
        before = len(faces)
        verts, faces = simplify(f, verts, faces, keep)
        print(f"  simplified {before} -> {len(faces)} triangles")
    normals = grad(f, verts)
    # Godot treats clockwise triangles as front faces.
    a, b, c = verts[faces[:, 0]], verts[faces[:, 1]], verts[faces[:, 2]]
    facing = np.einsum("ij,ij->i", np.cross(b - a, c - a), normals[faces[:, 0]])
    faces[facing > 0] = faces[facing > 0][:, ::-1]
    return verts, normals, faces


def occlusion(f, verts, normals, steps=(0.0025, 0.006, 0.012, 0.022)):
    """How open the surface is: 1 in the clear, darker in creases and contacts."""
    ao = np.zeros(len(verts))
    for h in steps:
        ao += np.clip(chunked(f, verts + normals * h) / h, 0.0, 1.0)
    return (ao / len(steps)) ** 0.75


def wear(f, verts, h=0.0012, lo=120.0, hi=520.0):
    """(edge, cavity): how sharply the surface bulges out or folds in, each 0-1.

    The sum of the field's second differences is the surface's mean curvature:
    large and positive on outside corners, negative in grooves.
    """
    lap = -6.0 * chunked(f, verts)
    for i in range(3):
        e = np.zeros(3)
        e[i] = h
        lap += chunked(f, verts + e) + chunked(f, verts - e)
    lap /= h * h
    edge = np.clip((lap - lo) / (hi - lo), 0.0, 1.0)
    cavity = np.clip((-lap - lo) / (hi - lo), 0.0, 1.0)
    return np.stack([edge, cavity], axis=1)


def zones(verts, groups, bias=0.0003):
    """Index of the group each vertex belongs to: the nearest one, earlier groups win ties."""
    best = np.full(len(verts), np.inf)
    zone = np.zeros(len(verts))
    for index, g in groups:
        d = chunked(g, verts)
        take = d < best - bias
        zone[take] = index
        best = np.minimum(best, d)
    return zone


def split_by_zone(faces, face_zone):
    """Gives every zone its own copy of the vertices it uses.

    Returns (source vertex of each new vertex, new faces, zone of each new
    vertex). A triangle then never mixes zones, so material borders follow
    triangle edges exactly instead of bleeding across them.
    """
    source, out_faces, out_zone = [], [], []
    offset = 0
    for z in np.unique(face_zone):
        fz = faces[face_zone == z]
        used, inverse = np.unique(fz, return_inverse=True)
        source.append(used)
        out_faces.append(inverse.reshape(fz.shape) + offset)
        out_zone.append(np.full(len(used), z))
        offset += len(used)
    return np.concatenate(source), np.concatenate(out_faces), np.concatenate(out_zone)


def save(name, verts, normals, faces, zone, ao, wear_uv):
    os.makedirs(OUT, exist_ok=True)
    uv = np.stack([zone / 7.0, ao], axis=1)
    with open(os.path.join(OUT, name + ".bin"), "wb") as fh:
        fh.write(b"ARM2")
        fh.write(struct.pack("<II", len(verts), faces.size))
        fh.write(verts.astype("<f4").tobytes())
        fh.write(normals.astype("<f4").tobytes())
        fh.write(uv.astype("<f4").tobytes())
        fh.write(wear_uv.astype("<f4").tobytes())
        fh.write(faces.astype("<i4").tobytes())
    print(f"{name}: {len(verts)} vertices, {len(faces)} triangles")
