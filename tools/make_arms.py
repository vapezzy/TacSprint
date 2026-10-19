"""Builds the first-person hands and sleeves as detailed meshes.

Each gloved hand is a signed distance field: finger bones, palm and cuff are
rounded segments blended together, so joints and finger webs come out soft.
On top of that come the things that make a glove read as a glove: creases
across every finger joint, stitched seams on the back of the hand, a moulded
knuckle guard with a bump per knuckle, pads on the fingers, a gathered cuff
and a wrist strap. Sleeves get folds, a hem and a seam.

Zones: 0 sleeve cloth, 1 glove textile, 2 grippy palm side, 3 moulded rubber.

Run: python tools/make_arms.py
"""
import numpy as np

from sdf import ball, box, chunked, grad, groove, mesh, occlusion, save, seg, smin, split_by_zone, v, wear

HAND_STEP = 0.0008
SLEEVE_STEP = 0.0015


def unit(a):
    return a / np.linalg.norm(a)


class Hand:
    def __init__(self, wrist, elbow, out, fingers, thumb, heel, thenar, prop):
        self.wrist = wrist
        self.elbow = elbow
        self.dir = unit(elbow - wrist)
        self.out = out          # direction the back of the hand faces
        self.fingers = fingers  # list of (4 points, scale)
        self.thumb = thumb      # 4 points: base, knuckle, joint, tip
        self.heel = heel
        self.thenar = thenar
        self.prop = prop        # function: distance to the object being held
        self.watch = False      # a tactical watch over the cuff (left hand)
        self.knuckles = [pts[0] for pts, _ in fingers]
        middle = np.mean(self.knuckles, axis=0)
        self.palm = (wrist + middle) / 2.0
        self.along = unit(middle - wrist)
        self.span = np.linalg.norm(middle - wrist)
        # Frame around the forearm, for anything that runs round the wrist.
        self.u = unit(np.cross(self.dir, v(0.0, 0.0, 1.0)))
        self.w = np.cross(self.dir, self.u)

    def _angle(self, p, origin):
        s = (p - origin) @ self.dir
        q = p - (origin + s[:, None] * self.dir)
        return s, np.arctan2(q @ self.w, q @ self.u)

    def _back(self, a, b):
        """Direction the back of a finger bone faces: away from the held object."""
        mid = ((a + b) / 2.0)[None, :]
        g = grad(self.prop, mid)[0]
        along = unit(b - a)
        g = g - along * (g @ along)
        return unit(g)

    def textile(self, p):
        w, d = self.wrist, self.dir
        hand = ball(p, self.heel, 0.0195)
        hand = smin(hand, ball(p, self.thenar, 0.0185), 0.012)
        n = len(self.fingers)
        for i, (pts, s) in enumerate(self.fingers):
            # Metacarpal from a spot on the wrist to the knuckle builds the palm slab.
            spread = (i - (n - 1) / 2.0) * 0.009
            root = w + v(0.0, -spread, 0.0) - d * 0.004
            hand = smin(hand, seg(p, root, pts[0], 0.0145, 0.0122 * s), 0.013)
        for pts, s in self.fingers:
            r = [0.0112 * s, 0.0103 * s, 0.0095 * s, 0.0086 * s]
            f = seg(p, pts[0], pts[1], r[0], r[1])
            f = smin(f, seg(p, pts[1], pts[2], r[1], r[2]), 0.004)
            f = smin(f, seg(p, pts[2], pts[3], r[2], r[3]), 0.004)
            f = smin(f, ball(p, pts[1], r[1] + 0.0009), 0.003)
            f = smin(f, ball(p, pts[2], r[2] + 0.0007), 0.003)
            hand = smin(hand, f, 0.0045)
        t = self.thumb
        th = seg(p, t[0], t[1], 0.0165, 0.0128)
        th = smin(th, seg(p, t[1], t[2], 0.0128, 0.0117), 0.004)
        th = smin(th, seg(p, t[2], t[3], 0.0117, 0.0102), 0.004)
        th = smin(th, ball(p, t[2], 0.0125), 0.003)
        hand = smin(hand, th, 0.011)
        hand = smin(hand, seg(p, w - d * 0.008, w + d * 0.02, 0.0285, 0.03), 0.012)

        # Creases where the fabric bunches over each finger joint.
        joints = [(pts[j], unit(pts[j + 1] - pts[j - 1]), 0.0105 * s, 3 if j == 1 else 2)
                  for pts, s in self.fingers for j in (1, 2)]
        joints.append((t[2], unit(t[3] - t[1]), 0.0125, 3))
        for centre, axis, radius, count in joints:
            x = (p - centre) @ axis
            near = ball(p, centre, radius + 0.0045)
            for k in range(count):
                off = (k - (count - 1) / 2.0) * 0.0019
                hand = groove(hand, np.maximum(np.abs(x - off) - 0.00045, near), 0.00055)

        # Stitched seams across and along the back of the hand.
        height = (p - self.palm) @ self.out
        back = np.maximum(0.002 - height, ball(p, self.palm, 0.062))
        s = (p - w) @ self.along
        for frac in (0.36, 0.74):
            hand = groove(hand, np.maximum(np.abs(s - frac * self.span) - 0.0005, back), 0.00055)
        side = (p - self.palm) @ np.cross(self.along, self.out)
        between = np.maximum(0.36 * self.span - s, s - 0.74 * self.span)
        hand = groove(hand, np.maximum(np.maximum(np.abs(side) - 0.0005, between), back), 0.00055)

        # Flared cuff, gathered by its elastic, with a hem.
        along, ang = self._angle(p, w)
        cuff = seg(p, w + d * 0.014, w + d * 0.05, 0.0318, 0.0345)
        cuff = cuff - 0.00055 * np.sin(ang * 18.0) * np.clip((along - 0.014) / 0.01, 0.0, 1.0)
        cuff = smin(cuff, seg(p, w + d * 0.05, w + d * 0.053, 0.0356), 0.0025)
        return smin(hand, cuff, 0.006)

    def reinforced(self, p):
        o = self.out
        ks = self.knuckles
        # Knuckle guard: a moulded bar with a raised bump over each knuckle.
        d = seg(p, ks[0] + o * 0.0068, ks[-1] + o * 0.0068, 0.0078)
        for k in ks:
            d = smin(d, ball(p, k + o * 0.0086, 0.0082), 0.003)
        # Two pads along the back of each finger.
        for pts, s in self.fingers:
            for a, b, lo, hi, r in ((pts[0], pts[1], 0.36, 0.8, 0.0047), (pts[1], pts[2], 0.24, 0.76, 0.004)):
                back = self._back(a, b)
                d = np.minimum(d, seg(p, a + (b - a) * lo + back * 0.0092 * s, a + (b - a) * hi + back * 0.0088 * s, r * s))
        # Wrist strap with its pull tab on the back of the wrist.
        w, dr = self.wrist, self.dir
        d = np.minimum(d, seg(p, w + dr * 0.027, w + dr * 0.037, 0.0352))
        if self.watch:
            # Round tactical watch on the back of the wrist: case, bezel ring and a
            # crown, sitting on the strap where the pull tab would be.
            c = w + dr * 0.034 + o * 0.0335
            case = seg(p, c, c + o * 0.0075, 0.0118, 0.0)
            bezel = seg(p, c + o * 0.0068, c + o * 0.0088, 0.0122, 0.0)
            bezel = np.maximum(bezel, -seg(p, c + o * 0.006, c + o * 0.012, 0.0096, 0.0))
            crown = seg(p, c + o * 0.004 + np.cross(dr, o) * 0.0115, c + o * 0.004 + np.cross(dr, o) * 0.0145, 0.0018)
            d = np.minimum(d, smin(case, np.minimum(bezel, crown), 0.0015))
        else:
            tab = w + dr * 0.032 + o * 0.036
            d = smin(d, seg(p, tab - self.along * 0.0, tab + np.cross(dr, o) * 0.016, 0.0052), 0.002)
        return d

    def field(self, p):
        return smin(self.textile(p), self.reinforced(p), 0.0022)

    def sleeve(self, p):
        w, d = self.wrist, self.dir
        a = w + d * 0.046
        length = np.linalg.norm(self.elbow - a)
        s, ang = self._angle(p, a)
        s = np.clip(s, 0.0, length)
        base = seg(p, a, self.elbow, 0.039, 0.055)
        # Cloth folds: slanted, uneven, bunching up at the cuff and the elbow.
        amp = 0.0015 + 0.0026 * np.exp(-s / 0.045) + 0.0028 * np.exp(-(length - s) / 0.09)
        folds = np.sin(2 * np.pi * s / 0.037 + 2.0 * np.sin(2 * ang + 1.0) + 1.4 * np.sin(3 * ang + 0.4))
        twist = np.sin(2 * np.pi * s / 0.09 + 2.0 * ang + 0.8) * np.sin(np.pi * s / length)
        fine = np.sin(2 * np.pi * s / 0.0135 + 4.0 * ang + 2.0 * np.sin(ang * 5.0))
        # The sleeve hangs a little looser underneath the arm.
        sag = 0.003 * np.sin(ang + 0.5) * np.sin(np.pi * s / length)
        # A felled seam running the length of the sleeve.
        seam = np.exp(-((np.abs(ang - 0.6) * 0.045) / 0.0022) ** 2)
        out = base - amp * folds - 0.0016 * twist - 0.0006 * fine - sag - 0.0012 * seam
        return smin(out, seg(p, a, a + d * 0.004, 0.0412), 0.003)                # hem


