extends "res://arena.gd"

# "Hafen": the Search and Destroy map. A mid-sized dock yard in three lanes, the
# way the classic shooters lay them out: the attackers start in the south, the
# defenders in the north behind the two bomb sites, A on the left and B on the
# right. Walls of containers stacked two high split the lanes; two gaps in each
# wall let you rotate between them. The building blocks (containers, props,
# ground) are the freight yard's.

const SD_BOUNDS := Rect2(-24.0, -34.0, 48.0, 68.0)
const SITES := [Vector3(-15.0, 0.0, -24.0), Vector3(15.0, 0.0, -24.0)]
const SITE_NAMES := ["A", "B"]
const SITE_RADIUS := 3.2
const ATTACK_SPAWN := Vector3(0.0, 0.05, 30.5)
const DEFEND_SPAWN := Vector3(0.0, 0.05, -30.5)

# [length, x, z, yaw, level, paint, open]
const SD_LAYOUT := [
	# Lane walls, two high. Left: gaps at z 11.5-15.9 and -5.0 to -0.7.
	[L40, -8.6, 22.0, 90, 0, 4, false], [L40, -8.6, 22.0, 90, 1, 0, false],
	[L40, -8.6, 5.4, 90, 0, 1, false], [L40, -8.6, 5.4, 90, 1, 6, false],
	[L20, -8.6, -8.0, 90, 0, 2, false], [L20, -8.6, -8.0, 90, 1, 5, false],
	[L20, -8.6, -14.1, 90, 0, 3, false], [L20, -8.6, -14.1, 90, 1, 7, false],
	# Right: gaps at z 10.0-14.4 and -6.4 to -2.2.
	[L40, 8.6, 20.5, 90, 0, 6, false], [L40, 8.6, 20.5, 90, 1, 2, false],
	[L40, 8.6, 3.9, 90, 0, 0, false], [L40, 8.6, 3.9, 90, 1, 3, false],
	[L20, 8.6, -9.4, 90, 0, 5, false], [L20, 8.6, -9.4, 90, 1, 1, false],
	[L20, 8.6, -15.5, 90, 0, 4, false], [L20, 8.6, -15.5, 90, 1, 6, false],
	# Mid lane: a two-high block in the middle with a way round on both sides.
	[L20, 0.0, 2.0, 0, 0, 1, false], [L20, 0.0, 2.0, 2, 1, 7, false],
	[L20, -3.0, 16.0, 90, 0, 3, true], [L20, 3.5, -9.0, 90, 0, 0, false],
	[L20, 0.0, -20.0, 0, 0, 2, false],
	# Left lane.
	[L20, -16.0, 20.0, 0, 0, 5, false], [L20, -13.0, 8.0, 90, 0, 6, false],
	[L20, -20.0, -2.0, 90, 0, 4, true], [L20, -13.0, -10.0, 0, 0, 1, false],
	# Right lane.
	[L20, 15.0, 18.0, 90, 0, 2, false], [L20, 18.0, 6.0, 0, 0, 3, false],
	[L20, 13.0, -3.0, 90, 0, 7, true], [L20, 19.0, -11.0, 0, 0, 0, false],
	# Site A.
	[L20, -20.0, -22.0, 90, 0, 0, false], [L20, -11.0, -27.0, 0, 0, 5, false], [L20, -11.0, -27.0, -3, 1, 2, false],
	# Site B.
	[L20, 20.0, -26.0, 90, 0, 1, false], [L20, 20.0, -26.0, 92, 1, 4, false], [L20, 11.0, -21.0, 0, 0, 6, false],
]

# Perimeter, two high: [length, x, z, yaw, paint low, paint high]
const SD_WALLS := [
	[L40, -18.3, -35.3, 0, 4, 0], [L40, -6.1, -35.3, 0, 1, 2], [L40, 6.1, -35.3, 0, 0, 3], [L40, 18.3, -35.3, 0, 2, 5],
	[L40, -18.3, 35.3, 0, 2, 5], [L40, -6.1, 35.3, 0, 6, 1], [L40, 6.1, 35.3, 0, 3, 4], [L40, 18.3, 35.3, 0, 5, 0],
	[L40, -25.3, -28.1, 90, 5, 6], [L40, -25.3, -15.9, 90, 0, 1], [L40, -25.3, -3.7, 90, 3, 2], [L40, -25.3, 8.5, 90, 1, 4],
	[L40, -25.3, 20.7, 90, 2, 0], [L20, -25.3, 29.8, 90, 6, 3], [L20, -25.3, 33.9, 90, 4, 5],
	[L40, 25.3, -28.1, 90, 2, 0], [L40, 25.3, -15.9, 90, 1, 5], [L40, 25.3, -3.7, 90, 4, 3], [L40, 25.3, 8.5, 90, 0, 1],
	[L40, 25.3, 20.7, 90, 6, 2], [L20, 25.3, 29.8, 90, 3, 4], [L20, 25.3, 33.9, 90, 5, 6],
]

