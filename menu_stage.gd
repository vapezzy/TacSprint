extends Node3D

# The scene behind the main menu, the way the big shooters do it: your operator
# stands in a dim hangar bay, lit hard from the front left with a cold rim
# light behind, dust hanging in the beams. Most of the time they stand, shift
# their weight and look around; now and then they walk a few steps across the
# bay and turn back, or raise the rifle and check it. The camera is close and
# low, breathes slightly like a handheld shot, and blurs the background.
#
# It sits far away from every map (STAGE_AT), keeps running while the game is
# paused for the menu, and hides itself while its camera is not in use.

const Assets := preload("res://assets.gd")
const Soldier := preload("res://soldier.gd")

const STAGE_AT := Vector3(0.0, 0.0, 600.0)
const MARK := Vector3(-0.25, 0.0, 0.0)          # where the operator likes to stand

var cam: Camera3D
var op: Soldier
var _t := 0.0
var _state := "idle"
var _state_t := 0.0
var _x := 0.0
var _target_x := 0.0
var _yaw := PI
var _look := 0.0
var _look_target := 0.0
var _look_t := 0.0
var _check := 0.0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = STAGE_AT


func _ready() -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_texture = Assets.tex("hangar_concrete_floor_diffuse.jpg")
	concrete.albedo_color = Color(0.55, 0.55, 0.56)
	concrete.normal_enabled = true
	concrete.normal_texture = Assets.tex("hangar_concrete_floor_nor_gl.jpg")
	concrete.roughness_texture = Assets.tex("hangar_concrete_floor_rough.jpg")
	concrete.uv1_triplanar = true
	concrete.uv1_scale = Vector3.ONE * 0.35
	var wall := StandardMaterial3D.new()
	wall.albedo_texture = Assets.tex("dirty_concrete_diffuse.jpg")
	wall.albedo_color = Color(0.5, 0.5, 0.52)
	wall.normal_enabled = true
	wall.normal_texture = Assets.tex("hangar_concrete_floor_nor_gl.jpg")
	wall.uv1_triplanar = true
	wall.uv1_scale = Vector3.ONE * 0.2
	var steel := StandardMaterial3D.new()
	steel.albedo_texture = Assets.tex("blue_metal_plate_diffuse.jpg", true)
	steel.albedo_color = Color(0.25, 0.26, 0.27)
	steel.metallic = 0.6
	steel.roughness = 0.5
	steel.uv1_triplanar = true
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = Assets.tex("weathered_planks_diffuse.jpg")
	wood.albedo_color = Color(0.7, 0.62, 0.5)
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3.ONE * 1.5
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.14, 0.16, 0.1)
	olive.roughness = 0.7
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.9, 0.75)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.65)
	lamp.emission_energy_multiplier = 6.0

	# The bay: floor, back wall with steel columns, side walls, a roof with light strips.
	_box(Vector3(30, 0.2, 30), Vector3(0, -0.1, 0), concrete)
	_box(Vector3(24, 9, 0.6), Vector3(0, 4.5, -7.0), wall)
	_box(Vector3(0.6, 9, 20), Vector3(-9.0, 4.5, 2.0), wall)
	_box(Vector3(0.6, 9, 20), Vector3(9.0, 4.5, 2.0), wall)
	_box(Vector3(24, 0.4, 20), Vector3(0, 7.2, 2.0), steel)
	for x: float in [-6.0, -2.0, 2.0, 6.0]:
		_box(Vector3(0.5, 9, 0.5), Vector3(x, 4.5, -6.6), steel)
	for x: float in [-4.0, 0.0, 4.0]:
		_box(Vector3(0.3, 0.08, 6.0), Vector3(x, 6.95, -1.0), lamp)
	# A big roller door behind, slightly open: a line of daylight under it.
	_box(Vector3(6.0, 4.6, 0.12), Vector3(3.2, 2.7, -6.65), steel)
	var gap := StandardMaterial3D.new()
	gap.albedo_color = Color(0.8, 0.85, 0.95)
	gap.emission_enabled = true
	gap.emission = Color(0.75, 0.82, 0.95)
	gap.emission_energy_multiplier = 3.0
	_box(Vector3(6.0, 0.35, 0.05), Vector3(3.2, 0.2, -6.58), gap)
	# Kit around the operator: crates, an ammo case, barrels, a weapon rack.
	_box(Vector3(1.2, 0.8, 0.8), Vector3(-2.6, 0.4, -2.4), wood)
	_box(Vector3(1.0, 0.7, 0.8), Vector3(-2.4, 1.15, -2.3), wood)
	_box(Vector3(0.9, 0.35, 0.45), Vector3(1.9, 0.18, -1.2), olive)
	_box(Vector3(0.9, 0.35, 0.45), Vector3(1.95, 0.53, -1.25), olive)
	for p: Vector3 in [Vector3(4.6, 0, -4.2), Vector3(5.3, 0, -3.8), Vector3(4.9, 0, -3.3)]:
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.3
		barrel.bottom_radius = 0.3
		barrel.height = 0.9
		_mesh(barrel, olive, p + Vector3(0, 0.45, 0))
	_box(Vector3(2.4, 0.08, 0.5), Vector3(-5.0, 1.5, -6.3), steel)
	_box(Vector3(2.4, 0.08, 0.5), Vector3(-5.0, 0.6, -6.3), steel)
	for i in 4:
		var rifle := MeshInstance3D.new()
		rifle.mesh = Assets.mesh("ar_body.bin")
		rifle.material_override = steel
		add_child(rifle)
		rifle.position = Vector3(-5.9 + i * 0.6, 1.05, -6.2)
		rifle.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)

	# Light: a warm key from the front left, a cold rim from behind right, a dim fill.
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 26.0
	key.spot_range = 14.0
	key.spot_angle = 42.0
	key.shadow_enabled = true
	key.light_volumetric_fog_energy = 2.0
	add_child(key)
	key.look_at_from_position(Vector3(-3.5, 5.0, 4.0), Vector3(-0.2, 1.0, 0.0))
	var rim := SpotLight3D.new()
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 30.0
	rim.spot_range = 12.0
	rim.spot_angle = 22.0
	rim.light_volumetric_fog_energy = 3.0
	add_child(rim)
	rim.look_at_from_position(Vector3(3.0, 3.6, -4.5), Vector3(-0.2, 1.3, 0.0))
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.6, 0.65, 0.75)
	fill.light_energy = 2.2
	fill.omni_range = 9.0
	fill.position = Vector3(1.5, 1.5, 3.5)
	add_child(fill)
	for x: float in [-4.0, 0.0, 4.0]:
		var strip := OmniLight3D.new()
		strip.light_color = Color(1.0, 0.85, 0.65)
		strip.light_energy = 2.5
		strip.omni_range = 6.0
		strip.position = Vector3(x, 6.4, -1.0)
		add_child(strip)

	# The operator.
	op = Soldier.new()
	add_child(op)
	op.setup(Color(0.25, 0.55, 1.0), false)
	_x = MARK.x
	_target_x = MARK.x
	op.position = MARK
	op.rotation.y = _yaw

	cam = Camera3D.new()
	cam.fov = 38.0
	cam.cull_mask = 1
	var lens := CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = true
	lens.dof_blur_far_distance = 5.5
	lens.dof_blur_far_transition = 3.0
	lens.dof_blur_amount = 0.06
	cam.attributes = lens
	add_child(cam)
	_place_camera()


