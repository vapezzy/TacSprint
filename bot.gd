extends CharacterBody3D

# A computer-controlled soldier. In the 1v1 it hunts the player through the
# container yard on a grid; once it has a clear line of sight it stops to strafe
# and fire in bursts, and it respawns far away. In a team game (Search and
# Destroy) it belongs to a team, picks the nearest enemy it can see from either
# side, goes where the game sends it (`goal`), and stays down when it dies.

signal died
signal headshot
signal remote_hit(damage: float)
signal was_hit(headshot: bool, killed: bool)
signal fired(from: Vector3, to: Vector3)
signal landed(killed: bool)          # one of its shots hit the player
signal sounded(file: String, at: Vector3, volume_db: float)

const Assets := preload("res://assets.gd")
const Arena := preload("res://arena.gd")

const CELL := 0.5
const SPEED := 4.3
const STRAFE_SPEED := 2.4
const MAX_HEALTH := 130.0
const HEAD_HEIGHT := 1.5		# hits above this count as headshots
const HEAD_MULTIPLIER := 1.5
const DAMAGE := 13.0
const SHOT_INTERVAL := 0.1
const REACTION := 0.4
const SIGHT_RANGE := 45.0
const EYE := 1.55

var target: CharacterBody3D       # the player
var health := MAX_HEALTH
var alive := true
var has_los := false
var travelled := 0.0
var shots := 0
var last_shot_ms := -100000

var grid: AStarGrid2D
var path: PackedVector2Array = PackedVector2Array()
var path_i := 0
var repath := 0.0
var seen_for := 0.0
var burst_left := 0
var shot_cd := 0.0
var pause := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var step := 0.0
var respawn_in := 0.0

# In a LAN game this figure stands for the other player: no thinking, it just
# follows the positions that arrive over the network.
var remote := false
var blind_t := 0.0
var stun_t := 0.0
var fall: Tween
var net_pos := Vector3.ZERO
var net_yaw := 0.0
var rng := RandomNumberGenerator.new()
var bot_name := "Gegner"
var band_color := Color(0.7, 0.08, 0.06)
var _voice: AudioStreamPlayer3D

# Team games.
var team := 1                     # the player's side is 0
var game: Node                    # the mode running it (enemies_of); null in the 1v1
var respawns := true
var bounds := Arena.BOUNDS        # the walkable area of the map
var goal := Vector3.INF           # where to go when no enemy is in sight
var watch := Vector3.ZERO         # which way to look while holding a spot
var skill := 1.0                  # aim and reaction: 0.6 easy, 1 normal, 1.35 hard
var frozen := false               # before a round starts
var last_seen := Vector3.ZERO
var last_seen_t := -100.0
var last_attacker: Node           # who shot it last (null: the player)
var clock := 0.0
var _pick_t := 0.0
var _path_to := Vector3.INF

var body: Node3D
var legs: Array[MeshInstance3D] = []
var flash: OmniLight3D
var tracer: MeshInstance3D
var muzzle: Node3D
var flash_mat: StandardMaterial3D


func _ready() -> void:
	rng.randomize()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.9
	add_child(col)
	floor_snap_length = 0.3
	_build_body()


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


