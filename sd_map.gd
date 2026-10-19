extends "res://arena.gd"

# The Search and Destroy maps. Both follow the classic layout: attackers start
# in the south, defenders in the north behind the two bomb sites (A left, B
# right), three lanes run between them, and every site has a main entrance
# from its lane and a short one from mid. Defenders reach their sites well
# before the attackers can, and rotate between them on a short path behind;
# the attackers have to cross mid to switch sites.
#
#   "hafen"       a dock yard: walls of containers split the lanes.
#   "raffinerie"  a refinery: concrete walls, a control building between the
#                 sites, an open courtyard at A and a walled yard at B.
#
# `use(id)` picks the map; everything below reads the static vars it sets.
# Besides the geometry each map carries what the bots need to play it on
# their own: the lanes, the ways into each site, spots to hold and watch.

const SITE_NAMES := ["A", "B"]
const SITE_RADIUS := 3.2
const MAP_NAMES := {"hafen": "Hafen", "raffinerie": "Raffinerie"}

static var current := "raffinerie"
static var SD_BOUNDS := Rect2(-24.0, -34.0, 48.0, 68.0)
static var SITES: Array = [Vector3(-15.0, 0.0, -24.0), Vector3(15.0, 0.0, -24.0)]
static var ATTACK_SPAWN := Vector3(0.0, 0.05, 30.5)
static var DEFEND_SPAWN := Vector3(0.0, 0.05, -30.5)
static var NAV: Dictionary = {}