def build(name, hand, scene):
    """scene: distance to everything nearby, used only for contact shading."""
    print(name)
    keys = [hand.wrist, hand.wrist + hand.dir * 0.06, hand.heel, hand.thenar] + list(hand.thumb)
    for pts, _ in hand.fingers:
        keys += list(pts)
    keys = np.array(keys)
    lo, hi = keys.min(axis=0) - 0.045, keys.max(axis=0) + 0.045
    verts, normals, faces = mesh(hand.field, lo, hi, HAND_STEP, 0.3)

    everything = lambda q: np.minimum(np.minimum(hand.field(q), hand.sleeve(q)), scene(q))
    ao = occlusion(everything, verts, normals)
    worn = wear(hand.field, verts, 0.0012, 90.0, 420.0)
    # Material per triangle, judged at its centre.
    centre = verts[faces].mean(axis=1)
    facing = grad(hand.field, centre)
    face_zone = np.ones(len(faces))
    # Palm side: surfaces that face the held object and sit close to it.
    toward = -np.einsum("ij,ij->i", facing, grad(hand.prop, centre))
    face_zone[(toward > 0.2) & (chunked(hand.prop, centre) < 0.03)] = 2.0
    face_zone[chunked(hand.reinforced, centre) < chunked(hand.textile, centre) + 0.0004] = 3.0
    src, faces, zone = split_by_zone(faces, face_zone)
    save(name + "_hand", verts[src], normals[src], faces, zone, ao[src], worn[src])

    a = hand.wrist + hand.dir * 0.03
    pts = np.array([a, hand.elbow])
    lo, hi = pts.min(axis=0) - 0.075, pts.max(axis=0) + 0.075
    verts, normals, faces = mesh(hand.sleeve, lo, hi, SLEEVE_STEP, 0.3)
    save(name + "_sleeve", verts, normals, faces, np.zeros(len(verts)), occlusion(everything, verts, normals),
         wear(hand.sleeve, verts, 0.002, 40.0, 220.0))