func _build_body() -> void:
	body = Node3D.new()
	add_child(body)
	# A different uniform from the player's: plain dark grey with a red armband.
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.16, 0.17, 0.18)
	cloth.roughness = 0.95
	cloth.normal_enabled = true
	cloth.normal_texture = Assets.tex("denim_fabric_nor_gl.jpg")
	cloth.uv1_triplanar = true
	cloth.uv1_scale = Vector3.ONE * 3.0
	var gear := StandardMaterial3D.new()
	gear.albedo_color = Color(0.03, 0.03, 0.035)
	gear.roughness = 0.8
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.5, 0.36, 0.28)
	skin.roughness = 0.7
	var band := StandardMaterial3D.new()
	band.albedo_color = band_color
	band.roughness = 0.8

	for side: float in [-1.0, 1.0]:
		var leg := _part(body, _capsule(0.085, 0.86), cloth, Vector3(side * 0.11, 0.45, 0))
		legs.append(leg)
		var boot := BoxMesh.new()
		boot.size = Vector3(0.11, 0.1, 0.27)
		_part(leg, boot, gear, Vector3(0, -0.4, -0.05))
	_part(body, _capsule(0.19, 0.7), cloth, Vector3(0, 1.17, 0))
	var vest := BoxMesh.new()
	vest.size = Vector3(0.42, 0.42, 0.3)
	_part(body, vest, gear, Vector3(0, 1.2, 0))
	var head := SphereMesh.new()
	head.radius = 0.11
	head.height = 0.24
	_part(body, head, skin, Vector3(0, 1.64, 0))
	var helmet := SphereMesh.new()
	helmet.radius = 0.135
	helmet.height = 0.2
	_part(body, helmet, gear, Vector3(0, 1.7, 0.01))
	# Arms raised to the weapon.
	_part(body, _capsule(0.06, 0.6), cloth, Vector3(0.2, 1.3, -0.2), Vector3(deg_to_rad(-70.0), 0, deg_to_rad(-12.0)))
	_part(body, _capsule(0.06, 0.66), cloth, Vector3(-0.17, 1.3, -0.27), Vector3(deg_to_rad(-72.0), 0, deg_to_rad(22.0)))
	var ring := CylinderMesh.new()
	ring.top_radius = 0.068
	ring.bottom_radius = 0.068
	ring.height = 0.07
	_part(body, ring, band, Vector3(0.21, 1.36, -0.07), Vector3(deg_to_rad(-70.0), 0, deg_to_rad(-12.0)))
	var gun := BoxMesh.new()
	gun.size = Vector3(0.05, 0.1, 0.62)
	_part(body, gun, gear, Vector3(0.06, 1.38, -0.5))
	var mag := BoxMesh.new()
	mag.size = Vector3(0.035, 0.17, 0.06)
	_part(body, mag, gear, Vector3(0.06, 1.27, -0.45), Vector3(deg_to_rad(-12.0), 0, 0))

	muzzle = Node3D.new()
	muzzle.position = Vector3(0.06, 1.38, -0.84)
	body.add_child(muzzle)
	flash = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.45)
	flash.omni_range = 6.0
	flash.light_energy = 0.0
	muzzle.add_child(flash)

	_voice = AudioStreamPlayer3D.new()
	_voice.max_polyphony = 6
	_voice.unit_size = 7.0
	muzzle.add_child(_voice)

	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.8)
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer = MeshInstance3D.new()
	var line := BoxMesh.new()
	line.size = Vector3(0.012, 0.012, 1.0)
	tracer.mesh = line
	tracer.material_override = flash_mat
	tracer.top_level = true
	tracer.visible = false
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer)


# --- finding the way -----------------------------------------------------------

func _build_grid() -> void:
	grid = build_grid(get_world_3d(), bounds, [get_rid(), target.get_rid()] if target != null else [get_rid()])


# A walking grid over `area`: a cell is blocked where a standing body would not fit.
static func build_grid(world: World3D, area: Rect2, exclude: Array[RID]) -> AStarGrid2D:
	var space := world.direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.exclude = exclude
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, int(area.size.x / CELL), int(area.size.y / CELL))
	g.cell_size = Vector2(CELL, CELL)
	g.offset = area.position + Vector2(CELL, CELL) / 2.0
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	for z in g.region.size.y:
		for x in g.region.size.x:
			var at := g.offset + Vector2(x, z) * CELL
			q.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, 0.95, at.y))
			if not space.intersect_shape(q, 1).is_empty():
				g.set_point_solid(Vector2i(x, z), true)
	return g


func _cell(pos: Vector3) -> Vector2i:
	var b := bounds
	var c := Vector2i(int((pos.x - b.position.x) / CELL), int((pos.z - b.position.y) / CELL))
	c = c.clamp(Vector2i.ZERO, grid.region.size - Vector2i.ONE)
	if not grid.is_point_solid(c):
		return c
	# Standing against a wall: take the nearest free cell.
	for r in range(1, 5):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dz)
				if grid.region.has_point(n) and not grid.is_point_solid(n):
					return n
	return c


