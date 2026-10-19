extends Node3D

const Player := preload("res://player.gd")
const Target := preload("res://target.gd")
const Arena := preload("res://arena.gd")
const PauseMenu := preload("res://pause_menu.gd")
const MainMenu := preload("res://main_menu.gd")
const Bot := preload("res://bot.gd")
const Minimap := preload("res://minimap.gd")
const Assets := preload("res://assets.gd")
const Hitmarker := preload("res://hitmarker.gd")
const Controls := preload("res://controls.gd")
const Projectile := preload("res://projectile.gd")
const Killcam := preload("res://killcam.gd")
const SdMode := preload("res://sd_mode.gd")
const SdMap := preload("res://sd_map.gd")
const Icons := preload("res://icons.gd")
const Loading := preload("res://loading.gd")
const TouchControls := preload("res://touch_controls.gd")
const EQUIP_ICONS := {"wurfmesser": "knife", "granate": "grenade", "blend": "flash", "betaeubung": "stun"}
const RATTE_KILLS := 3
const RATTE_SECONDS := 20.0
const LAN_PORT := 24565
# Places to start and to come back to life in a LAN game.
const LAN_SPAWNS := [Vector3(-17.0, 0.05, -8.7), Vector3(2.1, 0.05, 1.9), Vector3(6.6, 0.05, -8.7),
		Vector3(14.6, 0.05, -15.2), Vector3(16.9, 0.05, 14.6)]
const WIN_SCORE := 10

# Set before reloading the scene to start straight into a mode ("arena" or "range").
static var next_mode := ""

const EXPOSURE := 0.8
const SUN_ENERGY := 2.5

const GRID_SHADER := """
shader_type spatial;
uniform vec3 base : source_color = vec3(0.45);
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 uv = wp.xy;
	if (abs(wn.y) > 0.5) { uv = wp.xz; } else if (abs(wn.x) > 0.5) { uv = wp.zy; }
	vec2 g = abs(fract(uv) - 0.5);
	float line = step(0.485, max(g.x, g.y));
	ALBEDO = mix(base, base * 0.55, line);
	ROUGHNESS = 0.9;
}
"""

var player: Player
var grid: Shader
var score := 0

var info: Label
var ammo_label: Label
var tac_bar: ProgressBar
var cross: Array[ColorRect] = []

# Self-test state (started with: -- --selftest --out=<folder>).
var selftest := false
var out_dir := ""
var t := 0.0
var res := {}
var shots_done := {}
var teleported := {}

# Other start modes: --testrange (the old movement range), --greybox (arena as plain
# blocks), --arenatest (walkability and sight-line report plus screenshots).
var test_range := false
var greybox := false
var arena_test := false
var duel_test := false
var sd_test := false          # --sdtest: a Search and Destroy match with bots, photographed
var killcam_test := false     # --killcamtest: get killed in the 1v1 and photograph the killcam
var flash_test := false       # --flashtest: photographs the sniper's muzzle flash frame by frame

# Modes: "arena" (free play against targets), "range" (training ground), "duel" (1v1 against the bot).
var mode := "arena"
var bot: Bot
var killcam: Killcam
var sd: SdMode                 # Search and Destroy, when that is the mode
var score_you := 0
var score_bot := 0
var hurt_rect: ColorRect
var banner: Label
var match_over := false
var minimap: Minimap
var streak_label: Label
var health_label: Label
var health_bar: ProgressBar
var reserve_label: Label
var icon_vp: SubViewport
var icon_cam: Camera3D
var icon_parts: Array[MeshInstance3D] = []
var icon_rect: TextureRect
var shown_weapon := ""
var scope_vp: SubViewport
var scope_cam: Camera3D
var scope_mat: ShaderMaterial
var hitmarker: Hitmarker
var fps_label: Label
var equip_label: Label
var flash_rect: ColorRect
var streak := 0
var ratte_ready := false
var ratte_until := 0

# LAN: the other player's figure, and how often our own position goes out.
var puppet: Bot
var net_send := 0.0
var lan_test := ""          # "host" or "join" in the automated LAN check
var arena_started := false
var hud: CanvasLayer
var loading: Loading
var ready_done := false        # _ready builds the game in steps behind the loading screen
var music: AudioStreamPlayer
var _music_tween: Tween
var post_mat: ShaderMaterial
var lethal_icon: TextureRect
var lethal_count: Label
var tactical_icon: TextureRect
var tactical_count: Label
var hp_fill: StyleBoxFlat
var menu: PauseMenu
var main_menu: MainMenu
var menu_shots_started := false
var menu_shots_done := false
var weapon_label: Label
var scope: ColorRect
var weapon_shots_done := false
var weapon_shots_started := false


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--selftest":
			selftest = true
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a == "--testrange":
			test_range = true
		elif a == "--greybox":
			greybox = true
		elif a == "--arenatest":
			arena_test = true
		elif a == "--sdtest":
			sd_test = true
			next_mode = "snd"
		elif a == "--killcamtest":
			killcam_test = true
			next_mode = "duel"
		elif a == "--flashtest":
			flash_test = true
			arena_test = true
			test_range = true
		elif a == "--dueltest":
			duel_test = true
		elif a.begins_with("--sdmap="):
			SdMap.current = a.substr(8)
		elif a.begins_with("--startmode="):
			next_mode = a.substr(12)    # start straight into a mode, the normal way (for debugging)
		elif a == "--lantest-host":
			lan_test = "host"
		elif a == "--lantest-join":
			lan_test = "join"
	if lan_test != "":
		next_mode = "lan"
		var test_peer := ENetMultiplayerPeer.new()
		if lan_test == "host":
			test_peer.create_server(LAN_PORT, 1)
		else:
			test_peer.create_client("127.0.0.1", LAN_PORT)
		multiplayer.multiplayer_peer = test_peer
	var start_now := next_mode != ""
	if start_now:
		mode = next_mode
	if test_range:
		mode = "range"
	if duel_test:
		mode = "duel"
	test_range = mode == "range"
	next_mode = ""
	var testing := selftest or arena_test or duel_test or killcam_test or sd_test or flash_test or lan_test != ""
	if not testing:
		loading = Loading.new()
		add_child(loading)
		get_tree().paused = true      # nothing moves (or shoots) behind the loading screen
		_start_music()
		loading.set_progress(0.05, "Starte ...")
		await get_tree().process_frame
		await get_tree().process_frame
	grid = Shader.new()
	grid.code = GRID_SHADER
	# No frame-rate cap from the monitor's refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# One typeface for HUD and menus (Rajdhani, Open Font License, see fonts/OFL.txt).
	var font := FontFile.new()
	font.data = FileAccess.get_file_as_bytes("res://fonts/Rajdhani-SemiBold.ttf")
	if not font.data.is_empty():
		var look := Theme.new()
		look.default_font = font
		get_window().theme = look
	_build_environment()
	await _step(0.18, "Licht, Himmel und Atmosphäre ...")

	player = Player.new()
	if selftest or test_range:
		_build_test_range()
		add_child(player)
		player.global_position = Vector3(0, 0.05, 50)
	elif mode == "snd":
		SdMap.use(SdMap.current)
		var map := SdMap.new()
		add_child(map)
		add_child(player)
		player.global_position = SdMap.ATTACK_SPAWN
	else:
		var arena := Arena.new()
		arena.greybox = greybox
		arena.with_targets = mode == "arena"
		add_child(arena)
		arena.target_hit.connect(func() -> void:
			score += 1
			hitmarker.mark(false, false))
		add_child(player)
		player.global_position = Arena.SPAWN
		player.yaw = deg_to_rad(Arena.SPAWN_YAW)
	player.ai_enabled = selftest or arena_test or duel_test or killcam_test or sd_test or lan_test != ""
	await _step(0.4, "Karte und Spieler ...")
	_build_post()
	_build_hud()
	_build_duel_hud()
	if mode == "duel":
		bot = Bot.new()
		bot.target = player
		add_child(bot)
		bot.global_position = Vector3(14.0, 0.05, 15.0)
		bot.died.connect(_on_bot_died)
		bot.bot_name = "Bot"
		killcam = Killcam.new()
		add_child(killcam)
		killcam.watch_player(player)
		killcam.add_bot(bot)
		bot.was_hit.connect(func(head: bool, killed: bool) -> void: hitmarker.mark(killed, head))
		player.died.connect(_on_player_died)
	if mode == "lan":
		_lan_start()
	if mode == "snd":
		minimap.boxes = SdMap.map_boxes()
		sd = SdMode.new()
		add_child(sd)
		sd.setup.call_deferred(self)

	await _step(0.55, "Oberfläche ...")
	if TouchControls.wanted() and not testing:
		var touch := TouchControls.new()
		touch.player = player
		touch.main = self
		add_child(touch)
	# Pause menu: Esc opens it; its sliders drive the player's view settings.
	menu = PauseMenu.new()
	menu.enabled = not selftest and not arena_test and not duel_test and not killcam_test and not sd_test and lan_test == ""
	menu.fov_changed.connect(player.set_fov)
	menu.weapon_fov_changed.connect(player.set_weapon_fov)
	menu.sensitivity_changed.connect(func(v: float) -> void: player.sens_scale = v)
	menu.loadout_changed.connect(player.set_loadout)
	menu.perks_changed.connect(player.set_perks)
	menu.attachments_changed.connect(player.set_attachments)
	menu.equipment_changed.connect(player.set_equipment)
	player.threw.connect(_on_threw)
	menu.skin_changed.connect(func(i: int) -> void: player.vmodel.weapon_mat.set_shader_parameter("skin", i))
	add_child(menu)

	# Main menu: shown first, and again from the pause menu.
	main_menu = MainMenu.new()
	main_menu.store = menu
	add_child(main_menu)
	main_menu.play.connect(_on_play)
	# The camera that circles the map behind the main menu.
	var backdrop := Camera3D.new()
	backdrop.cull_mask = 1
	backdrop.fov = 55.0
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(backdrop)
	main_menu.backdrop = backdrop
	main_menu.game_cam = player.cam
	main_menu.orbit_centre = Vector3(0, 0, 30) if (selftest or test_range) else Vector3.ZERO
	main_menu.lan_host.connect(_lan_host)
	main_menu.lan_join.connect(_lan_join)
	menu.main_menu_requested.connect(_open_main_menu)
	if not selftest and not arena_test and not duel_test and not killcam_test and not sd_test and lan_test == "":
		if start_now:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			_open_main_menu()
	menu.music_volume_changed.connect(func(_v: float) -> void: _music(main_menu.is_open))
	if loading != null:
		await _preload_assets()
		await loading.finish()
		get_tree().paused = main_menu.is_open
		if start_now:
			_music(false)
	ready_done = true


func _open_main_menu() -> void:
	if mode == "lan":
		_lan_leave()
	menu.blocked = true
	hud.visible = false
	main_menu.open()
	_music(true)