func _box(size: Vector3, at: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	_mesh(b, mat, at)


func _mesh(mesh: Mesh, mat: Material, at: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = at
	add_child(m)


func _place_camera() -> void:
	# Low and close, the operator in the right half of the picture.
	var sway := Vector3(sin(_t * 0.31) * 0.03, sin(_t * 0.47) * 0.02, 0.0)
	var eye := global_position + Vector3(-0.6, 1.2, 4.4) + sway
	var at := global_position + Vector3(_x * 0.8 - 0.62, 1.02, 0.0)
	cam.look_at_from_position(eye, at, Vector3.UP)


func _process(dt: float) -> void:
	visible = cam.current
	if not visible:
		return
	_t += dt
	_state_t -= dt
	var speed := 0.0
	match _state:
		"idle":
			if _state_t <= 0.0:
				# Pick what to do next: mostly stand, sometimes walk, sometimes check the rifle.
				var r := randf()
				if r < 0.35:
					_state = "walk"
					# A few steps across the lit patch of floor, never out of the light.
					_target_x = MARK.x + randf_range(-1.0, 0.45)
					if absf(_target_x - _x) < 0.6:
						_target_x = MARK.x - 0.8 if _x > MARK.x - 0.3 else MARK.x + 0.4
				elif r < 0.6:
					_state = "check"
					_state_t = 2.6
				else:
					_state_t = randf_range(3.0, 6.0)
		"walk":
			var to := _target_x - _x
			if absf(to) < 0.05:
				_state = "idle"
				_state_t = randf_range(2.5, 5.0)
			else:
				var step := signf(to) * minf(absf(to), 1.25 * dt)
				_x += step
				speed = 1.25
		"check":
			if _state_t <= 0.0:
				_state = "idle"
				_state_t = randf_range(3.0, 5.0)
	# Facing: towards the camera when standing, sideways while walking.
	var want_yaw := PI + 0.35
	if _state == "walk":
		want_yaw = PI + (PI / 2.0 if _target_x < _x else -PI / 2.0) * 0.85
	_yaw = lerp_angle(_yaw, want_yaw, 1.0 - exp(-5.0 * dt))
	op.position = Vector3(_x, 0.0, 0.0)
	op.rotation.y = _yaw
	# Rifle check: raise it, tilt it to look at the side, lower it again.
	var raise := 0.0
	if _state == "check":
		var k := 1.0 - _state_t / 2.6
		raise = sin(clampf(k, 0.0, 1.0) * PI)
	_check = lerpf(_check, raise, 1.0 - exp(-6.0 * dt))
	op.aim_pitch = _check * 0.25
	op.animate(dt, speed, _check > 0.5)
	op.gun.rotation.z += _check * 0.6
	# The head looks around now and then.
	_look_t -= dt
	if _look_t <= 0.0:
		_look_t = randf_range(1.5, 4.0)
		_look_target = randf_range(-0.6, 0.6) if randf() < 0.6 else 0.0
	_look = lerpf(_look, _look_target, 1.0 - exp(-3.0 * dt))
	op.head.rotation.y = _look
	_place_camera()
