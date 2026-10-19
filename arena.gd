extends Node3D

# A compact freight yard: rows of stacked shipping containers with narrow
# lanes between them. The layout lives in the tables below; set `greybox`
# before adding the node to see plain blocks instead of detailed containers.

signal target_hit

const Assets := preload("res://assets.gd")
const ContainerMesh := preload("res://container_mesh.gd")
const Target := preload("res://target.gd")

const W := 2.438
const H := 2.591
const L20 := 6.058
const L40 := 12.192

# Playable area (x, z) and where the player starts.
const BOUNDS := Rect2(-18.05, -16.05, 36.1, 32.1)
const SPAWN := Vector3(-16.6, 0.05, -4.4)
const SPAWN_YAW := -90.0

# Muted, worn paint colours.
const PAINTS := [
	Color(0.13, 0.24, 0.38),   # 0 blue
	Color(0.42, 0.12, 0.09),   # 1 red
	Color(0.15, 0.29, 0.2),    # 2 green
	Color(0.6, 0.44, 0.12),    # 3 yellow
	Color(0.4, 0.41, 0.4),     # 4 grey
	Color(0.5, 0.24, 0.1),     # 5 orange
	Color(0.1, 0.27, 0.29),    # 6 teal
	Color(0.62, 0.6, 0.55),    # 7 off-white
]

# Containers: [length, x, z, yaw in degrees, stack level, paint, open at both ends]
# Four bands of boxes standing north-south with three cross lanes between them.
# The outer bands use one set of columns, the inner bands another, so a gap in
# one band always faces a box in the next. Boxes laid across the lanes cut the
# long views; each leaves a gap beside it to get around.
const LAYOUT := [
	# Band A, against the north wall.
	[L20, -16.86, -13.05, 90, 0, 2, false], [L20, -10.49, -13.05, 90, 0, 5, false], [L20, -5.45, -13.05, 90, 0, 0, false],
	[L20, -0.41, -13.05, 90, 0, 1, false], [L20, 9.67, -13.05, 90, 0, 3, false], [L20, 16.86, -13.05, 90, 0, 6, false],
	# Band B.
	[L20, -13.01, -4.37, 90, 0, 4, false], [L20, -7.97, -4.37, 90, 0, 1, false], [L20, -2.93, -4.37, 90, 0, 3, false],
	[L20, 2.11, -4.37, 90, 0, 0, false], [L20, 7.15, -4.37, 90, 0, 2, false],
	# Band C.
	[L20, -14.42, 4.29, 90, 0, 6, false], [L20, -7.97, 4.29, 90, 0, 0, false], [L20, -2.93, 4.29, 90, 0, 5, false],
	[L20, 7.15, 4.29, 90, 0, 1, false], [L20, 12.19, 4.29, 90, 0, 4, false],
	# Band D, against the south wall.
	[L20, -10.49, 13.05, 93, 0, 3, false], [L20, -5.45, 13.05, 90, 0, 2, false], [L20, -0.41, 13.05, 90, 0, 7, false],
	[L20, 4.63, 13.05, 90, 0, 0, false], [L20, 9.67, 13.05, 90, 0, 5, false], [L20, 14.71, 13.05, 87, 0, 6, false],
	# Boxes laid across the cross lanes; two of them are open and can be run through.
	[L20, -6.16, -8.71, 0, 0, 7, false], [L20, 12.2, -8.71, 0, 0, 4, true],
	[L20, 5.84, -0.04, 0, 0, 6, false],
	[L20, -1.12, 8.61, 0, 0, 1, false], [L20, 11.0, 8.61, 0, 0, 3, true],
	# Two boxes against the side walls stop the view down the outer lanes.
	[L20, -16.86, 4.29, 90, 0, 2, false], [L20, 16.86, -4.37, 90, 0, 5, false],
	# Second level. Those lying crosswise roof over the gap beneath them.
	[L20, -2.93, -13.05, 0, 1, 4, false], [L20, -16.86, -12.9, 90, 1, 0, false], [L20, 16.86, -13.2, 90, 1, 1, false],
	[L20, -0.41, -4.37, 0, 1, 5, false], [L20, -13.01, -4.5, 90, 1, 2, false],
	[L20, 12.19, 4.1, 90, 1, 7, false], [L20, -5.45, 4.29, 0, 1, 3, false],
	[L20, 7.15, 13.05, 0, 1, 6, false], [L20, -5.45, 13.2, 90, 1, 0, false],
	[L20, -6.16, -8.6, 4, 1, 2, false], [L20, 5.84, 0.1, -3, 1, 1, false],
]