# The main menu's play buttons end up here.
func _on_play(mode: String) -> void:
	if mode != self.mode:
		menu._save()
		next_mode = mode
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	main_menu.close()
	_music(false)
	menu.blocked = false
	menu._save()
	hud.visible = true
	score = 0
	score_you = 0
	score_bot = 0
	streak = 0
	ratte_ready = false
	ratte_until = 0
	match_over = false
	banner.visible = false
	player.revive()
	if bot != null:
		bot.respawn()
	player.velocity = Vector3.ZERO
	if mode == "lan":
		player.global_position = LAN_SPAWNS[0 if multiplayer.is_server() else 4]
	elif test_range:
		player.global_position = Vector3(0, 0.05, 50)
		player.yaw = 0.0
	else:
		player.global_position = Arena.SPAWN
		player.yaw = deg_to_rad(Arena.SPAWN_YAW)
	player.pitch = 0.0


# A last pass over the finished picture: sharpening, lens fringing, vignette, grain.
func _build_post() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://post.gdshader")
	rect.material = mat
	post_mat = mat
	layer.add_child(rect)


func _block(size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := ShaderMaterial.new()
	mat.shader = grid
	mat.set_shader_parameter("base", color)
	box.material = mat
	mesh.mesh = box
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	body.position = pos
	body.rotation = rot
	add_child(body)
	return body


# A box standing on the ground: pos is the centre of its base.
func _crate(size: Vector3, base: Vector3, color: Color) -> void:
	_block(size, base + Vector3.UP * size.y / 2.0, color)


# Finds the brightest spot of the sky panorama and returns the direction to it.
func _sun_direction(pano: Image) -> Vector3:
	var small: Image = pano.duplicate()
	small.convert(Image.FORMAT_RGBF)
	small.resize(256, 128, Image.INTERPOLATE_BILINEAR)
	var best := -1.0
	var at := Vector2i.ZERO
	for y in 128:
		for x in 256:
			var c := small.get_pixel(x, y)
			var l := c.r + c.g + c.b
			if l > best:
				best = l
				at = Vector2i(x, y)
	var theta := (at.x + 0.5) / 256.0 * TAU - PI
	var phi := (at.y + 0.5) / 128.0 * PI
	return Vector3(sin(phi) * sin(theta), cos(phi), -sin(phi) * cos(theta))


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var pano := Assets.image("res://textures/sky_2k.hdr")
	if pano != null:
		var pano_mat := PanoramaSkyMaterial.new()
		pano_mat.panorama = ImageTexture.create_from_image(pano)
		sky.sky_material = pano_mat
	else:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.3, 0.45, 0.7)
		sky_mat.sky_horizon_color = Color(0.7, 0.75, 0.8)
		sky_mat.ground_horizon_color = Color(0.7, 0.75, 0.8)
		sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.background_energy_multiplier = 1.0
	# The sky photo contains the sun, so its ambient share is kept low to avoid counting it twice.
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Film-like response: no clipped highlights, slightly muted colour.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = EXPOSURE
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.92
	# Indirect light and contact shading.
	# Light bouncing between the containers, and sky light that no longer reaches into closed corners.
	env.sdfgi_enabled = false
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_energy = 1.35
	env.sdfgi_min_cell_size = 0.2
	env.ssil_enabled = false
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Sunlight in the air: shafts of light between the containers, haze in the distance.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.9, 0.9, 0.88)
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_ambient_inject = 0.3
	# Thin haze that takes its colour from the sky, and leaves the sky itself clear.
	env.fog_enabled = true
	env.fog_density = 0.0012
	env.fog_light_color = Color(0.7, 0.75, 0.8)
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	if pano != null:
		# Put the sun light where the sun sits in the sky photo, so shadows agree with it.
		var to_sun := _sun_direction(pano)
		if to_sun.y > 0.15:
			sun.look_at_from_position(Vector3.ZERO, -to_sun)
	sun.shadow_enabled = true
	sun.light_energy = SUN_ENERGY
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_angular_distance = 0.7
	sun.light_volumetric_fog_energy = 1.4
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.3
	add_child(sun)


func _build_test_range() -> void:
	var ground := Color(0.42, 0.44, 0.42)
	var wall := Color(0.55, 0.52, 0.46)
	var crate := Color(0.6, 0.45, 0.25)
	var blue := Color(0.3, 0.42, 0.58)

	_block(Vector3(140, 1, 140), Vector3(0, -0.5, 0), ground)
	_crate(Vector3(140, 5, 1), Vector3(0, 0, 70), wall)
	_crate(Vector3(140, 5, 1), Vector3(0, 0, -70), wall)
	_crate(Vector3(1, 5, 140), Vector3(70, 0, 0), wall)
	_crate(Vector3(1, 5, 140), Vector3(-70, 0, 0), wall)

	# Sprint lane down the middle with cover on both sides.
	for i in 6:
		var z := 44.0 - i * 9.0
		_crate(Vector3(2, 1.2, 2), Vector3(-6, 0, z), crate)
		_crate(Vector3(1.2, 2.4, 3), Vector3(6, 0, z - 4.0), crate)
	_crate(Vector3(8, 1.0, 0.4), Vector3(0, 0, 5), wall)       # low wall to vault
	_crate(Vector3(10, 3.2, 0.4), Vector3(-9, 0, 5), wall)
	_crate(Vector3(10, 3.2, 0.4), Vector3(9, 0, 5), wall)

	# Mantle course: four ledges from waist height to full reach.
	var heights := [0.6, 1.0, 1.5, 2.0]
	for i in heights.size():
		_crate(Vector3(4, heights[i], 3), Vector3(12, 0, 40.0 - i * 6.0), blue)
	_crate(Vector3(4, 3.0, 3), Vector3(12, 0, 14), blue)       # too high on purpose

	# Ramp up to a platform you can jump or slide off.
	_block(Vector3(4, 0.3, 10), Vector3(24, 1.35, 30), wall, Vector3(deg_to_rad(17.0), 0, 0))
	_crate(Vector3(8, 2.8, 8), Vector3(24, 0, 21.3), wall)
	_crate(Vector3(3, 1.4, 3), Vector3(31, 0, 21), crate)

	# A small building shell with a doorway and a window to climb through.
	_crate(Vector3(12, 3.2, 0.4), Vector3(-30, 0, 10), wall)
	_crate(Vector3(0.4, 3.2, 12), Vector3(-36, 0, 16), wall)
	_crate(Vector3(0.4, 3.2, 12), Vector3(-24, 0, 16), wall)
	_crate(Vector3(4, 3.2, 0.4), Vector3(-34, 0, 22), wall)
	_crate(Vector3(4, 3.2, 0.4), Vector3(-26, 0, 22), wall)
	_crate(Vector3(4, 1.0, 0.4), Vector3(-30, 0, 22), wall)    # window sill

	# Shooting range.
	for i in 5:
		var tg := Target.new()
		add_child(tg)
		tg.global_position = Vector3(-19.0 + i * 2.0, 0, 25)
		tg.was_hit.connect(func() -> void: score += 1)
	_crate(Vector3(12, 3.5, 0.5), Vector3(-15, 0, 22), wall)


func _hud_label(layer: Node, size: int, pos: Vector2, box: Vector2, right := false) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = box
	if right:
		l.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		l.position = pos
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	layer.add_child(l)
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hud = layer

	# Top left: minimap, then score, tactical sprint and the streak.
	minimap = Minimap.new()
	minimap.position = Vector2(24, 24)
	minimap.player = player
	minimap.visible = mode != "range" and not selftest
	layer.add_child(minimap)
	var top := 236.0 if mode != "range" else 20.0
	info = _hud_label(layer, 26, Vector2(24, top), Vector2(400, 90))
	tac_bar = ProgressBar.new()
	tac_bar.position = Vector2(24, top + (40.0 if mode != "range" else 100.0))
	tac_bar.size = Vector2(200, 8)
	tac_bar.max_value = Player.TAC_MAX
	tac_bar.show_percentage = false
	layer.add_child(tac_bar)
	streak_label = _hud_label(layer, 20, Vector2(24, top + 54.0), Vector2(400, 30))

	# Soft dark shades in the two bottom corners, so the numbers always read.
	for right: bool in [false, true]:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(1.0 if right else 0.0, 1.0)
		gt.fill_to = Vector2(0.45 if right else 0.55, 0.15)
		var shade := TextureRect.new()
		shade.texture = gt
		shade.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if right else Control.PRESET_BOTTOM_LEFT)
		shade.size = Vector2(620, 300)
		shade.position = Vector2(-620 if right else 0, -300)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(shade)

	# Bottom left: health, with a cross icon and a segmented bar.
	var heart := Icons.rect("heart", 36, Color(0.95, 0.96, 0.98))
	heart.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	heart.position = Vector2(24, -88)
	layer.add_child(heart)
	health_label = Label.new()
	health_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_label.position = Vector2(68, -98)
	health_label.add_theme_font_size_override("font_size", 52)
	health_label.add_theme_color_override("font_outline_color", Color.BLACK)
	health_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(health_label)
	health_bar = ProgressBar.new()
	health_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_bar.position = Vector2(28, -40)
	health_bar.size = Vector2(260, 10)
	health_bar.show_percentage = false
	hp_fill = StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.92, 0.94, 0.96)
	hp_fill.skew = Vector2(0.3, 0)
	health_bar.add_theme_stylebox_override("fill", hp_fill)
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(1, 1, 1, 0.12)
	hp_bg.skew = Vector2(0.3, 0)
	health_bar.add_theme_stylebox_override("background", hp_bg)
	layer.add_child(health_bar)
	# Cuts across the bar every 10 points.
	for k in range(1, 13):
		var cut := ColorRect.new()
		cut.color = Color(0, 0, 0, 0.55)
		cut.size = Vector2(2, 10)
		cut.position = Vector2(260.0 * k / 13.0, 0)
		cut.mouse_filter = Control.MOUSE_FILTER_IGNORE
		health_bar.add_child(cut)

	# Bottom right: weapon picture, its name, rounds in the magazine and in reserve.
	_build_icon()
	icon_rect = TextureRect.new()
	icon_rect.texture = icon_vp.get_texture()
	icon_rect.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	icon_rect.offset_left = -348.0
	icon_rect.offset_right = -28.0
	icon_rect.offset_top = -240.0
	icon_rect.offset_bottom = -140.0
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.modulate = Color(1, 1, 1, 0.9)
	layer.add_child(icon_rect)
	weapon_label = _hud_label(layer, 24, Vector2(-428, -136), Vector2(400, 30), true)
	ammo_label = _hud_label(layer, 64, Vector2(-330, -108), Vector2(200, 70), true)
	reserve_label = _hud_label(layer, 30, Vector2(-124, -74), Vector2(96, 36), true)
	reserve_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	reserve_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.8))

	# Sniper scope: a second camera renders the magnified view, and it is shown
	# exactly where the scope's rear lens is on screen. The rifle, its scope and
	# mount stay visible around it and sway with you.
	scope_vp = SubViewport.new()
	scope_vp.size = Vector2i(768, 768)
	scope_vp.msaa_3d = Viewport.MSAA_2X
	scope_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(scope_vp)
	scope_cam = Camera3D.new()
	scope_cam.cull_mask = 1
	scope_cam.near = 0.2
	scope_vp.add_child(scope_cam)
	scope = ColorRect.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scope_shader := Shader.new()
	scope_shader.code = """
shader_type canvas_item;
uniform sampler2D pip : filter_linear, repeat_disable;
uniform vec2 centre = vec2(0.5);
uniform float radius = 0.3;
uniform vec2 flick = vec2(0.0);
void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 d = (UV - centre) * vec2(aspect, 1.0);
	float r = length(d);
	float inside = 1.0 - smoothstep(radius * 0.97, radius, r);
	vec3 c = texture(pip, d / (radius * 2.0) + 0.5).rgb;
		// Only a fast swing of the rifle throws a shadow across the lens.
	c *= 1.0 - 0.95 * smoothstep(radius * 0.72, radius * 1.02, length(d + flick * radius));
	c *= 1.0 - 0.3 * smoothstep(radius * 0.55, radius, r);
	float line = max(step(abs(d.x), 0.0008), step(abs(d.y), 0.0008));
	float thick = max(step(abs(d.x), 0.003) * step(radius * 0.42, abs(d.y)), step(abs(d.y), 0.003) * step(radius * 0.42, abs(d.x)));
	c = mix(c, vec3(0.0), max(line, thick));
	COLOR = vec4(c, inside);
}
"""
	scope_mat = ShaderMaterial.new()
	scope_mat.shader = scope_shader
	scope_mat.set_shader_parameter("pip", scope_vp.get_texture())
	scope.material = scope_mat
	scope.visible = false
	layer.add_child(scope)
	layer.move_child(scope, 0)

	var center := Control.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(center)
	hitmarker = Hitmarker.new()
	center.add_child(hitmarker)
	equip_label = _hud_label(layer, 20, Vector2(-428, -168), Vector2(400, 28), true)
	equip_label.visible = false
	var kit := HBoxContainer.new()
	kit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	kit.position = Vector2(-430, -142)
	kit.size = Vector2(300, 40)
	kit.alignment = BoxContainer.ALIGNMENT_END
	kit.add_theme_constant_override("separation", 6)
	kit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(kit)
	lethal_icon = Icons.rect("grenade", 36)
	kit.add_child(lethal_icon)
	lethal_count = _hud_label(kit, 22, Vector2.ZERO, Vector2(28, 30))
	kit.add_child(Control.new())
	tactical_icon = Icons.rect("flash", 36)
	kit.add_child(tactical_icon)
	tactical_count = _hud_label(kit, 22, Vector2.ZERO, Vector2(28, 30))
	var bullet := Icons.rect("bullet", 38, Color(1, 1, 1, 0.9))
	bullet.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bullet.position = Vector2(-246, -90)
	layer.add_child(bullet)
	equip_label.add_theme_color_override("font_color", Color(0.82, 0.85, 0.88))
	# White-out from a flashbang, over everything else.
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 1, 1, 0)
	layer.add_child(flash_rect)
	fps_label = Label.new()
	fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_label.position = Vector2(-110, 14)
	fps_label.size = Vector2(96, 24)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", 18)
	fps_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8, 0.8))
	layer.add_child(fps_label)
	for i in 4:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.9)
		r.size = Vector2(2, 10) if i < 2 else Vector2(10, 2)
		center.add_child(r)
		cross.append(r)


