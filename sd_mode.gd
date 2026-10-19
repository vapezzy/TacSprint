extends Node

# Search and Destroy on the maps in sd_map.gd ("Raffinerie", "Hafen"). Two teams, no respawns within a round. The
# attackers carry a bomb to site A or B and plant it; the defenders stop them
# or defuse it. A round is won by wiping out the other side, by the bomb going
# off (attackers), by defusing it or running out the clock (defenders). Sides
# switch every SWITCH_EVERY rounds; ROUNDS_TO_WIN rounds win the match. Bots
# fill both teams (set in the lobby: up to 5 with you, up to 6 against you).
# After each round the last kill is shown as the final killcam.

const Bot := preload("res://bot.gd")
const SdMap := preload("res://sd_map.gd")
const Killcam := preload("res://killcam.gd")
const Assets := preload("res://assets.gd")
const Icons := preload("res://icons.gd")

const ROUNDS_TO_WIN := 4
const SWITCH_EVERY := 3
const PREP_TIME := 4.0
const ROUND_TIME := 105.0
const BOMB_TIME := 40.0
const PLANT_TIME := 4.0
const DEFUSE_TIME := 6.0
const BLAST_RADIUS := 11.0
const ALLY_NAMES := ["Kowalski", "Brandt", "Novak", "Weber", "Krüger"]
const FOE_NAMES := ["Viper", "Krähe", "Wolf", "Kobra", "Hai", "Falke"]
const BLUE := Color(0.25, 0.55, 1.0)
const RED := Color(0.95, 0.28, 0.22)

# Lobby settings, kept across the scene reload that starts the match.
static var allies := 3
static var enemies := 4
static var skill := 1.0

var main: Node
var player: CharacterBody3D
var killcam: Killcam
var bots: Array[Bot] = []
var attackers := 0             # which team attacks this round (0 = yours)
var round_no := 0
var score := [0, 0]            # rounds won: your team, the other
var phase := ""                # "prep", "live", "planted", "over", "done"
var timer := 0.0
var target_site := 0
var carrier: Node3D            # who has the bomb (player or bot), null when it lies on the ground
var bomb: Node3D
var bomb_at := Vector3.ZERO
var bomb_site := -1
var bomb_t := 0.0
var plant_p := 0.0
var defuse_p := 0.0
var _beep := 0.0
var last_kill := {}            # {"killer": -1 player / bot index, "victim": -2 player / bot index}
var spectating := false
var spec_cam: Camera3D
var _spec_i := 0
var _death_t := 0.0
var _hunt_t := 0.0
var grid: AStarGrid2D          # the walking grid all bots share
var plans := {}                # Bot -> its own plan for this round (see _plan_round)
var clock := 0.0
var _contact := [-100.0, -100.0]   # when attackers were last near each site
var _sense_t := 0.0

var hud: CanvasLayer
var _score_label: Label
var _role_label: Label
var _time_label: Label
var _bomb_label: Label
var _hint: Label
var _banner: Label
var _sub_banner: Label
var _progress: ProgressBar
var _progress_label: Label
var _pips: HBoxContainer
var _feed: VBoxContainer
var _spec_label: Label
var _beeper: AudioStreamPlayer3D
var _clock_icon: TextureRect
var _bomb_icon: TextureRect


func setup(game: Node) -> void:
	main = game
	player = main.get("player")
	# One walking grid for everyone, built before anybody stands in the way.
	grid = Bot.build_grid(player.get_world_3d(), SdMap.SD_BOUNDS, [player.get_rid()])
	for i in allies + enemies:
		var b := Bot.new()
		b.team = 0 if i < allies else 1
		b.bot_name = ALLY_NAMES[i % ALLY_NAMES.size()] if i < allies else FOE_NAMES[(i - allies) % FOE_NAMES.size()]
		b.band_color = BLUE if b.team == 0 else RED
		b.game = self
		b.respawns = false
		b.bounds = SdMap.SD_BOUNDS
		b.skill = skill
		b.grid = grid
		main.add_child(b)
		bots.append(b)
		b.died.connect(_on_bot_died.bind(b))
		if b.team == 0:
			# Your side wears its name over its head.
			var tag := Label3D.new()
			tag.text = b.bot_name
			tag.modulate = BLUE
			tag.outline_size = 8
			tag.font_size = 48
			tag.pixel_size = 0.004
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.position = Vector3(0, 2.1, 0)
			b.add_child(tag)
	killcam = Killcam.new()
	main.add_child(killcam)
	killcam.watch_player(player)
	for b in bots:
		killcam.add_bot(b)
	player.died.connect(_on_player_died)
	spec_cam = Camera3D.new()
	spec_cam.fov = 70.0
	main.add_child(spec_cam)
	bomb = _make_bomb()
	main.add_child(bomb)
	_build_hud()
	_start_round()


# --- who fights whom ----------------------------------------------------------------

