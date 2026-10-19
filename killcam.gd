extends Node

# Killcam. The match is recorded all the time (positions and facing of the player
# and the bots, every shot, hit and sound with where it came from), keeping the
# last few seconds. When the player is killed: a short death camera while the
# recording runs on, then the kill played back through the killer's eyes, with
# its weapon in view - BEFORE seconds before the kill to AFTER seconds after it -
# with shots, tracers, hitmarkers, deaths and sounds as they happened. At the end
# of a match the last kill is shown the same way (the final killcam), from the
# player's own eyes if the player made it. Then `finished` is emitted.

signal finished

const Bot := preload("res://bot.gd")
const Assets := preload("res://assets.gd")
const Viewmodel := preload("res://viewmodel.gd")
const Weapons := preload("res://weapons.gd")
const Hitmarker := preload("res://hitmarker.gd")
const Player := preload("res://player.gd")

const RATE := 30.0             # recorded frames per second
const KEEP := 16.0             # seconds kept
const BEFORE := 8.5
const AFTER := 1.5
const DEATH_CAM := 1.5         # = AFTER: the recording has to run on that long first

var player: Node3D
var bots: Array = []           # Bot nodes, in a fixed order
var time := 0.0
var frames: Array = []         # {t, p, yaw, pitch, eye, alive, bots: [[pos, yaw, alive], ...]}
var events: Array = []         # {t, kind ("shot"/"sound"/"hit"), who (-1 player / bot index), ...}
var _acc := 0.0

# Playback state.
var state := ""                # "", "death", "wait", "replay"
var killer := 0                # bot index, or -1 for the player
var victim := -2               # bot index, or -2 for the player
var final := false
var death_t := 0.0
var play_t := 0.0
var _phase_t := 0.0
var _next_event := 0
var cam: Camera3D
var avatar: Bot
var vm: Viewmodel
var _kick := 0.0
var _look := Basis.IDENTITY
var _shown_w := {}
var _step := 0.0
var _run := 0.0
var _turn_lag := 0.0
var _saved := []               # live bot state to put back afterwards
var overlay: CanvasLayer
var _title: Label
var _sub: Label
var _bar: ProgressBar
var _hitmarker: Hitmarker
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_i := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.012
	cam.cull_mask = 1 | 2
	add_child(cam)
	for i in 12:
		var v := AudioStreamPlayer3D.new()
		v.unit_size = 6.0
		v.max_db = 3.0
		add_child(v)
		_voices.append(v)
	_build_overlay()


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 30
	overlay.visible = false
	add_child(overlay)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0, 0, 0, 0.45)
	bar_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar_bg.size = Vector2(0, 92)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(bar_bg)
	_title = Label.new()
	_title.text = "KILLCAM"
	_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title.position = Vector2(-300, 8)
	_title.size = Vector2(600, 50)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color(0.95, 0.3, 0.22))
	overlay.add_child(_title)
	_sub = Label.new()
	_sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub.position = Vector2(-300, 54)
	_sub.size = Vector2(600, 30)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 20)
	overlay.add_child(_sub)
	var centre := Control.new()
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(centre)
	_hitmarker = Hitmarker.new()
	centre.add_child(_hitmarker)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.position = Vector2(-260, -70)
	_bar.size = Vector2(520, 8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.3, 0.22)
	_bar.add_theme_stylebox_override("fill", fill)
	overlay.add_child(_bar)
	var hint := Label.new()
	hint.text = "Leertaste / A: überspringen"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-200, -56)
	hint.size = Vector2(400, 26)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	overlay.add_child(hint)


# --- recording ------------------------------------------------------------------

func add_bot(b: Bot) -> void:
	bots.append(b)
	var who := bots.size() - 1
	b.fired.connect(func(from: Vector3, to: Vector3) -> void:
		if state != "replay":
			events.append({"t": time, "kind": "shot", "who": who, "from": from, "to": to}))
	b.sounded.connect(func(file: String, at: Vector3, db: float) -> void:
		if state != "replay":
			events.append({"t": time, "kind": "sound", "who": who, "file": file, "at": at, "db": db}))
	# Hits: the bot's on the player, and the player's on the bot.
	b.landed.connect(func(killed: bool) -> void:
		if state != "replay":
			events.append({"t": time, "kind": "hit", "who": who, "head": false, "killed": killed}))
	b.was_hit.connect(func(head: bool, killed: bool) -> void:
		if state != "replay":
			events.append({"t": time, "kind": "hit", "who": -1, "head": head, "killed": killed}))