# A small side-on picture of the weapon in hand, rendered once per weapon.
func _build_icon() -> void:
	icon_vp = SubViewport.new()
	icon_vp.size = Vector2i(640, 200)
	icon_vp.transparent_bg = true
	icon_vp.own_world_3d = true
	icon_vp.msaa_3d = Viewport.MSAA_4X
	icon_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(icon_vp)
	icon_cam = Camera3D.new()
	icon_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	icon_vp.add_child(icon_cam)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.93, 0.95, 0.97)
	for i in 10:
		var m := MeshInstance3D.new()
		m.material_override = white
		icon_vp.add_child(m)
		icon_parts.append(m)


func _update_icon() -> void:
	var w: Dictionary = player.w
	icon_parts[0].mesh = Assets.mesh(w["mesh"])
	icon_parts[1].mesh = Assets.mesh(w["mag"]) if w["mag"] != "" else null
	icon_parts[2].mesh = Assets.mesh(w["barrel"]) if w.has("barrel") else null
	icon_parts[3].mesh = Assets.mesh(w["optic"]) if w.has("optic") else null
	var parts: Array = w.get("parts", [])
	for i in range(4, icon_parts.size()):
		var k := i - 4
		icon_parts[i].mesh = Assets.mesh(parts[k][0]) if k < parts.size() else null
		icon_parts[i].position = parts[k][1] if k < parts.size() else Vector3.ZERO
	var box: AABB = icon_parts[0].mesh.get_aabb()
	for part: MeshInstance3D in icon_parts.slice(1):
		if part.mesh != null:
			box = box.merge(Transform3D(Basis.IDENTITY, part.position) * part.mesh.get_aabb())
	var mid := box.get_center()
	icon_cam.size = maxf(box.size.y, box.size.z / 3.2) * 1.12
	# Seen from the weapon's left side, muzzle pointing left.
	icon_cam.look_at_from_position(mid + Vector3(-3, 0, 0), mid, Vector3.UP)
	icon_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _unhandled_input(event: InputEvent) -> void:
	if not ready_done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F11:
			var full := get_window().mode == Window.MODE_FULLSCREEN
			get_window().mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not selftest and not arena_test and not duel_test and lan_test == "" and not menu.is_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# The streak: three kills without dying earn the Ratte, which marks the enemy
# on the minimap for a while.
func use_ratte() -> void:
	if not ratte_ready:
		return
	ratte_ready = false
	streak = 0
	ratte_until = Time.get_ticks_msec() + int(RATTE_SECONDS * 1000.0)


func _process(_dt: float) -> void:
	if not ready_done:
		return
	_motion_blur()
	var now := Time.get_ticks_msec()
	if Input.is_action_just_pressed("mv_ratte"):
		use_ratte()
	fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	equip_label.text = "%s ×%d    %s ×%d" % [Projectile.ALL[player.lethal]["name"], player.lethal_left,
			Projectile.ALL[player.tactical]["name"], player.tactical_left]
	flash_rect.color = Color(1, 1, 1, clampf(player.flash_t / 1.3, 0.0, 1.0)) if player.flash_t > 0.0 \
			else Color(0.5, 0.65, 1.0, 0.12 * clampf(player.stun_t, 0.0, 1.0))
	var foe: Bot = bot if mode == "duel" else puppet
	if mode == "duel" or mode == "lan":
		info.text = "DU  %d : %d  %s" % [score_you, score_bot, "BOT" if mode == "duel" else "GEGNER"]
		var left := (ratte_until - now) / 1000.0
		if left > 0.0:
			streak_label.text = "RATTE AKTIV  %d s" % int(ceil(left))
		elif ratte_ready:
			streak_label.text = "RATTE BEREIT  ·  Taste 3"
		else:
			streak_label.text = "RATTE  %d / %d" % [streak, RATTE_KILLS]
		streak_label.add_theme_color_override("font_color", Color(0.95, 0.62, 0.16) if (ratte_ready or left > 0.0) else Color(0.8, 0.82, 0.84))
		if foe == null:
			streak_label.text = "Warte auf Mitspieler ..."
		minimap.enemy = foe
		minimap.reveal = foe != null and foe.alive and (left > 0.0 or now - foe.last_shot_ms < 1500)
		minimap.sweep = fmod(left, 2.0) / 2.0 if left > 0.0 else 0.0
	elif mode == "arena":
		info.text = "Treffer: %d" % score
		streak_label.text = ""
	elif mode == "snd":
		info.text = ""
		streak_label.text = ""
		if sd != null:
			minimap.dots = sd.minimap_dots()
	else:
		info.text = "%s\n%.1f m/s\nTreffer: %d" % [player.state_name(), player.speed_h(), score]
		streak_label.text = ""
	var full := player.max_health()
	hurt_rect.color.a = clampf((full - player.health) / full, 0.0, 1.0) * 0.42
	hp_fill.bg_color = Color(0.92, 0.94, 0.96) if player.health > full * 0.35 else Color(0.95, 0.28, 0.22)
	lethal_icon.texture = Icons.tex(EQUIP_ICONS.get(player.lethal, "grenade"), 56)
	tactical_icon.texture = Icons.tex(EQUIP_ICONS.get(player.tactical, "flash"), 56)
	lethal_count.text = "×%d" % player.lethal_left
	tactical_count.text = "×%d" % player.tactical_left
	lethal_icon.modulate = Color(1, 1, 1, 1.0 if player.lethal_left > 0 else 0.3)
	tactical_icon.modulate = Color(1, 1, 1, 1.0 if player.tactical_left > 0 else 0.3)
	health_label.text = "%d" % int(ceil(player.health))
	health_bar.max_value = full
	health_bar.value = player.health
	tac_bar.max_value = player.tac_max()
	tac_bar.value = player.tac_energy
	var mag_size: int = player.mag_cap(player.w)
	if mag_size == 0:
		ammo_label.text = ""
		reserve_label.text = ""
	else:
		ammo_label.text = "%d" % player.ammo
		ammo_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.25) if player.ammo <= mag_size / 5 else Color.WHITE)
		reserve_label.text = "| %d" % player.reserve
	weapon_label.text = "%s" % player.w["name"]
	var look := str(player.w["mesh"]) + str(player.w.get("barrel", "")) + str(player.w.get("optic", "")) + str(player.w.get("plain_hold", false)) \
			+ str(player.w.get("parts", [])) + str(player.w["mag"])
	if shown_weapon != look:
		shown_weapon = look
		_update_icon()
	scope.visible = player.scoped
	scope_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if player.scoped else SubViewport.UPDATE_DISABLED
	if player.scoped:
		scope_cam.global_transform = player.cam.global_transform
		if player.w.has("scope_mag"):
			# Magnification N: the scope shows 1/N of the view's angle.
			scope_cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(player.base_fov) * 0.5) / float(player.w["scope_mag"])))
		else:
			scope_cam.fov = player.base_fov * float(player.w.get("scope_zoom", 0.15))
		var lens: Array = player.scope_circle()
		scope_mat.set_shader_parameter("centre", lens[0])
		scope_mat.set_shader_parameter("radius", lens[1])
		# Shadow in the lens: nothing for calm aiming, growing with the speed of the swing.
		var speed := player.turn.length()
		var amount := smoothstep(2.2, 7.0, speed) * 0.85
		var dir := Vector2(player.turn.x, -player.turn.y).normalized() if speed > 0.01 else Vector2.ZERO
		scope_mat.set_shader_parameter("flick", dir * amount)
	var gap := lerpf(8.0, 26.0, clampf(player.speed_h() / 8.0, 0.0, 1.0)) + player.kick * 200.0
	var show: bool = player.ads_amt < 0.5 and player.sprint_amt < 0.5 and not player.w["melee"]
	var offs := [Vector2(-1, -gap - 10), Vector2(-1, gap), Vector2(-gap - 10, -1), Vector2(gap, -1)]
	for i in 4:
		cross[i].visible = show
		cross[i].position = offs[i]