func enemies_of(b: Bot) -> Array:
	var out := []
	if b.team != 0 and float(player.health) > 0.0 and not spectating:
		out.append(player)
	for o in bots:
		if o.team != b.team and o.alive:
			out.append(o)
	return out


func blast_targets() -> Array:
	var out := []
	for b in bots:
		if b.alive:
			out.append(b)
	return out


func _alive_count(team: int) -> int:
	var n := 0
	if team == 0 and float(player.health) > 0.0 and not spectating:
		n += 1
	for b in bots:
		if b.team == team and b.alive:
			n += 1
	return n


# --- rounds ---------------------------------------------------------------------------

func _spawn_points(team: int) -> Array:
	var attack := team == attackers
	var base: Vector3 = SdMap.ATTACK_SPAWN if attack else SdMap.DEFEND_SPAWN
	var pts := []
	for i in 6:
		var row := i / 3
		var col := i % 3
		pts.append(base + Vector3((col - 1) * 2.2, 0.0, (1.6 if attack else -1.6) * row))
	return pts


func _start_round() -> void:
	round_no += 1
	if round_no > 1 and (round_no - 1) % SWITCH_EVERY == 0:
		attackers = 1 - attackers
		_show_banner("SEITENWECHSEL", "Ihr greift jetzt an" if attackers == 0 else "Ihr verteidigt jetzt", 2.5)
		await get_tree().create_timer(2.5).timeout
	phase = "prep"
	timer = PREP_TIME
	plant_p = 0.0
	defuse_p = 0.0
	bomb_site = -1
	target_site = randi() % 2
	last_kill = {}
	for child in _feed.get_children():
		child.queue_free()
	# Everybody back at their side's spawn.
	var points := [_spawn_points(0), _spawn_points(1)]
	var used := [0, 0]
	_stop_spectating()
	player.call("revive")
	player.call("_fill_ammo")
	player.call("_equip", player.get("slot"))
	player.global_position = points[0][0]
	used[0] = 1
	player.velocity = Vector3.ZERO
	player.yaw = 0.0 if attackers == 0 else PI
	player.pitch = 0.0
	for b in bots:
		var pts: Array = points[b.team]
		var at: Vector3 = pts[used[b.team] % pts.size()]
		used[b.team] += 1
		b.reset_at(at, 0.0 if b.team == attackers else PI)
		b.frozen = true
		b.goal = Vector3.INF
	# The bomb goes to an attacker: you, if you attack.
	if attackers == 0:
		carrier = player
	else:
		var options := bots.filter(func(b: Bot) -> bool: return b.team == attackers)
		carrier = options[randi() % options.size()] if not options.is_empty() else null
	bomb.visible = false
	_plan_round()
	var role := "ANGRIFF" if attackers == 0 else "VERTEIDIGUNG"
	_show_banner("RUNDE %d  ·  %s" % [round_no, role],
			("Leg die Bombe auf A oder B  ·  E halten" if attackers == 0 else "Verteidige A und B"), PREP_TIME)


func _physics_process(dt: float) -> void:
	if hud == null:
		return
	clock += dt
	if spectating:
		_spectate(dt)
	match phase:
		"prep":
			timer -= dt
			if timer <= 0.0:
				phase = "live"
				timer = ROUND_TIME
				for b in bots:
					b.frozen = false
		"live", "planted":
			_drive(dt)
			_play_round(dt)
	_update_hud()


func _play_round(dt: float) -> void:
	timer -= dt
	_hunt_t -= dt
	if _hunt_t <= 0.0:
		_hunt_t = 1.0
		_hunt()
	var interact: bool = player.held.get("interact", false) or player.held.get("reload", false)
	var still: bool = float(player.call("speed_h")) < 0.6
	# The bomb: carried, dropped when its carrier falls, picked up again.
	if carrier != null and not _is_alive(carrier):
		bomb_at = carrier.global_position
		carrier = null
		bomb.global_position = bomb_at
		bomb.visible = true
		_on_bomb_dropped()
	if carrier == null and bomb_site < 0:
		var takers: Array = []
		takers.append_array(bots.filter(func(b: Bot) -> bool: return b.team == attackers and b.alive))
		if attackers == 0 and float(player.health) > 0.0:
			takers.append(player)
		for t: Node3D in takers:
			if t.global_position.distance_to(bomb_at) < 1.4:
				carrier = t
				bomb.visible = false
				_feed_line("%s hat die Bombe" % _name_of(t), BLUE if attackers == 0 else RED)
				_on_bomb_taken(t)
				break
	if phase == "live":
		# Planting: the carrier inside a site, still, for PLANT_TIME.
		var planting := false
		if carrier != null:
			var site := _site_at(carrier.global_position)
			if site >= 0:
				if carrier == player:
					planting = interact and still
				else:
					planting = not (carrier as Bot).has_los
			if planting:
				plant_p += dt
				if plant_p >= PLANT_TIME:
					_plant(site)
					return
		if not planting:
			plant_p = 0.0
	else:
		# Defusing: a defender at the bomb, still, for DEFUSE_TIME.
		var defusing := false
		if attackers != 0 and float(player.health) > 0.0 and not spectating:
			if player.global_position.distance_to(bomb_at) < 1.8 and interact and still:
				defusing = true
		for b in bots:
			if b.team != attackers and b.alive and not b.has_los and b.global_position.distance_to(bomb_at) < 1.8:
				defusing = true
		if defusing:
			defuse_p += dt
			if defuse_p >= DEFUSE_TIME:
				_end_round(1 - attackers, "Bombe entschärft")
				return
		else:
			defuse_p = 0.0
		bomb_t -= dt
		_beep -= dt
		if _beep <= 0.0:
			_beep = clampf(bomb_t / BOMB_TIME, 0.12, 1.0) * 0.9
			_beeper.play()
		if bomb_t <= 0.0:
			_explode()
			return
	# Who is left.
	var att_left := _alive_count(attackers)
	var def_left := _alive_count(1 - attackers)
	if def_left == 0:
		_end_round(attackers, "Alle Verteidiger ausgeschaltet")
	elif att_left == 0 and phase == "live":
		_end_round(1 - attackers, "Alle Angreifer ausgeschaltet")
	elif timer <= 0.0 and phase == "live":
		_end_round(1 - attackers, "Zeit abgelaufen")


