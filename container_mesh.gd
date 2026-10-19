extends RefCounted

# Builds a shipping container as one mesh: corrugated walls, frame, corner
# castings and doors with locking rods. Origin is the centre of the base,
# the length runs along X and the doors sit at +X.
#
# Vertex colour: r = how exposed the part is to wear, g = surface kind
# (0 paint, 0.33 bare steel, 0.66 rubber, 1 wood).

const W := 2.438
const H := 2.591
const PAINT := 0.0
const STEEL := 0.33
const RUBBER := 0.66
const WOOD := 1.0

var st: SurfaceTool
var xf := Transform3D.IDENTITY
var col := Color(0.2, PAINT, 0)


func build(length: float, open: bool) -> ArrayMesh:
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var l := length
	var hx := l / 2.0
	var hz := W / 2.0

	# Corrugated side walls and roof.
	_paint(0.15)
	_corrugated(Vector3(-hx + 0.16, 0.16, hz - 0.045), Vector3.RIGHT, Vector3.UP, Vector3.BACK, l - 0.32, H - 0.26, 0.036, 0.278)
	_corrugated(Vector3(hx - 0.16, 0.16, -hz + 0.045), Vector3.LEFT, Vector3.UP, Vector3.FORWARD, l - 0.32, H - 0.26, 0.036, 0.278)
	_corrugated(Vector3(-hx + 0.1, H - 0.045, hz - 0.1), Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, l - 0.2, W - 0.2, 0.02, 0.21)

	# Frame: posts, rails and the cast corner fittings.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_paint(0.6)
			_box(Vector3(sx * (hx - 0.08), H / 2.0, sz * (hz - 0.08)), Vector3(0.16, H, 0.16))
			_paint(0.95)
			_box(Vector3(sx * (hx - 0.085), 0.065, sz * (hz - 0.08)), Vector3(0.19, 0.13, 0.18))
			_box(Vector3(sx * (hx - 0.085), H - 0.065, sz * (hz - 0.08)), Vector3(0.19, 0.13, 0.18))
	for sz: float in [-1.0, 1.0]:
		_paint(0.75)
		_box(Vector3(0, 0.08, sz * (hz - 0.05)), Vector3(l - 0.32, 0.16, 0.1))
		_paint(0.5)
		_box(Vector3(0, H - 0.05, sz * (hz - 0.04)), Vector3(l - 0.32, 0.1, 0.08))
		if l < 7.0:
			# Forklift pockets.
			col = Color(0.3, RUBBER, 0)
			for px: float in [-1.02, 1.02]:
				_box(Vector3(px, 0.075, sz * (hz - 0.047)), Vector3(0.36, 0.1, 0.11))
	for sx: float in [-1.0, 1.0]:
		_paint(0.7)
		_box(Vector3(sx * (hx - 0.06), 0.08, 0), Vector3(0.12, 0.16, W - 0.32))
		_box(Vector3(sx * (hx - 0.06), H - 0.06, 0), Vector3(0.12, 0.12, W - 0.32))

	if open:
		# Both ends open: plywood floor, door leaves folded back along the sides.
		col = Color(0.5, WOOD, 0)
		_box(Vector3(0, 0.02, 0), Vector3(l - 0.1, 0.03, W - 0.2))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var c := Vector3(sx * (hx - 0.68), H / 2.0, sz * (hz + 0.035))
				_paint(0.35)
				_box(c, Vector3(1.14, H - 0.36, 0.045))
				col = Color(0.6, STEEL, 0)
				for rx: float in [-0.3, 0.28]:
					_rod(c + Vector3(rx, -(H - 0.4) / 2.0, sz * 0.04), H - 0.4, 0.017)
	else:
		_paint(0.2)
		_box(Vector3(0, 0.11, 0), Vector3(l - 0.3, 0.1, W - 0.2))
		_corrugated(Vector3(-hx + 0.045, 0.16, -hz + 0.16), Vector3.BACK, Vector3.UP, Vector3.LEFT, W - 0.32, H - 0.28, 0.036, 0.278)
		_doors(hx, hz)

	return st.commit()