func _physics_process(dt: float) -> void:
	if not ready_done:
		return
	if mode == "lan" and puppet != null:
		# Tell the other player where we are, thirty times a second.
		net_send -= dt
		if net_send <= 0.0:
			net_send = 1.0 / 30.0
			net_state.rpc(player.global_position, player.yaw)
	if lan_test != "":
		if not arena_started:
			arena_started = true
			_run_lan_test()
	elif selftest:
		_run_selftest(dt)
	elif duel_test:
		t += dt
		# Keep looking at the bot, so the picture shows it once it comes round a corner.
		var to_bot := bot.global_position + Vector3.UP * 1.2 - player.cam.global_position
		player.yaw = atan2(-to_bot.x, -to_bot.z)
		player.pitch = atan2(to_bot.y, Vector2(to_bot.x, to_bot.z).length())
		if not arena_started:
			arena_started = true
			_run_duel_test()
	elif sd_test:
		t += dt
		if t > 1.0 and not arena_started:
			arena_started = true
			_run_sd_test()
	elif killcam_test:
		t += dt
		if player.process_mode != Node.PROCESS_MODE_DISABLED:
			var to_bot := bot.global_position + Vector3.UP * 1.2 - player.cam.global_position
			player.yaw = atan2(-to_bot.x, -to_bot.z)
			player.pitch = atan2(to_bot.y, Vector2(to_bot.x, to_bot.z).length())
		if t > 1.0 and not arena_started:
			arena_started = true
			_run_killcam_test()
	elif flash_test:
		t += dt
		if t > 1.0 and not arena_started:
			arena_started = true
			_run_flash_test()
	elif arena_test:
		t += dt
		if t > 0.6 and not arena_started:
			arena_started = true
			_run_arena_test()


func _between(a: float, b: float) -> bool:
	return t >= a and t < b


func _teleport(key: String, pos: Vector3) -> void:
	if teleported.has(key):
		return
	teleported[key] = true
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.pitch = 0.0


func _shot(key: String) -> void:
	if shots_done.has(key) or out_dir == "":
		return
	shots_done[key] = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(key + ".png"))


func _track(key: String, value: float) -> void:
	res[key] = maxf(float(res.get(key, 0.0)), value)


func _run_selftest(dt: float) -> void:
	t += dt
	var k := {}
	var v: float = player.speed_h()

	# Phase 1: walk, sprint, tactical sprint, slide, slide cancel.
	k["fwd"] = _between(0.5, 6.0) or _between(6.7, 8.0)
	k["sprint"] = _between(2.0, 3.5) or _between(3.55, 3.6) or _between(3.65, 5.6)
	k["crouch"] = _between(5.0, 5.1)
	k["jump"] = _between(5.35, 5.45) or _between(6.8, 6.9)
	if _between(1.5, 2.0):
		_track("walk_speed", v)
	if _between(3.0, 3.5):
		_track("sprint_speed", v)
	if _between(4.3, 5.0):
		_track("tac_speed", v)
		if player.tac:
			res["tac_active"] = true
	if _between(4.9, 4.95):
		res["tac_energy_before_slide"] = player.tac_energy
	if _between(5.0, 5.35):
		_track("slide_speed", v)
	if _between(5.5, 5.55):
		res["tac_energy_after_cancel"] = player.tac_energy
	if t > 1.2:
		_shot("0_hip")
	if t > 4.6:
		_shot("1_tac_sprint")
	if t > 5.2:
		_shot("2_slide")

	# Phase 2: mantle the 1.5 m ledge.
	if t > 6.5:
		_teleport("mantle", Vector3(12, 0.02, 30.4))
	if t > 7.02:
		_shot("3_mantle")
	if _between(7.8, 7.9):
		res["mantle_end_height"] = player.global_position.y

	# Phase 3: aim and fire at a target.
	if t > 8.0:
		_teleport("range", Vector3(-15, 0.02, 40))
	k["ads"] = _between(8.2, 9.4)
	k["fire"] = _between(8.6, 9.2)
	if t > 8.9:
		_shot("4_aim_fire")
	k["inspect"] = _between(9.6, 10.9)
	if t > 10.05:
		_shot("5a_inspect_reach")
	if _between(10.7, 10.75):
		res["inspect_progress"] = snappedf(player.inspect_p, 0.01)
	# Phase 4: break off a reload with the trigger, then let one finish.
	k["reload"] = _between(11.0, 11.1) or _between(11.9, 12.0)
	k["fire"] = k["fire"] or _between(11.5, 11.53)
	if _between(11.45, 11.5):
		res["reloading_before_cancel"] = player.reloading > 0.0
	if _between(11.7, 11.75):
		res["reload_cancelled"] = player.reloading <= 0.0 and player.ammo < Player.MAG
	if t > 12.5:
		_shot("5b_reload_out")
	if t > 13.45:
		_shot("5c_reload_in")
	if _between(14.1, 14.2):
		res["ammo_after_reload"] = player.ammo

	# Phase 5: every stance change on its own - crouch, crouch walk, prone, stand, jump.
	k["crouch"] = k["crouch"] or _between(14.4, 14.5) or _between(15.9, 16.0)
	k["fwd"] = k["fwd"] or _between(15.1, 15.7) or _between(20.4, 21.0)
	k["prone"] = _between(16.4, 16.5) or _between(18.0, 18.1)
	k["jump"] = k["jump"] or _between(19.2, 19.3)
	if _between(14.95, 15.0):
		res["eye_crouch"] = snappedf(player.head.position.y, 0.01)
	if t > 15.5:
		_shot("6_crouch_walk")
	if _between(17.7, 17.75):
		res["eye_prone"] = snappedf(player.head.position.y, 0.01)
		res["legs_prone_behind"] = snappedf(player.legs.ankle[0].z, 0.01)
	if t > 17.8:
		_shot("7_prone")
	if _between(19.0, 19.05):
		res["eye_stand"] = snappedf(player.head.position.y, 0.01)
	if t > 10.6:
		_shot("5_inspect")
	if not weapon_shots_started:
		player.ai = k

	# Phase 6: look down at the legs while walking, sprinting, sliding, jumping and crouching.
	if t > 21.4 and not weapon_shots_started:
		_teleport("legs", Vector3(0, 0.02, 50))
		player.pitch = deg_to_rad(-40.0 if _between(23.6, 24.6) else -62.0)
	k["fwd"] = k["fwd"] or _between(21.7, 24.5)
	k["sprint"] = k["sprint"] or _between(22.7, 24.5)
	k["crouch"] = k["crouch"] or _between(23.6, 23.7) or _between(25.9, 26.0)
	k["jump"] = k["jump"] or _between(25.1, 25.2)
	if t > 22.4:
		_shot("8_legs_walk")
	if t > 23.4:
		_shot("9_legs_sprint")
	if t > 24.0:
		_shot("10_legs_slide")
	if _between(24.0, 24.05):
		res["legs_slide_reach"] = snappedf(-player.legs.ankle[1].z, 0.01)
		res["legs_slide_folded"] = snappedf(-player.legs.ankle[0].z, 0.01)
	if t > 25.32:
		_shot("11_legs_jump")
	if _between(25.32, 25.37):
		res["legs_jump_lift"] = snappedf(player.legs.ankle[0].y, 0.01)
	if t > 26.6:
		_shot("12_legs_crouch")

	# Phase 7: the pause menu's sliders must reach the player.
	if t > 27.0 and not teleported.has("menu"):
		teleported["menu"] = true
		menu.open(false)
		menu.set_value("fov", 110.0)
		menu.set_value("weapon_zoom", 10.0)
		menu.set_value("sensitivity", 1.5)
	if _between(27.3, 27.35):
		res["menu_fov"] = player.fov_h
		res["menu_camera_fov"] = snappedf(player.cam.fov, 0.1)
		res["menu_weapon_fov"] = player.vm_fov
		res["menu_sensitivity"] = player.sens_scale
	if t > 27.4:
		_shot("13_pause_menu")
	if t > 27.7 and not teleported.has("menu_closed"):
		teleported["menu_closed"] = true
		menu.set_value("fov", 100.0)
		menu.set_value("weapon_zoom", 0.0)
		menu.set_value("sensitivity", 1.0)
		menu.close()
	# Phase 8: the class system - equip every weapon once and photograph it.
	if t > 28.0 and not weapon_shots_started:
		weapon_shots_started = true
		_weapon_shots()
	# Phase 9: perks reach the player, and the main menu's pages are photographed.
	if weapon_shots_done and not menu_shots_started:
		menu_shots_started = true
		_menu_shots()
	if menu_shots_done:
		res["slides"] = player.slide_count
		res["slide_cancels"] = player.slide_cancel_count
		res["mantles"] = player.mantle_count
		res["shots_fired"] = player.shots_fired
		res["target_hits"] = score
		# Every view state must have been entered at least once during the run.
		var missing: Array[String] = []
		for state_name: String in Player.POV_NAMES:
			if not player.pov_seen.has(state_name):
				missing.append(state_name)
		res["states_seen"] = player.pov_seen.size()
		res["states_missing"] = missing
		var ok: bool = absf(res["walk_speed"] - Player.WALK_SPEED) < 0.2 \
				and absf(res["sprint_speed"] - Player.SPRINT_SPEED) < 0.2 \
				and absf(res["tac_speed"] - Player.TAC_SPEED) < 0.2 \
				and res.get("tac_active", false) \
				and res["slide_speed"] > Player.TAC_SPEED \
				and res["slides"] == 2 and res["slide_cancels"] == 1 \
				and res["tac_energy_after_cancel"] > res["tac_energy_before_slide"] + 0.5 \
				and res["mantles"] == 1 and absf(res["mantle_end_height"] - 1.5) < 0.1 \
				and res["shots_fired"] >= 5 and res["target_hits"] >= 1 \
				and res.get("reloading_before_cancel", false) and res.get("reload_cancelled", false) \
				and player.reload_cancels == 1 and res.get("ammo_after_reload", 0) == Player.MAG \
				and absf(res.get("eye_crouch", 0.0) - Player.EYE_CROUCH) < 0.03 \
				and absf(res.get("eye_prone", 0.0) - Player.EYE_PRONE) < 0.03 \
				and absf(res.get("eye_stand", 0.0) - Player.EYE_STAND) < 0.03 \
				and missing.is_empty() \
				and res.get("menu_fov", 0.0) == 110.0 and absf(res.get("menu_camera_fov", 0.0) - 77.6) < 1.0 \
				and res.get("menu_weapon_fov", 0.0) == 60.0 and res.get("menu_sensitivity", 0.0) == 1.5 \
				and player.shells_ejected == player.shots_fired \
				and res.get("class_ok", false) and res.get("perks_ok", false) \
				and res.get("legs_slide_reach", 0.0) > 0.45 and res.get("legs_slide_folded", 1.0) < 0.3 \
				and res.get("legs_jump_lift", 0.0) > 0.2 and res.get("legs_prone_behind", 0.0) > 1.4
		res["passed"] = ok
		print("SELFTEST ", JSON.stringify(res))
		if out_dir != "":
			var f := FileAccess.open(out_dir.path_join("selftest.json"), FileAccess.WRITE)
			f.store_string(JSON.stringify(res, "  "))
			f.close()
		get_tree().quit(0 if ok else 1)
		selftest = false