# When a round drags on, the bots stop holding and go after the enemies that are
# left, each after its own patience runs out (35 to 70 s). The bomb carrier and,
# once it is planted, everybody (guarding it, or going for it) keep their jobs.
func _hunt() -> void:
	if phase != "live":
		return
	var since := ROUND_TIME - timer
	for b in bots:
		if not b.alive or b.has_los or b == carrier or not plans.has(b):
			continue
		var plan: Dictionary = plans[b]
		if since < float(plan["hunt_after"]) or plan["role"] == "fetch":
			continue
		var best: Node3D = null
		var best_d := INF
		for e: Node3D in enemies_of(b):
			var d := b.global_position.distance_to(e.global_position)
			if d < best_d:
				best = e
				best_d = d
		if best != null:
			var p2 := _new_plan("hunt", [_free(best.global_position)], best.global_position, 0.0)
			p2["hunt_after"] = plan["hunt_after"]
			p2["site"] = plan["site"]
			p2["react_at"] = -1.0
			plans[b] = p2


func _site_at(pos: Vector3) -> int:
	for i in SdMap.SITES.size():
		var s: Vector3 = SdMap.SITES[i]
		if Vector2(pos.x - s.x, pos.z - s.z).length() < SdMap.SITE_RADIUS:
			return i
	return -1


func _plant(site: int) -> void:
	phase = "planted"
	bomb_site = site
	bomb_at = carrier.global_position
	bomb.global_position = bomb_at
	bomb.visible = true
	carrier = null
	bomb_t = BOMB_TIME
	plant_p = 0.0
	_beep = 0.0
	_show_banner("BOMBE GELEGT", "Bombenplatz %s  ·  %d Sekunden" % [SdMap.SITE_NAMES[site], int(BOMB_TIME)], 2.5)
	_on_planted()


func _explode() -> void:
	main.call("effect_blast", "granate", bomb_at + Vector3.UP * 0.4)
	bomb.visible = false
	for b in bots:
		if b.alive and b.global_position.distance_to(bomb_at) < BLAST_RADIUS:
			b.hit(500.0, Vector3.ZERO, 1 - b.team)
	if float(player.health) > 0.0 and player.global_position.distance_to(bomb_at) < BLAST_RADIUS:
		player.call("hurt", 500.0, bomb_at)
	_end_round(attackers, "Die Bombe ist explodiert")


func _end_round(winner: int, why: String) -> void:
	if phase == "over" or phase == "done":
		return
	phase = "over"
	score[0 if winner == 0 else 1] += 1
	for b in bots:
		b.frozen = true
	var won := winner == 0
	_show_banner("RUNDE GEWONNEN" if won else "RUNDE VERLOREN", "%s   ·   %d : %d" % [why, score[0], score[1]], 3.0)
	await get_tree().create_timer(2.2).timeout
	# The round's last kill, as the final killcam.
	if not last_kill.is_empty():
		hud.visible = false
		var main_hud: CanvasLayer = main.get("hud")
		main_hud.visible = false
		spec_cam.current = false
		killcam.start(last_kill["killer"], true, last_kill["victim"])
		await killcam.finished
		hud.visible = true
		main_hud.visible = true
	else:
		await get_tree().create_timer(1.5).timeout
	if score[0] >= ROUNDS_TO_WIN or score[1] >= ROUNDS_TO_WIN:
		phase = "done"
		var match_won: bool = score[0] >= ROUNDS_TO_WIN
		_show_banner("SIEG" if match_won else "NIEDERLAGE", "Endstand %d : %d" % [score[0], score[1]], 5.0)
		await get_tree().create_timer(5.0).timeout
		main.call("_open_main_menu")
		return
	_start_round()