# Perimeter rows, two high: [length, x, z, yaw, paint low, paint high, third level paint or -1]
const WALLS := [
	[L40, -12.0, -17.3, 0, 4, 0, -1], [L40, 0.192, -17.3, 0, 1, 2, 5], [L40, 12.384, -17.3, 0, 0, 3, -1],
	[L40, -12.0, 17.3, 0, 2, 5, 0], [L40, 0.192, 17.3, 0, 6, 1, -1], [L40, 12.384, 17.3, 0, 3, 4, 2],
	[L40, -19.3, -11.9, 90, 5, 6, -1], [L40, -19.3, 0.292, 90, 0, 1, 3], [L20, -19.3, 9.417, 90, 3, 2, -1], [L20, -19.3, 15.475, 90, 1, 4, -1],
	[L20, 19.3, -14.924, 90, 2, 0, -1], [L40, 19.3, -5.8, 90, 1, 5, 6], [L40, 19.3, 6.392, 90, 4, 3, -1], [L20, 19.3, 15.517, 90, 0, 1, -1],
]

# Low cover and steps: [kind, x, z, yaw]. A crate beside a container lets you climb onto it.
const PROPS := [
	["crate", 3.95, -15.3, 0], ["pallets", 5.1, -12.4, 12], ["barrels", 3.8, -10.9, 0],
	["crate", 11.6, -6.6, 6], ["barrier", 12.2, -3.4, 80], ["barrels", 14.2, -2.2, 30],
	["crate", 1.5, 4.3, 10], ["crate_small", 2.5, 5.0, 30], ["cone", 0.1, 2.3, 0],
	["pallets", -17.4, -1.9, 90], ["pipes", -14.9, -15.2, 90],
	["barrier", -14.8, 11.5, 88], ["barrels", -16.9, 15.0, 0], ["crate", -12.35, 15.3, 0],
	["crate_small", 16.7, 5.6, 20], ["barrels", 16.9, 9.1, 50],
	["cone", -16.2, -8.0, 0], ["cone", 16.8, 0.6, 0],
]

# Target dummies: [x, z, yaw]
const TARGETS := [[-17.2, 13.2, 90], [14.4, -14.6, -30], [5.0, -14.9, 0], [2.0, 6.5, 180], [14.6, -6.2, 200], [17.1, 4.3, -90]]

var greybox := false
var with_targets := true
var _meshes := {}
var _container_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_container_mat = ShaderMaterial.new()
	_container_mat.shader = load("res://container.gdshader")
	_container_mat.set_shader_parameter("grime", Assets.grime())
	_container_mat.set_shader_parameter("scratch_d", Assets.tex("blue_metal_plate_diffuse.jpg", true))
	_container_mat.set_shader_parameter("scratch_n", Assets.tex("blue_metal_plate_nor_gl.jpg"))
	_container_mat.set_shader_parameter("rust_d", Assets.tex("rusty_metal_02_diffuse.jpg"))
	_container_mat.set_shader_parameter("wood_d", Assets.tex("weathered_planks_diffuse.jpg"))

	_ground()
	for c: Array in LAYOUT:
		_container(c[0], Vector3(c[1], c[4] * H, c[2]), c[3], c[5], c[6], c[4] > 0)
	for w: Array in WALLS:
		_container(w[0], Vector3(w[1], 0, w[2]), w[3], w[4], false, false)
		_container(w[0], Vector3(w[1], H, w[2]), w[3], w[5], false, true)
		if w[6] >= 0:
			_container(L20 if w[0] > 7.0 else w[0], Vector3(w[1], H * 2.0, w[2]), w[3], w[6], false, true)
	if not greybox:
		_backdrop()
	for p: Array in PROPS:
		_prop(p[0], Vector3(p[1], 0, p[2]), p[3])
	for t: Array in (TARGETS if with_targets else []):
		var tg := Target.new()
		add_child(tg)
		tg.position = Vector3(t[0], 0, t[1])
		tg.rotation.y = deg_to_rad(t[2])
		tg.was_hit.connect(func() -> void: target_hit.emit())