def right_hand():
    rake = lambda y: -(y + 0.098) * 0.249          # the pistol grip leans back
    grip = lambda p: box(p, v(0, -0.098, 0.072), (0.016, 0.05, 0.022), -14.0)
    housing = lambda p: box(p, v(0, -0.034, 0.03), (0.018, 0.017, 0.06))
    receiver = lambda p: box(p, v(0, 0.002, -0.02), (0.02, 0.02, 0.12))
    prop = lambda p: np.minimum(grip(p), housing(p))
    fingers = [([v(0.032, -0.070, 0.078), v(0.029, -0.052, 0.038), v(0.0275, -0.047, 0.010), v(0.026, -0.045, -0.014)], 1.0)]
    for i, s in enumerate([1.0, 0.96, 0.87]):
        y = -0.096 - i * 0.0205
        z = rake(y)
        fingers.append(([v(0.031, y + 0.006, 0.082 + z), v(0.027, y, 0.039 + z),
                         v(-0.001, y - 0.002, 0.0365 + z), v(-0.0255, y - 0.004, 0.050 + z)], s))
    thumb = [v(0.012, -0.092, 0.122), v(-0.014, -0.060, 0.100), v(-0.0275, -0.054, 0.072), v(-0.0285, -0.050, 0.046)]
    hand = Hand(v(0.036, -0.128, 0.150), v(0.17, -0.30, 0.46), v(1.0, 0.0, 0.0), fingers, thumb,
                v(0.020, -0.118, 0.118), v(0.008, -0.085, 0.118), prop)
    build("right", hand, lambda p: np.minimum(prop(p), receiver(p)))