# --- kills ----------------------------------------------------------------------------

func _name_of(n: Node) -> String:
	if n == null or n == player:
		return "Du"
	return str(n.get("bot_name"))


func _on_bot_died(b: Bot) -> void:
	var killer: Node = b.last_attacker
	last_kill = {"killer": -1 if killer == null else bots.find(killer), "victim": bots.find(b)}
	var killer_team := 0 if killer == null else int(killer.get("team"))
	_feed_kill(_name_of(killer), killer_team, b.bot_name, b.team)
	if killer == null:
		main.get("hitmarker").call("mark", true, false)


func _on_player_died() -> void:
	var by: Node = player.get("last_hurt_by")
	last_kill = {"killer": maxi(bots.find(by), 0), "victim": -2}
	_feed_kill(_name_of(by), 1, "Du", 0)
	_start_spectating()


func _start_spectating() -> void:
	spectating = true
	_death_t = 0.0
	spec_cam.global_transform = (player.get("cam") as Camera3D).global_transform
	spec_cam.make_current()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	(main.get("hud") as CanvasLayer).visible = false
	_spec_label.visible = true


func _stop_spectating() -> void:
	spectating = false
	_spec_label.visible = false
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.visible = true
	(player.get("cam") as Camera3D).make_current()
	(main.get("hud") as CanvasLayer).visible = true


# While dead: a moment of falling, then over the shoulder of a living teammate
# (Leertaste / A for the next one), or high above the map when nobody is left.
func _spectate(dt: float) -> void:
	_death_t += dt
	if Input.is_action_just_pressed("mv_jump"):
		_spec_i += 1
	var mates := bots.filter(func(b: Bot) -> bool: return b.team == 0 and b.alive)
	var target_xf: Transform3D
	if _death_t < 1.2:
		var from: Vector3 = player.global_position + Vector3.UP * 1.6
		var low := from.lerp(player.global_position + Vector3.UP * 0.4, smoothstep(0.0, 1.0, _death_t / 1.2))
		target_xf = Transform3D(spec_cam.global_basis.rotated(spec_cam.global_basis.z, dt * 0.25), low)
		_spec_label.text = "AUSGESCHALTET"
	elif not mates.is_empty():
		var m: Bot = mates[_spec_i % mates.size()]
		var fwd := Vector3(-sin(m.rotation.y), 0.0, -cos(m.rotation.y))
		var right := fwd.cross(Vector3.UP).normalized()
		var eye := m.global_position + Vector3.UP * 1.6
		var at := eye - fwd * 2.2 + right * 0.55 + Vector3.UP * 0.35
		var q := PhysicsRayQueryParameters3D.create(eye, at)
		q.collision_mask = 1
		q.exclude = [m.get_rid()]
		var hit := spec_cam.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			at = eye.lerp(hit["position"], 0.85)
		target_xf = Transform3D(Transform3D().looking_at(fwd + Vector3(0, -0.12, 0), Vector3.UP).basis, at)
		_spec_label.text = "ZUSCHAUEN  ·  %s     (Leertaste: nächster)" % m.bot_name
	else:
		var t := _death_t * 0.12
		var at := Vector3(sin(t) * 22.0, 30.0, cos(t) * 30.0)
		target_xf = Transform3D(Transform3D().looking_at(-at, Vector3.UP).basis, at)
		_spec_label.text = "ZUSCHAUEN"
	spec_cam.global_transform = spec_cam.global_transform.interpolate_with(target_xf, 1.0 - exp(-7.0 * dt))


func _is_alive(n: Node) -> bool:
	if n == player:
		return float(player.health) > 0.0 and not spectating
	return bool(n.get("alive"))


# --- the bomb ---------------------------------------------------------------------------

func _make_bomb() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.32, 0.12, 0.22)
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.22, 0.16)
	mat.roughness = 0.7
	body.material_override = mat
	body.position.y = 0.06
	root.add_child(body)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.15, 0.1)
	lamp.light_energy = 0.8
	lamp.omni_range = 1.6
	lamp.position = Vector3(0, 0.2, 0)
	root.add_child(lamp)
	_beeper = AudioStreamPlayer3D.new()
	_beeper.stream = _beep_sound()
	_beeper.unit_size = 4.0
	root.add_child(_beeper)
	root.visible = false
	return root