func _doors(hx: float, hz: float) -> void:
	var leaf := hz - 0.17
	for sz: float in [-1.0, 1.0]:
		_paint(0.3)
		var z0 := 0.012 if sz > 0.0 else -leaf - 0.012
		_corrugated(Vector3(hx - 0.035, 0.2, z0), Vector3.UP, Vector3.BACK, Vector3.RIGHT, H - 0.38, leaf, 0.018, 0.47)
		# Hinges on the outer post.
		_paint(1.0)
		for hy: float in [0.42, 1.0, 1.6, 2.18]:
			_box(Vector3(hx + 0.004, hy, sz * (hz - 0.13)), Vector3(0.05, 0.15, 0.07))
		# Two locking rods per leaf with guides, cams and handles.
		for rz: float in [0.3, 0.9]:
			var z := sz * rz
			col = Color(0.7, STEEL, 0)
			_rod(Vector3(hx + 0.012, 0.1, z), H - 0.2, 0.017)
			for gy: float in [0.16, 0.55, H / 2.0, H - 0.55, H - 0.16]:
				_box(Vector3(hx + 0.012, gy, z), Vector3(0.05, 0.06, 0.075))
			var hy2 := 1.12 if rz < 0.5 else 1.36
			_box(Vector3(hx + 0.04, hy2, z - sz * 0.15), Vector3(0.022, 0.034, 0.34))
			_box(Vector3(hx + 0.03, hy2, z - sz * 0.31), Vector3(0.04, 0.07, 0.05))
	# Rubber gasket where the leaves meet.
	col = Color(0.2, RUBBER, 0)
	_box(Vector3(hx - 0.012, H / 2.0, 0), Vector3(0.03, H - 0.38, 0.03))


func _paint(wear: float) -> void:
	col = Color(wear, PAINT, 0)


# a, b, c, d run counter-clockwise when seen from outside.
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	a = xf * a
	b = xf * b
	c = xf * c
	d = xf * d
	var n := (b - a).cross(c - a).normalized()
	for v: Vector3 in [a, c, b, a, d, c]:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


func _box(c: Vector3, size: Vector3) -> void:
	var h := size / 2.0
	var p := func(x: float, y: float, z: float) -> Vector3: return c + Vector3(x * h.x, y * h.y, z * h.z)
	_quad(p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1))        # +X
	_quad(p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1))    # -X
	_quad(p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1))        # +Y
	_quad(p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1))    # -Y
	_quad(p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1))        # +Z
	_quad(p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1))    # -Z


# A ribbed sheet. The trapezoid profile runs along u, the ribs stand along v
# and bulge towards n; u, v, n must be right-handed (u x v = n).
func _corrugated(origin: Vector3, u: Vector3, v: Vector3, n: Vector3, u_len: float, v_len: float, depth: float, period: float) -> void:
	var steps := [[0.0, 1.0], [0.3, 1.0], [0.5, 0.0], [0.8, 0.0]]
	var pts: Array[Vector2] = []
	var count := int(ceil(u_len / period))
	for i in count + 1:
		for s: Array in steps:
			var x: float = (i + s[0]) * period
			if x >= u_len:
				break
			pts.append(Vector2(x, s[1] * depth))
	pts.append(Vector2(u_len, pts[-1].y))
	for i in pts.size() - 1:
		var a := origin + u * pts[i].x + n * pts[i].y
		var b := origin + u * pts[i + 1].x + n * pts[i + 1].y
		_quad(a, b, b + v * v_len, a + v * v_len)


# Upright round bar starting at base.
func _rod(base: Vector3, height: float, radius: float) -> void:
	var sides := 8
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var verts := [base + d0 * radius, base + d0 * radius + Vector3.UP * height,
				base + d1 * radius + Vector3.UP * height, base + d1 * radius]
		var norms := [d0, d0, d1, d1]
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal((xf.basis * norms[k]).normalized())
			st.set_color(col)
			st.add_vertex(xf * verts[k])
