extends Node3D

# The player's own legs, seen when looking down. Each view state has a leg
# pose (hip position and where each foot goes); the knees are solved from hip
# and foot, and each leg eases into a new pose at its own speed, so the two
# never move as one block. Walking and running add a stride that follows the
# distance actually covered.
#
# Local space: +X right, +Y up, -Z forward (the way the body faces).

const Assets := preload("res://assets.gd")

const THIGH := 0.44
const SHIN := 0.45
const ANKLE := 0.09      # ankle height above the sole
const RIGHT := 0
const LEFT := 1

# state -> [hip, right foot, left foot, stride, lift]
const POSES := {
	"Idle": [Vector3(0, 0.93, 0.01), Vector3(0.12, ANKLE, -0.1), Vector3(-0.11, ANKLE, -0.03), 0.0, 0.0],
	"Walk": [Vector3(0, 0.92, 0.02), Vector3(0.11, ANKLE, -0.06), Vector3(-0.11, ANKLE, -0.06), 0.3, 0.11],
	"Sprint": [Vector3(0, 0.9, 0.07), Vector3(0.11, ANKLE, 0.03), Vector3(-0.11, ANKLE, 0.03), 0.5, 0.2],
	"Tactical Sprint": [Vector3(0, 0.88, 0.09), Vector3(0.11, ANKLE, 0.04), Vector3(-0.11, ANKLE, 0.04), 0.58, 0.26],
	# Jump: one knee drives up, the other leg trails.
	"Jump": [Vector3(0, 0.94, 0.05), Vector3(0.11, 0.36, -0.14), Vector3(-0.11, 0.2, 0.24), 0.0, 0.0],
	# Fall: both legs reach down and forward for the ground.
	"Fall": [Vector3(0, 0.94, 0.05), Vector3(0.13, 0.12, -0.18), Vector3(-0.13, 0.16, 0.08), 0.0, 0.0],
	# Land: feet planted wide, hips sink.
	"Land": [Vector3(0, 0.72, 0.09), Vector3(0.15, ANKLE, -0.08), Vector3(-0.15, ANKLE, 0.09), 0.0, 0.0],
	# Slide: hips drop behind the view, the left leg shoots out, the right folds under.
	"Slide Enter": [Vector3(0, 0.44, 0.2), Vector3(0.21, 0.1, -0.26), Vector3(-0.06, 0.16, -0.6), 0.0, 0.0],
	"Slide Loop": [Vector3(0, 0.3, 0.3), Vector3(0.23, 0.1, -0.27), Vector3(-0.05, 0.12, -0.58), 0.0, 0.0],
	"Slide Exit": [Vector3(0, 0.5, 0.13), Vector3(0.12, ANKLE, -0.26), Vector3(-0.13, ANKLE, 0.1), 0.0, 0.0],
	"Crouch Idle": [Vector3(0, 0.5, 0.14), Vector3(0.13, ANKLE, -0.22), Vector3(-0.14, ANKLE, 0.12), 0.0, 0.0],
	"Crouch Walk": [Vector3(0, 0.5, 0.14), Vector3(0.13, ANKLE, -0.1), Vector3(-0.14, ANKLE, 0.02), 0.2, 0.08],
	# Prone: the body stretches out behind the head, toes down.
	"Prone Enter": [Vector3(0, 0.4, 0.4), Vector3(0.13, ANKLE, 0.22), Vector3(-0.14, 0.1, 0.95), 0.0, 0.0],
	"Prone Idle": [Vector3(0, 0.16, 0.85), Vector3(0.15, 0.1, 1.71), Vector3(-0.15, 0.1, 1.71), 0.1, 0.0],
	"Prone Exit": [Vector3(0, 0.5, 0.3), Vector3(0.13, ANKLE, -0.1), Vector3(-0.14, ANKLE, 0.62), 0.0, 0.0],
	"Mantle": [Vector3(0, 0.9, 0.1), Vector3(0.12, 0.5, -0.2), Vector3(-0.12, 0.15, 0.16), 0.0, 0.0],
}

