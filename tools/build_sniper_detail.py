"""Rebuilds only the sniper parts that carry the AX-50 detail pass."""
import make_weapons as m

box_lo, box_hi = (-0.045, -0.165, -0.66), (0.065, 0.075, 0.33)
m.build_hi("sniper", [(0, m.sn_painted), (1, m.sn_polymer), (2, m.sn_steel)], box_lo, box_hi, 0.4)
m.build_hi("sniper_bolt", [(2, m.sn_bolt)], (-0.02, -0.01, -0.1), (0.07, 0.04, 0.11), 0.6)
b_lo, b_hi = (-0.035, -0.02, -1.02), (0.035, 0.05, -0.15)
m.build_hi("sniper_optic_scope", [(3, m.sn_glass), (0, m.sn_scope)], (-0.055, 0.035, -0.285), (0.06, 0.14, 0.19), 0.45)
