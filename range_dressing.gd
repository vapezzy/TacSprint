extends Node3D

# The training ground's landscape around the obstacle course (main.gd builds
# the course itself): a lawn with tufts of grass, broadleaf trees and pines
# along the walls and outside them, a long-range target lane, and on the
# horizon a nuclear power station whose cooling towers steam into the sun.
#
# Everything is generated here: bark and leaf textures, tree meshes (a trunk
# and branches as tapered tubes, foliage as clusters of leaf cards), grass
# tufts as crossed blades, and the towers as hyperboloid shells.

const Target := preload("res://target.gd")

const AREA := 68.0                  # the range's inner half-size (walls at 70)
var station_at := Vector3(150.0, 0.0, -230.0)   # main.gd puts it towards the sun
var rng := RandomNumberGenerator.new()
var _leaf_mat: StandardMaterial3D
var _needle_mat: StandardMaterial3D
var _bark_mat: StandardMaterial3D
var _grass_mat: StandardMaterial3D


func _ready() -> void:
	rng.seed = 1977
	_materials()
	_lawn()
	_grass()
	for i in 34:
		# Trees along the inside of the walls, more outside them.
		var at := _edge_spot(rng.randf_range(58.0, 66.0))
		_tree(at, rng.randf() < 0.55)
	for i in 70:
		var at := _edge_spot(rng.randf_range(76.0, 130.0))
		_tree(at, rng.randf() < 0.45)
	_targets()
	_power_station(station_at)


func _edge_spot(r: float) -> Vector3:
	var a := rng.randf() * TAU
	var x := cos(a) * r
	var z := sin(a) * r
	# Push points towards the square's edge rather than a circle.
	var k := r / maxf(absf(x), absf(z))
	return Vector3(x * k, 0.0, z * k)


# --- materials ------------------------------------------------------------------------

func _noise_tex(seed: int, freq: float, colors: PackedColorArray, offsets: PackedFloat32Array, size := 512) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = 5
	var ramp := Gradient.new()
	ramp.colors = colors
	ramp.offsets = offsets
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.color_ramp = ramp
	return t


func _materials() -> void:
	_bark_mat = StandardMaterial3D.new()
	_bark_mat.albedo_texture = _noise_tex(4, 0.05, PackedColorArray([Color(0.09, 0.07, 0.05), Color(0.2, 0.16, 0.12), Color(0.32, 0.27, 0.21)]), PackedFloat32Array([0.0, 0.5, 1.0]))
	var bump := _noise_tex(5, 0.09, PackedColorArray([Color.BLACK, Color.WHITE]), PackedFloat32Array([0.0, 1.0]))
	bump.as_normal_map = true
	bump.bump_strength = 12.0
	_bark_mat.normal_enabled = true
	_bark_mat.normal_texture = bump
	_bark_mat.roughness = 0.95
	_bark_mat.uv1_scale = Vector3(3.0, 6.0, 1.0)
	_leaf_mat = _card_mat(_leaf_texture(false))
	_needle_mat = _card_mat(_leaf_texture(true))
	_grass_mat = _card_mat(_grass_texture())
	_grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _card_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	# Light shining through the leaves.
	m.backlight_enabled = true
	m.backlight = Color(0.35, 0.45, 0.15)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# A cluster of leaves (or a spray of needles) on a transparent card.