var hip := Vector3(0, 0.93, 0.05)
var foot: Array[Vector3] = [Vector3(0.11, ANKLE, 0.03), Vector3(-0.11, ANKLE, 0.0)]
var ankle: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]    # where each ankle ended up, read by the self-test
var stride := 0.0
var lift := 0.0

var thigh: Array[MeshInstance3D] = []
var shin: Array[MeshInstance3D] = []
var boot: Array[Node3D] = []
var pelvis: Node3D
var torso: MeshInstance3D


func _init() -> void:
	var cloth := _cloth()
	var leather := _leather()
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color(0.016, 0.016, 0.015)
	pad.roughness = 0.95

	pelvis = Node3D.new()
	add_child(pelvis)
	# Hips as a rounded shape, with a matte belt around them.
	var hips := MeshInstance3D.new()
	var hm := CapsuleMesh.new()
	hm.radius = 0.12
	hm.height = 0.42
	hips.mesh = hm
	hips.material_override = cloth
	hips.rotation.z = PI / 2.0
	hips.scale = Vector3(1.0, 1.0, 0.9)
	pelvis.add_child(hips)
	# (Belt, holster and pouch boxes are gone: the generated torso carries the gear.)

	# Upper body: a vest that runs from the hips up towards the camera, so
	# looking down shows a chest and gear instead of a cut-off waist.
	# A generated model (tools/make_legs.py): shirt, plate carrier with pouches, radio.
	torso = MeshInstance3D.new()
	torso.mesh = Assets.mesh("torso.bin")
	torso.material_override = Assets.cloth(0.0)
	add_child(torso)

	# Thigh, shin and boot are generated models (tools/make_legs.py), one set per side.
	var worn := Assets.cloth(0.0)
	for side in 2:
		var tag := "r" if side == RIGHT else "l"
		var t := MeshInstance3D.new()
		t.mesh = Assets.mesh("thigh_" + tag + ".bin")
		t.material_override = worn
		add_child(t)
		thigh.append(t)

		var s := MeshInstance3D.new()
		s.mesh = Assets.mesh("shin_" + tag + ".bin")
		s.material_override = worn
		add_child(s)
		shin.append(s)

		var b := MeshInstance3D.new()
		b.mesh = Assets.mesh("boot_" + tag + ".bin")
		b.material_override = worn
		add_child(b)
		boot.append(b)


func _cloth() -> StandardMaterial3D:
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.085, 0.095, 0.06), Color(0.085, 0.095, 0.06), Color(0.17, 0.18, 0.11),
			Color(0.17, 0.18, 0.11), Color(0.27, 0.245, 0.17), Color(0.27, 0.245, 0.17), Color(0.13, 0.11, 0.075)])
	ramp.offsets = PackedFloat32Array([0.0, 0.36, 0.385, 0.54, 0.565, 0.7, 0.725])
	var n := FastNoiseLite.new()
	n.seed = 21
	n.frequency = 0.011
	n.fractal_octaves = 4
	var camo := NoiseTexture2D.new()
	camo.width = 512
	camo.height = 512
	camo.seamless = true
	camo.noise = n
	camo.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_texture = camo
	m.normal_enabled = true
	m.normal_texture = Assets.tex("denim_fabric_nor_gl.jpg")
	m.normal_scale = 0.8
	m.roughness_texture = Assets.tex("denim_fabric_rough.jpg")
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 2.4
	return m


func _leather() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.035, 0.03, 0.026)
	m.normal_enabled = true
	m.normal_texture = Assets.tex("brown_leather_nor_gl.jpg")
	m.roughness_texture = Assets.tex("brown_leather_rough.jpg")
	m.roughness = 0.8
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 6.0
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	parent.add_child(m)