# ---------------------------------------------------------------------------
# Arena check: is every lane walkable, how long is the longest sight line,
# and what does it look like from the player's eyes.

const ARENA_VIEWS := [
	["arena_1_lane", Vector3(-17.0, 0.05, -8.7), -90.0, 0.0],
	["arena_2_yard", Vector3(2.1, 0.05, 1.9), 180.0, 0.0],
	["arena_3_tunnel", Vector3(6.6, 0.05, -8.7), -90.0, 0.0],
	["arena_4_corner", Vector3(14.6, 0.05, -15.2), 150.0, -3.0],
	["arena_5_doors", Vector3(-0.9, 0.05, -8.7), 90.0, 5.0],
	["arena_6_south", Vector3(16.9, 0.05, 14.6), 45.0, 0.0],
	["arena_7_overhead", Vector3(-2.4, 0.05, -8.4), 0.0, 14.0],
	["arena_8_ground", Vector3(15.6, 0.05, -4.6), 200.0, -28.0],
]


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _save_view(key: String) -> void:
	if out_dir == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(key + ".png"))


func _flood(free: PackedByteArray, nx: int, nz: int, start: int) -> int:
	var seen := PackedByteArray()
	seen.resize(free.size())
	var stack := PackedInt32Array([start])
	var count := 0
	while not stack.is_empty():
		var i := stack[-1]
		stack.remove_at(stack.size() - 1)
		if seen[i] == 1 or free[i] == 0:
			continue
		seen[i] = 1
		count += 1
		var x := i % nx
		var z := i / nx
		if x > 0:
			stack.append(i - 1)
		if x < nx - 1:
			stack.append(i + 1)
		if z > 0:
			stack.append(i - nx)
		if z < nz - 1:
			stack.append(i + nx)
	free.clear()
	free.append_array(seen)
	return count


func _scan(radius: float, cell: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.exclude = [player.get_rid()]
	var b := Arena.BOUNDS
	var nx := int(b.size.x / cell)
	var nz := int(b.size.y / cell)
	var free := PackedByteArray()
	free.resize(nx * nz)
	var open := 0
	for iz in nz:
		for ix in nx:
			q.transform = Transform3D(Basis.IDENTITY, Vector3(b.position.x + (ix + 0.5) * cell, 0.98, b.position.y + (iz + 0.5) * cell))
			if space.intersect_shape(q, 1).is_empty():
				free[iz * nx + ix] = 1
				open += 1
	var sx := int((Arena.SPAWN.x - b.position.x) / cell)
	var sz := int((Arena.SPAWN.z - b.position.y) / cell)
	var reached := _flood(free, nx, nz, sz * nx + sx)
	return {"open": open, "reached": reached, "grid": free, "nx": nx, "nz": nz, "cell": cell}


# Cells where a body of this radius fits at all, reachable or not.
func _scan_open(radius: float, cell: float) -> PackedByteArray:
	var space := get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.exclude = [player.get_rid()]
	var b := Arena.BOUNDS
	var nx := int(b.size.x / cell)
	var nz := int(b.size.y / cell)
	var free := PackedByteArray()
	free.resize(nx * nz)
	for iz in nz:
		for ix in nx:
			q.transform = Transform3D(Basis.IDENTITY, Vector3(b.position.x + (ix + 0.5) * cell, 0.98, b.position.y + (iz + 0.5) * cell))
			if space.intersect_shape(q, 1).is_empty():
				free[iz * nx + ix] = 1
	return free


func _run_arena_test() -> void:
	# Walkability with the player's own size, then with a fatter body to find tight spots.
	var thin := _scan(0.35, 0.25)
	var wide := _scan(0.6, 0.25)
	var cell: float = thin["cell"]
	res["walkable_m2"] = snappedf(thin["reached"] * cell * cell, 0.1)
	res["cut_off_m2"] = snappedf((thin["open"] - thin["reached"]) * cell * cell, 0.1)
	res["comfortable_share"] = snappedf(float(wide["reached"]) / maxf(float(thin["reached"]), 1.0), 0.01)
	res["arena_m2"] = snappedf(Arena.BOUNDS.size.x * Arena.BOUNDS.size.y, 0.1)
	if out_dir != "":
		# Map of the result: green = roomy, orange = only a tight squeeze leads here, red = cut off.
		var tg: PackedByteArray = thin["grid"]
		var wg: PackedByteArray = wide["grid"]
		var w: int = thin["nx"]
		var img := Image.create(w, thin["nz"], false, Image.FORMAT_RGB8)
		var blocked := _scan_open(0.35, 0.25)
		for i in tg.size():
			var c := Color(0.1, 0.1, 0.1)
			if wg[i] == 1:
				c = Color(0.35, 0.75, 0.4)
			elif tg[i] == 1:
				c = Color(0.95, 0.6, 0.15)
			elif blocked[i] == 1:
				c = Color(0.9, 0.15, 0.15)
			img.set_pixel(i % w, i / w, c)
		img.resize(w * 5, int(thin["nz"]) * 5, Image.INTERPOLATE_NEAREST)
		img.save_png(out_dir.path_join("arena_walkable.png"))

	# Longest clear line at eye height from any standing spot.
	var space := get_world_3d().direct_space_state
	var grid: PackedByteArray = thin["grid"]
	var nx: int = thin["nx"]
	var nz: int = thin["nz"]
	var longest := 0.0
	var from_at := Vector3.ZERO
	var to_at := Vector3.ZERO
	var per_spot: Array[float] = []
	for iz in range(0, nz, 4):
		for ix in range(0, nx, 4):
			if grid[iz * nx + ix] == 0:
				continue
			var eye := Vector3(Arena.BOUNDS.position.x + (ix + 0.5) * cell, 1.6, Arena.BOUNDS.position.y + (iz + 0.5) * cell)
			var best := 0.0
			for k in 96:
				var dir := Vector3(cos(TAU * k / 96.0), 0, sin(TAU * k / 96.0))
				var rq := PhysicsRayQueryParameters3D.create(eye, eye + dir * 80.0)
				rq.exclude = [player.get_rid()]
				var hit := space.intersect_ray(rq)
				var d := 80.0 if hit.is_empty() else eye.distance_to(hit["position"])
				best = maxf(best, d)
				if d > longest:
					longest = d
					from_at = eye
					to_at = eye + dir * d
			per_spot.append(best)
	per_spot.sort()
	res["longest_sight_m"] = snappedf(longest, 0.1)
	res["longest_sight_from"] = [snappedf(from_at.x, 0.1), snappedf(from_at.z, 0.1)]
	res["longest_sight_to"] = [snappedf(to_at.x, 0.1), snappedf(to_at.z, 0.1)]
	res["median_sight_m"] = snappedf(per_spot[per_spot.size() / 2], 0.1)

	# Pictures: plan view first, then from the player's eyes.
	hud.visible = false
	player.vm.visible = false
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 46.0
	top.far = 200.0
	add_child(top)
	top.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 70, 0))
	top.make_current()
	await _frames(6)
	await _save_view("arena_0_plan")
	player.cam.make_current()
	top.queue_free()
	player.vm.visible = true
	for view: Array in ARENA_VIEWS:
		player.global_position = view[1]
		player.velocity = Vector3.ZERO
		player.yaw = deg_to_rad(view[2])
		player.pitch = deg_to_rad(view[3])
		await _frames(30)
		await _save_view(view[0])
		res[view[0] + "_height"] = snappedf(player.global_position.y, 0.01)

	var start := Time.get_ticks_usec()
	await _frames(120)
	res["frames_per_second"] = snappedf(120.0 / ((Time.get_ticks_usec() - start) / 1000000.0), 0.1)
	# The same without weapon and arms, to see what they cost.
	player.vm.visible = false
	await _frames(20)
	start = Time.get_ticks_usec()
	await _frames(120)
	res["frames_per_second_no_weapon"] = snappedf(120.0 / ((Time.get_ticks_usec() - start) / 1000000.0), 0.1)
	player.vm.visible = true
	print("ARENATEST ", JSON.stringify(res))
	if out_dir != "":
		var f := FileAccess.open(out_dir.path_join("arenatest.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(res, "  "))
		f.close()
	get_tree().quit(0)


# Class system check: each loadout must arrive at the player, swapping must
# change the weapon in hand, and every weapon is shown held and aimed.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _weapon_shots() -> void:
	var ok := true
	player.pitch = 0.0
	player._set_stance(Player.Stance.STAND)
	for pair: Array in [["ar", "pistol"], ["sniper", "knife"], ["smg", "pistol"]]:
		menu.set_weapon("primary", pair[0])
		menu.set_weapon("secondary", pair[1])
		ok = ok and player.loadout[0] == pair[0] and player.loadout[1] == pair[1] and player.slot == 0
		for index in 2:
			if index == 1:
				player.swap(1)
				await _wait(0.9)
				ok = ok and player.slot == 1
			var id: String = player.loadout[player.slot]
			if pair[0] == "smg":
				continue
			await _wait(0.5)
			await _save_view("w_" + id)
			if id == "sniper":
				menu.set_sniper_grip(false)
				await _wait(0.4)
				await _save_view("w_sniper_nogrip")
				ok = ok and not player.sniper_grip
				menu.set_sniper_grip(true)
				await _wait(0.3)
				var cycles_before := player.bolt_cycles
				var shells_before := player.shells_ejected
				player.ai = {"fire": true}
				await _wait(0.05)
				player.ai = {}
				await _wait(0.6)
				await _save_view("w_sniper_bolt")
				await _wait(1.0)
				res["bolt_cycled"] = player.bolt_cycles == cycles_before + 1 and player.shells_ejected == shells_before + 1
				ok = ok and res["bolt_cycled"]
				res["sniper_sounds"] = player._sfx.has("shot") and player._sfx.has("bolt") and player._sfx.has("shell") \
						and (player._sfx["shot"] as AudioStreamPlayer).stream != null
				ok = ok and res["sniper_sounds"]
				# Silent shot: fire, then the knife key at once; then the swap key puts the knife away.
				player.set_equipment("wurfmesser", "blend")
				var silent_before := player.silent_shots
				await _wait(player.fire_cd + 0.05)
				cycles_before = player.bolt_cycles
				player.ai = {"fire": true}
				await _wait(0.04)
				player.ai = {"lethal": true}
				await _wait(0.3)
				await _save_view("w_sniper_silent")
				var shot_player: AudioStreamPlayer = player._sfx["shot"]
				res["silent_shot"] = player.silent_shots == silent_before + 1 and player.bolt_cycles == cycles_before + 1 \
						and player.bolt_t == 0.0 and not shot_player.playing and player.lethal_t > 0.0
				var throws_before := player.throws
				player.ai = {"lethal": true, "swap": true}
				await _wait(0.4)
				player.ai = {}
				await _wait(0.2)
				res["knife_cancelled"] = player.throws == throws_before and player.lethal_t == 0.0 \
						and player.lethal_left == 1 and player.slot == index and player.swap_t <= 0.0
				ok = ok and res["silent_shot"] and res["knife_cancelled"]
				# Class editor: every barrel and optic, seen from the hip and through the sight.
				var damage_std := float(player.w["damage"])
				menu.set_attachment("sniper", "lauf", "lang")
				await _wait(0.4)
				await _save_view("w_sniper_long")
				res["long_barrel_damage"] = float(player.w["damage"]) > damage_std
				menu.set_attachment("sniper", "lauf", "schalldaempfer")
				menu.set_attachment("sniper", "visier", "kompakt")
				await _wait(0.4)
				await _save_view("w_sniper_sup_compact")
				player.ai = {"ads": true}
				await _wait(0.8)
				await _save_view("w_sniper_compact_aim")
				res["compact_scoped"] = player.scoped and is_equal_approx(float(player.w["scope_mag"]), 4.0)
				player.ai = {}
				menu.set_attachment("sniper", "visier", "rotpunkt")
				await _wait(0.5)
				player.ai = {"ads": true}
				await _wait(0.8)
				await _save_view("w_sniper_dot_aim")
				res["dot_not_scoped"] = not player.scoped and player.vmodel.dot_part.visible
				player.ai = {}
				menu.set_attachment("sniper", "visier", "zielfernrohr")
				menu.set_attachment("sniper", "lauf", "standard")
				await _wait(0.5)
				ok = ok and res["long_barrel_damage"] and res["compact_scoped"] and res["dot_not_scoped"]
				# Auto reload: empty the magazine, it reloads without a key press.
				var reloads_before := player.auto_reloads
				player.ammo = 0
				await _wait(0.3)
				res["auto_reload"] = player.auto_reloads == reloads_before + 1 and player.reloading > 0.0
				await _wait(3.2)
				ok = ok and res["auto_reload"] and player.ammo == player.mag_cap(player.w)
			if not player.w["melee"]:
				player.ai = {"ads": true}
				await _wait(0.8)
				await _save_view("w_" + id + "_aim")
				if id == "sniper":
					ok = ok and player.scoped
				player.ai = {}
				await _wait(0.5)
			else:
				player.ai = {"fire": true}
				await _wait(0.14)
				await _save_view("w_knife_slash")
				player.ai = {}
				await _wait(0.5)
	res["class_ok"] = ok
	res["weapon_swaps"] = player.swaps
	weapon_shots_done = true


func _menu_shots() -> void:
	var ok := true
	menu.set_perk(0, "dauerlaeufer")
	menu.set_perk(1, "flinke_finger")
	menu.set_perk(2, "erweitertes_magazin")
	ok = ok and is_equal_approx(player.tac_max(), Player.TAC_MAX * 2.0)
	ok = ok and is_equal_approx(player.reload_time(), float(player.w["reload"]) * 0.7)
	var base := int(player.w["mag_size"])
	var bigger := int(ceil(base * 1.3))
	ok = ok and player.mag_cap(player.w) == bigger and player.ammo == bigger
	menu.set_perk(0, "gleiter")
	menu.set_perk(2, "ruhige_hand")
	ok = ok and is_equal_approx(player.slide_time(), Player.SLIDE_TIME * 1.25) and player.mag_cap(player.w) == base
	main_menu.open(false)
	for i in 7:
		main_menu.show_tab(i)
		await _wait(0.25)
		await _save_view("menu_%d" % i)
	main_menu.show_tab(1)
	main_menu.open_editor()
	await _wait(0.4)
	await _save_view("menu_editor")
	res["editor_open"] = main_menu.editor.visible
	main_menu.close_editor()
	main_menu.close()
	for i in 3:
		menu.set_perk(i, "")
	ok = ok and is_equal_approx(player.tac_max(), Player.TAC_MAX)
	res["perks_ok"] = ok
	menu_shots_done = true


# --- 1v1 against the bot -----------------------------------------------------

func _build_duel_hud() -> void:
	# Red wash over the picture that grows as health drops.
	hurt_rect = ColorRect.new()
	hurt_rect.color = Color(0.6, 0.0, 0.0, 0.0)
	hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hurt_rect)
	hud.move_child(hurt_rect, 0)
	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-400, 150)
	banner.size = Vector2(800, 80)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 56)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 10)
	banner.visible = false
	hud.add_child(banner)