func watch_player(p: Node3D) -> void:
	player = p
	p.connect("shot_fired", func(to: Vector3) -> void:
		if state != "replay":
			events.append({"t": time, "kind": "shot", "who": -1, "from": p.global_position + Vector3.UP * 1.4, "to": to}))
	p.connect("sound_played", func(file: String, db: float) -> void:
		if state != "replay":
			events.append({"t": time, "kind": "sound", "who": -1, "file": file, "db": db}))


func _physics_process(dt: float) -> void:
	if state == "replay":
		return
	time += dt
	_acc += dt
	if _acc < 1.0 / RATE or player == null:
		return
	_acc = 0.0
	var bot_states := []
	for b: Bot in bots:
		bot_states.append([b.global_position, b.rotation.y, b.alive])
	# What the player saw: the real camera (bob, tilt, zoom) and the weapon and arms
	# exactly as they were - tac sprint, reload, inspect, bolt, throws, all of it.
	var pcam: Camera3D = player.get("cam")
	var pvm: Viewmodel = player.get("vmodel")
	frames.append({"t": time, "p": player.global_position, "yaw": float(player.get("yaw")),
			"pitch": float(player.get("pitch")), "eye": (player.get("head") as Node3D).position.y,
			"alive": float(player.get("health")) > 0.0, "bots": bot_states,
			"cam": pcam.global_transform, "fov": pcam.fov, "view": pvm.snapshot(), "w": player.get("w"),
			"vm_fov": float(player.get("vm_fov"))})
	while not frames.is_empty() and frames[0]["t"] < time - KEEP:
		frames.pop_front()
	while not events.is_empty() and events[0]["t"] < time - KEEP:
		events.pop_front()


# --- playback --------------------------------------------------------------------

# A kill has just happened. by: the bot that killed the player, or -1 when the
# player made the kill (only shown as the final killcam). last: end of the match.
func start(by: int, last := false, vic := -2) -> void:
	killer = by if by < 0 else clampi(by, 0, maxi(bots.size() - 1, 0))
	victim = vic
	final = last
	death_t = time
	_phase_t = 0.0
	if killer < 0 or last:
		state = "wait"          # the player lives on; the recording just runs a moment longer
		return
	state = "death"
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false          # no arms or legs of your own in the death camera
	cam.global_transform = (player.get("cam") as Camera3D).global_transform
	cam.make_current()


func _process(dt: float) -> void:
	match state:
		"death":
			_death_cam(dt)
		"wait":
			_phase_t += dt
			if _phase_t >= AFTER:
				cam.make_current()
				_begin_replay()
		"replay":
			_replay(dt)


# The view drops to the ground and turns to the killer while the recording runs on.
func _death_cam(dt: float) -> void:
	_phase_t += dt
	var k := smoothstep(0.0, 0.7, _phase_t)
	var from: Vector3 = player.global_position + Vector3.UP * 1.6
	var at := from.lerp(player.global_position + Vector3.UP * 0.35, k)
	var foe: Bot = bots[killer]
	var look := foe.global_position + Vector3.UP * 1.3
	if at.distance_to(look) > 0.2:
		var target := Transform3D().looking_at(look - at, Vector3.UP)
		cam.global_transform = Transform3D(cam.global_basis.slerp(target.basis.rotated(target.basis.z, deg_to_rad(18.0) * k), 1.0 - exp(-5.0 * dt)), at)
	if _phase_t >= DEATH_CAM:
		_begin_replay()


func _begin_replay() -> void:
	state = "replay"
	overlay.visible = true
	_title.text = "FINAL KILLCAM" if final else "KILLCAM"
	var victim_name: String = "dich" if victim == -2 else str(bots[victim].get("bot_name"))
	if killer < 0:
		_sub.text = "Du hast %s ausgeschaltet" % victim_name
	else:
		_sub.text = "%s  hat %s ausgeschaltet" % [bots[killer].get("bot_name"), victim_name]
	play_t = maxf(death_t - BEFORE, frames[0]["t"] if not frames.is_empty() else death_t)
	_next_event = 0
	while _next_event < events.size() and events[_next_event]["t"] < play_t:
		_next_event += 1
	# The bots stop thinking and are moved along the recording instead.
	_saved.clear()
	for b: Bot in bots:
		_saved.append([b.global_transform, b.alive, b.remote, b.health])
		b.remote = true
	avatar = Bot.new()
	avatar.remote = true
	avatar.band_color = Color(0.1, 0.35, 0.85)
	avatar.collision_layer = 0
	avatar.collision_mask = 0
	add_child(avatar)
	player.visible = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	# The killer's own weapon in view: the player's current one, or the bots' rifle.
	vm = Viewmodel.new()
	cam.add_child(vm)
	var w: Dictionary = (player.get("w") as Dictionary) if killer < 0 else Weapons.build("ar", {})
	vm.set_weapon(w, bool(w.get("plain_hold", false)))
	vm.set_fov(55.0)
	_shown_w = w
	_step = 0.0
	_run = 0.0
	_turn_lag = 0.0
	vm.position = Player.GUN_HIP + Player.HOLD_CLOSER
	vm.rotation = Vector3(0.0, deg_to_rad(2.5), deg_to_rad(-2.0))
	# Inside the killer's head: its own body is hidden.
	if killer >= 0:
		(bots[killer] as Bot).body.visible = false
	else:
		avatar.body.visible = false
	_look = cam.global_basis