def left_hand():
    lean = lambda y: (y + 0.07) * 0.105             # the foregrip leans forward
    grip = lambda p: box(p, v(0, -0.07, -0.185), (0.015, 0.04, 0.017), 6.0)
    guard = lambda p: box(p, v(0, -0.026, -0.19), (0.02, 0.007, 0.045))
    stop = lambda p: box(p, v(0, -0.045, -0.237), (0.015, 0.015, 0.006))
    fingers = []
    for i, s in enumerate([1.0, 1.0, 0.96, 0.87]):
        y = -0.047 - i * 0.0185
        z = lean(y)
        fingers.append(([v(-0.031, y + 0.005, -0.165 + z), v(-0.026, y, -0.2125 + z),
                         v(0.002, y - 0.002, -0.2135 + z), v(0.0245, y - 0.004, -0.199 + z)], s))
    thumb = [v(-0.030, -0.070, -0.125), v(-0.021, -0.044, -0.150), v(0.004, -0.040, -0.1545), v(0.026, -0.043, -0.164)]
    hand = Hand(v(-0.052, -0.105, -0.105), v(-0.27, -0.30, 0.22), v(-1.0, 0.0, 0.0), fingers, thumb,
                v(-0.035, -0.095, -0.125), v(-0.030, -0.070, -0.128), grip)
    build("left", hand, lambda p: np.minimum(np.minimum(grip(p), guard(p)), stop(p)))


def left_hold():
    """Support hand cupping the rifle's fore-end from below, for a weapon without a foregrip."""
    forend = lambda p: box(p, v(0, -0.008, -0.2), (0.019, 0.017, 0.12))
    fingers = []
    for i, s in enumerate([1.0, 1.0, 0.96, 0.87]):
        z = -0.238 + i * 0.0195
        fingers.append(([v(-0.016, -0.043, z), v(0.014, -0.039, z - 0.002),
                         v(0.0335, -0.022, z - 0.003), v(0.0335, 0.002, z - 0.003)], s))
    thumb = [v(-0.034, -0.05, -0.15), v(-0.036, -0.022, -0.168), v(-0.0335, -0.002, -0.186), v(-0.031, 0.01, -0.206)]
    hand = Hand(v(-0.05, -0.085, -0.115), v(-0.27, -0.30, 0.22), v(0.0, -1.0, 0.0), fingers, thumb,
                v(-0.034, -0.066, -0.145), v(-0.04, -0.05, -0.165), forend)
    build("left_hold", hand, forend)


# --- fingers that find their own grip -------------------------------------------------
# Phalanx lengths (proximal, middle, distal) for index, middle, ring and little finger.
PHALANGES = [(0.039, 0.024, 0.019), (0.043, 0.027, 0.020), (0.040, 0.025, 0.019), (0.032, 0.0195, 0.017)]


def rotate(vec, axis, angle):
    """Rodrigues: vec turned about the unit axis."""
    axis = unit(axis)
    return vec * np.cos(angle) + np.cross(axis, vec) * np.sin(angle) + axis * (axis @ vec) * (1 - np.cos(angle))


def solve_finger(knuckle, start, palm, lengths, scale, prop, limits, gap=0.0011):
    """Curls one finger joint by joint until each bone touches the held object.

    start: direction the finger points with the joints straight; palm: the way it
    bends (towards the palm). limits: (min, max) degrees per joint. Returns the
    knuckle and the three joints after it."""
    radii = [0.0112 * scale, 0.0103 * scale, 0.0095 * scale, 0.0086 * scale]
    pts = [knuckle]
    p, d = knuckle, unit(start)
    bend = unit(palm - d * (palm @ d))
    for j, length in enumerate(lengths):
        axis = np.cross(d, bend)
        lo, hi = limits[j]
        chosen = None
        for deg in np.arange(lo, hi + 0.01, 1.5):
            dj = rotate(d, axis, np.radians(deg))
            t = np.linspace(0.25, 1.0, 7)
            samples = p + np.outer(t, dj * length)
            clearance = (prop(samples) - (radii[j] + (radii[j + 1] - radii[j]) * t)).min()
            if chosen is not None and clearance < gap:
                break
            chosen = (deg, dj)
        deg, dj = chosen
        bend = rotate(bend, axis, np.radians(deg))
        p = p + dj * length
        d = dj
        pts.append(p)
    return pts