# Knee position for a leg from hip h to ankle f, bending towards pole.
func _knee(h: Vector3, f: Vector3, pole: Vector3) -> Vector3:
	var v := f - h
	var d := clampf(v.length(), 0.08, THIGH + SHIN - 0.002)
	var n := v.normalized()
	var along := (THIGH * THIGH - SHIN * SHIN + d * d) / (2.0 * d)
	var out := sqrt(maxf(THIGH * THIGH - along * along, 0.0))
	var side := pole - n * pole.dot(n)
	if side.length() < 0.001:
		side = Vector3.FORWARD
	return h + n * along + side.normalized() * out


# Stretches a limb mesh from a to b.
func _span(m: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var y := (b - a).normalized()
	var x := Vector3.RIGHT - y * y.x
	if x.length() < 0.01:
		x = Vector3.BACK
	x = x.normalized()
	m.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) / 2.0)


# state: the view state's name. phase: step cycle from distance covered.
# speed: horizontal speed. sink: landing dip (negative when compressed).
# turn: where the legs point relative to the view, used while sliding.
# eye: camera height, so the chest always ends below it.
func update(dt: float, state: String, phase: float, speed: float, sink: float, turn: float, eye: float) -> void:
	var pose: Array = POSES.get(state, POSES["Idle"])
	rotation.y = lerp_angle(rotation.y, turn, 1.0 - exp(-12.0 * dt))

	# Hips lead; the legs follow at different speeds, the right one a touch quicker.
	hip = hip.lerp(pose[0], 1.0 - exp(-13.0 * dt))
	foot[RIGHT] = foot[RIGHT].lerp(pose[1], 1.0 - exp(-17.0 * dt))
	foot[LEFT] = foot[LEFT].lerp(pose[2], 1.0 - exp(-12.0 * dt))
	stride = lerpf(stride, pose[3], 1.0 - exp(-10.0 * dt))
	lift = lerpf(lift, pose[4], 1.0 - exp(-10.0 * dt))

	var h := hip + Vector3(0, clampf(sink * 2.2, -0.25, 0.05), 0)
	pelvis.position = h
	# The chest ends a little below and behind the eyes.
	var chest := Vector3(0, maxf(eye - 0.4, h.y * 0.6 + 0.1), h.z + 0.2 if eye > 0.6 else h.z * 0.35 + 0.1)
	_span(torso, h + Vector3(0, 0.02, 0.1), chest)
	var moving := clampf(speed / 3.0, 0.0, 1.0)
	var prone := state == "Prone Idle"

	for side in 2:
		var s := 1.0 if side == RIGHT else -1.0
		var cycle := phase + (0.0 if side == RIGHT else PI)
		var target := foot[side]
		if prone:
			# Crawling: the knees work out to the sides in turn.
			target += Vector3(s * maxf(sin(cycle), 0.0) * stride * moving * 2.0, 0, -maxf(sin(cycle), 0.0) * stride * moving * 3.0)
		else:
			target += Vector3(0, maxf(cos(cycle), 0.0) * lift, -sin(cycle) * stride) * moving

		var joint := h + Vector3(s * 0.1, -0.06, 0.0)
		# Keep the ankle within reach of the hip.
		var reach := target - joint
		if reach.length() > THIGH + SHIN - 0.002:
			target = joint + reach.normalized() * (THIGH + SHIN - 0.002)
		var pole := Vector3(s * 0.25, 0.25, -1.0)
		if prone:
			pole = Vector3(s * 1.0, -0.2, -0.2)
		var knee := _knee(joint, target, pole)
		knee.y = maxf(knee.y, 0.08)
		ankle[side] = target

		_span(thigh[side], joint, knee)
		_span(shin[side], knee, target)
		# The foot stays square to the shin: toes up in a slide, down when lying.
		var down := (target - knee).normalized()
		var toes := Vector3.RIGHT.cross(down).normalized()
		boot[side].transform = Transform3D(Basis(Vector3.RIGHT, Vector3.RIGHT.cross(toes), -toes).orthonormalized(), target)