func _flash_banner(text: String, seconds: float) -> void:
	banner.text = text
	banner.visible = true
	await get_tree().create_timer(seconds).timeout
	if not match_over:
		banner.visible = false


func _on_bot_died() -> void:
	if match_over:
		return
	score_you += 1
	streak += 1
	if streak >= RATTE_KILLS:
		ratte_ready = true
	if score_you >= WIN_SCORE:
		if killcam != null and not duel_test:
			# The last kill of the match, from your own eyes.
			match_over = true
			hud.visible = false
			killcam.start(-1, true)
			await killcam.finished
			hud.visible = true
			match_over = false
		_end_match("SIEG")
	else:
		_flash_banner("BOT AUSGESCHALTET", 1.2)


func _on_player_died() -> void:
	if match_over:
		return
	score_bot += 1
	streak = 0
	if score_bot >= WIN_SCORE:
		if mode == "lan":
			net_died.rpc()
		elif killcam != null and not duel_test:
			match_over = true
			hud.visible = false
			killcam.start(0, true)
			await killcam.finished
			hud.visible = true
			match_over = false
		_end_match("NIEDERLAGE")
		return
	_flash_banner("DU WURDEST AUSGESCHALTET", 1.5)
	if mode == "lan":
		net_died.rpc()
		player.global_position = _lan_spawn()
		player.revive()
		net_respawned.rpc()
		return
	if killcam != null and not duel_test:
		# Death camera, then the kill again from the killer's side, then back in.
		hud.visible = false
		killcam.start(0)
		await killcam.finished
		hud.visible = true
	player.global_position = bot.far_point(bot.global_position)
	player.revive()


func _end_match(text: String) -> void:
	match_over = true
	banner.text = "%s   %d : %d" % [text, score_you, score_bot]
	banner.visible = true
	player.revive()
	await get_tree().create_timer(3.5).timeout
	if match_over and not duel_test and lan_test == "":
		_open_main_menu()


# Automated check of the 1v1 mode: the bot must find the player, hurt them,
# take damage, die and come back.
func _run_duel_test() -> void:
	await _wait(1.0)
	var waited := 0.0
	while not bot.has_los and waited < 40.0:
		await _wait(0.1)
		waited += 0.1
	res["bot_found_player"] = bot.has_los
	res["bot_search_seconds"] = snappedf(waited, 0.1)
	res["bot_travelled_m"] = snappedf(bot.travelled, 0.1)
	await _wait(0.3)
	await _save_view("duel_bot")
	waited = 0.0
	while player.health >= player.max_health() and score_bot == 0 and waited < 15.0:
		await _wait(0.1)
		waited += 0.1
	res["bot_hurt_player"] = player.health < player.max_health() or score_bot > 0
	res["bot_shots"] = bot.shots
	# Body shots, then a headshot must do more, then the streak.
	var before := bot.health
	bot.hit(20.0, bot.global_position + Vector3.UP * 1.0)
	res["marker_body"] = hitmarker.last_kind
	var body_damage := before - bot.health
	bot.hit(20.0, bot.global_position + Vector3.UP * 1.65)
	res["headshot_bonus"] = snappedf((before - body_damage - bot.health) / body_damage, 0.01)
	res["marker_head"] = hitmarker.last_kind
	bot.hit(200.0)
	res["marker_kill"] = hitmarker.last_kind
	res["bot_died"] = not bot.alive and score_you == 1
	await _wait(3.0)
	res["bot_respawned"] = bot.alive and bot.health == Bot.MAX_HEALTH
	for i in 2:
		bot.hit(500.0)
		await _wait(2.6)
	res["ratte_ready"] = ratte_ready and score_you == 3
	use_ratte()
	await _wait(0.4)
	res["ratte_shows_bot"] = minimap.reveal
	res["player_max_health"] = player.max_health()
	# Equipment: a grenade at the bot's feet, a flash at the player's eyes, a stun on the bot, a knife into the bot.
	await _wait(2.5)
	menu.set_equipment("wurfmesser", "blend")
	var kills := score_you
	# Pin the bot down first, or it walks out of the blast during the fuse.
	bot.blind(4.0)
	bot.stun(4.0)
	spawn_throw("granate", bot.global_position + Vector3(0.3, 0.3, 0.0), Vector3.ZERO, player, true)
	await _wait(2.8)
	res["grenade_killed_bot"] = score_you == kills + 1
	await _wait(2.6)
	spawn_throw("blend", player.cam.global_position - player.cam.global_transform.basis.z * 2.5, Vector3.ZERO, player, true)
	await _wait(1.6)
	res["flash_blinded_player"] = player.flash_t > 0.5
	bot.blind(2.5)
	spawn_throw("betaeubung", bot.global_position + Vector3(0.6, 0.4, 0.0), Vector3.ZERO, player, true)
	await _wait(1.6)
	res["stun_hit_bot"] = bot.stun_t > 0.5
	kills = score_you
	var to_bot := (bot.global_position + Vector3.UP * 1.2) - (bot.global_position + Vector3(2.0, 1.2, 0.0))
	spawn_throw("wurfmesser", bot.global_position + Vector3(2.0, 1.2, 0.0), to_bot.normalized() * 30.0, player, true)
	await _wait(0.6)
	res["knife_killed_bot"] = score_you == kills + 1
	var throws := player.throws
	player.flash_t = 0.0
	player.ai = {"lethal": true}
	await _wait(0.6)
	await _save_view("throw_knife_held")
	res["knife_held_not_thrown"] = player.throws == throws and player.lethal_t >= 0.29 and player.vmodel.right_items[player.lethal].visible
	player.ai = {}
	await _wait(0.5)
	res["knife_thrown_on_release"] = player.throws == throws + 1
	player.ai = {"tactical": true}
	await _wait(0.16)
	await _save_view("throw_tactical")
	res["tactical_left_hand"] = player.vmodel.left_throw > 0.0
	await _wait(0.1)
	await _save_view("throw_tactical_out")
	player.ai = {}
	await _wait(0.5)
	res["tactical_thrown"] = player.throws == throws + 2
	menu.set_equipment("granate", "blend")
	await _wait(0.2)
	player.ai = {"lethal": true}
	await _wait(0.5)
	await _save_view("throw_nade_held")
	player.ai = {}
	await _wait(0.075)
	await _save_view("throw_nade_cocked")
	await _wait(0.06)
	await _save_view("throw_nade_out")
	await _wait(0.6)
	res["grenade_thrown"] = player.throws == throws + 3
	await _save_view("duel_hud")
	var ok: bool = res["bot_found_player"] and res["bot_hurt_player"] and res["bot_died"] and res["bot_respawned"] \
			and res["headshot_bonus"] == 1.5 and res["ratte_ready"] and res["ratte_shows_bot"] \
			and res["knife_held_not_thrown"] and res["knife_thrown_on_release"] and res["tactical_left_hand"] and res["tactical_thrown"] and res["grenade_thrown"] \
			and res["grenade_killed_bot"] and res["flash_blinded_player"] and res["stun_hit_bot"] and res["knife_killed_bot"] \
			and res["marker_body"] == "hit" and res["marker_head"] == "hit+head" and res["marker_kill"] == "kill"
	res["passed"] = ok
	print("DUELTEST ", JSON.stringify(res))
	get_tree().quit(0 if ok else 1)