def grip_fingers(wrist, knuckles, out, prop, poses):
    """poses: per finger (spread degrees, joint limits, scale)."""
    fingers = []
    for knuckle, lengths, (spread, limits, scale) in zip(knuckles, PHALANGES, poses):
        start = rotate(unit(knuckle - wrist), out, np.radians(spread))
        fingers.append((solve_finger(knuckle, start, -out, lengths, scale, prop, limits), scale))
    return fingers


LEFT_WRIST = v(-0.052, -0.105, -0.105)
LEFT_ELBOW = v(-0.27, -0.30, 0.22)
LEFT_OUT = v(-1.0, 0.0, 0.0)
LEFT_KNUCKLES = [v(-0.031, -0.042 - i * 0.0185, -0.165 + (-0.047 - i * 0.0185 + 0.07) * 0.105) for i in range(4)]
LEFT_THUMB = [v(-0.030, -0.070, -0.125), v(-0.021, -0.044, -0.150), v(0.004, -0.040, -0.1545), v(0.026, -0.043, -0.164)]
GRAB = v(0.0, -0.058, 0.095)       # viewmodel.gd: the hand's move from the foregrip to the magazine


def left_mag(name, mag_field):
    """Support hand holding a magazine (in the hand's own space, where viewmodel.gd
    carries it): the index finger lies straight along the front of the magazine,
    the others wrap round it each at their own height and curl."""
    prop = lambda p: mag_field(p + GRAB)
    poses = [(-4.0, [(0, 16), (0, 14), (0, 10)], 1.0),          # index: pointing along the front
             (2.0, [(8, 85), (10, 100), (6, 70)], 1.0),
             (6.0, [(12, 88), (12, 102), (8, 72)], 0.96),
             (11.0, [(16, 92), (14, 105), (10, 75)], 0.87)]
    fingers = grip_fingers(LEFT_WRIST, LEFT_KNUCKLES, LEFT_OUT, prop, poses)
    hand = Hand(LEFT_WRIST, LEFT_ELBOW, LEFT_OUT, fingers, LEFT_THUMB,
                v(-0.035, -0.095, -0.125), v(-0.030, -0.070, -0.128), prop)
    hand.watch = True
    build(name, hand, prop)


def left_open():
    """Support hand on its way between grip and magazine: open, relaxed, every
    finger curled a little differently."""
    nothing = lambda p: np.full(len(p), 1.0)
    poses = [(-6.0, [(14, 14), (16, 16), (8, 8)], 1.0),
             (0.0, [(20, 20), (24, 24), (12, 12)], 1.0),
             (6.0, [(26, 26), (30, 30), (16, 16)], 0.96),
             (13.0, [(32, 32), (36, 36), (20, 20)], 0.87)]
    fingers = grip_fingers(LEFT_WRIST, LEFT_KNUCKLES, LEFT_OUT, nothing, poses)
    thumb = [LEFT_THUMB[0], v(-0.024, -0.05, -0.152), v(-0.012, -0.044, -0.172), v(0.0, -0.042, -0.19)]
    hand = Hand(LEFT_WRIST, LEFT_ELBOW, LEFT_OUT, fingers, thumb,
                v(-0.035, -0.095, -0.125), v(-0.030, -0.070, -0.128), lambda p: ball(p, v(-0.004, -0.068, -0.19), 0.012))
    hand.watch = True
    build("left_open", hand, lambda p: np.full(len(p), 1.0))