func _replay(dt: float) -> void:
	if Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A):
		play_t = death_t + AFTER
	play_t += dt
	var end_t := death_t + AFTER
	var start_t := end_t - BEFORE - AFTER
	_bar.value = clampf((play_t - start_t) / (end_t - start_t), 0.0, 1.0) * 100.0
	var f := _frame_at(play_t)
	if f.is_empty():
		_finish()
		return
	# The player's figure.
	avatar.net_pos = f["p"]
	avatar.net_yaw = f["yaw"]
	if bool(f["alive"]) == not avatar.alive:
		avatar.set_dead(not bool(f["alive"]))
	# The bots.
	var states: Array = f["bots"]
	for i in mini(states.size(), bots.size()):
		var b: Bot = bots[i]
		b.net_pos = states[i][0]
		b.net_yaw = states[i][1]
		if bool(states[i][2]) == not b.alive:
			b.set_dead(not bool(states[i][2]))
	# Shots, hits and sounds, at the moment they happened.
	while _next_event < events.size() and events[_next_event]["t"] <= play_t:
		_fire_event(events[_next_event], f)
		_next_event += 1
	# Through the killer's eyes.
	if killer < 0:
		_player_view(f)
	else:
		_bot_view(f, dt)
	if play_t >= end_t:
		_finish()


# The player as killer: camera, weapon and arms exactly as recorded.
func _player_view(f: Dictionary) -> void:
	var a: Dictionary = f.get("_a", f)
	var k := float(f.get("_k", 0.0))
	cam.global_transform = (a["cam"] as Transform3D).interpolate_with(f["cam"], k)
	cam.fov = lerpf(float(a["fov"]), float(f["fov"]), k)
	if vm == null:
		return
	if f["w"] != _shown_w:
		_shown_w = f["w"]
		vm.set_weapon(_shown_w, bool(_shown_w.get("plain_hold", false)))
		vm.set_fov(float(f["vm_fov"]))
	vm.apply_snapshot(a["view"], f["view"], k)


# A bot as killer: it has no animations of its own, so its weapon moves with how
# it moves - steps, a lowered rifle when running, lag when it turns, recoil.
func _bot_view(f: Dictionary, dt: float) -> void:
	var foe: Bot = bots[killer]
	var a: Dictionary = f.get("_a", f)
	var speed := 0.0
	var turn := 0.0
	var span := maxf(float(f["t"]) - float(a["t"]), 0.0001)
	if (a["bots"] as Array).size() > killer and (f["bots"] as Array).size() > killer:
		var pa: Vector3 = a["bots"][killer][0]
		var pb: Vector3 = f["bots"][killer][0]
		speed = Vector2(pb.x - pa.x, pb.z - pa.z).length() / span
		turn = angle_difference(float(a["bots"][killer][1]), float(f["bots"][killer][1])) / span
	_step += speed * dt * 2.2
	_run = lerpf(_run, clampf((speed - 2.0) / 2.5, 0.0, 1.0), 1.0 - exp(-6.0 * dt))
	_turn_lag = lerpf(_turn_lag, clampf(turn, -4.0, 4.0), 1.0 - exp(-8.0 * dt))
	var eye := foe.global_position + Vector3.UP * (1.62 + sin(_step * 2.0) * 0.012 * minf(speed / 4.0, 1.0))
	var aim := Vector3(-sin(foe.rotation.y), 0.0, -cos(foe.rotation.y))
	var prey: Bot = avatar if victim == -2 or victim >= bots.size() else bots[victim]
	var to_victim: Vector3 = (prey.global_position + Vector3.UP * 1.2) - eye
	if prey.alive and to_victim.length() > 0.5 and to_victim.normalized().dot(aim) > 0.6:
		aim = aim.slerp(to_victim.normalized(), 0.9 * (1.0 - _run))
	var aim_basis := Transform3D().looking_at(aim, Vector3.UP).basis
	aim_basis = aim_basis * Basis(Vector3.BACK, sin(_step) * 0.012 * minf(speed / 4.0, 1.0))
	_look = _look.slerp(aim_basis, 1.0 - exp(-18.0 * dt))
	cam.global_transform = Transform3D(_look, eye)
	_kick = move_toward(_kick, 0.0, dt * 0.6)
	if vm == null:
		return
	var bob := Vector3(sin(_step) * 0.012, -absf(cos(_step)) * 0.014, 0.0) * minf(speed / 4.0, 1.0)
	var run_pos := Vector3(0.02, -0.05, 0.03) * _run
	var run_rot := Vector3(deg_to_rad(-18.0), deg_to_rad(28.0), deg_to_rad(12.0)) * _run
	vm.position = Player.GUN_HIP + Player.HOLD_CLOSER + bob + run_pos + Vector3(-_turn_lag * 0.006, 0.0, _kick)
	vm.rotation = Vector3(deg_to_rad(0.0), deg_to_rad(2.5), deg_to_rad(-2.0)) + run_rot \
			+ Vector3(_kick * 1.5, -_turn_lag * 0.025, -_turn_lag * 0.04)