# --- LAN: one against one over the local network -----------------------------------
# The host opens a server; the other player connects to the host's address.
# Each game moves its own player and only tells the other where it is, when it
# fires, and when it dies. A hit is decided by the shooter and sent to the victim.

func _lan_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(LAN_PORT, 1) != OK:
		main_menu.lan_status("Hosten fehlgeschlagen. Läuft schon ein Spiel auf diesem PC?")
		return
	multiplayer.multiplayer_peer = peer
	_on_play("lan")


func _lan_join(address: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, LAN_PORT) != OK:
		main_menu.lan_status("Diese Adresse ist ungültig.")
		return
	multiplayer.multiplayer_peer = peer
	_on_play("lan")


func _lan_start() -> void:
	player.died.connect(_on_player_died)
	player.shot_fired.connect(func(to: Vector3) -> void:
		if puppet != null:
			net_shot.rpc(to))
	player.global_position = LAN_SPAWNS[0 if multiplayer.is_server() else 4]
	multiplayer.peer_connected.connect(_lan_peer_joined)
	multiplayer.peer_disconnected.connect(_lan_peer_left)
	multiplayer.connection_failed.connect(_lan_lost.bind("VERBINDUNG FEHLGESCHLAGEN"))
	multiplayer.server_disconnected.connect(_lan_lost.bind("HOST HAT DAS SPIEL BEENDET"))
	# The connection may already be up by the time the map has loaded.
	for id: int in multiplayer.get_peers():
		_lan_peer_joined(id)


func _lan_peer_joined(_id: int) -> void:
	if puppet != null:
		return
	puppet = Bot.new()
	puppet.remote = true
	add_child(puppet)
	puppet.net_pos = LAN_SPAWNS[4 if multiplayer.is_server() else 0]
	puppet.global_position = puppet.net_pos
	puppet.remote_hit.connect(func(damage: float) -> void: net_hurt.rpc(damage, player.global_position))
	puppet.was_hit.connect(func(head: bool, killed: bool) -> void: hitmarker.mark(killed, head))
	_flash_banner("MITSPIELER VERBUNDEN", 1.5)


func _lan_peer_left(_id: int) -> void:
	if puppet != null:
		puppet.queue_free()
		puppet = null
	_flash_banner("MITSPIELER HAT VERLASSEN", 2.0)


func _lan_lost(text: String) -> void:
	if lan_test != "":
		return
	_open_main_menu()
	main_menu.show_tab(4)
	main_menu.lan_status(text.capitalize())


func _lan_leave() -> void:
	for sig: Signal in [multiplayer.peer_connected, multiplayer.peer_disconnected, multiplayer.connection_failed, multiplayer.server_disconnected]:
		for c: Dictionary in sig.get_connections():
			sig.disconnect(c["callable"])
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if puppet != null:
		puppet.queue_free()
		puppet = null
	# Leaving ends the round; the next LAN game loads the map fresh.
	mode = "left"


# The spawn point furthest from the other player.
func _lan_spawn() -> Vector3:
	var best: Vector3 = LAN_SPAWNS[0]
	if puppet == null:
		return best
	for spot: Vector3 in LAN_SPAWNS:
		if spot.distance_to(puppet.global_position) > best.distance_to(puppet.global_position):
			best = spot
	return best


@rpc("any_peer", "reliable")
func net_throw(kind: String, from: Vector3, velocity: Vector3) -> void:
	if puppet != null:
		spawn_throw(kind, from, velocity, puppet, false)


@rpc("any_peer", "unreliable_ordered")
func net_state(pos: Vector3, yaw: float) -> void:
	if puppet != null:
		puppet.net_pos = pos
		puppet.net_yaw = yaw


@rpc("any_peer", "unreliable")
func net_shot(to: Vector3) -> void:
	if puppet != null:
		puppet.show_shot(to)


@rpc("any_peer", "reliable")
func net_hurt(damage: float, from: Vector3) -> void:
	if not match_over:
		player.hurt(damage, from)


# The other player died: that is a point for us.
@rpc("any_peer", "reliable")
func net_died() -> void:
	if puppet != null:
		puppet.set_dead(true)
	hitmarker.mark(true, hitmarker.head and hitmarker.age < 0.6)
	if match_over:
		return
	score_you += 1
	streak += 1
	if streak >= RATTE_KILLS:
		ratte_ready = true
	if score_you >= WIN_SCORE:
		_end_match("SIEG")
	else:
		_flash_banner("GEGNER AUSGESCHALTET", 1.2)


@rpc("any_peer", "reliable")
func net_respawned() -> void:
	if puppet != null:
		puppet.set_dead(false)


# Automated check with two copies of the game on one PC (--lantest-host and
# --lantest-join): they must connect, see each other in the right place, and a
# kill on one side must count on both.
func _run_lan_test() -> void:
	var waited := 0.0
	while puppet == null and waited < 25.0:
		await _wait(0.1)
		waited += 0.1
	res["role"] = lan_test
	res["connected"] = puppet != null
	if puppet == null:
		print("LANTEST ", JSON.stringify(res))
		get_tree().quit(1)
		return
	await _wait(1.5)
	var other: Vector3 = LAN_SPAWNS[4 if lan_test == "host" else 0]
	res["sees_other_player"] = puppet.global_position.distance_to(other) < 1.0
	if lan_test == "host":
		await _save_view("lan_host_view")
		player.shot_fired.emit(puppet.global_position + Vector3.UP)
		puppet.hit(20.0, puppet.global_position + Vector3.UP * 1.0)
		await _wait(0.5)
		puppet.hit(500.0, puppet.global_position + Vector3.UP * 1.0)
		await _wait(1.5)
		res["kill_counted"] = score_you == 1
		waited = 0.0
		while puppet != null and not puppet.alive and waited < 4.0:
			await _wait(0.1)
			waited += 0.1
		res["other_came_back"] = puppet != null and puppet.alive
	else:
		waited = 0.0
		while score_bot == 0 and waited < 12.0:
			await _wait(0.1)
			waited += 0.1
		res["died_once"] = score_bot == 1
		res["saw_shot"] = puppet.last_shot_ms > 0
		res["alive_again"] = player.health == player.max_health()
		await _wait(4.0)
	var ok := true
	for key: String in res:
		if res[key] is bool and not res[key]:
			ok = false
	res["passed"] = ok
	print("LANTEST ", JSON.stringify(res))
	get_tree().quit(0 if ok else 1)


# --- equipment ---------------------------------------------------------------------

func _on_threw(kind: String, from: Vector3, velocity: Vector3) -> void:
	spawn_throw(kind, from, velocity, player, true)
	if mode == "lan" and puppet != null:
		net_throw.rpc(kind, from, velocity)


func spawn_throw(kind: String, from: Vector3, velocity: Vector3, thrower: Node3D, local: bool) -> Node3D:
	var p := Projectile.new()
	p.kind = kind
	p.velocity = velocity
	p.thrower = thrower
	p.local_throw = local
	p.game = self
	add_child(p)
	p.global_position = from
	return p


# Flash of light, fireball and smoke where a grenade goes off.
func effect_blast(kind: String, at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = {"granate": Color(1.0, 0.62, 0.3), "blend": Color(1, 1, 1), "betaeubung": Color(0.7, 0.8, 1.0)}[kind]
	light.light_energy = 14.0 if kind == "blend" else 9.0
	light.omni_range = 12.0
	add_child(light)
	light.global_position = at + Vector3.UP * 0.3
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hot.albedo_color = Color(1.0, 0.7, 0.3, 0.9) if kind == "granate" else Color(1, 1, 1, 0.9)
	sphere.material = hot
	ball.mesh = sphere
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = at
	ball.scale = Vector3.ONE * 0.2
	var tw := create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * (3.6 if kind == "granate" else 1.6), 0.28)
	tw.tween_property(hot, "albedo_color:a", 0.0, 0.32)
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.chain().tween_callback(func() -> void:
		ball.queue_free()
		light.queue_free())
	if kind == "granate":
		var smoke := CPUParticles3D.new()
		smoke.one_shot = true
		smoke.amount = 28
		smoke.lifetime = 2.2
		smoke.explosiveness = 0.9
		smoke.direction = Vector3.UP
		smoke.spread = 80.0
		smoke.gravity = Vector3(0, 0.6, 0)
		smoke.initial_velocity_min = 1.0
		smoke.initial_velocity_max = 4.0
		smoke.damping_min = 2.0
		smoke.damping_max = 3.0
		smoke.scale_amount_min = 2.0
		smoke.scale_amount_max = 4.0
		var fade := Gradient.new()
		fade.colors = PackedColorArray([Color(0.3, 0.28, 0.25, 0.5), Color(0.4, 0.38, 0.35, 0.0)])
		smoke.color_ramp = fade
		var puff := QuadMesh.new()
		puff.size = Vector2(0.6, 0.6)
		puff.material = player.dust_mat
		smoke.mesh = puff
		add_child(smoke)
		smoke.global_position = at
		smoke.emitting = true
		get_tree().create_timer(2.6).timeout.connect(smoke.queue_free)
	# Close blasts shake the view.
	var d := at.distance_to(player.global_position)
	if d < 14.0:
		player.dip_vel -= (1.0 - d / 14.0) * 1.2
		player.punch_roll += deg_to_rad(randf_range(-4.0, 4.0)) * (1.0 - d / 14.0)