func _leaf_texture(needles: bool) -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 31 if needles else 17
	var count := 260 if needles else 70
	for i in count:
		var c := Vector2(r.randf_range(20, s - 20), r.randf_range(20, s - 20))
		if c.distance_to(Vector2(s, s) / 2.0) > s * 0.46:
			continue
		var shade := r.randf_range(0.6, 1.15)
		var col := Color(0.16, 0.3, 0.08) * shade if needles else Color(0.22, 0.38, 0.1) * shade
		col.a = 1.0
		var ang := r.randf() * TAU
		var length := r.randf_range(14, 22) if needles else r.randf_range(16, 26)
		var width := 1.6 if needles else length * 0.42
		var dir := Vector2(cos(ang), sin(ang))
		var side := Vector2(-dir.y, dir.x)
		# Draw an elongated leaf (or needle) pixel by pixel.
		for y in range(int(c.y - length), int(c.y + length)):
			for x in range(int(c.x - length), int(c.x + length)):
				if x < 0 or y < 0 or x >= s or y >= s:
					continue
				var d := Vector2(x, y) - c
				var u := d.dot(dir) / length
				var v := d.dot(side) / width
				if absf(u) <= 1.0 and absf(v) <= sqrt(maxf(1.0 - u * u, 0.0)):
					var vein := 1.0 - 0.25 * exp(-v * v * 40.0)
					img.set_pixel(x, y, Color(col.r * vein, col.g * vein, col.b * vein, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _grass_texture() -> ImageTexture:
	var w := 128
	var h := 128
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = 77
	for i in 46:
		var x0 := r.randf_range(8, w - 8)
		var tall := r.randf_range(0.55, 1.0) * h
		var lean := r.randf_range(-18, 18)
		var base_w := r.randf_range(2.0, 3.6)
		var col := Color(0.25, 0.42, 0.12) * r.randf_range(0.7, 1.2)
		for yy in int(tall):
			var t := float(yy) / tall
			var cx := x0 + lean * t * t
			var half := base_w * (1.0 - t)
			for xx in range(int(cx - half - 1), int(cx + half + 2)):
				if xx >= 0 and xx < w and absf(xx - cx) <= half:
					var c := col.lerp(Color(0.55, 0.62, 0.25), t * 0.6)
					img.set_pixel(xx, h - 1 - yy, Color(c.r, c.g, c.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- ground ----------------------------------------------------------------------------

func _lawn() -> void:
	var lawn := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	lawn.mesh = plane
	var m := StandardMaterial3D.new()
	m.albedo_texture = _noise_tex(9, 0.012, PackedColorArray([Color(0.12, 0.2, 0.06), Color(0.2, 0.31, 0.09), Color(0.27, 0.36, 0.12), Color(0.33, 0.33, 0.17)]), PackedFloat32Array([0.0, 0.4, 0.75, 1.0]), 1024)
	var bump := _noise_tex(10, 0.2, PackedColorArray([Color.BLACK, Color.WHITE]), PackedFloat32Array([0.0, 1.0]))
	bump.as_normal_map = true
	bump.bump_strength = 6.0
	m.normal_enabled = true
	m.normal_texture = bump
	m.roughness = 0.95
	m.uv1_scale = Vector3(40, 40, 1)
	lawn.material_override = m
	lawn.position.y = 0.012
	add_child(lawn)


func _grass() -> void:
	# A tuft: three blade cards crossing at the middle.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var dx := Vector3(cos(a), 0, sin(a)) * 0.22
		var up := Vector3(0, 0.38, 0)
		var quad := [-dx, dx, dx + up, -dx + up]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(quad[idx])
	var tuft := st.commit()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tuft
	mm.instance_count = 14000
	for i in mm.instance_count:
		var p := Vector3(rng.randf_range(-AREA, AREA), 0.0, rng.randf_range(-AREA, AREA))
		# Keep the sprint lane and the course mostly clear, thicker at the edges.
		if absf(p.x) < 12.0 and rng.randf() < 0.85:
			p.x = signf(p.x + 0.001) * rng.randf_range(12.0, AREA)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.4))
		mm.set_instance_transform(i, Transform3D(b, p))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _grass_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- trees ----------------------------------------------------------------------------

# A tapered tube from a to b, with bark.
func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides := 9) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var other := axis.cross(side)
	var length := a.distance_to(b)
	for k in sides:
		var a0 := float(k) / sides * TAU
		var a1 := float(k + 1) / sides * TAU
		var n0 := side * cos(a0) + other * sin(a0)
		var n1 := side * cos(a1) + other * sin(a1)
		var verts := [a + n0 * ra, a + n1 * ra, b + n1 * rb, b + n0 * rb]
		var norms := [n0, n1, n1, n0]
		var uvs := [Vector2(float(k) / sides, 0), Vector2(float(k + 1) / sides, 0), Vector2(float(k + 1) / sides, length), Vector2(float(k) / sides, length)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(norms[idx])
			st.set_uv(uvs[idx])
			st.add_vertex(verts[idx])


func _tree(at: Vector3, pine: bool) -> void:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = rng.randf() * TAU
	add_child(root)
	var size := rng.randf_range(0.8, 1.35)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ends: Array[Vector3] = []
	var height := (11.0 if pine else 8.0) * size
	_tube(st, Vector3.ZERO, Vector3(0, height, 0), 0.32 * size, 0.06 * size)
	if pine:
		# Whorls of short branches drooping down the trunk.
		for level in 9:
			var y := height * (0.25 + level * 0.085)
			var reach := (3.2 - level * 0.3) * size
			for k in 5:
				var a := k * TAU / 5.0 + level * 0.6
				var tip := Vector3(cos(a) * reach, y - 0.6 * size, sin(a) * reach)
				_tube(st, Vector3(0, y, 0), tip, 0.06 * size, 0.02 * size, 5)
				ends.append(tip)
				ends.append(Vector3(0, y, 0).lerp(tip, 0.5))
		ends.append(Vector3(0, height, 0))
	else:
		# A few big limbs forking off, each with smaller branches.
		for k in 5:
			var a := k * TAU / 5.0 + rng.randf_range(-0.3, 0.3)
			var y := height * rng.randf_range(0.4, 0.6)
			var tip := Vector3(cos(a) * 3.0 * size, height * rng.randf_range(0.75, 0.95), sin(a) * 3.0 * size)
			_tube(st, Vector3(0, y, 0), tip, 0.16 * size, 0.05 * size, 7)
			for j in 3:
				var twig := tip + Vector3(rng.randf_range(-1.6, 1.6), rng.randf_range(0.3, 1.4), rng.randf_range(-1.6, 1.6)) * size
				var from := Vector3(0, y, 0).lerp(tip, rng.randf_range(0.5, 0.9))
				_tube(st, from, twig, 0.05 * size, 0.015 * size, 5)
				ends.append(twig)
			ends.append(tip)
		ends.append(Vector3(0, height, 0))
	st.generate_tangents()
	var wood := MeshInstance3D.new()
	wood.mesh = st.commit()
	wood.material_override = _bark_mat
	root.add_child(wood)
	# Foliage: leaf cards packed round every branch end, facing every way.
	var card := QuadMesh.new()
	card.size = Vector2(1.6, 1.6) * size * (0.8 if pine else 1.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = card
	var per := 9 if pine else 22
	mm.instance_count = ends.size() * per
	var i := 0
	for e: Vector3 in ends:
		for k in per:
			var spread := (1.0 if pine else 1.8) * size
			var p := e + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.8), rng.randf_range(-1, 1)) * spread
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU))
			b = b.scaled(Vector3.ONE * rng.randf_range(0.7, 1.2))
			mm.set_instance_transform(i, Transform3D(b, p))
			i += 1
	var leaves := MultiMeshInstance3D.new()
	leaves.multimesh = mm
	leaves.material_override = _needle_mat if pine else _leaf_mat
	root.add_child(leaves)