func _beep_sound() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.09)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var v := sin(TAU * 1900.0 * t) * exp(-t * 18.0) * 0.6
		data.encode_s16(i * 2, int(v * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s


# --- HUD ------------------------------------------------------------------------------------

func _label(size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 6
	main.add_child(hud)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-220, 10)
	top.size = Vector2(440, 120)
	top.add_theme_constant_override("separation", 0)
	hud.add_child(top)
	_role_label = _label(16, Color(0.95, 0.62, 0.16))
	top.add_child(_role_label)
	_score_label = _label(30)
	top.add_child(_score_label)
	var clock_row := HBoxContainer.new()
	clock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	clock_row.add_theme_constant_override("separation", 6)
	_clock_icon = Icons.rect("clock", 20)
	clock_row.add_child(_clock_icon)
	_time_label = _label(24)
	clock_row.add_child(_time_label)
	top.add_child(clock_row)
	_pips = HBoxContainer.new()
	_pips.alignment = BoxContainer.ALIGNMENT_CENTER
	_pips.add_theme_constant_override("separation", 4)
	top.add_child(_pips)
	var bomb_row := HBoxContainer.new()
	bomb_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bomb_row.add_theme_constant_override("separation", 8)
	_bomb_icon = Icons.rect("bomb", 26, RED)
	bomb_row.add_child(_bomb_icon)
	_bomb_label = _label(22, RED)
	bomb_row.add_child(_bomb_label)
	top.add_child(bomb_row)
	_banner = _label(54)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-500, 190)
	_banner.size = Vector2(1000, 70)
	hud.add_child(_banner)
	_sub_banner = _label(22, Color(0.85, 0.88, 0.9))
	_sub_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub_banner.position = Vector2(-500, 262)
	_sub_banner.size = Vector2(1000, 34)
	hud.add_child(_sub_banner)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.set_anchors_preset(Control.PRESET_CENTER)
	_progress.position = Vector2(-160, 60)
	_progress.size = Vector2(320, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.62, 0.16)
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.visible = false
	hud.add_child(_progress)
	_progress_label = _label(18)
	_progress_label.set_anchors_preset(Control.PRESET_CENTER)
	_progress_label.position = Vector2(-200, 76)
	_progress_label.size = Vector2(400, 28)
	hud.add_child(_progress_label)
	_hint = _label(18, Color(1, 1, 1, 0.85))
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.position = Vector2(-300, 104)
	_hint.size = Vector2(600, 28)
	hud.add_child(_hint)
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.position = Vector2(-380, 60)
	_feed.size = Vector2(360, 200)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	hud.add_child(_feed)
	_spec_label = _label(22)
	_spec_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spec_label.position = Vector2(-400, -90)
	_spec_label.size = Vector2(800, 34)
	_spec_label.visible = false
	hud.add_child(_spec_label)


func _show_banner(text: String, sub: String, seconds: float) -> void:
	_banner.text = text
	_sub_banner.text = sub
	_banner.visible = true
	_sub_banner.visible = true
	var mine := text
	await get_tree().create_timer(seconds).timeout
	if _banner.text == mine:
		_banner.visible = false
		_sub_banner.visible = false


func _feed_line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	_feed.add_child(l)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	get_tree().create_timer(7.0).timeout.connect(func() -> void:
		if is_instance_valid(l):
			l.queue_free())


# A kill in the feed: the killer in its team colour, a rifle, the victim in its own.
func _feed_kill(killer: String, killer_team: int, victim: String, victim_team: int) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.4)
	bg.skew = Vector2(0.2, 0)
	bg.set_content_margin_all(4)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", bg)
	panel.add_child(row)
	var a := _label(18, BLUE if killer_team == 0 else RED)
	a.text = killer
	row.add_child(a)
	row.add_child(Icons.rect("rifle", 22))
	var v := _label(18, BLUE if victim_team == 0 else RED)
	v.text = victim
	row.add_child(v)
	_feed.add_child(panel)
	if _feed.get_child_count() > 6:
		_feed.get_child(0).queue_free()
	get_tree().create_timer(7.0).timeout.connect(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free())


func _update_hud() -> void:
	_role_label.text = "ANGRIFF" if attackers == 0 else "VERTEIDIGUNG"
	_score_label.text = "WIR  %d  :  %d  GEGNER" % [score[0], score[1]]
	var t := maxf(timer, 0.0) if phase != "planted" else maxf(bomb_t, 0.0)
	_time_label.text = "%d:%02d" % [int(t) / 60, int(t) % 60] if phase != "prep" else "Start in %d" % int(ceil(timer))
	_time_label.add_theme_color_override("font_color", RED if phase == "planted" else Color.WHITE)
	_clock_icon.modulate = RED if phase == "planted" else Color.WHITE
	_bomb_label.text = "BOMBE GELEGT  ·  %s" % SdMap.SITE_NAMES[bomb_site] if phase == "planted" else ""
	_bomb_icon.visible = phase == "planted"
	if phase == "planted":
		_bomb_icon.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
	# One pip per player: blue for your side, red for theirs, dim when down.
	var want := 1 + bots.size()
	while _pips.get_child_count() < want:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(14, 14)
		_pips.add_child(r)
	var i := 0
	var mine := [player] + bots.filter(func(b: Bot) -> bool: return b.team == 0)
	var theirs := bots.filter(func(b: Bot) -> bool: return b.team == 1)
	for n: Node in mine + theirs:
		var r: ColorRect = _pips.get_child(i)
		var c: Color = BLUE if (n == player or int(n.get("team")) == 0) else RED
		r.color = c if _is_alive(n) else Color(c, 0.22)
		i += 1
	# Planting and defusing.
	var p := 0.0
	var what := ""
	if phase == "live" and plant_p > 0.0:
		p = plant_p / PLANT_TIME
		what = "BOMBE WIRD GELEGT"
	elif phase == "planted" and defuse_p > 0.0:
		p = defuse_p / DEFUSE_TIME
		what = "BOMBE WIRD ENTSCHÄRFT"
	_progress.visible = p > 0.0
	_progress.value = p * 100.0
	_progress_label.text = what
	# What you can do right now.
	_hint.text = ""
	if not spectating and float(player.health) > 0.0:
		if phase == "live" and carrier == player:
			_hint.text = "E / X halten: Bombe legen" if _site_at(player.global_position) >= 0 else "Du hast die Bombe  ·  zu A oder B"
		elif phase == "planted" and attackers != 0 and player.global_position.distance_to(bomb_at) < 1.8:
			_hint.text = "E / X halten: Bombe entschärfen"