func _fire_event(e: Dictionary, f: Dictionary) -> void:
	var who: int = e["who"]
	var source: Node3D = avatar if who < 0 else (bots[who] if who < bots.size() else null)
	match str(e["kind"]):
		"shot":
			if who == killer and vm != null:
				if killer < 0:
					var w: Dictionary = f["w"]
					vm.fire_flash(bool(w.get("side_flash", false)), float(w.get("flash_bright", 1.0)))
				else:
					vm.fire_flash(false)
					_kick = minf(_kick + 0.035, 0.08)
			elif source is Bot:
				(source as Bot).show_shot(e["to"])
			return
		"hit":
			if who == killer:
				_hitmarker.mark(bool(e["killed"]), bool(e["head"]))
			return
	var stream := Assets.sound(str(e["file"]).replace(".wav", "_%d.wav" % (randi() % 4)))
	if stream == null:
		return
	var v := _voices[_voice_i]
	_voice_i = (_voice_i + 1) % _voices.size()
	v.stream = stream
	v.volume_db = float(e["db"]) + 4.0
	v.pitch_scale = randf_range(0.97, 1.03)
	v.global_position = e["at"] if e.has("at") else (f["p"] as Vector3) + Vector3.UP * 1.4
	v.play()


# The recorded state at time t, interpolated between frames.
func _frame_at(t: float) -> Dictionary:
	if frames.is_empty():
		return {}
	if t <= frames[0]["t"]:
		return frames[0]
	for i in range(1, frames.size()):
		var b: Dictionary = frames[i]
		if b["t"] >= t:
			var a: Dictionary = frames[i - 1]
			var k := (t - float(a["t"])) / maxf(float(b["t"]) - float(a["t"]), 0.0001)
			var out := b.duplicate()
			out["p"] = (a["p"] as Vector3).lerp(b["p"], k)
			out["yaw"] = lerp_angle(float(a["yaw"]), float(b["yaw"]), k)
			out["pitch"] = lerpf(float(a["pitch"]), float(b["pitch"]), k)
			out["eye"] = lerpf(float(a["eye"]), float(b["eye"]), k)
			var mixed := []
			for j in (b["bots"] as Array).size():
				var sa: Array = a["bots"][j] if j < (a["bots"] as Array).size() else b["bots"][j]
				var sb: Array = b["bots"][j]
				mixed.append([(sa[0] as Vector3).lerp(sb[0], k), lerp_angle(float(sa[1]), float(sb[1]), k), sb[2]])
			out["bots"] = mixed
			out["_a"] = a
			out["_k"] = k
			return out
	return frames[-1]


func _finish() -> void:
	state = ""
	overlay.visible = false
	for v in _voices:
		v.stop()
	if avatar != null:
		avatar.queue_free()
		avatar = null
	if vm != null:
		vm.queue_free()
		vm = null
	for i in mini(_saved.size(), bots.size()):
		var b: Bot = bots[i]
		var s: Array = _saved[i]
		b.body.visible = true
		b.remote = s[2]
		b.net_pos = (s[0] as Transform3D).origin
		b.global_transform = s[0]
		b.set_dead(not bool(s[1]))
		b.alive = s[1]
		b.health = s[3]
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_INHERIT
	(player.get("cam") as Camera3D).make_current()
	# Nothing from the replay is kept in the recording.
	frames.clear()
	events.clear()
	finished.emit()