# [length, x, z, yaw, level, paint, open]
const HAFEN_LAYOUT := [
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
const HAFEN_WALLS := [
	[L40, -18.3, -35.3, 0, 4, 0], [L40, -6.1, -35.3, 0, 1, 2], [L40, 6.1, -35.3, 0, 0, 3], [L40, 18.3, -35.3, 0, 2, 5],
	[L40, -18.3, 35.3, 0, 2, 5], [L40, -6.1, 35.3, 0, 6, 1], [L40, 6.1, 35.3, 0, 3, 4], [L40, 18.3, 35.3, 0, 5, 0],
	[L40, -25.3, -28.1, 90, 5, 6], [L40, -25.3, -15.9, 90, 0, 1], [L40, -25.3, -3.7, 90, 3, 2], [L40, -25.3, 8.5, 90, 1, 4],
	[L40, -25.3, 20.7, 90, 2, 0], [L20, -25.3, 29.8, 90, 6, 3], [L20, -25.3, 33.9, 90, 4, 5],
	[L40, 25.3, -28.1, 90, 2, 0], [L40, 25.3, -15.9, 90, 1, 5], [L40, 25.3, -3.7, 90, 4, 3], [L40, 25.3, 8.5, 90, 0, 1],
	[L40, 25.3, 20.7, 90, 6, 2], [L20, 25.3, 29.8, 90, 3, 4], [L20, 25.3, 33.9, 90, 5, 6],
]

const HAFEN_PROPS := [
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
	if current == "raffinerie":
		_build_refinery()
	else:
		_build_harbour()
	for i in SITES.size():
		_site_marker(SITES[i], SITE_NAMES[i])
	if current == "hafen":
		_far_stacks()


func _build_harbour() -> void:
	for c: Array in HAFEN_LAYOUT:
		_container(c[0], Vector3(c[1], c[4] * H, c[2]), c[3], c[5], c[6], c[4] > 0)
	for w: Array in HAFEN_WALLS:
		_container(w[0], Vector3(w[1], 0, w[2]), w[3], w[4], false, false)
		_container(w[0], Vector3(w[1], H, w[2]), w[3], w[5], false, true)
	for p: Array in HAFEN_PROPS:
		_prop(p[0], Vector3(p[1], 0, p[2]), p[3])


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
	if current == "raffinerie":
		for w: Array in REF_WALLS:
			var a := Vector2(w[0], w[1])
			var b := Vector2(w[2], w[3])
			out.append([(a + b) / 2.0, a.distance_to(b) / 2.0, 0.3, -(b - a).angle(), true])
		for k: Array in REF_BLOCKS:
			out.append([Vector2(k[0], k[1]), float(k[2]) / 2.0, float(k[3]) / 2.0, 0.0, true])
		for c: Array in REF_CONTAINERS:
			out.append([Vector2(c[1], c[2]), float(c[0]) / 2.0, W / 2.0, deg_to_rad(float(c[3])), int(c[4]) > 0])
		return out
	for c: Array in HAFEN_LAYOUT:
		out.append([Vector2(c[1], c[2]), float(c[0]) / 2.0, W / 2.0, deg_to_rad(float(c[3])), int(c[4]) > 0])
	for w: Array in HAFEN_WALLS:
		out.append([Vector2(w[1], w[2]), float(w[0]) / 2.0, W / 2.0, deg_to_rad(float(w[3])), false])
	return out


# --- picking a map ---------------------------------------------------------------------

static func use(id: String) -> void:
	current = id if MAP_NAMES.has(id) else "raffinerie"
	if current == "raffinerie":
		SD_BOUNDS = Rect2(-26.0, -36.0, 52.0, 72.0)
		SITES = [Vector3(-18.0, 0.0, -19.0), Vector3(17.0, 0.0, -19.0)]
		ATTACK_SPAWN = Vector3(0.0, 0.05, 31.0)
		DEFEND_SPAWN = Vector3(0.0, 0.05, -32.0)
		NAV = REF_NAV
	else:
		SD_BOUNDS = Rect2(-24.0, -34.0, 48.0, 68.0)
		SITES = [Vector3(-15.0, 0.0, -24.0), Vector3(15.0, 0.0, -24.0)]
		ATTACK_SPAWN = Vector3(0.0, 0.05, 30.5)
		DEFEND_SPAWN = Vector3(0.0, 0.05, -30.5)
		NAV = HAFEN_NAV


static func display_name() -> String:
	return MAP_NAMES.get(current, current)


# --- what the bots know about each map --------------------------------------------------
# All points are (x, z). lanes: the way from the attack spawn up each lane, and
# which site it leads to. entries[site][lane]: from the end of that lane onto the
# site. holds[site]: [spot, where to look] for defenders. forward: aggressive
# defender spots out in the lanes. postplant[site]: attacker spots around a
# planted bomb. lurk: attacker spots off to the side, to catch rotating defenders.

const HAFEN_NAV := {
	"lanes": {
		"left": [Vector2(-11, 26), Vector2(-16, 14), Vector2(-17, 2), Vector2(-17, -6)],
		"mid_a": [Vector2(0, 26), Vector2(-5, 12), Vector2(-6, -6), Vector2(-6, -13)],
		"mid_b": [Vector2(0, 26), Vector2(6, 12), Vector2(6, -4), Vector2(6, -14)],
		"right": [Vector2(11, 26), Vector2(17, 12), Vector2(16, 0), Vector2(14, -7)],
	},
	"lane_site": {"left": 0, "mid_a": 0, "mid_b": 1, "right": 1},
	"entries": [
		{"left": [Vector2(-18, -13), Vector2(-15, -18)], "mid_a": [Vector2(-6, -18), Vector2(-12, -21)]},
		{"right": [Vector2(14, -14), Vector2(16, -18)], "mid_b": [Vector2(6, -18), Vector2(7, -24), Vector2(12, -24)]},
	],
	"holds": [
		[[Vector2(-18, -17), Vector2(-17, -8)], [Vector2(-11, -23), Vector2(-6, -16)], [Vector2(-22, -28), Vector2(-17, -10)], [Vector2(-13, -19), Vector2(-17, -8)]],
		[[Vector2(17, -19), Vector2(14, -8)], [Vector2(13, -25), Vector2(7, -17)], [Vector2(22, -21), Vector2(16, -10)], [Vector2(9, -24), Vector2(7, -15)]],
	],
	"forward": [[Vector2(-6, -15), Vector2(0, 10)], [Vector2(6, -16), Vector2(0, 10)], [Vector2(-17, -12), Vector2(-17, 10)], [Vector2(16, -14), Vector2(16, 10)]],
	"postplant": [
		[[Vector2(-17, -14), Vector2(-15, -30)], [Vector2(-8, -20), Vector2(-15, -30)], [Vector2(-21, -14), Vector2(-15, -24)]],
		[[Vector2(16, -14), Vector2(15, -30)], [Vector2(7, -18), Vector2(15, -24)], [Vector2(21, -15), Vector2(15, -30)]],
	],
	"lurk": [[Vector2(-6, -8), Vector2(-6, -18)], [Vector2(6, -6), Vector2(6, -17)], [Vector2(-17, 0), Vector2(-17, -12)], [Vector2(16, 2), Vector2(16, -12)]],
}

const REF_NAV := {
	"lanes": {
		"left": [Vector2(-12, 22), Vector2(-13, 6), Vector2(-17, -5), Vector2(-17, -8)],
		"mid_a": [Vector2(0, 20), Vector2(-5, 9), Vector2(-5, -3), Vector2(-7.5, -12)],
		"mid_b": [Vector2(0, 20), Vector2(5, 9), Vector2(6, -3), Vector2(7.5, -12)],
		"right": [Vector2(12, 22), Vector2(11, 8), Vector2(15, -5), Vector2(15, -8)],
	},
	"lane_site": {"left": 0, "mid_a": 0, "mid_b": 1, "right": 1},
	"entries": [
		{"left": [Vector2(-17, -12)], "mid_a": [Vector2(-7.5, -20), Vector2(-12, -20)]},
		{"right": [Vector2(15, -12)], "mid_b": [Vector2(7.5, -17), Vector2(12, -17)]},
	],
	"holds": [
		[[Vector2(-23, -17), Vector2(-17, -10)], [Vector2(-13, -24), Vector2(-17, -10)], [Vector2(-12, -15), Vector2(-9, -20)],
			[Vector2(-24, -24), Vector2(-17, -10)], [Vector2(-18, -25), Vector2(-9, -20)]],
		[[Vector2(19, -21), Vector2(15, -10)], [Vector2(12, -24), Vector2(15, -10)], [Vector2(13, -12.5), Vector2(9, -17)],
			[Vector2(24, -23), Vector2(15, -10)], [Vector2(17, -24.5), Vector2(9, -17)]],
	],
	"forward": [[Vector2(-7.5, -14), Vector2(0, 12)], [Vector2(7.5, -14), Vector2(0, 12)], [Vector2(-17, -8), Vector2(-13, 14)],
		[Vector2(15, -8), Vector2(12, 14)], [Vector2(-3, -11), Vector2(0, 20)]],
	"postplant": [
		[[Vector2(-14, -12), Vector2(-18, -28)], [Vector2(-24, -12), Vector2(-18, -28)], [Vector2(-17, -8), Vector2(-18, -19)], [Vector2(-7.5, -17), Vector2(-12, -20)]],
		[[Vector2(13, -12), Vector2(17, -28)], [Vector2(24, -12), Vector2(23, -28)], [Vector2(15, -8), Vector2(17, -19)], [Vector2(7.5, -15), Vector2(12, -17)]],
	],
	"lurk": [[Vector2(-4, -10), Vector2(-7.5, -20)], [Vector2(4, -10), Vector2(7.5, -20)], [Vector2(-12, -4), Vector2(-17, -10)], [Vector2(13, -1), Vector2(15, -10)]],
}


# --- "Raffinerie" ---------------------------------------------------------------------------
# Concrete walls as [x1, z1, x2, z2, height]; solid blocks as [x, z, size x, size z, height];
# containers as in the harbour: [length, x, z, yaw, level, paint, open].

const REF_WALLS := [
	# Outer wall.
	[-26.3, -36.3, 26.3, -36.3, 4.5], [-26.3, 36.3, 26.3, 36.3, 4.5], [-26.3, -36.3, -26.3, 36.3, 4.5], [26.3, -36.3, 26.3, 36.3, 4.5],
	# Lane walls: left (gaps at z 8 to 11 and -6 to -3), right (gaps at z 4 to 7 and -10 to -7).
	[-9, 22, -9, 11, 3.4], [-9, 8, -9, -3, 3.4], [-9, -6, -9, -18, 3.4], [-9, -22, -9, -26, 3.4],
	[9, 22, 9, 7, 3.4], [9, 4, 9, -7, 3.4], [9, -10, 9, -15, 3.4], [9, -19, 9, -26, 3.4],
	# A: the front wall with the main door (x -19 to -15).
	[-26, -10, -19, -10, 3.4], [-15, -10, -9, -10, 3.4],
	# B: front wall with its door (x 13 to 17), and a back wall open on the right.
	[9, -10, 13, -10, 3.4], [17, -10, 26, -10, 3.4], [9, -26, 20, -26, 3.4],
	# Low walls at the spawns.
	[-6, 24, -2, 24, 1.1], [2, 25, 6, 25, 1.1], [-5, -28.5, -1, -28.5, 1.1], [2, -29.5, 6, -29.5, 1.1],
]

const REF_BLOCKS := [
	[0.0, -20.0, 12.0, 12.0, 6.5],      # the control building between the sites
	[22.0, 2.0, 8.0, 8.0, 4.2],         # pump house in the right lane
	[-21.5, 27.0, 6.0, 5.0, 3.0],       # sheds by the attack spawn
	[21.0, 28.0, 6.0, 6.0, 3.0],
]

const REF_CONTAINERS := [
	# Left lane: a long stack splits it in two.
	[L40, -18.0, 5.0, 90, 0, 3, false], [L40, -18.0, 5.0, 90, 1, 6, false],
	[L20, -14.0, 15.5, 0, 0, 1, false],
	# Mid: a stack breaks the long view, an open box to run through.
	[L20, 0.0, 6.0, 0, 0, 2, false], [L20, 0.0, 6.0, 3, 1, 5, false],
	[L20, 2.5, -7.0, 90, 0, 0, true],
	# Right lane.
	[L20, 15.0, 12.0, 90, 0, 4, true], [L20, 12.5, -3.5, 0, 0, 7, false],
	# Site A: a container to plant behind.
	[L20, -22.5, -14.0, 0, 0, 5, false],
	# Site B.
	[L20, 22.0, -15.0, 90, 0, 1, false], [L20, 22.0, -15.0, 92, 1, 3, false],
]

const REF_PROPS := [
	# Site A.
	["crate", -14.0, -16.0, 10], ["crate_small", -16.0, -21.5, 25], ["barrier", -20.0, -23.0, 0], ["pallets", -12.0, -24.5, 90],
	# Site B.
	["crate", 13.0, -22.0, -8], ["barrels", 19.0, -23.0, 0], ["pipes", 15.0, -13.5, 0], ["crate_small", 11.5, -13.0, 15],
	# Mid.
	["barrier", 4.5, 15.0, 0], ["crate", -4.0, -4.0, 20], ["barrels", -6.5, 2.0, 0], ["cone", 6.5, 18.0, 0], ["crate_small", 5.5, -12.5, 0],
	# Lanes.
	["crate", -23.0, 17.0, 0], ["barrels", -12.0, -6.0, 0], ["pallets", -23.5, -5.0, 0],
	["crate", 18.0, 18.0, 12], ["barrels", 24.0, 12.0, 0], ["pipes", 14.0, -7.5, 90],
	# Spawns.
	["crate", -10.0, 30.0, 0], ["crate", 11.0, 31.0, 8], ["crate", -12.0, -32.5, 0], ["barrels", 13.0, -33.0, 0],
]


func _build_refinery() -> void:
	# Weathered concrete, lighter than the floor, with grime down low.
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_texture = Assets.tex("dirty_concrete_diffuse.jpg")
	wall_mat.albedo_color = Color(1.25, 1.22, 1.15)
	wall_mat.normal_enabled = true
	wall_mat.normal_texture = Assets.tex("hangar_concrete_floor_nor_gl.jpg")
	wall_mat.roughness = 0.95
	wall_mat.uv1_triplanar = true
	wall_mat.uv1_scale = Vector3.ONE * 0.25
	var grime := _flat(Color(0.2, 0.19, 0.17), 1.0)
	var trim := _painted_metal(Color(0.32, 0.3, 0.24))
	var stripe := _flat(Color(0.95, 0.75, 0.15), 0.6)
	for w: Array in REF_WALLS:
		var a := Vector3(w[0], 0.0, w[1])
		var b := Vector3(w[2], 0.0, w[3])
		var h: float = w[4]
		var length := a.distance_to(b) + 0.6
		var basis := Basis(Vector3.UP, atan2(-(b - a).z, (b - a).x))
		var centre := (a + b) / 2.0
		var box := BoxMesh.new()
		box.size = Vector3(length, h, 0.6)
		_mesh(box, wall_mat, Transform3D(basis, centre + Vector3(0, h / 2.0, 0)))
		_static(_box_shape(box.size), Transform3D(basis, centre + Vector3(0, h / 2.0, 0)))
		var foot := BoxMesh.new()
		foot.size = Vector3(length + 0.02, 0.35, 0.64)
		_mesh(foot, grime, Transform3D(basis, centre + Vector3(0, 0.175, 0)))
		if h > 2.0:
			# A metal cap on the tall walls.
			var cap := BoxMesh.new()
			cap.size = Vector3(length, 0.12, 0.7)
			_mesh(cap, trim, Transform3D(basis, centre + Vector3(0, h + 0.06, 0)))
	for k: Array in REF_BLOCKS:
		var size := Vector3(k[2], k[4], k[3])
		var at := Vector3(k[0], size.y / 2.0, k[1])
		var box := BoxMesh.new()
		box.size = size
		_mesh(box, wall_mat, Transform3D(Basis.IDENTITY, at))
		_static(_box_shape(size), Transform3D(Basis.IDENTITY, at))
		# A yellow hazard band and a roof edge, so the blocks read as buildings.
		var band := BoxMesh.new()
		band.size = Vector3(size.x + 0.04, 0.25, size.z + 0.04)
		_mesh(band, stripe, Transform3D(Basis.IDENTITY, Vector3(k[0], 1.1, k[1])))
		var roof := BoxMesh.new()
		roof.size = Vector3(size.x + 0.3, 0.2, size.z + 0.3)
		_mesh(roof, trim, Transform3D(Basis.IDENTITY, Vector3(k[0], size.y + 0.1, k[1])))
	# Pipes along the control building and tanks behind the outer wall, for the refinery look.
	var steel := _flat(Color(0.45, 0.46, 0.44), 0.45)
	steel.metallic = 0.7
	for z: float in [-13.8, -26.2]:
		var pipe := CylinderMesh.new()
		pipe.top_radius = 0.25
		pipe.bottom_radius = 0.25
		pipe.height = 12.4
		_mesh(pipe, steel, Transform3D(Basis(Vector3.FORWARD, PI / 2.0), Vector3(0, 5.2, z)))
	for t: Vector3 in [Vector3(-34, 0, -24), Vector3(-35, 0, -8), Vector3(34, 0, -26), Vector3(35, 0, 12), Vector3(-8, 0, -45), Vector3(12, 0, -46)]:
		var tank := CylinderMesh.new()
		tank.top_radius = 4.5
		tank.bottom_radius = 4.5
		tank.height = 11.0
		_mesh(tank, steel, Transform3D(Basis.IDENTITY, t + Vector3(0, 5.5, 0)))
		var top := SphereMesh.new()
		top.radius = 4.5
		top.height = 3.0
		_mesh(top, steel, Transform3D(Basis.IDENTITY, t + Vector3(0, 11.0, 0)))
	for c: Array in REF_CONTAINERS:
		_container(c[0], Vector3(c[1], c[4] * H, c[2]), c[3], c[5], c[6], c[4] > 0)
	for p: Array in REF_PROPS:
		_prop(p[0], Vector3(p[1], 0, p[2]), p[3])