def right_bolt():
    """Firing hand on the sniper's bolt knob (in the hand's own space, as
    viewmodel.gd pose_bolt carries it): the fingers close round the ball each as
    far as they can, the thumb presses on from the other side."""
    knob = v(0.054, 0.0, 0.079) - v(0.028, 0.078, 0.0)            # make_weapons sn_bolt ball, minus HAND_TO_KNOB
    prop = lambda p: np.minimum(ball(p, knob, 0.0105),
                                seg(p, knob + v(-0.039, 0.016, -0.014), knob, 0.0042))
    wrist = v(0.036, -0.128, 0.150)
    out = v(1.0, 0.0, 0.0)
    rake = lambda y: -(y + 0.098) * 0.249
    knuckles = [v(0.032, -0.070, 0.078)] + [v(0.031, -0.096 - i * 0.0205 + 0.006, 0.082 + rake(-0.096 - i * 0.0205)) for i in range(3)]
    poses = [(-8.0, [(10, 80), (10, 95), (6, 65)], 1.0),
             (-2.0, [(14, 88), (12, 100), (8, 70)], 1.0),
             (5.0, [(20, 92), (14, 104), (10, 72)], 0.96),
             (12.0, [(26, 95), (16, 106), (12, 75)], 0.87)]
    fingers = grip_fingers(wrist, knuckles, out, prop, poses)
    thumb = [v(0.012, -0.092, 0.122), v(-0.006, -0.074, 0.104), v(-0.004, -0.07, 0.086), v(0.006, -0.072, 0.074)]
    hand = Hand(wrist, v(0.17, -0.30, 0.46), out, fingers, thumb, v(0.020, -0.118, 0.118), v(0.008, -0.085, 0.118), prop)
    build("right_bolt", hand, prop)


# The hook grip on the bolt, as in a photo of a real hand: palm turned up under
# the rifle, index and middle finger hooked round the knob from behind, ring and
# little finger loosely curled, thumb left open. viewmodel.gd turns the forearm
# HOOK_TURN degrees about its own axis and puts HOOK_KNOB on the knob.
HOOK_TURN = -100.0
HOOK_KNOB = v(0.009, -0.0642, 0.0566)


def right_bolt_hook():
    wrist = v(0.036, -0.128, 0.150)
    elbow = v(0.17, -0.30, 0.46)
    f = unit(elbow - wrist)
    turn = lambda q: rotate(q, f, np.radians(HOOK_TURN))
    knob_w = v(0.054, 0.0, 0.079)
    origin = knob_w - turn(HOOK_KNOB)
    to_hand = lambda q: rotate(q - origin, f, -np.radians(HOOK_TURN))
    stem_a, stem_b = to_hand(v(0.015, 0.016, 0.065)), to_hand(v(0.05, 0.002, 0.078))
    prop = lambda p: np.minimum(ball(p, HOOK_KNOB, 0.0105), seg(p, stem_a, stem_b, 0.0042))
    out = v(1.0, 0.0, 0.0)
    rake = lambda y: -(y + 0.098) * 0.249
    knuckles = [v(0.032, -0.070, 0.078)] + [v(0.031, -0.096 - i * 0.0205 + 0.006, 0.082 + rake(-0.096 - i * 0.0205)) for i in range(3)]
    poses = [(-4.0, [(0, 30), (20, 115), (15, 85)], 1.0),       # index: hooked
             (0.0, [(0, 30), (20, 115), (15, 85)], 1.0),        # middle: hooked
             (6.0, [(35, 35), (55, 55), (35, 35)], 0.96),       # ring: loosely curled
             (12.0, [(45, 45), (60, 60), (40, 40)], 0.87)]      # little finger
    fingers = grip_fingers(wrist, knuckles, out, prop, poses)
    thumb = [v(0.012, -0.092, 0.122), v(-0.008, -0.08, 0.102), v(-0.022, -0.072, 0.086), v(-0.033, -0.066, 0.071)]
    hand = Hand(wrist, elbow, out, fingers, thumb, v(0.020, -0.118, 0.118), v(0.008, -0.085, 0.118), prop)
    build("right_bolt_hook", hand, prop)


def magazines():
    import make_gun as mg
    import make_weapons as mw
    left_mag("left_mag_rifle", mg.magazine)
    left_mag("left_mag_sniper", lambda p: np.minimum(mw.sn_mag(p), mw.sn_mag_brass(p)))
    left_open()


if __name__ == "__main__":
    import sys
    if "--hold" in sys.argv:
        left_hold()
        sys.exit(0)
    if "--mag" in sys.argv:
        magazines()
        sys.exit(0)
    if "--bolt" in sys.argv:
        right_bolt()
        right_bolt_hook()
        sys.exit(0)
    if "--hook" in sys.argv:
        right_bolt_hook()
        sys.exit(0)
    right_hand()
    left_hand()
    left_hold()