# Dots for the minimap: your team always, the other side while it fires.
func minimap_dots() -> Array:
	var out := []
	var now := Time.get_ticks_msec()
	for b in bots:
		if not b.alive:
			continue
		if b.team == 0:
			out.append([b.global_position, BLUE])
		elif now - b.last_shot_ms < 1500:
			out.append([b.global_position, RED])
	if bomb.visible:
		out.append([bomb.global_position, Color(1.0, 0.85, 0.2)])
	return out


# --- the bots: each one plays on its own -------------------------------------------------
# Nobody moves as a squad. At the start of every round each bot gets its own
# plan: a role, a lane, a route of waypoints and a spot to hold, plus its own
# timing. Attackers: the carrier takes a lane to the target site, entries go
# early, supports leave later (often by another lane), lurkers sit off to the
# side to catch rotations. Defenders: anchors hold a site and shift between
# spots, forwards take an aggressive spot in a lane and fall back later,
# rotators sit between and go wherever there is contact. Everyone stops to
# check corners now and then, reacts to what happens with a delay of their own,
# and goes hunting at a time of their own when the round drags on.

func _v3(v: Vector2) -> Vector3:
	return _free(Vector3(v.x, 0.05, v.y))


# The nearest walkable point (a waypoint may sit a little inside cover).
func _free(p: Vector3) -> Vector3:
	if grid == null:
		return p
	var b := SdMap.SD_BOUNDS
	var c := Vector2i(int((p.x - b.position.x) / Bot.CELL), int((p.z - b.position.y) / Bot.CELL))
	c = c.clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
	if not grid.is_point_solid(c):
		return p
	for r in range(1, 10):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dz)
				if grid.region.has_point(n) and not grid.is_point_solid(n):
					var at := grid.offset + Vector2(n) * Bot.CELL
					return Vector3(at.x, 0.05, at.y)
	return p


func _route(points: Array) -> Array:
	var out := []
	for v: Vector2 in points:
		out.append(_v3(v))
	return out


func _new_plan(role: String, route: Array, look: Vector3, wait: float) -> Dictionary:
	return {"role": role, "route": route, "i": 0, "wait": wait, "look": look, "stuck": 0.0,
			"last": Vector3.INF, "pause_p": randf_range(0.1, 0.4), "until": INF, "react_at": INF,
			"react_site": -1, "site": -1, "hunt_after": randf_range(35.0, 70.0)}


func _site_point(site: int, spread: float) -> Vector3:
	var s: Vector3 = SdMap.SITES[site]
	var a := randf() * TAU
	return _free(s + Vector3(cos(a), 0.0, sin(a)) * randf() * spread)


func _lanes_to(site: int) -> Array:
	var nav: Dictionary = SdMap.NAV
	var out := []
	for lane: String in nav["lanes"]:
		if int(nav["lane_site"][lane]) == site:
			out.append(lane)
	return out


# Up a lane and in through that lane's entrance.
func _attack_route(lane: String, site: int) -> Array:
	var nav: Dictionary = SdMap.NAV
	var pts: Array = (nav["lanes"][lane] as Array).duplicate()
	var entries: Dictionary = nav["entries"][site]
	if entries.has(lane):
		pts.append_array(entries[lane])
	else:
		# A lane that leads to the other site: cross over through its end.
		pts.append_array(entries.values()[0])
	# Each bot starts its lane from a slightly different line.
	var out := _route(pts)
	for i in out.size() - 1:
		out[i] = _free(out[i] + Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2)))
	return out


func _hold_spot(site: int, avoid: Array) -> Array:
	var holds: Array = SdMap.NAV["holds"][site]
	var free := holds.filter(func(h: Array) -> bool: return not avoid.has(h))
	var pick: Array = (free if not free.is_empty() else holds).pick_random()
	return pick