# --- targets ---------------------------------------------------------------------------

signal target_hit


func _targets() -> void:
	# A long-range lane: targets from 20 to 90 metres in front of the start.
	for i in 8:
		var tg := Target.new()
		add_child(tg)
		tg.global_position = Vector3(-50.0 + i * 1.8, 0, 30.0 - i * 11.0)
		tg.was_hit.connect(func() -> void: target_hit.emit())
	# A scattered field among the trees and the course.
	var spots := [Vector3(30, 0, 50), Vector3(40, 0, 35), Vector3(48, 0, 12), Vector3(52, 0, -15), Vector3(35, 0, -40),
			Vector3(15, 0, -55), Vector3(-10, 0, -60), Vector3(-30, 0, -50), Vector3(-55, 0, -30), Vector3(-60, 0, 0),
			Vector3(-45, 0, 45), Vector3(0, 0, -30), Vector3(20, 0, -10), Vector3(-15, 0, -20)]
	for s: Vector3 in spots:
		var tg := Target.new()
		add_child(tg)
		tg.global_position = s
		tg.was_hit.connect(func() -> void: target_hit.emit())


# --- the power station on the horizon ------------------------------------------------------

func _power_station(at: Vector3) -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_texture = _noise_tex(21, 0.02, PackedColorArray([Color(0.55, 0.54, 0.5), Color(0.68, 0.67, 0.63), Color(0.6, 0.58, 0.54)]), PackedFloat32Array([0.0, 0.5, 1.0]))
	concrete.roughness = 0.95
	concrete.uv1_scale = Vector3(4, 2, 1)
	for k in 2:
		var tower := _cooling_tower(110.0, 38.0)
		tower.material_override = concrete
		tower.position = at + Vector3(k * 95.0, 0, k * -40.0)
		add_child(tower)
		_steam(tower.position + Vector3(0, 112.0, 0))
	# The reactor block and a stack beside the towers.
	var block := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60, 30, 40)
	block.mesh = bm
	block.material_override = concrete
	block.position = at + Vector3(-70, 15, 30)
	add_child(block)
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 22.0
	dm.height = 22.0
	dm.is_hemisphere = true
	dome.mesh = dm
	dome.material_override = concrete
	dome.position = at + Vector3(-70, 30, 30)
	add_child(dome)
	var stack := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 2.5
	sm.bottom_radius = 4.0
	sm.height = 120.0
	stack.mesh = sm
	stack.material_override = concrete
	stack.position = at + Vector3(-30, 60, 60)
	add_child(stack)


