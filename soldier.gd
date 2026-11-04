extends Node3D

# The figure of a bot (or the other player in LAN): the same generated legs,
# trousers, boots and plate carrier the player wears (legs.gd), with arms that
# reach for a real rifle model, a head with helmet, ear protection and a
# night-vision mount, and an armband in the team colour. The legs walk with the
# knee solver; the arms are solved the same way from shoulder to hand, so the
# hands stay on the grip and the handguard while the upper body aims.
#
# Local space: +X right, +Y up, -Z forward, origin on the ground between the feet.

const Assets := preload("res://assets.gd")
const Legs := preload("res://legs.gd")

const UPPER_ARM := 0.29
const FOREARM := 0.28
const PIVOT := Vector3(0, 1.38, 0.0)           # where the upper body turns to aim
const SHOULDER_R := Vector3(0.19, 0.03, -0.01)  # relative to PIVOT
const SHOULDER_L := Vector3(-0.19, 0.03, -0.01)
const GUN_AT := Vector3(0.1, 0.06, -0.42)       # rifle origin, relative to PIVOT
const GRIP := Vector3(0.0, -0.085, 0.045)       # in the rifle's frame
const HANDGUARD := Vector3(-0.01, -0.035, -0.3)

var legs: Legs
var upper: Node3D
var gun: Node3D
var muzzle: Node3D
var head: Node3D
var arm_parts: Array[MeshInstance3D] = []       # upper r, fore r, upper l, fore l
var hands: Array[MeshInstance3D] = []
var aim_pitch := 0.0
var _phase := 0.0
var _pitch := 0.0
var _breath := 0.0