func _plan_round() -> void:
	plans.clear()
	_contact = [-100.0, -100.0]
	var nav: Dictionary = SdMap.NAV
	var att := bots.filter(func(b: Bot) -> bool: return b.team == attackers)
	var def := bots.filter(func(b: Bot) -> bool: return b.team != attackers)
	att.shuffle()
	def.shuffle()
	var defend_look := Vector3(0, 0, -30)
	# Attackers.
	var lurkers := 0
	for b: Bot in att:
		var role: String = "carrier" if b == carrier else ["entry", "entry", "support", "support", "support", "lurk"].pick_random()
		if role == "lurk" and lurkers >= maxi(1, att.size() / 3):
			role = "support"
		var site := target_site
		var lane: String = _lanes_to(site).pick_random()
		var plan: Dictionary
		match role:
			"carrier":
				var r := _attack_route(lane, site)
				r.append(_free(SdMap.SITES[site]))
				plan = _new_plan(role, r, defend_look, randf_range(0.3, 2.5))
			"entry":
				var r := _attack_route(lane, site)
				r.append(_site_point(site, 4.0))
				plan = _new_plan(role, r, defend_look, randf_range(0.0, 1.2))
				plan["pause_p"] = 0.08
			"support":
				# Often by another lane: a fake, or to pinch from two sides.
				if randf() < 0.4:
					lane = (nav["lanes"] as Dictionary).keys().pick_random()
				var r := _attack_route(lane, site)
				r.append(_site_point(site, 5.0))
				plan = _new_plan(role, r, defend_look, randf_range(2.0, 8.0))
			"lurk":
				lurkers += 1
				var spot: Array = (nav["lurk"] as Array).pick_random()
				var r := _route([spot[0]])
				plan = _new_plan(role, r, _v3(spot[1]), randf_range(0.0, 4.0))
				plan["until"] = clock + PREP_TIME + randf_range(25.0, 45.0)
		plan["site"] = site
		plans[b] = plan
	# Defenders: one anchor per site first, the rest pick their own job.
	var taken := []
	var forwards: Array = (nav["forward"] as Array).duplicate()
	forwards.shuffle()
	for i in def.size():
		var b: Bot = def[i]
		var role: String = "anchor" if i < 2 else ["anchor", "anchor", "forward", "forward", "rotator"].pick_random()
		if role == "forward" and forwards.is_empty():
			role = "anchor"
		var site := i % 2 if i < 2 else randi() % 2
		var plan: Dictionary
		match role:
			"anchor", "rotator":
				var hold := _hold_spot(site, taken)
				taken.append(hold)
				plan = _new_plan(role, _route([hold[0]]), _v3(hold[1]), randf_range(0.0, 1.5))
				plan["until"] = clock + PREP_TIME + randf_range(8.0, 18.0)
			"forward":
				var spot: Array = forwards.pop_back()
				plan = _new_plan(role, _route([spot[0]]), _v3(spot[1]), randf_range(0.0, 0.8))
				plan["until"] = clock + PREP_TIME + randf_range(14.0, 32.0)
				site = 0 if spot[0].x < 0.0 else 1
		plan["site"] = site
		plans[b] = plan


# The bomb lies on the ground: whoever of the attackers is closest goes for it.
func _on_bomb_dropped() -> void:
	var best: Bot = null
	var best_d := INF
	for b in bots:
		if b.team == attackers and b.alive:
			var d := b.global_position.distance_to(bomb_at)
			if d < best_d:
				best = b
				best_d = d
	if best != null:
		var plan := _new_plan("fetch", [_free(bomb_at)], bomb_at, randf_range(0.2, 1.0))
		plan["site"] = target_site
		plans[best] = plan


func _on_bomb_taken(t: Node3D) -> void:
	if t is Bot:
		var r := [_site_point(target_site, 0.5)]
		var plan := _new_plan("carrier", r, Vector3(0, 0, -30), 0.0)
		plan["site"] = target_site
		plan["pause_p"] = 0.05
		plans[t] = plan


# Planted: attackers spread over their own spots round the bomb; defenders come
# back for it, each in their own time and some by a spot near the site first.
func _on_planted() -> void:
	var nav: Dictionary = SdMap.NAV
	var spots: Array = (nav["postplant"][bomb_site] as Array).duplicate()
	spots.shuffle()
	for b in bots:
		if not b.alive:
			continue
		var plan: Dictionary
		if b.team == attackers:
			var spot: Array = spots.pop_back() if not spots.is_empty() else [Vector2(bomb_at.x, bomb_at.z), Vector2(0, -30)]
			plan = _new_plan("postplant", _route([spot[0]]), _v3(spot[1]), randf_range(0.0, 1.5))
		else:
			var r := []
			if randf() < 0.5:
				var hold := _hold_spot(bomb_site, [])
				r.append(_v3(hold[0]))
			r.append(_free(bomb_at + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))))
			plan = _new_plan("retake", r, bomb_at, randf_range(0.3, 3.0))
			plan["pause_p"] = 0.2
		plan["site"] = bomb_site
		plans[b] = plan