# A free spot at least min_dist away from `from`, for respawning.
func far_point(from: Vector3, min_dist := 18.0) -> Vector3:
	if grid == null:
		_build_grid()
	for attempt in 200:
		var c := Vector2i(rng.randi_range(2, grid.region.size.x - 3), rng.randi_range(2, grid.region.size.y - 3))
		if grid.is_point_solid(c):
			continue
		var at := grid.offset + Vector2(c) * CELL
		var p := Vector3(at.x, 0.05, at.y)
		if p.distance_to(from) >= min_dist - attempt * 0.05:
			# It has to connect to where the other one stands.
			if not grid.get_id_path(c, _cell(from)).is_empty():
				return p
	return Vector3(Arena.SPAWN.x, 0.05, Arena.SPAWN.z)


func blind(seconds: float) -> void:
	blind_t = maxf(blind_t, seconds)


func stun(seconds: float) -> void:
	stun_t = maxf(stun_t, seconds)


func respawn() -> void:
	reset_at(far_point(target.global_position), rotation.y)


# Back on its feet at `at` (a new round, or a respawn).
func reset_at(at: Vector3, yaw: float) -> void:
	blind_t = 0.0
	stun_t = 0.0
	global_position = at
	net_pos = at
	rotation.y = yaw
	velocity = Vector3.ZERO
	health = MAX_HEALTH
	alive = true
	if fall != null:
		fall.kill()
	body.rotation = Vector3.ZERO
	body.position = Vector3.ZERO
	path = PackedVector2Array()
	seen_for = 0.0
	burst_left = 0
	last_seen_t = -100.0
	last_attacker = null
	collision_layer = 1


# --- being shot ------------------------------------------------------------------

# from_team: who fired (-1 = the player, whose team is 0). attacker: the bot that
# fired, or null for the player. Nobody hurts their own side.
func hit(damage := 25.0, at := Vector3.ZERO, from_team := -1, attacker: Node = null) -> void:
	if not alive:
		return
	var shooter_team := 0 if from_team < 0 else from_team
	if shooter_team == team and not remote:
		return
	var by_player := from_team < 0
	var head := at != Vector3.ZERO and at.y - global_position.y > HEAD_HEIGHT
	if head:
		damage *= HEAD_MULTIPLIER
		if by_player:
			headshot.emit()
	if remote:
		# The other player's own game decides what the hit does to them.
		was_hit.emit(head, false)
		remote_hit.emit(damage)
		return
	health -= damage
	last_attacker = attacker
	if by_player:
		was_hit.emit(head, health <= 0.0)
	# Being shot at makes it turn on the shooter at once.
	seen_for = maxf(seen_for, REACTION * 0.6)
	if attacker is Node3D:
		last_seen = (attacker as Node3D).global_position
		last_seen_t = clock
	elif by_player and target != null:
		last_seen = target.global_position
		last_seen_t = clock
	if health <= 0.0:
		alive = false
		collision_layer = 0
		respawn_in = 2.2
		tracer.visible = false
		fall = create_tween()
		fall.tween_property(body, "rotation:x", deg_to_rad(-88.0), 0.35).set_ease(Tween.EASE_IN)
		fall.parallel().tween_property(body, "position:y", 0.12, 0.35)
		died.emit()


# --- thinking --------------------------------------------------------------------