func _static(shape: Shape3D, at: Transform3D, parent: Node3D = self) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.transform = at
	parent.add_child(body)


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _flat(color: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _mesh(mesh: Mesh, mat: Material, at: Transform3D, parent: Node3D = self) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.transform = at
	parent.add_child(m)
	return m


func _ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(160, 160)
	var mat: Material
	if greybox:
		mat = _flat(Color(0.4, 0.4, 0.4))
	else:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://ground.gdshader")
		sm.set_shader_parameter("conc_d", Assets.tex("hangar_concrete_floor_diffuse.jpg"))
		sm.set_shader_parameter("conc_n", Assets.tex("hangar_concrete_floor_nor_gl.jpg"))
		sm.set_shader_parameter("conc_r", Assets.tex("hangar_concrete_floor_rough.jpg"))
		sm.set_shader_parameter("dirt_d", Assets.tex("dirty_concrete_diffuse.jpg"))
		sm.set_shader_parameter("grime", Assets.grime())
		mat = sm
	_mesh(plane, mat, Transform3D.IDENTITY)
	_static(_box_shape(Vector3(160, 1, 160)), Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)))


func _container(length: float, base: Vector3, yaw: float, paint: int, open: bool, stacked: bool) -> void:
	var root := Node3D.new()
	# Stacked boxes never sit perfectly square on the one below.
	var jitter := _rng.randf_range(-1.2, 1.2) if stacked else 0.0
	root.position = base
	root.rotation.y = deg_to_rad(yaw + jitter)
	add_child(root)

	if greybox:
		var b := BoxMesh.new()
		b.size = Vector3(length, H, W)
		var c: Color = PAINTS[paint]
		_mesh(b, _flat(c.lightened(0.25) if open else c), Transform3D(Basis.IDENTITY, Vector3(0, H / 2.0, 0)), root)
	else:
		var key := "%d%s" % [int(length), "o" if open else "c"]
		if not _meshes.has(key):
			_meshes[key] = ContainerMesh.new().build(length, open)
		var m := _mesh(_meshes[key], _container_mat, Transform3D.IDENTITY, root)
		m.set_instance_shader_parameter("paint", PAINTS[paint])
		m.set_instance_shader_parameter("seed", _rng.randf_range(0.0, 40.0))

	if open:
		# Walk-through: only the two long walls and the roof block the player.
		for sz: float in [-1.0, 1.0]:
			_static(_box_shape(Vector3(length, H, 0.09)), Transform3D(Basis.IDENTITY, Vector3(0, H / 2.0, sz * (W / 2.0 - 0.045))), root)
		_static(_box_shape(Vector3(length, 0.1, W)), Transform3D(Basis.IDENTITY, Vector3(0, H - 0.05, 0)), root)
	else:
		_static(_box_shape(Vector3(length, H, W)), Transform3D(Basis.IDENTITY, Vector3(0, H / 2.0, 0)), root)


# Taller stacks and a pair of light masts outside the play area, for depth.
func _backdrop() -> void:
	var far := [
		[L40, -9.0, -24.5, 2, 3], [L40, 6.0, -25.5, -3, 4], [L40, 20.0, -24.0, 5, 3],
		[L40, -27.0, -8.0, 92, 4], [L40, -26.0, 7.5, 88, 3], [L40, 27.0, 2.0, 91, 4], [L40, 26.5, -13.0, 87, 3],
		[L40, -8.0, 25.0, -2, 3], [L40, 8.5, 24.5, 3, 4],
	]
	for f: Array in far:
		for level in int(f[4]):
			_container(f[0], Vector3(f[1], level * H, f[2]), f[3], _rng.randi_range(0, PAINTS.size() - 1), false, level > 0)
	for mast: Vector3 in [Vector3(-22.5, 0, -21.5), Vector3(22.5, 0, 21.5)]:
		var steel := _flat(Color(0.3, 0.31, 0.3), 0.6)
		steel.metallic = 0.6
		var pole := CylinderMesh.new()
		pole.top_radius = 0.12
		pole.bottom_radius = 0.2
		pole.height = 16.0
		_mesh(pole, steel, Transform3D(Basis.IDENTITY, mast + Vector3(0, 8, 0)))
		var head := BoxMesh.new()
		head.size = Vector3(2.6, 0.5, 0.5)
		_mesh(head, steel, Transform3D(Basis(Vector3.UP, 0.7), mast + Vector3(0, 16.1, 0)))


func _wood() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = Assets.tex("weathered_planks_diffuse.jpg")
	m.albedo_color = Color(0.85, 0.8, 0.72)
	m.normal_enabled = true
	m.normal_texture = Assets.tex("weathered_planks_nor_gl.jpg")
	m.roughness = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.9
	return m