# Who is near which site, to react to (like hearing steps and shots there).
func _sense() -> void:
	for s in SdMap.SITES.size():
		var at: Vector3 = SdMap.SITES[s]
		for b in bots:
			if b.team == attackers and b.alive and b.global_position.distance_to(at) < 13.0:
				_contact[s] = clock
		if attackers == 0 and float(player.health) > 0.0 and player.global_position.distance_to(at) < 13.0:
			_contact[s] = clock


func _drive(dt: float) -> void:
	_sense_t -= dt
	if _sense_t <= 0.0:
		_sense_t = 0.5
		_sense()
	var nav: Dictionary = SdMap.NAV
	for b in bots:
		if not b.alive or not plans.has(b):
			continue
		var plan: Dictionary = plans[b]
		var route: Array = plan["route"]
		# Reacting to contact at a site, each with its own delay and its own mind.
		if b.team != attackers and phase == "live":
			for s in 2:
				if s != int(plan["site"]) and clock - float(_contact[s]) < 1.0 and float(plan["react_at"]) == INF:
					var keen := 0.9 if plan["role"] == "rotator" else (0.5 if plan["role"] == "forward" else 0.3)
					if randf() < keen:
						plan["react_at"] = clock + randf_range(0.4, 2.5)
						plan["react_site"] = s
					else:
						plan["react_at"] = -1.0      # decided to stay
			if float(plan["react_at"]) > 0.0 and float(plan["react_at"]) != INF and clock >= float(plan["react_at"]):
				var s: int = plan["react_site"]
				var hold := _hold_spot(s, [])
				var p2 := _new_plan("anchor", _route([hold[0]]), _v3(hold[1]), 0.0)
				p2["site"] = s
				p2["react_at"] = -1.0
				p2["until"] = clock + randf_range(10.0, 20.0)
				plans[b] = p2
				continue
		if float(plan["wait"]) > 0.0:
			plan["wait"] = float(plan["wait"]) - dt
			b.goal = b.global_position
			continue
		var i: int = plan["i"]
		if i < route.size():
			var to: Vector3 = route[i]
			b.goal = to
			var flat := Vector2(to.x - b.global_position.x, to.z - b.global_position.z)
			if flat.length() > 0.1:
				b.watch = Vector3(flat.x, 0.0, flat.y).normalized()
			if flat.length() < 1.6:
				plan["i"] = i + 1
				plan["stuck"] = 0.0
				# Stop and check the corner before going on.
				if i + 1 < route.size() and randf() < float(plan["pause_p"]):
					plan["wait"] = randf_range(0.5, 2.0)
			else:
				var last: Vector3 = plan["last"]
				if b.has_los or last == Vector3.INF or b.global_position.distance_to(last) > 0.05:
					plan["stuck"] = 0.0
				else:
					plan["stuck"] = float(plan["stuck"]) + dt
					if float(plan["stuck"]) > 2.5:
						plan["i"] = i + 1      # cannot get there: skip it
						plan["stuck"] = 0.0
			plan["last"] = b.global_position
			continue
		# Holding the end of the route.
		var look: Vector3 = plan["look"]
		var hold_at: Vector3 = route.back() if not route.is_empty() else b.global_position
		b.goal = hold_at
		var dir := Vector3(look.x - b.global_position.x, 0.0, look.z - b.global_position.z)
		if dir.length() > 0.1:
			b.watch = dir.normalized()
		if clock < float(plan["until"]):
			continue
		match plan["role"]:
			"anchor", "rotator":
				# Shift to another spot on the same site, so they are never quite where you expect.
				var hold := _hold_spot(int(plan["site"]), [])
				var p2 := _new_plan(plan["role"], _route([hold[0]]), _v3(hold[1]), 0.0)
				p2["site"] = plan["site"]
				p2["until"] = clock + randf_range(8.0, 18.0)
				p2["react_at"] = plan["react_at"]
				p2["hunt_after"] = plan["hunt_after"]
				plans[b] = p2
			"forward":
				# Fall back to the nearer site.
				var s := 0 if b.global_position.x < 0.0 else 1
				var hold := _hold_spot(s, [])
				var p2 := _new_plan("anchor", _route([hold[0]]), _v3(hold[1]), 0.0)
				p2["site"] = s
				p2["until"] = clock + randf_range(8.0, 18.0)
				p2["hunt_after"] = plan["hunt_after"]
				plans[b] = p2
			"lurk":
				# Done waiting: join the attack on the site.
				var p2 := _new_plan("support", [_site_point(target_site, 5.0)], Vector3(0, 0, -30), 0.0)
				p2["site"] = target_site
				p2["hunt_after"] = plan["hunt_after"]
				plans[b] = p2