func _alive(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node is CharacterBody3D and node.get("alive") != null:
		return bool(node.get("alive"))
	return float(node.get("health")) > 0.0


func _sees(node: Node3D) -> bool:
	var from := global_position + Vector3.UP * EYE
	var height := 1.4
	if node.get("capsule") != null:
		height = float(node.get("capsule").height) - 0.25
	var to := node.global_position + Vector3.UP * height
	if from.distance_to(to) > SIGHT_RANGE:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [get_rid(), (node as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _sees_target() -> bool:
	return target != null and _alive(target) and _sees(target)


# In a team game: the nearest enemy it can see, or the nearest one at all.
func _pick_target() -> void:
	var enemies: Array = game.call("enemies_of", self)
	var best: Node3D = null
	var best_d := INF
	var seen := false
	for e: Node3D in enemies:
		var d := global_position.distance_to(e.global_position)
		var visible_now := blind_t <= 0.0 and d < SIGHT_RANGE and _sees(e)
		# Something it can see always beats something it cannot.
		if (visible_now and not seen) or (visible_now == seen and d < best_d):
			best = e
			best_d = d
			seen = visible_now
	target = best
	has_los = seen
	if seen:
		last_seen = best.global_position
		last_seen_t = clock


# Shows or hides the fallen pose for the remote player.
func set_dead(dead: bool) -> void:
	alive = not dead
	collision_layer = 0 if dead else 1
	tracer.visible = false
	if fall != null:
		fall.kill()
	if dead:
		fall = create_tween()
		fall.tween_property(body, "rotation:x", deg_to_rad(-88.0), 0.35).set_ease(Tween.EASE_IN)
		fall.parallel().tween_property(body, "position:y", 0.12, 0.35)
	else:
		body.rotation = Vector3.ZERO
		body.position = Vector3.ZERO
		global_position = net_pos


# A shot fired by the remote player: flash and tracer from this figure's muzzle.
func show_shot(to: Vector3) -> void:
	last_shot_ms = Time.get_ticks_msec()
	flash.light_energy = 2.0
	var from := muzzle.global_position
	if from.distance_to(to) < 0.1:
		return
	tracer.global_transform = Transform3D(Basis.looking_at(to - from, Vector3.UP).scaled(Vector3(1, 1, from.distance_to(to))), (from + to) / 2.0)
	tracer.visible = true


func _remote_step(dt: float) -> void:
	flash.light_energy = move_toward(flash.light_energy, 0.0, dt * 40.0)
	if tracer.visible and flash.light_energy < 0.6:
		tracer.visible = false
	if not alive:
		return
	var before := global_position
	# Far off (a respawn): jump there. Otherwise glide, so 30 updates a second look smooth.
	if global_position.distance_to(net_pos) > 4.0:
		global_position = net_pos
	else:
		global_position = global_position.lerp(net_pos, 1.0 - exp(-18.0 * dt))
	rotation.y = lerp_angle(rotation.y, net_yaw, 1.0 - exp(-18.0 * dt))
	var moved := (global_position - before).length()
	step += moved * 3.2
	var swing := sin(step) * 0.5 * clampf(moved / maxf(dt, 0.0001) / SPEED, 0.0, 1.0)
	legs[0].rotation.x = swing
	legs[1].rotation.x = -swing


func _physics_process(dt: float) -> void:
	if remote:
		_remote_step(dt)
		return
	clock += dt
	if game == null and target == null:
		return
	if grid == null:
		_build_grid()
		respawn()
	flash.light_energy = move_toward(flash.light_energy, 0.0, dt * 40.0)
	if tracer.visible and flash.light_energy < 0.6:
		tracer.visible = false
	if not alive:
		if respawns:
			respawn_in -= dt
			if respawn_in <= 0.0:
				respawn()
		return
	if frozen:
		velocity = Vector3.ZERO
		return

	blind_t = maxf(blind_t - dt, 0.0)
	stun_t = maxf(stun_t - dt, 0.0)
	if game != null:
		_pick_t -= dt
		if _pick_t <= 0.0:
			_pick_t = 0.2
			_pick_target()
	else:
		# Blinded it cannot see you; it stumbles about instead.
		has_los = blind_t <= 0.0 and _sees_target()
	var wish := Vector3.ZERO
	var face := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var dist := 999.0

	if has_los and target != null:
		var to_target := target.global_position - global_position
		var flat := Vector3(to_target.x, 0, to_target.z)
		dist = flat.length()
		face = flat
		seen_for += dt
		# In sight: keep some distance and sidestep, changing side now and then.
		strafe_t -= dt
		if strafe_t <= 0.0:
			strafe_t = rng.randf_range(0.7, 1.6)
			strafe_dir = -strafe_dir if rng.randf() < 0.7 else strafe_dir
		var side := flat.normalized().cross(Vector3.UP) * strafe_dir
		wish = side * STRAFE_SPEED
		if dist > 14.0:
			wish += flat.normalized() * SPEED * 0.7
		elif dist < 5.0:
			wish -= flat.normalized() * STRAFE_SPEED
		_fire_control(dt, dist)
	else:
		seen_for = maxf(seen_for - dt * 2.0, 0.0)
		burst_left = 0
		# Where to go: in a team game the last place an enemy was seen (for a while),
		# otherwise its goal; in the 1v1 straight for the player.
		var dest := Vector3.INF
		if game == null:
			dest = target.global_position
		elif clock - last_seen_t < 4.0 and global_position.distance_to(last_seen) > 2.0:
			dest = last_seen
		elif goal != Vector3.INF:
			dest = goal
		if dest != Vector3.INF and Vector2(dest.x - global_position.x, dest.z - global_position.z).length() > 1.2:
			repath -= dt
			if repath <= 0.0 or path_i >= path.size() or _path_to.distance_to(dest) > 1.5:
				repath = 0.6
				_path_to = dest
				path = grid.get_point_path(_cell(global_position), _cell(dest))
				path_i = 1
			if path_i < path.size():
				var next := Vector3(path[path_i].x, global_position.y, path[path_i].y)
				var leg := next - global_position
				leg.y = 0.0
				if leg.length() < 0.3:
					path_i += 1
				else:
					wish = leg.normalized() * SPEED
					face = leg
		elif game != null:
			# Holding its spot: look out the way it is told to watch.
			if watch != Vector3.ZERO:
				face = watch

	if blind_t > 0.0:
		wish = Vector3(sin(blind_t * 3.0), 0, cos(blind_t * 2.3)) * 1.2
	if stun_t > 0.0:
		wish *= 0.3
	velocity.x = move_toward(velocity.x, wish.x, 30.0 * dt)
	velocity.z = move_toward(velocity.z, wish.z, 30.0 * dt)
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * dt
	var before := global_position
	move_and_slide()
	var moved := (global_position - before).length()
	travelled += moved

	if face.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-10.0 * dt))
	# Legs swing with the ground covered.
	step += moved * 3.2
	var swing := sin(step) * 0.5 * clampf(moved / maxf(dt, 0.0001) / SPEED, 0.0, 1.0)
	legs[0].rotation.x = swing
	legs[1].rotation.x = -swing


func _fire_control(dt: float, dist: float) -> void:
	pause -= dt
	shot_cd -= dt
	if seen_for < REACTION / skill or pause > 0.0:
		return
	if burst_left <= 0:
		burst_left = rng.randi_range(3, 6)
	if shot_cd > 0.0:
		return
	shot_cd = SHOT_INTERVAL
	burst_left -= 1
	if burst_left <= 0:
		pause = rng.randf_range(0.45, 0.95)
	shots += 1
	last_shot_ms = Time.get_ticks_msec()

	# The further away and the faster the target moves, the more it misses.
	var chance := clampf(0.5 - dist * 0.011, 0.14, 0.5) * skill
	if target.has_method("speed_h") and float(target.call("speed_h")) > 5.0:
		chance *= 0.6
	if stun_t > 0.0:
		chance *= 0.3
	var aim := target.global_position + Vector3.UP * 1.2
	var from := muzzle.global_position
	if rng.randf() < chance:
		if target.has_method("hurt"):
			target.set("last_hurt_by", self)
			target.call("hurt", DAMAGE, global_position)
			landed.emit(float(target.get("health")) <= 0.0)
		else:
			target.call("hit", DAMAGE, aim + Vector3.UP * (0.4 if rng.randf() < 0.12 * skill else 0.0), team, self)
	else:
		aim += Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.8), rng.randf_range(-1.0, 1.0)) * 0.9
		var q := PhysicsRayQueryParameters3D.create(from, from + (aim - from).normalized() * 80.0)
		q.collision_mask = 1
		q.exclude = [get_rid(), (target as CollisionObject3D).get_rid()]
		var hit_info := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit_info.is_empty():
			aim = hit_info["position"]
	flash.light_energy = 2.0
	_sound("ar_shot.wav", -1.0)
	fired.emit(from, aim)
	var length := from.distance_to(aim)
	tracer.global_transform = Transform3D(Basis.looking_at(aim - from, Vector3.UP).scaled(Vector3(1, 1, length)), (from + aim) / 2.0)
	tracer.visible = true


# Its own gunfire, heard from where it stands; one of the recorded takes each time.
func _sound(file: String, volume_db: float) -> void:
	var stream := Assets.sound(file.replace(".wav", "_%d.wav" % rng.randi_range(0, 3)))
	if stream == null:
		return
	_voice.stream = stream
	_voice.volume_db = volume_db + rng.randf_range(-1.5, 1.5)
	_voice.pitch_scale = rng.randf_range(0.96, 1.04)
	_voice.play()
	sounded.emit(file, muzzle.global_position, volume_db)