func _run_flash_test() -> void:
	if OS.get_cmdline_user_args().has("--lobbyshot"):
		main_menu.open(false)
		main_menu.show_tab(0)
		await _wait(0.8)
		await _save_view("menu_play")
		main_menu.show_tab(1)
		await _wait(0.4)
		await _save_view("menu_weapons")
		main_menu.show_tab(0)
		main_menu.play_info.visible = false
		main_menu.lobby.visible = true
		await _wait(0.5)
		await _save_view("lobby")
		get_tree().quit(0)
		return
	if OS.get_cmdline_user_args().has("--legshots"):
		await _leg_shots()
		get_tree().quit(0)
		return
	if OS.get_cmdline_user_args().has("--attachshots"):
		await _attach_shots()
		get_tree().quit(0)
		return
	menu.set_weapon("primary", "ar")
	await _wait(1.5)
	# Twice: with the smoke, and with the smoke hidden, to tell the two apart.
	for round in 2:
		player.smoke.visible = round == 0
		player.puffs.visible = round == 0
		player.ai = {"fire": true}
		for frame in 5:
			await RenderingServer.frame_post_draw
			if frame == 1:
				player.ai = {}
			var vmd: Node3D = player.vmodel
			await _save_view("flash_%s_%d" % ["smoke" if round == 0 else "nosmoke", frame])
		await _wait(1.0)
	player.smoke.visible = true
	player.puffs.visible = true
	await _wait(0.4)
	await _save_view("flash_after")
	await _wait(1.0)
	player.ammo = 3
	player.ai = {"reload": true}
	await _wait(0.1)
	player.ai = {}
	await _wait(0.9)
	await _save_view("reload_mid")
	await _wait(0.6)
	await _save_view("reload_late")
	await _wait(1.5)
	player.ammo = 3
	player.ai = {"reload": true}
	await _wait(0.1)
	player.ai = {}
	await _wait(0.3)
	await _save_view("reload_grab")
	await _wait(3.0)
	player.ai = {"inspect": true}
	await _wait(1.0)
	await _save_view("inspect_reach")
	await _wait(1.8)
	await _save_view("inspect_mag")
	player.ai = {}
	menu.set_weapon("primary", "sniper")
	await _wait(1.5)
	player.ai = {"fire": true}
	await _wait(0.05)
	player.ai = {}
	await _wait(0.55)
	await _save_view("bolt_grab")
	await _wait(1.5)
	player.ai = {"fire": true}
	await _wait(0.05)
	player.ai = {}
	await _wait(0.3)
	player.vmodel.bolt_hook = true
	await _wait(0.25)
	await _save_view("bolt_hook")
	await _wait(1.5)
	player.ammo = 2
	player.ai = {"reload": true}
	await _wait(0.1)
	player.ai = {}
	player.reload_style = 1
	player.vmodel.reload_style = 1
	await _wait(0.9)
	await _save_view("reload_b_mid")
	await _wait(1.25)
	await _save_view("reload_b_slap")
	get_tree().quit(0)


# Pictures of the attachments on MP5 and KR-4 (--flashtest --attachshots).
func _attach_shots() -> void:
	var looks := [
		["smg", {}, "att_smg_default", false],
		["smg", {"muendung": "kompensator", "laser": "kombi", "schaft": "fest", "visier": "holo", "magazin": "erweitert"}, "att_smg_full", false],
		["smg", {"muendung": "kompensator", "laser": "kombi", "schaft": "fest", "visier": "holo", "magazin": "erweitert"}, "att_smg_full_aim", true],
		["ar", {"muendung": "bremse", "laser": "laser", "griff": "taktisch", "schaft": "skelett", "visier": "rotpunkt", "magazin": "schnell"}, "att_ar_full", false],
		["ar", {"muendung": "bremse", "laser": "laser", "griff": "taktisch", "schaft": "skelett", "visier": "rotpunkt", "magazin": "schnell"}, "att_ar_dot_aim", true],
		["ar", {"muendung": "schalldaempfer", "griff": "keiner", "visier": "zielvisier"}, "att_ar_sup", false],
		["ar", {"muendung": "schalldaempfer", "griff": "keiner", "visier": "zielvisier"}, "att_ar_acog_aim", true],
	]
	for look: Array in looks:
		menu.set_weapon("primary", look[0])
		for slot: String in look[1]:
			menu.set_attachment(look[0], slot, look[1][slot])
		await _wait(0.8)
		if look[3]:
			player.ai = {"ads": true}
			await _wait(0.8)
		await _save_view(look[2])
		if look[0] == "ar" and look[2] == "att_ar_full":
			player.ai = {"fire": true}
			await _wait(0.03)
			await _save_view("att_ar_fire")
			await _wait(0.2)
		player.ai = {}
		await _wait(0.3)
		menu.attach[look[0]] = {}
	main_menu.open(false)
	main_menu.show_tab(1)
	main_menu.open_editor("ar")
	menu.set_attachment("ar", "muendung", "bremse")
	await _wait(0.6)
	await _save_view("att_editor_ar")
	main_menu.close_editor()
	main_menu.close()


# Pictures of the player's own legs (--flashtest --legshots).
func _leg_shots() -> void:
	player.global_position = Vector3(0, 0.05, 20)
	var looks := [
		["legs_stand", {}, -1.25, 0.8],
		["legs_walk", {"fwd": true}, -1.15, 0.9],
		["legs_sprint", {"fwd": true, "sprint": true}, -1.1, 0.9],
		["legs_crouch", {"crouch": true}, -1.2, 0.8],
		["legs_side", {}, -0.75, 0.6],
	]
	for look: Array in looks:
		player.global_position = Vector3(0, 0.05, 20)
		player.ai = look[1]
		player.pitch = look[2]
		await _wait(look[3])
		player.pitch = look[2]
		await _save_view(look[0])
		player.ai = {}
		await _wait(0.6)
	player.ai = {"fwd": true, "sprint": true}
	await _wait(1.2)
	player.ai = {"fwd": true, "sprint": true, "crouch": true}
	await _wait(0.25)
	player.pitch = -0.9
	await _save_view("legs_slide")
	player.ai = {}


func _run_killcam_test() -> void:
	player.global_position = Vector3(-12.0, 0.05, 0.0)
	bot.global_position = Vector3(-3.0, 0.05, 0.0)
	bot.health = 999.0
	await _wait(4.0)
	player.ai = {"fire": true}
	await _wait(0.8)
	player.ai = {}
	await _wait(1.5)
	player.health = 25.0
	var waited := 0.0
	while player.health > 0.0 and waited < 12.0:
		await _wait(0.1)
		waited += 0.1
	await _wait(0.8)
	await _save_view("kc_death")
	await _wait(2.5)
	await _save_view("kc_fp_early")
	await _wait(5.2)
	await _save_view("kc_fp_kill")
	await killcam.finished
	bot.set_physics_process(false)
	player.health = 9999.0
	await _wait(1.0)
	# The last kill of the match, from your own eyes: tac sprint, reload, inspect,
	# fire - the final killcam has to show all of it as it happened.
	bot.set_physics_process(false)
	bot.blind(60.0)
	bot.health = 9999.0
	player.health = 9999.0
	await _wait(1.0)
	player.ai = {"fwd": true, "sprint": true}
	await _wait(0.4)
	player.ai = {"fwd": true, "sprint": true}
	await _wait(1.6)
	player.ai = {}
	await _wait(0.4)
	player.ammo = 5
	player.ai = {"reload": true}
	await _wait(0.1)
	player.ai = {}
	await _wait(2.6)
	player.ai = {"inspect": true}
	await _wait(2.0)
	player.ai = {}
	await _wait(0.8)
	player.ai = {"fire": true}
	await _wait(0.6)
	player.ai = {}
	score_you = WIN_SCORE - 1
	_on_bot_died()
	await _wait(1.5)
	for shot in 9:
		await _wait(1.1)
		await _save_view("kc_final_%d" % shot)
	await killcam.finished
	print("KILLCAMTEST ok=", player.health > 0.0, " final=", score_you)
	get_tree().quit(0)


# Bots a grenade can hurt in a team game.
func blast_targets() -> Array:
	return sd.blast_targets() if sd != null else []


func _run_sd_test() -> void:
	await _wait(1.0)
	# The test player only watches: the bomb goes to one of its team's bots, and the
	# player waits out of the way.
	player.global_position = Vector3(-3.5, 0.05, 32.5)
	var mates := sd.bots.filter(func(b: Bot) -> bool: return b.team == sd.attackers)
	if not mates.is_empty():
		sd.carrier = mates[0]
		sd._plan_round()
	await _save_view("sd_prep")
	await _wait(4.0)
	await _save_view("sd_live")
	var shots := 0
	for i in 75:
		await _wait(2.0)
		if sd == null:
			break
		var alive := sd.bots.filter(func(b: Bot) -> bool: return b.alive).size()
		print("SDTEST t=%d phase=%s round=%d score=%s alive_bots=%d planted=%s player_hp=%d spect=%s" % [i * 2, sd.phase, sd.round_no, str(sd.score), alive, str(sd.bomb_site), int(player.health), str(sd.spectating)])
		if i % 4 == 1 and shots < 8:
			await _save_view("sd_%02d" % i)
			shots += 1
	get_tree().quit(0)


# --- loading, music, motion blur ------------------------------------------------------

func _step(p: float, what: String) -> void:
	if loading == null:
		return
	loading.set_progress(p, what)
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--loadshot") and p >= 0.5:
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("shots/loading.png")


# Reads every model and sound once, so nothing stutters the first time it is needed.
func _preload_assets() -> void:
	var files: Array[String] = []
	for folder: String in ["res://models/", "res://sounds/"]:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".bin") or f.ends_with(".wav"):
				files.append(folder + f)
	for i in files.size():
		var f := files[i]
		if f.ends_with(".bin"):
			Assets.mesh(f.get_file())
		elif not f.contains("music"):
			Assets.sound(f.get_file())
		if i % 6 == 0:
			loading.set_progress(0.6 + 0.38 * float(i) / maxf(files.size(), 1.0),
					"Lade %s  (%d / %d)" % ["Modelle" if f.ends_with(".bin") else "Sounds", i + 1, files.size()])
			await get_tree().process_frame


# The orchestral theme: on in the menus and while loading, quiet in a match.
func _start_music() -> void:
	music = AudioStreamPlayer.new()
	var stream := Assets.sound("music_menu.wav")
	if stream == null:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 4
	music.stream = stream
	music.volume_db = -60.0
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(music)
	music.play()
	_music(true)


func _music(on: bool) -> void:
	if music == null:
		return
	var level: float = menu.music_volume if menu != null else 0.45
	var target := linear_to_db(maxf(level, 0.0001)) - 6.0 if (on and level > 0.001) else -60.0
	if _music_tween != null:
		_music_tween.kill()
	# On the music player itself: the menu pauses the game, and a tween on a paused
	# node would never turn the music up.
	_music_tween = music.create_tween()
	_music_tween.tween_property(music, "volume_db", target, 1.6 if on else 1.0)


# Camera motion blur: the picture smears along the way the view turns.
func _motion_blur() -> void:
	if post_mat == null:
		return
	var on: bool = menu != null and menu.motion_blur and not main_menu.is_open and player.process_mode != Node.PROCESS_MODE_DISABLED
	var blur := Vector2.ZERO
	if on:
		var vfov := deg_to_rad(player.cam.fov)
		var hfov := 2.0 * atan(tan(vfov * 0.5) * 16.0 / 9.0)
		var shutter := 1.0 / 90.0
		blur = Vector2(-player.turn.x / hfov, player.turn.y / vfov) * shutter
		blur = blur.limit_length(0.035)
	post_mat.set_shader_parameter("blur", blur)