# A hyperboloid shell: wide at the foot, narrowest about two thirds up, flaring at the top.
func _cooling_tower(height: float, base_r: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 32
	var sides := 48
	var waist := height * 0.72
	var waist_r := base_r * 0.6
	var c := waist / sqrt((base_r / waist_r) * (base_r / waist_r) - 1.0)
	var prof := []
	for i in rings + 1:
		var y := height * float(i) / rings
		var r := waist_r * sqrt(1.0 + pow((y - waist) / c, 2.0))
		prof.append(Vector2(r, y))
	for i in rings:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		for k in sides:
			var a0 := float(k) / sides * TAU
			var a1 := float(k + 1) / sides * TAU
			var v := [Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x), Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x),
					Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x), Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)]
			var slope := (p1.x - p0.x) / maxf(p1.y - p0.y, 0.001)
			var n0 := Vector3(cos(a0), -slope, sin(a0)).normalized()
			var n1 := Vector3(cos(a1), -slope, sin(a1)).normalized()
			var ns := [n0, n1, n1, n0]
			var uv := [Vector2(float(k) / sides, float(i) / rings), Vector2(float(k + 1) / sides, float(i) / rings),
					Vector2(float(k + 1) / sides, float(i + 1) / rings), Vector2(float(k) / sides, float(i + 1) / rings)]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(ns[idx])
				st.set_uv(uv[idx])
				st.add_vertex(v[idx])
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	return m


# Steam rising out of a tower: huge, slow, bright billows drifting with the wind.
func _steam(top: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = top
	p.amount = 160
	p.lifetime = 26.0
	p.preprocess = 26.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 20.0
	p.direction = Vector3(0.25, 1, 0)
	p.spread = 12.0
	p.gravity = Vector3(1.4, 1.2, 0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 5.0
	p.damping_min = 0.05
	p.damping_max = 0.12
	p.scale_amount_min = 1.2
	p.scale_amount_max = 1.8
	var grow := Curve.new()
	grow.max_value = 6.0
	grow.add_point(Vector2(0.0, 1.0))
	grow.add_point(Vector2(1.0, 5.5))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(0.97, 0.97, 0.97, 0.32), Color(0.92, 0.92, 0.93, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.1, 1.0])
	p.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2(40, 40)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _soft_puff()
	mat.backlight_enabled = true
	mat.backlight = Color(1.0, 0.95, 0.85)
	puff.material = mat
	p.mesh = puff
	add_child(p)


func _soft_puff() -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.05
	for y in s:
		for x in s:
			var d := Vector2(x - s / 2.0, y - s / 2.0).length() / (s / 2.0)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (0.6 + 0.4 * (n.get_noise_2d(x, y) * 0.5 + 0.5))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