const SD_PROPS := [
	# Site A.
	["crate", -13.0, -21.0, 8], ["crate_small", -12.2, -20.2, 30], ["barrier", -17.5, -27.5, 0], ["pallets", -21.5, -29.0, 90],
	# Site B.
	["barrels", 13.0, -26.5, 0], ["crate", 17.0, -20.5, -6], ["barrier", 16.0, -29.0, 0], ["pipes", 22.0, -31.0, 0],
	# Mid.
	["crate", 5.0, 10.0, 15], ["barrier", -5.0, -3.0, 80], ["cone", 4.6, 22.0, 0], ["crate_small", -5.5, -14.0, 0],
	["barrels", 5.5, -18.0, 0],
	# Lanes.
	["crate", -19.5, 12.0, 0], ["pallets", -11.0, 1.5, 0], ["barrels", 21.5, 13.0, 0], ["crate", 12.0, 2.5, 20],
	# Spawns.
	["crate", -4.5, 30.0, 0], ["crate", 4.5, 29.5, 10], ["crate", -4.0, -31.0, 0], ["crate_small", 4.0, -31.5, 0],
]


func _ready() -> void:
	_rng.seed = 11
	_container_mat = ShaderMaterial.new()
	_container_mat.shader = load("res://container.gdshader")
	_container_mat.set_shader_parameter("grime", Assets.grime())
	_container_mat.set_shader_parameter("scratch_d", Assets.tex("blue_metal_plate_diffuse.jpg", true))
	_container_mat.set_shader_parameter("scratch_n", Assets.tex("blue_metal_plate_nor_gl.jpg"))
	_container_mat.set_shader_parameter("rust_d", Assets.tex("rusty_metal_02_diffuse.jpg"))
	_container_mat.set_shader_parameter("wood_d", Assets.tex("weathered_planks_diffuse.jpg"))
	_ground()
	for c: Array in SD_LAYOUT:
		_container(c[0], Vector3(c[1], c[4] * H, c[2]), c[3], c[5], c[6], c[4] > 0)
	for w: Array in SD_WALLS:
		_container(w[0], Vector3(w[1], 0, w[2]), w[3], w[4], false, false)
		_container(w[0], Vector3(w[1], H, w[2]), w[3], w[5], false, true)
	for p: Array in SD_PROPS:
		_prop(p[0], Vector3(p[1], 0, p[2]), p[3])
	for i in SITES.size():
		_site_marker(SITES[i], SITE_NAMES[i])
	_far_stacks()


# A painted square on the ground and a big letter on a post.
func _site_marker(at: Vector3, letter: String) -> void:
	var paint := PlaneMesh.new()
	paint.size = Vector2(SITE_RADIUS * 2.0, SITE_RADIUS * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.2, 0.12, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh(paint, mat, Transform3D(Basis.IDENTITY, at + Vector3(0, 0.02, 0)))
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color(0.95, 0.85, 0.2)
	for side in 4:
		var strip := BoxMesh.new()
		strip.size = Vector3(SITE_RADIUS * 2.0, 0.02, 0.12)
		var b := Basis(Vector3.UP, side * PI / 2.0)
		_mesh(strip, edge, Transform3D(b, at + b * Vector3(0, 0.03, SITE_RADIUS)))
	# The bomb case target: a low crate the bomb is set against.
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.7, 0.7)
	_mesh(box, _painted_metal(Color(0.25, 0.27, 0.2)), Transform3D(Basis.IDENTITY, at + Vector3(0, 0.35, 0)))
	_static(_box_shape(Vector3(1.0, 0.7, 0.7)), Transform3D(Basis.IDENTITY, at + Vector3(0, 0.35, 0)))
	var label := Label3D.new()
	label.text = letter
	label.font_size = 220
	label.outline_size = 24
	label.modulate = Color(1.0, 0.85, 0.25)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = at + Vector3(0, 3.6, 0)
	add_child(label)


func _far_stacks() -> void:
	var far := [
		[L40, -12.0, -42.0, 2, 3], [L40, 8.0, -43.0, -3, 4], [L40, -14.0, 42.5, 1, 3], [L40, 10.0, 43.0, -2, 4],
		[L40, -32.0, -18.0, 92, 3], [L40, -33.0, 6.0, 88, 4], [L40, 32.5, -10.0, 91, 4], [L40, 32.0, 14.0, 87, 3],
	]
	for f: Array in far:
		for level in int(f[4]):
			_container(f[0], Vector3(f[1], level * H, f[2]), f[3], _rng.randi_range(0, PAINTS.size() - 1), false, level > 0)


# Footprints for the minimap: [centre, half length, half width, yaw, stacked]
static func map_boxes() -> Array:
	var out := []
	for c: Array in SD_LAYOUT:
		out.append([Vector2(c[1], c[2]), float(c[0]) / 2.0, W / 2.0, deg_to_rad(float(c[3])), int(c[4]) > 0])
	for w: Array in SD_WALLS:
		out.append([Vector2(w[1], w[2]), float(w[0]) / 2.0, W / 2.0, deg_to_rad(float(w[3])), false])
	return out