func setup(team_color: Color, enemy_look: bool) -> void:
	legs = Legs.new()
	add_child(legs)
	var cloth: ShaderMaterial = legs.torso.material_override
	if enemy_look:
		# The other side wears grey urban camo instead of the green woodland pattern.
		cloth = cloth.duplicate()
		cloth.set_shader_parameter("camo", _urban_camo())
		for part: Node in legs.find_children("*", "MeshInstance3D", true, false):
			var mi := part as MeshInstance3D
			if mi.material_override is ShaderMaterial:
				mi.material_override = cloth
	# Sleeves and neck: plain cloth in the same camo (the capsules carry no zones
	# for the arms shader).
	var sleeve: StandardMaterial3D = legs._cloth()
	if enemy_look:
		sleeve.albedo_texture = _urban_camo()
	var gear := StandardMaterial3D.new()
	gear.albedo_color = Color(0.05, 0.05, 0.05) if enemy_look else Color(0.13, 0.12, 0.08)
	gear.roughness = 0.75
	gear.normal_enabled = true
	gear.normal_texture = Assets.tex("rubberized_track_nor_gl.jpg")
	gear.uv1_triplanar = true
	gear.uv1_scale = Vector3.ONE * 5.0
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.04, 0.04, 0.04)
	glove.roughness = 0.6
	glove.normal_enabled = true
	glove.normal_texture = Assets.tex("brown_leather_nor_gl.jpg")
	glove.uv1_triplanar = true
	glove.uv1_scale = Vector3.ONE * 8.0
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.55, 0.4, 0.31) if randf() < 0.6 else Color(0.33, 0.23, 0.17)
	skin.roughness = 0.55
	skin.subsurf_scatter_enabled = true
	skin.subsurf_scatter_strength = 0.35
	skin.rim_enabled = true
	skin.rim = 0.25
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.07, 0.072, 0.075)
	metal.metallic = 0.55
	metal.roughness = 0.42
	var band := StandardMaterial3D.new()
	band.albedo_color = team_color
	band.emission_enabled = true
	band.emission = team_color
	band.emission_energy_multiplier = 0.6

	upper = Node3D.new()
	upper.position = PIVOT
	add_child(upper)

	# Head: a sculpted face and neck (tools/make_soldier.py), eyes, a high-cut
	# helmet with ear protection under it. The enemies pull a balaclava over the face.
	head = Node3D.new()
	head.position = Vector3(0, 0.215, 0.0)
	upper.add_child(head)
	# Nobody shows a bare face: a balaclava over the sculpted head, and wrap-around
	# ballistic glasses over the eyes, the way most operators wear it.
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.035, 0.035, 0.035) if enemy_look else Color(0.1, 0.105, 0.075)
	face_mat.roughness = 0.97
	face_mat.normal_enabled = true
	face_mat.normal_texture = Assets.tex("stretch_poplin_nor_gl.jpg")
	face_mat.normal_scale = 1.4
	face_mat.uv1_triplanar = true
	face_mat.uv1_scale = Vector3.ONE * 14.0
	_model(head, "soldier_head_masked.bin", face_mat)
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.025, 0.028, 0.032)
	lens.metallic = 0.85
	lens.roughness = 0.08
	_model(head, "soldier_goggles.bin", lens)
	var shell := gear.duplicate() as StandardMaterial3D
	shell.albedo_color = Color(0.06, 0.06, 0.065) if enemy_look else Color(0.3, 0.27, 0.19)
	_model(head, "soldier_helmet.bin", shell)
	for sx: float in [-1.0, 1.0]:
		var cup := CylinderMesh.new()
		cup.top_radius = 0.04
		cup.bottom_radius = 0.045
		cup.height = 0.04
		_part(head, cup, gear, Vector3(sx * 0.09, 0.0, 0.004), Vector3(0, 0, PI / 2.0))
	var mount := BoxMesh.new()
	mount.size = Vector3(0.045, 0.035, 0.03)
	_part(head, mount, metal, Vector3(0, 0.082, -0.122))

	# The rifle: the player's own KR-4 model with a magazine and a holo sight.
	gun = Node3D.new()
	gun.position = GUN_AT
	upper.add_child(gun)
	for part: Array in [["ar_body.bin", Vector3.ZERO], ["mag.bin", Vector3.ZERO], ["opt_holo.bin", Vector3(0, 0.055, -0.02)]]:
		var m := MeshInstance3D.new()
		m.mesh = Assets.mesh(part[0])
		m.material_override = metal
		m.position = part[1]
		gun.add_child(m)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0.0, -0.54)
	gun.add_child(muzzle)

	# Arms: upper arm and forearm in the uniform, gloves, the band on the left arm.
	for i in 4:
		var m := _model(upper, "soldier_upper_arm.bin" if i % 2 == 0 else "soldier_forearm.bin", cloth)
		arm_parts.append(m)
	for i in 2:
		var h := _part(upper, _sphere(0.048, 0.09), glove, Vector3.ZERO)
		h.scale = Vector3(0.8, 0.9, 1.25)
		hands.append(h)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.072
	ring.bottom_radius = 0.072
	ring.height = 0.06
	var armband := _part(arm_parts[2], ring, band, Vector3(0, 0.03, 0))
	armband.name = "Band"
	# Pouches on the belt and a small pack on the back.
	var pack := BoxMesh.new()
	pack.size = Vector3(0.24, 0.28, 0.09)
	_part(upper, pack, gear, Vector3(0, -0.12, 0.17))
	_solve_arms()


func _model(parent: Node3D, file: String, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = Assets.mesh(file)
	m.material_override = mat
	parent.add_child(m)
	return m


func _urban_camo() -> Texture2D:
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.06, 0.06, 0.065), Color(0.06, 0.06, 0.065), Color(0.16, 0.165, 0.17),
			Color(0.16, 0.165, 0.17), Color(0.3, 0.3, 0.3), Color(0.3, 0.3, 0.3), Color(0.11, 0.11, 0.115)])
	ramp.offsets = PackedFloat32Array([0.0, 0.36, 0.385, 0.54, 0.565, 0.7, 0.725])
	var n := FastNoiseLite.new()
	n.seed = 77
	n.frequency = 0.013
	n.fractal_octaves = 4
	var camo := NoiseTexture2D.new()
	camo.width = 512
	camo.height = 512
	camo.seamless = true
	camo.noise = n
	camo.color_ramp = ramp
	return camo


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	parent.add_child(m)
	return m


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	return c