func _concrete() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = Assets.tex("hangar_concrete_floor_diffuse.jpg")
	m.albedo_color = Color(0.8, 0.8, 0.78)
	m.normal_enabled = true
	m.normal_texture = Assets.tex("hangar_concrete_floor_nor_gl.jpg")
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.7
	return m


func _painted_metal(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = Assets.tex("blue_metal_plate_diffuse.jpg", true)
	m.albedo_color = color * 2.4
	m.normal_enabled = true
	m.normal_texture = Assets.tex("blue_metal_plate_nor_gl.jpg")
	m.roughness_texture = Assets.tex("blue_metal_plate_rough.jpg")
	m.roughness = 0.85
	m.metallic = 0.25
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.8
	return m


func _prop(kind: String, at: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = deg_to_rad(yaw)
	add_child(root)
	match kind:
		"crate":
			_crate(root, Vector3(1.15, 1.05, 1.15))
		"crate_small":
			_crate(root, Vector3(0.8, 0.62, 0.8))
		"pallets":
			_pallets(root, 5)
		"barrier":
			_barrier(root)
		"barrels":
			_barrels(root)
		"pipes":
			_pipes(root)
		"cone":
			_cone(root)


func _crate(root: Node3D, size: Vector3) -> void:
	var b := BoxMesh.new()
	b.size = size
	_mesh(b, _flat(Color(0.55, 0.42, 0.25)) if greybox else _wood(), Transform3D(Basis.IDENTITY, Vector3(0, size.y / 2.0, 0)), root)
	_static(_box_shape(size), Transform3D(Basis.IDENTITY, Vector3(0, size.y / 2.0, 0)), root)
	if greybox:
		return
	# Corner battens and a lid frame.
	var wood := _wood()
	wood.albedo_color = Color(0.6, 0.55, 0.48)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var post := BoxMesh.new()
			post.size = Vector3(0.09, size.y + 0.02, 0.09)
			_mesh(post, wood, Transform3D(Basis.IDENTITY, Vector3(sx * (size.x / 2.0), size.y / 2.0, sz * (size.z / 2.0))), root)
	for sz: float in [-1.0, 1.0]:
		var rail := BoxMesh.new()
		rail.size = Vector3(size.x + 0.04, 0.08, 0.05)
		_mesh(rail, wood, Transform3D(Basis.IDENTITY, Vector3(0, size.y - 0.04, sz * (size.z / 2.0 + 0.012))), root)
		var rail2 := BoxMesh.new()
		rail2.size = Vector3(0.05, 0.08, size.z + 0.04)
		_mesh(rail2, wood, Transform3D(Basis.IDENTITY, Vector3(sz * (size.x / 2.0 + 0.012), size.y - 0.04, 0)), root)


func _pallets(root: Node3D, count: int) -> void:
	var total := count * 0.145
	_static(_box_shape(Vector3(1.2, total, 0.8)), Transform3D(Basis.IDENTITY, Vector3(0, total / 2.0, 0)), root)
	if greybox:
		var b := BoxMesh.new()
		b.size = Vector3(1.2, total, 0.8)
		_mesh(b, _flat(Color(0.6, 0.5, 0.3)), Transform3D(Basis.IDENTITY, Vector3(0, total / 2.0, 0)), root)
		return
	var wood := _wood()
	for i in count:
		var layer := Node3D.new()
		layer.position = Vector3(_rng.randf_range(-0.03, 0.03), i * 0.145, _rng.randf_range(-0.03, 0.03))
		layer.rotation.y = deg_to_rad(_rng.randf_range(-3.0, 3.0))
		root.add_child(layer)
		for sz: float in [-0.35, 0.0, 0.35]:
			var runner := BoxMesh.new()
			runner.size = Vector3(1.2, 0.1, 0.09)
			_mesh(runner, wood, Transform3D(Basis.IDENTITY, Vector3(0, 0.072, sz)), layer)
		for k in 5:
			var board := BoxMesh.new()
			board.size = Vector3(0.14, 0.022, 0.8)
			_mesh(board, wood, Transform3D(Basis.IDENTITY, Vector3(-0.53 + k * 0.265, 0.134, 0)), layer)
		for sx: float in [-0.53, 0.0, 0.53]:
			var under := BoxMesh.new()
			under.size = Vector3(0.14, 0.022, 0.8)
			_mesh(under, wood, Transform3D(Basis.IDENTITY, Vector3(sx, 0.011, 0)), layer)


func _barrier(root: Node3D) -> void:
	_static(_box_shape(Vector3(0.6, 0.81, 2.0)), Transform3D(Basis.IDENTITY, Vector3(0, 0.405, 0)), root)
	# Road barrier profile, pushed out along Z.
	var profile := [Vector2(-0.3, 0), Vector2(0.3, 0), Vector2(0.3, 0.08), Vector2(0.12, 0.33), Vector2(0.08, 0.81),
			Vector2(-0.08, 0.81), Vector2(-0.12, 0.33), Vector2(-0.3, 0.08)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	for i in n:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[(i + 1) % n]
		var quad := [Vector3(a.x, a.y, 1), Vector3(b.x, b.y, 1), Vector3(b.x, b.y, -1), Vector3(a.x, a.y, -1)]
		var normal: Vector3 = (quad[1] - quad[0]).cross(quad[2] - quad[0]).normalized()
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(normal)
			st.add_vertex(quad[k])
	for end: float in [1.0, -1.0]:
		for i in range(1, n - 1):
			var tri := [profile[0], profile[i], profile[i + 1]]
			var order := [0, 2, 1] if end > 0.0 else [0, 1, 2]
			for k: int in order:
				st.set_normal(Vector3(0, 0, end))
				st.add_vertex(Vector3(tri[k].x, tri[k].y, end))
	_mesh(st.commit(), _flat(Color(0.5, 0.5, 0.48)) if greybox else _concrete(), Transform3D.IDENTITY, root)


func _barrels(root: Node3D) -> void:
	var spots := [Vector3(0, 0, 0), Vector3(0.63, 0, 0.1), Vector3(0.28, 0, 0.58)]
	var colours := [Color(0.1, 0.17, 0.3), Color(0.33, 0.09, 0.07), Color(0.1, 0.17, 0.3)]
	for i in spots.size():
		var shape := CylinderShape3D.new()
		shape.radius = 0.29
		shape.height = 0.88
		_static(shape, Transform3D(Basis.IDENTITY, spots[i] + Vector3(0, 0.44, 0)), root)
		var mat := _flat(colours[i]) if greybox else _painted_metal(colours[i])
		var drum := CylinderMesh.new()
		drum.top_radius = 0.285
		drum.bottom_radius = 0.285
		drum.height = 0.88
		_mesh(drum, mat, Transform3D(Basis(Vector3.UP, i * 1.3), spots[i] + Vector3(0, 0.44, 0)), root)
		if greybox:
			continue
		for y: float in [0.015, 0.3, 0.58, 0.865]:
			var ring := CylinderMesh.new()
			ring.top_radius = 0.296
			ring.bottom_radius = 0.296
			ring.height = 0.03
			_mesh(ring, mat, Transform3D(Basis.IDENTITY, spots[i] + Vector3(0, y, 0)), root)


func _pipes(root: Node3D) -> void:
	_static(_box_shape(Vector3(1.3, 0.62, 4.0)), Transform3D(Basis.IDENTITY, Vector3(0, 0.31, 0)), root)
	var mat := _flat(Color(0.3, 0.3, 0.32)) if greybox else _painted_metal(Color(0.2, 0.2, 0.21))
	var lie := Basis(Vector3.RIGHT, PI / 2.0)
	for spot: Vector3 in [Vector3(-0.33, 0.31, 0), Vector3(0.33, 0.31, 0), Vector3(0, 0.88, 0.1)]:
		if spot.y > 0.5 and greybox:
			continue
		var pipe := CylinderMesh.new()
		pipe.top_radius = 0.31
		pipe.bottom_radius = 0.31
		pipe.height = 4.0
		pipe.cap_top = false
		pipe.cap_bottom = false
		var m := _mesh(pipe, mat, Transform3D(lie, spot), root)
		if not greybox:
			(m.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	# The top pipe rests on the lower two and is solid as well.
	_static(_box_shape(Vector3(0.6, 0.55, 4.0)), Transform3D(Basis.IDENTITY, Vector3(0, 0.9, 0.1)), root)


func _cone(root: Node3D) -> void:
	var body := CylinderMesh.new()
	body.top_radius = 0.025
	body.bottom_radius = 0.14
	body.height = 0.5
	_mesh(body, _flat(Color(0.75, 0.22, 0.04), 0.6), Transform3D(Basis.IDENTITY, Vector3(0, 0.27, 0)), root)
	var foot := BoxMesh.new()
	foot.size = Vector3(0.34, 0.03, 0.34)
	_mesh(foot, _flat(Color(0.03, 0.03, 0.03)), Transform3D(Basis.IDENTITY, Vector3(0, 0.015, 0)), root)