func _sphere(radius: float, height: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = height
	return s


# Elbow for an arm from shoulder s to hand h, bending towards pole.
func _joint(s: Vector3, h: Vector3, pole: Vector3, a: float, b: float) -> Vector3:
	var v := h - s
	var d := clampf(v.length(), 0.05, a + b - 0.002)
	var n := v.normalized()
	var along := (a * a - b * b + d * d) / (2.0 * d)
	var out := sqrt(maxf(a * a - along * along, 0.0))
	var side := pole - n * pole.dot(n)
	if side.length() < 0.001:
		side = Vector3.DOWN
	return s + n * along + side.normalized() * out


func _span(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var y := (b - a).normalized()
	var x := Vector3.RIGHT - y * y.x
	if x.length() < 0.01:
		x = Vector3.BACK
	x = x.normalized()
	m.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) / 2.0)


func _solve_arms() -> void:
	var to_upper := gun.transform
	var hand_r := to_upper * GRIP
	var hand_l := to_upper * HANDGUARD
	var targets := [[SHOULDER_R, hand_r, Vector3(1.0, -1.0, 0.4)], [SHOULDER_L, hand_l, Vector3(-0.5, -1.0, 0.2)]]
	for i in 2:
		var s: Vector3 = targets[i][0]
		var h: Vector3 = targets[i][1]
		var reach := h - s
		if reach.length() > UPPER_ARM + FOREARM - 0.004:
			h = s + reach.normalized() * (UPPER_ARM + FOREARM - 0.004)
		var e := _joint(s, h, targets[i][2], UPPER_ARM, FOREARM)
		_span(arm_parts[i * 2], s, e)
		_span(arm_parts[i * 2 + 1], e, h)
		hands[i].transform = Transform3D(Basis.looking_at(to_upper.basis * Vector3.FORWARD, Vector3.UP), h)


# speed: how fast the figure moves over the ground; dt: frame time.
# aiming: whether it is in a fight (rifle up) or moving about (rifle lower).
func animate(dt: float, speed: float, aiming: bool, crouched := false) -> void:
	_phase += speed * dt * 3.0
	_breath += dt
	var state := "Bot Idle"
	if crouched:
		state = "Crouch Walk" if speed > 0.4 else "Crouch Idle"
	elif speed > 3.6:
		state = "Bot Run"
	elif speed > 0.4:
		state = "Bot Walk"
	legs.update(dt, state, _phase, speed, 0.0, 0.0, 1.62)
	# legs.gd leans the chest back for the player's own view; stand the bot upright.
	var hip := legs.pelvis.position
	legs._span(legs.torso, hip + Vector3(0, 0.02, 0.0), hip + Vector3(0, 0.4, -0.02))
	upper.position = PIVOT + Vector3(0, hip.y - 0.975, 0)
	# The upper body follows the aim, sways a little with each step and breathes.
	var walk_bob := sin(_phase * 2.0) * 0.012 * clampf(speed / 3.0, 0.0, 1.0)
	_pitch = lerpf(_pitch, aim_pitch, 1.0 - exp(-10.0 * dt))
	upper.rotation = Vector3(_pitch + sin(_breath * 1.7) * 0.01, sin(_phase) * 0.05 * clampf(speed / 3.0, 0.0, 1.0), 0)
	upper.position.y += walk_bob
	# Rifle up at the shoulder in a fight, angled down while moving.
	var low := 0.0 if aiming else 1.0
	gun.position = GUN_AT.lerp(GUN_AT + Vector3(-0.02, -0.06, 0.08), low)
	gun.rotation = Vector3(deg_to_rad(-22.0) * low, deg_to_rad(10.0) * low, 0.0)
	head.rotation.x = -_pitch * 0.3
	_solve_arms()
