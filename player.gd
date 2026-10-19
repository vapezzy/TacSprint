extends CharacterBody3D

const Viewmodel := preload("res://viewmodel.gd")
const Pose := preload("res://pose.gd")
const Legs := preload("res://legs.gd")
const Weapons := preload("res://weapons.gd")
const Controls := preload("res://controls.gd")
const Projectile := preload("res://projectile.gd")

# Movement tuning. Speeds are in metres per second.
const WALK_SPEED := 4.6
const SPRINT_SPEED := 6.4
const TAC_SPEED := 8.0
const CROUCH_SPEED := 2.6
const PRONE_SPEED := 0.9
const ADS_MULT := 0.6
const BACK_MULT := 0.7
const STRAFE_MULT := 0.85
const GROUND_ACCEL := 45.0
const GROUND_FRICTION := 40.0
const AIR_ACCEL := 14.0
const GRAVITY := 20.0
const JUMP_VELOCITY := 6.3
const TAC_MAX := 3.5
const TAC_REGEN := 0.6
const DOUBLE_TAP := 0.3
const SLIDE_TIME := 0.8
const SLIDE_START := 8.6
const SLIDE_END := 4.4
const SLIDE_COOLDOWN := 0.35
const H_STAND := 1.8
const H_CROUCH := 1.15
const H_PRONE := 0.7
const RADIUS := 0.35
const MANTLE_MIN := 0.45
const MANTLE_MAX := 2.15

# Weapon tuning.
const ADS_TIME := 0.25
const SPRINT_OUT := 0.22
const TAC_OUT := 0.36
const FIRE_INTERVAL := 60.0 / 800.0
const MAG := 30
const RELOAD_TIME := 2.2
const ADS_ZOOM := 0.72              # aiming narrows the view to this share
const MOUSE_SENS := 0.0022
const MAX_SHELLS := 40

const KEYS := ["fwd", "back", "left", "right", "sprint", "jump", "crouch", "prone", "ads", "fire", "reload", "inspect", "slot1", "slot2", "swap", "ratte", "lethal", "tactical", "interact"]

enum Stance { STAND, CROUCH, PRONE }

# What the first-person view is doing. Each state has its own pose (see _build_poses).
enum Pov { IDLE, WALK, SPRINT, TAC_SPRINT, JUMP, FALL, LAND, SLIDE_ENTER, SLIDE_LOOP, SLIDE_EXIT,
		CROUCH_IDLE, CROUCH_WALK, PRONE_ENTER, PRONE_IDLE, PRONE_EXIT, MANTLE }
const POV_NAMES := ["Idle", "Walk", "Sprint", "Tactical Sprint", "Jump", "Fall", "Land", "Slide Enter", "Slide Loop",
		"Slide Exit", "Crouch Idle", "Crouch Walk", "Prone Enter", "Prone Idle", "Prone Exit", "Mantle"]
const POV_LABELS := ["Stehen", "Gehen", "Sprint", "Tac-Sprint", "Sprung", "Fallen", "Landung", "Slide", "Slide",
		"Slide-Ende", "Geduckt", "Geduckt gehen", "Hinlegen", "Liegen", "Aufstehen", "Klettern"]
const GUN_HIP := Vector3(0.07, -0.082, -0.33)
# The poses below were first laid out around this older hip position, for a weapon
# drawn at the world's field of view; _fit() moves them to the weapon's own, narrower one.
const OLD_HIP := Vector3(0.1, -0.115, -0.5)
const EYE_STAND := 1.65
const EYE_CROUCH := 1.0
const EYE_PRONE := 0.42
# Inspect: the weapon is held up one-handed, left side to the camera, muzzle high.
const INSPECT_POS := Vector3(0.16, -0.095, -0.4)
const INSPECT_ROLL := -70.0
const INSPECT_YAW := 75.0

var ai_enabled := false
var ai := {}
var held := {}
var prev := {}
var move := Vector2.ZERO
var touch_move := Vector2.ZERO    # from the on-screen stick (touch_controls.gd)

var stance := Stance.STAND
var sprinting := false
var tac := false
var tac_energy := TAC_MAX
var last_sprint_press := -10.0
var sliding := false
var slide_t := 0.0
var slide_dir := Vector3.ZERO
var slide_from := SLIDE_START
var slide_cd := 0.0
var mantling := false
var mantle_t := 0.0
var mantle_dur := 0.4
var mantle_from := Vector3.ZERO
var mantle_to := Vector3.ZERO
var was_on_floor := true
var coyote := 0.0
var land_slow := 0.0
var jump_fatigue := 0.0
var clock := 0.0

var yaw := 0.0
var pitch := 0.0
var recoil := Vector2.ZERO
var mouse_delta := Vector2.ZERO
var bob_t := 0.0
var dip := 0.0
var dip_vel := 0.0
var roll := 0.0

var ads_amt := 0.0
var sprint_amt := 0.0
var tac_amt := 0.0
var inspect_p := 0.0
var ammo := MAG

# Class system: one primary and one secondary; w is the weapon in hand.
var loadout: Array[String] = ["smg", "pistol"]
var slot := 0
var ammo_slots: Array[int] = [30, 15]
var reserve := 90			# rounds left for the weapon in hand, outside the magazine
var reserve_slots: Array[int] = [90, 45]
var w: Dictionary = Weapons.ALL["smg"]
var swap_t := 0.0		   # 0 = not swapping, otherwise progress 0-1
var swap_to := 0
var swapped := false
var melee_t := 0.0
var melee_hit := false
var scoped := false
var swaps := 0
var last_hurt_by: Node            # the bot whose shot hurt us last (for the killcam and the kill feed)
var yy_cancels := 0
var swap_wipe := false        # this swap is the MP5's tactical-sprint wiper swing
var bolt_t := 0.0           # bolt cycle: 0 at rest, below 0 waiting after the shot, then up to 1
var bolt_cycles := 0
# Equipment: one lethal and one tactical piece, refilled on every respawn.
var lethal := "granate"
var tactical := "blend"
var lethal_left := 1
var tactical_left := 2
var throw_t := 0.0
var lethal_t := 0.0          # right-hand throw: up to 0.3 held ready, then the throw to 1
var lethal_holding := false
var tactical_t := 0.0        # left-hand throw, 0 to 1
var throws := 0
var lethal_cancel := false   # the held lethal is being put away again
# Silent shot: the knife key pressed straight after a sniper shot skips the bolt
# animation and swallows the shot's sound.
var silent_shots := 0
var last_shot_silent := false
var reload_style := 0         # sniper: 0 = right hand on the fore-end, 1 = canted the other way with a palm slap
var reload_empty := false     # this reload started on an empty magazine (the action is worked at the end)
var heat := 0.0               # barrel heat: smoke keeps rising from the muzzle while it lasts
var puffs: CPUParticles3D
var laser_dot: MeshInstance3D
var _sfx := {}
var _reload_prev := 0.0
var _last_take := {}
const SOUND_TAKES := 4      # takes per sound in sounds/ (tools/make_sounds.py)
const Assets := preload("res://assets.gd")
var flash_t := 0.0          # seconds of blindness left after a flashbang
var stun_t := 0.0           # seconds of slowness left after a stun grenade
const BOLT_DELAY := 0.22
const BOLT_TIME := 0.85
# Every firearm sits this much nearer the eye than its pose says (closer to the body).
const HOLD_CLOSER := Vector3(0.012, -0.02, 0.035)
# Long guns are turned in a little at the hip, so their stocks leave the picture to the lower right.
const HIP_TURN := Vector3(0.03, 0.0, 0.0)
var sprint_latch := false
var sniper_grip := true       # attachment: vertical foregrip on the sniper rifle
var attach := {}             # class editor picks (weapons.gd ATTACHMENTS)
var auto_reloads := 0
var melee_count := 0
var turn := Vector2.ZERO      # how fast the view is turning, radians per second
var last_look := Vector2.ZERO
var fire_cd := 0.0
var reloading := 0.0
var mag_in := false
var reload_cancels := 0
var burst := 0
var last_shot := -10.0
var punch_roll := 0.0
var noise := FastNoiseLite.new()

var poses := {}
var pov := Pov.IDLE
var pov_from: Pose
var pov_to: Pose
var pov_cur: Pose
var pov_t := 0.0
var pov_seen := {}
var air_t := 0.0
var land_t := -10.0
var land_impact := 0.0
var slide_end_t := -10.0
var prone_enter_t := -10.0
var prone_exit_t := -10.0
var w_pos := Vector3.ZERO
var w_vel := Vector3.ZERO
var prev_local_v := Vector3.ZERO
var kick := 0.0
var shake := 0.0              # full-auto fire: how hard the picture trembles, 0-1
var rcam := Vector3.ZERO      # reload jolts of the head (spring)
var rcam_vel := Vector3.ZERO
var sway := Vector2.ZERO
var shots_fired := 0

# Counters the self-test reads.
var slide_count := 0
var slide_cancel_count := 0
var mantle_count := 0

var head: Node3D
var cam: Camera3D
var col: CollisionShape3D
var capsule: CapsuleShape3D
var vm: Node3D
var vmodel: Viewmodel
var legs: Legs
var flash: OmniLight3D
var flash_mesh: Node3D
var smoke: CPUParticles3D
var dust_mat: StandardMaterial3D
var lens: CameraAttributesPractical

# Settings the pause menu changes.
var fov_h := 100.0          # field of view as shooters quote it: horizontal, on a 16:9 screen
var base_fov := 67.7        # the same, as the vertical angle the camera wants
var vm_fov := 55.0          # the weapon's own field of view (vertical)
var sens_scale := 1.0
var shells_ejected := 0
var shells: Array[RigidBody3D] = []


func _ready() -> void:
	floor_snap_length = 0.3
	_build_poses()
	noise.frequency = 1.0
	floor_max_angle = deg_to_rad(46.0)

	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	col = CollisionShape3D.new()
	col.shape = capsule
	add_child(col)
	_set_height(H_STAND)

	head = Node3D.new()
	head.position.y = H_STAND - 0.15
	add_child(head)
	cam = Camera3D.new()
	cam.fov = base_fov
	cam.near = 0.012
	# Lens: distant things soften a touch. (Blurring the rear sight while aiming was tried
	# and dropped: it smeared the sight into a dark disc over the target.)
	lens = CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = true
	lens.dof_blur_far_distance = 40.0
	lens.dof_blur_far_transition = 120.0
	lens.dof_blur_amount = 0.045
	cam.attributes = lens
	head.add_child(cam)
	cam.make_current()

	_build_viewmodel()
	legs = Legs.new()
	add_child(legs)
	_own_layer(legs)
	_bind_inputs()
	yaw = rotation.y
	for k: String in KEYS:
		held[k] = false
	prev = held.duplicate()


func _bind_inputs() -> void:
	var keys := {
		"fwd": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
		"sprint": KEY_SHIFT, "jump": KEY_SPACE, "crouch": KEY_C,
		"prone": KEY_CTRL, "reload": KEY_R, "inspect": KEY_F, "slot1": KEY_1, "slot2": KEY_2, "ratte": KEY_3, "lethal": KEY_G, "tactical": KEY_Q, "interact": KEY_E,
	}
	for k: String in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[k]
		_add_action("mv_" + k, ev)
	var fire := InputEventMouseButton.new()
	fire.button_index = MOUSE_BUTTON_LEFT
	_add_action("mv_fire", fire)
	var ads := InputEventMouseButton.new()
	ads.button_index = MOUSE_BUTTON_RIGHT
	_add_action("mv_ads", ads)
	# Controller buttons come from the controls settings.
	Controls.load_saved()


func _add_action(action: String, ev: InputEvent) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_add_event(action, ev)


func _build_viewmodel() -> void:
	var v := Viewmodel.new()
	cam.add_child(v)
	vm = v
	vmodel = v
	flash = v.flash
	flash_mesh = v.flash_mesh
	v.set_fov(vm_fov)
	v.set_weapon(w)
	_own_layer(v)

	# A thin wisp of smoke off the suppressor while firing.
	smoke = CPUParticles3D.new()
	smoke.top_level = true
	smoke.emitting = false
	smoke.amount = 26
	smoke.lifetime = 0.7
	smoke.local_coords = false
	smoke.direction = Vector3(0, 0.4, -1)
	smoke.spread = 22.0
	smoke.gravity = Vector3(0, 0.5, 0)
	smoke.initial_velocity_min = 0.3
	smoke.initial_velocity_max = 1.1
	smoke.damping_min = 1.5
	smoke.damping_max = 2.5
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.75, 0.75, 0.75, 0.0), Color(0.7, 0.7, 0.7, 0.13), Color(0.6, 0.6, 0.6, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	smoke.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2(0.16, 0.16)
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	puff_mat.albedo_texture = _soft_dot()
	puff.material = puff_mat
	dust_mat = puff_mat
	smoke.mesh = puff
	add_child(smoke)
	# The heat haze: slower, thinner, longer, curling upwards.
	smoke.amount = 70
	smoke.lifetime = 2.4
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 18.0
	smoke.gravity = Vector3(0, 0.35, 0)
	smoke.initial_velocity_min = 0.05
	smoke.initial_velocity_max = 0.25
	var haze := Gradient.new()
	haze.colors = PackedColorArray([Color(0.8, 0.8, 0.8, 0.0), Color(0.78, 0.78, 0.78, 0.09), Color(0.7, 0.7, 0.7, 0.0)])
	haze.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	smoke.color_ramp = haze
	var curl := Curve.new()
	curl.max_value = 3.0
	curl.add_point(Vector2(0.0, 0.2))
	curl.add_point(Vector2(1.0, 1.6))
	smoke.scale_amount_curve = curl
	# The puff blown out with each shot.
	puffs = CPUParticles3D.new()
	puffs.top_level = true
	puffs.emitting = false
	puffs.amount = 120
	puffs.lifetime = 1.5
	puffs.local_coords = false
	puffs.spread = 26.0
	puffs.gravity = Vector3(0, 0.25, 0)
	puffs.initial_velocity_min = 0.6
	puffs.initial_velocity_max = 2.2
	puffs.damping_min = 2.5
	puffs.damping_max = 4.0
	puffs.scale_amount_min = 0.6
	puffs.scale_amount_max = 1.3
	var swell := Curve.new()
	swell.max_value = 3.0
	swell.add_point(Vector2(0.0, 0.3))
	swell.add_point(Vector2(1.0, 2.2))
	puffs.scale_amount_curve = swell
	var thin := Gradient.new()
	thin.colors = PackedColorArray([Color(0.85, 0.85, 0.85, 0.0), Color(0.8, 0.8, 0.8, 0.16), Color(0.7, 0.7, 0.7, 0.0)])
	thin.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	puffs.color_ramp = thin
	puffs.mesh = puff
	add_child(puffs)
	# Both smokes draw with their own shader: soft grey puffs facing the camera.
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = load("res://smoke.gdshader")
	smoke.material_override = smoke_mat
	puffs.material_override = smoke_mat
	# Where the laser lands in the world.
	laser_dot = MeshInstance3D.new()
	laser_dot.top_level = true
	var spot := SphereMesh.new()
	spot.radius = 0.012
	spot.height = 0.024
	laser_dot.mesh = spot
	var red := StandardMaterial3D.new()
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color(1.0, 0.1, 0.06)
	laser_dot.material_override = red
	laser_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser_dot.visible = false
	add_child(laser_dot)


# A soft round blob, for smoke.
func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


# Health: damage comes from the bot; it grows back after a few seconds without a hit.
signal died
signal shot_fired(to: Vector3)
signal threw(kind: String, from: Vector3, velocity: Vector3)
signal silent_shot
signal sound_played(file: String, volume_db: float)

var health := 130.0
var last_hurt := -10.0
var hurt_from := Vector3.ZERO


func hurt(damage: float, from: Vector3) -> void:
	if health <= 0.0:
		return
	health -= damage
	last_hurt = clock
	hurt_from = from
	dip_vel -= 0.5
	punch_roll += deg_to_rad(randf_range(-2.5, 2.5))
	if health <= 0.0:
		health = 0.0
		died.emit()


func max_health() -> float:
	return 150.0 if perk("dickes_fell") else 130.0


func revive() -> void:
	health = max_health()
	_fill_equipment()
	flash_t = 0.0
	stun_t = 0.0
	velocity = Vector3.ZERO
	reloading = 0.0
	ammo = mag_cap(w)
	_fill_ammo()
	_set_stance(Stance.STAND)


func set_equipment(l: String, t: String) -> void:
	lethal = l
	tactical = t
	_fill_equipment()


func _fill_equipment() -> void:
	lethal_left = int(Projectile.ALL[lethal]["count"])
	tactical_left = int(Projectile.ALL[tactical]["count"])


func flashed(seconds: float) -> void:
	flash_t = maxf(flash_t, seconds)


func stun(seconds: float) -> void:
	stun_t = maxf(stun_t, seconds)


# Perks, one per slot (see perks.gd for what each does).
var perks: Array[String] = ["", "", ""]


func set_perks(a: String, b: String, c: String) -> void:
	perks = [a, b, c]
	tac_energy = tac_max()
	health = max_health()
	_fill_ammo()
	_equip(slot)


# Full magazines and three more of each in reserve.
func _fill_ammo() -> void:
	ammo_slots = [mag_cap(built(loadout[0])), mag_cap(built(loadout[1]))]
	reserve_slots = [ammo_slots[0] * 3, ammo_slots[1] * 3]
	reserve = reserve_slots[slot]


func perk(id: String) -> bool:
	return perks.has(id)


func tac_max() -> float:
	return TAC_MAX * (2.0 if perk("dauerlaeufer") else 1.0)


func slide_time() -> float:
	return SLIDE_TIME * (1.25 if perk("gleiter") else 1.0)


func mag_cap(weapon: Dictionary) -> int:
	var n := int(weapon["mag_size"])
	return int(ceil(n * 1.3)) if perk("erweitertes_magazin") else n


func reload_time() -> float:
	return float(w["reload"]) * (0.7 if perk("flinke_finger") else 1.0)


# Picks the class: a primary and a secondary from weapons.gd, both fully loaded.
func set_loadout(primary: String, secondary: String) -> void:
	if not Weapons.ALL.has(primary) or not Weapons.ALL.has(secondary):
		return
	if loadout[0] == primary and loadout[1] == secondary:
		return
	loadout = [primary, secondary]
	_fill_ammo()
	_equip(0)


func _equip(index: int) -> void:
	slot = index
	w = Weapons.build(loadout[slot], attach.get(loadout[slot], {}))
	ammo = ammo_slots[slot]
	reserve = reserve_slots[slot]
	reloading = 0.0
	inspect_p = 0.0
	bolt_t = 0.0
	lethal_t = 0.0
	lethal_cancel = false
	tactical_t = 0.0
	fire_cd = 0.2
	vmodel.set_weapon(w, bool(w.get("plain_hold", false)))


func set_sniper_grip(on: bool) -> void:
	var picks := attach.duplicate(true)
	if not picks.has("sniper"):
		picks["sniper"] = {}
	picks["sniper"]["griff"] = "vertikal" if on else "keiner"
	set_attachments(picks)


# picks: weapon id -> (slot -> option id). Magazines may change size, so they are refilled.
func set_attachments(picks: Dictionary) -> void:
	attach = picks.duplicate(true)
	sniper_grip = str(attach.get("sniper", {}).get("griff", "vertikal")) != "keiner"
	if vmodel != null:
		_fill_ammo()
		_equip(slot)


func built(id: String) -> Dictionary:
	return Weapons.build(id, attach.get(id, {}))


# Starts lowering the weapon in hand; the other one comes up half-way through.
func swap(index: int) -> void:
	if index == slot or swap_t > 0.0 or mantling:
		return
	ammo_slots[slot] = ammo
	reserve_slots[slot] = reserve
	swap_to = index
	swap_t = 0.001
	swap_wipe = str(w.get("id", "")) == "smg" and tac_amt > 0.5
	# Whatever the bolt was doing is broken off; the case still comes out.
	if bolt_t != 0.0:
		if bolt_t < 0.5:
			_eject_shell()
		bolt_cycles += 1
	bolt_t = 0.0
	swapped = false
	reloading = 0.0
	swaps += 1


# A swap: the weapon goes down quickly (SWAP_MOVE), stays out of the way while
# the hands change weapons (the hold, much shorter with Flinke Hände), and the
# next one comes up just as quickly. swap_t runs 0 -> 1 over all of it; the
# weapons change in the middle, and the timeline is symmetric so YY can mirror it.
const SWAP_MOVE := 0.15
const SWAP_HOLD := 0.6
const SWAP_HOLD_QUICK := 0.06


func _swap_total() -> float:
	return SWAP_MOVE * 2.0 + (SWAP_HOLD_QUICK if perk("aufgeputscht") else SWAP_HOLD)


# How far down the weapon is, 0 (in hand) to 1 (fully down), for swap_t.
func _swap_down() -> float:
	var s := swap_t * _swap_total()
	var total := _swap_total()
	if s < SWAP_MOVE:
		return smoothstep(0.0, SWAP_MOVE, s)
	if s > total - SWAP_MOVE:
		return 1.0 - smoothstep(total - SWAP_MOVE, total, s)
	return 1.0


# "YY": the swap key a second time before the other weapon is out. The swap is
# called off and the weapon in hand comes straight back up from where it got to,
# with the bolt worked and the reload or shot recovery skipped, so it is ready at once.
func _yy() -> void:
	yy_cancels += 1
	swapped = true
	swap_to = slot
	swap_t = maxf(1.0 - swap_t, 0.5)
	fire_cd = minf(fire_cd, 0.12)


# Weapon, arms and the player's own body go on visual layer 2, so the scope's
# camera (which only draws layer 1) sees the world without them.
func _own_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 2
	for child: Node in node.get_children():
		_own_layer(child)


# Where the scope's rear lens is on screen: centre (0-1 across the picture) and
# radius as a share of the picture's height.
func scope_circle() -> Array:
	var at := vm.transform * Vector3(0.0, float(w["sight_y"]), float(w.get("eye_z", 0.165)))
	var k := 1.0 / tan(deg_to_rad(vm_fov) * 0.5)
	var depth := maxf(-at.z, 0.015)
	var view := get_viewport().get_visible_rect().size
	var centre := Vector2(0.5 + at.x * k / depth * view.y / view.x * 0.5, 0.5 - at.y * k / depth * 0.5)
	return [centre, float(w.get("eye_r", 0.0168)) * k / depth * 0.5]


# Field of view the way shooters state it: the horizontal angle on a 16:9 screen.
func set_fov(horizontal: float) -> void:
	fov_h = horizontal
	base_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(horizontal) * 0.5) * 9.0 / 16.0))


func set_weapon_fov(vertical: float) -> void:
	vm_fov = vertical
	vmodel.set_fov(vertical)


# Where something on the weapon appears to be in the world. The weapon is drawn
# with its own field of view, so shells and smoke must start where it looks
# like they should, not where the weapon's true position is.
func _apparent(on_weapon: Vector3) -> Vector3:
	var in_cam := vm.transform * on_weapon
	var k := tan(deg_to_rad(cam.fov) * 0.5) / tan(deg_to_rad(vm_fov) * 0.5)
	return cam.global_transform * Vector3(in_cam.x * k, in_cam.y * k, in_cam.z)


func _unhandled_input(event: InputEvent) -> void:
	if ai_enabled:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		swap(1 - slot)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = MOUSE_SENS * sens_scale * _aim_slowdown()
		yaw -= event.relative.x * sens
		pitch = clampf(pitch - event.relative.y * sens, deg_to_rad(-85.0), deg_to_rad(85.0))
		mouse_delta += event.relative


# Looking around with a finger on a touch screen: delta in radians.
func touch_look(delta: Vector2) -> void:
	var sens: float = sens_scale * _aim_slowdown()
	yaw -= delta.x * sens
	pitch = clampf(pitch - delta.y * sens, deg_to_rad(-85.0), deg_to_rad(85.0))
	mouse_delta += delta * 400.0


# How much slower you turn while aiming (more so through a scope).
func _aim_slowdown() -> float:
	var slow := lerpf(1.0, Controls.ads_mult * (0.42 if w["scope"] else 1.0), ads_amt)
	return slow * (0.35 if stun_t > 0.0 else 1.0)


# Right stick: look around.
func _stick_look(dt: float) -> void:
	if ai_enabled or Input.get_connected_joypads().is_empty():
		return
	var pad: int = Input.get_connected_joypads()[0]
	var look := Controls.stick(Input.get_joy_axis(pad, JOY_AXIS_RIGHT_X), Input.get_joy_axis(pad, JOY_AXIS_RIGHT_Y))
	if look == Vector2.ZERO:
		return
	# A little curve: fine aim near the centre, full speed at the edge.
	look *= lerpf(0.45, 1.0, look.length())
	var speed := Controls.stick_sens * _aim_slowdown()
	yaw -= look.x * 3.6 * speed * dt
	pitch = clampf(pitch - look.y * 2.5 * speed * dt, deg_to_rad(-85.0), deg_to_rad(85.0))
	mouse_delta += look * 900.0 * speed * dt


func _read_input() -> void:
	prev = held.duplicate()
	for k: String in KEYS:
		if ai_enabled:
			held[k] = bool(ai.get(k, false))
		else:
			held[k] = Input.is_action_pressed("mv_" + k)
	move = Vector2(float(held["right"]) - float(held["left"]), float(held["fwd"]) - float(held["back"]))
	if not ai_enabled and not Input.get_connected_joypads().is_empty():
		var pad: int = Input.get_connected_joypads()[0]
		var st := Controls.stick(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		move += Vector2(st.x, -st.y)
	if not ai_enabled:
		move += touch_move
	if move.length() > 1.0:
		move = move.normalized()


func _just(k: String) -> bool:
	return held[k] and not prev[k]


func _set_height(h: float) -> void:
	capsule.height = h
	col.position.y = h / 2.0


func _height_for(s: Stance) -> float:
	match s:
		Stance.CROUCH:
			return H_CROUCH
		Stance.PRONE:
			return H_PRONE
	return H_STAND


func _ray(from: Vector3, to: Vector3, from_inside := false) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collision_mask = 1          # the world only, not spent shells
	q.hit_from_inside = from_inside
	return get_world_3d().direct_space_state.intersect_ray(q)


func _room_for(h: float) -> bool:
	var cur := capsule.height
	if h <= cur:
		return true
	return _ray(global_position + Vector3.UP * (cur - 0.1), global_position + Vector3.UP * h).is_empty()


func _set_stance(s: Stance) -> bool:
	if not _room_for(_height_for(s)):
		return false
	if s == Stance.PRONE and stance != Stance.PRONE:
		prone_enter_t = clock
	elif s != Stance.PRONE and stance == Stance.PRONE:
		prone_exit_t = clock
	if s != stance and not sliding and not mantling:
		if s == Stance.PRONE:
			_play("move", "move_prone.wav", -8.0)
		else:
			_play("move", "move_crouch.wav", -11.0)
	stance = s
	_set_height(_height_for(s))
	return true


func _forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _physics_process(dt: float) -> void:
	clock += dt
	_read_input()
	_stick_look(dt)
	rotation.y = yaw

	if mantling:
		_process_mantle(dt)
		_update_weapon(dt)
		_update_view(dt)
		return

	var on_floor := is_on_floor()
	coyote = 0.1 if on_floor else maxf(coyote - dt, 0.0)
	slide_cd = maxf(slide_cd - dt, 0.0)
	land_slow = maxf(land_slow - dt, 0.0)
	if health > 0.0 and clock - last_hurt > 4.0:
		health = minf(health + 40.0 * dt, max_health())
	jump_fatigue = maxf(jump_fatigue - dt / 1.2, 0.0)

	# Landing: the harder the fall, the deeper the dip and the longer the recovery.
	if on_floor and not was_on_floor and air_t > 0.12:
		land_impact = clampf(-velocity.y, 0.0, 14.0)
		_play("land", "move_land.wav", lerpf(-18.0, -4.0, clampf(land_impact / 10.0, 0.0, 1.0)))
		land_t = clock
		dip_vel -= land_impact * 0.12
		land_slow = 0.0 if perk("leichtfuss") else 0.22
	was_on_floor = on_floor
	air_t = 0.0 if on_floor else air_t + dt

	_handle_sprint(on_floor)
	_handle_stance(on_floor)

	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var basis_y := Basis(Vector3.UP, yaw)
	var wish: Vector3 = basis_y * Vector3(move.x, 0.0, -move.y)

	if sliding:
		slide_t += dt
		var t := clampf(slide_t / slide_time(), 0.0, 1.0)
		hv = slide_dir * lerpf(slide_from, SLIDE_END, t * t)
		if slide_t >= slide_time() or not on_floor:
			_end_slide(false)
	elif on_floor:
		var target := wish * _target_speed()
		var rate := GROUND_ACCEL if wish.length() > 0.01 else GROUND_FRICTION
		hv = hv.move_toward(target, rate * dt)
	elif wish.length() > 0.01:
		hv = hv.move_toward(wish * maxf(hv.length(), 3.0), AIR_ACCEL * dt)

	velocity.x = hv.x
	velocity.z = hv.z
	if not on_floor:
		velocity.y -= GRAVITY * dt

	_handle_jump(on_floor)
	if mantling:
		return
	move_and_slide()

	_update_weapon(dt)
	_update_view(dt)


func _target_speed() -> float:
	var s := WALK_SPEED
	if stance == Stance.CROUCH:
		s = CROUCH_SPEED * (1.3 if perk("dauerlaeufer") else 1.0)
	elif stance == Stance.PRONE:
		s = PRONE_SPEED
	elif tac:
		s = TAC_SPEED
	elif sprinting:
		s = SPRINT_SPEED
	if not sprinting:
		if move.y < -0.1:
			s *= BACK_MULT
		elif absf(move.x) > 0.1 and absf(move.y) < 0.1:
			s *= STRAFE_MULT
		s *= lerpf(1.0, ADS_MULT, ads_amt)
	if land_slow > 0.0:
		s *= 0.75
	if stun_t > 0.0:
		s *= 0.5
	return s


func _handle_sprint(on_floor: bool) -> void:
	# One press starts the sprint and it lasts until you stop pushing forward;
	# holding the key works as before. Automatic sprint needs no press at all.
	if _just("sprint"):
		sprint_latch = true
	if move.y < 0.5:
		sprint_latch = false
	var pushing := move.y > 0.9
	var sprint_held: bool = held["sprint"] or sprint_latch or ((Controls.auto_sprint or Controls.auto_tac) and pushing)
	if Controls.auto_tac and pushing and not tac and tac_energy > tac_max() * 0.5:
		tac = true
	if _just("sprint"):
		if clock - last_sprint_press < DOUBLE_TAP and tac_energy > 0.5:
			tac = true
		last_sprint_press = clock
	var can: bool = sprint_held and move.y > 0.5 and stance == Stance.STAND \
			and not held["ads"] and not sliding
	sprinting = can
	if not sprinting:
		tac = false
	if tac:
		tac_energy -= get_physics_process_delta_time()
		if tac_energy <= 0.0:
			tac_energy = 0.0
			tac = false
	else:
		tac_energy = minf(tac_energy + TAC_REGEN * get_physics_process_delta_time(), tac_max())
	if not on_floor and not sprinting:
		tac = false


func _handle_stance(on_floor: bool) -> void:
	if _just("crouch"):
		if sliding:
			_end_slide(true)
		elif sprinting and on_floor and slide_cd <= 0.0:
			_start_slide()
		elif stance == Stance.STAND:
			_set_stance(Stance.CROUCH)
		elif stance == Stance.CROUCH:
			_set_stance(Stance.STAND)
		else:
			_set_stance(Stance.CROUCH)
	if _just("prone") and not sliding:
		if stance == Stance.PRONE:
			if not _set_stance(Stance.STAND):
				_set_stance(Stance.CROUCH)
		else:
			_set_stance(Stance.PRONE)
	# Sprinting out of a crouch stands you up, as in the original.
	if stance != Stance.STAND and held["sprint"] and move.y > 0.5 and not sliding and _just("sprint"):
		_set_stance(Stance.STAND)


func _start_slide() -> void:
	sliding = true
	_play("slide", "move_slide.wav", -6.0)
	slide_t = 0.0
	slide_count += 1
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	slide_dir = hv.normalized() if hv.length() > 0.5 else _forward()
	slide_from = clampf(hv.length() * 1.15, SLIDE_START, 10.0)
	sprinting = false
	tac = false
	_set_stance(Stance.CROUCH)


func _end_slide(cancelled: bool) -> void:
	sliding = false
	slide_end_t = clock
	slide_cd = SLIDE_COOLDOWN
	if cancelled:
		slide_cancel_count += 1
		# The famous quirk: cancelling a slide refills tactical sprint.
		tac_energy = tac_max()
		_set_stance(Stance.STAND)
	elif held["sprint"] and held["fwd"]:
		_set_stance(Stance.STAND)


func _handle_jump(on_floor: bool) -> void:
	if _just("jump"):
		if sliding:
			_end_slide(true)
			return
		if stance != Stance.STAND:
			_set_stance(Stance.STAND)
			return
		if _try_mantle():
			return
		if coyote > 0.0:
			velocity.y = JUMP_VELOCITY * (1.0 - 0.15 * minf(jump_fatigue, 3.0))
			_play("move", "move_jump.wav", -9.0)
			jump_fatigue += 0.0 if perk("leichtfuss") else 1.0
			coyote = 0.0
			dip_vel += 0.25
	elif held["jump"] and not on_floor and move.y > 0.5 and velocity.y < 3.0:
		_try_mantle()


func _try_mantle() -> bool:
	var fwd := _forward()
	var origin := global_position
	var wall := _ray(origin + Vector3.UP * 0.5, origin + Vector3.UP * 0.5 + fwd * 0.9)
	if wall.is_empty():
		wall = _ray(origin + Vector3.UP * 1.3, origin + Vector3.UP * 1.3 + fwd * 0.9)
	if wall.is_empty():
		return false
	var wall_n: Vector3 = wall["normal"]
	if absf(wall_n.y) > 0.3:
		return false
	var wall_p: Vector3 = wall["position"]
	var probe := Vector3(wall_p.x, 0.0, wall_p.z) + fwd * 0.4
	var top := _ray(Vector3(probe.x, origin.y + MANTLE_MAX + 0.15, probe.z), Vector3(probe.x, origin.y + 0.1, probe.z), true)
	if top.is_empty():
		return false
	var top_n: Vector3 = top["normal"]
	var top_p: Vector3 = top["position"]
	if top_n.y < 0.7:
		return false
	var ledge := top_p.y - origin.y
	var min_h := MANTLE_MIN if is_on_floor() else 0.2
	if ledge < min_h or ledge > MANTLE_MAX:
		return false
	if not _ray(top_p + Vector3.UP * 0.05, top_p + Vector3.UP * H_CROUCH).is_empty():
		return false

	mantling = true
	mantle_count += 1
	mantle_t = 0.0
	mantle_dur = lerpf(0.3, 0.65, clampf(ledge / MANTLE_MAX, 0.0, 1.0))
	mantle_from = origin
	mantle_to = top_p + Vector3.UP * 0.02
	velocity = Vector3.ZERO
	sprinting = false
	tac = false
	sliding = false
	return true


func _process_mantle(dt: float) -> void:
	mantle_t += dt / mantle_dur
	var t := minf(mantle_t, 1.0)
	var up_t := clampf(t / 0.65, 0.0, 1.0)
	up_t = 1.0 - (1.0 - up_t) * (1.0 - up_t)
	var fw_t := smoothstep(0.35, 1.0, t)
	var p := mantle_from.lerp(mantle_to, fw_t)
	p.y = lerpf(mantle_from.y, mantle_to.y, up_t)
	global_position = p
	if t >= 1.0:
		mantling = false
		if not _set_stance(Stance.STAND):
			_set_stance(Stance.CROUCH)
		velocity = _forward() * (WALK_SPEED if held["fwd"] else 1.5)
		was_on_floor = true
		dip_vel -= 0.6


func _update_weapon(dt: float) -> void:
	fire_cd = maxf(fire_cd - dt, 0.0)
	# Weapon swap: 1 and 2 pick the slot, the mouse wheel flips between them.
	if lethal_t > 0.0 or tactical_t > 0.0:
		# Hands full: the swap key puts a held lethal away instead of throwing it.
		if _just("swap") and lethal_holding:
			lethal_cancel = true
	elif swap_t > 0.0 and not swapped and (_just("swap") or (_just("slot1") and slot == 0) or (_just("slot2") and slot == 1)):
		# The swap key again, or the number of the weapon still in hand: YY.
		_yy()
	elif _just("swap"):
		swap(1 - slot)
	elif _just("slot1"):
		swap(0)
	elif _just("slot2"):
		swap(1)
	if swap_t > 0.0:
		swap_t += dt / _swap_total()
		if swap_t >= 0.5 and not swapped:
			swapped = true
			_equip(swap_to)
		if swap_t >= 1.0:
			swap_t = 0.0
	var busy := swap_t > 0.0
	var mag_size := mag_cap(w)
	var reload_for := reload_time()

	var want_ads: bool = held["ads"] and not mantling and reloading <= 0.0 and not sprinting and not busy and not w["melee"]
	ads_amt = move_toward(ads_amt, 1.0 if want_ads else 0.0, dt / (float(w["ads_time"]) * (0.75 if perk("schnellzieher") else 1.0)))
	scoped = w["scope"] and ads_amt > 0.8
	# Through the scope the far distance has to stay sharp.
	lens.dof_blur_far_enabled = not scoped
	tac_amt = move_toward(tac_amt, 1.0 if tac else 0.0, dt / TAC_OUT)
	sprint_amt = move_toward(sprint_amt, 1.0 if (sprinting or mantling) else 0.0, dt / SPRINT_OUT)

	if reloading > 0.0:
		reloading -= dt
		# The magazine is seated 80 % of the way through; the rest is the hand coming back.
		if not mag_in and reloading <= reload_for * 0.2:
			mag_in = true
			var take := mini(mag_size - ammo, reserve)
			ammo += take
			reserve -= take
		# Sprinting or pulling the trigger breaks off the reload.
		var cancel: bool = sprinting or (_just("fire") and ammo > 0)
		if cancel:
			reload_cancels += 1
		if cancel or reloading <= 0.0:
			reloading = 0.0
	elif mag_size > 0 and reserve > 0 and not busy and _just("reload") and ammo < mag_size:
		reloading = reload_for
		mag_in = false
		reload_empty = ammo == 0
		reload_style = randi() % 2 if w.has("bolt") else 0
		vmodel.reload_style = reload_style
	elif mag_size > 0 and reserve > 0 and not busy and ammo == 0 and fire_cd <= 0.0 and bolt_t == 0.0 and throw_t == 0.0 \
			and not sprinting and swap_t <= 0.0:
		# Empty: the weapon reloads by itself.
		reloading = reload_for
		mag_in = false
		reload_empty = true
		reload_style = randi() % 2 if w.has("bolt") else 0
		vmodel.reload_style = reload_style
		auto_reloads += 1

	# Working the bolt after a shot: a short pause for the recoil, then the hand cycles it.
	if bolt_t != 0.0:
		var before := bolt_t
		bolt_t += dt / (BOLT_DELAY if bolt_t < 0.0 else BOLT_TIME)
		if before < 0.0 and bolt_t >= 0.0:
			bolt_t = 0.0001
			# Now over the knob, now hooked under it, never the same way every time.
			vmodel.bolt_hook = randf() < 0.5
		if before < 0.5 and bolt_t >= 0.5:
			_eject_shell()
			_play("shell", "sniper_shell.wav", -14.0, 0.45)
		if before < 0.22 and bolt_t >= 0.22:
			_play("bolt", "sniper_bolt_open.wav", -4.0)
			_jolt(4.0, 0.0, -3.0)
		if before < 0.6 and bolt_t >= 0.6:
			_play("bolt", "sniper_bolt_close.wav", -4.0)
			_jolt(-5.0, 0.0, 3.0)
		if bolt_t >= 1.0:
			bolt_t = 0.0
			bolt_cycles += 1
	vmodel.pose_bolt(maxf(bolt_t, 0.0))
	flash_t = maxf(flash_t - dt, 0.0)
	stun_t = maxf(stun_t - dt, 0.0)
	# Lethal equipment comes up in the right hand at once (the weapon drops away) and
	# stays there while the key is held; letting go throws it. Tactical equipment is
	# lobbed with the left hand while the right keeps hold of the weapon.
	var free_hands := swap_t <= 0.0 and not mantling and bolt_t == 0.0 and lethal_t == 0.0 and tactical_t == 0.0
	var silent := w.has("bolt") and bolt_t < 0.0 and lethal == "wurfmesser" and swap_t <= 0.0 and not mantling \
			and lethal_t == 0.0 and tactical_t == 0.0
	if silent and _just("lethal") and lethal_left > 0:
		_silent_shot()
		lethal_t = 0.001
		lethal_holding = true
	elif free_hands and _just("lethal") and lethal_left > 0:
		lethal_t = 0.001
		lethal_holding = true
		reloading = 0.0
	elif free_hands and _just("tactical") and tactical_left > 0:
		tactical_left -= 1
		tactical_t = 0.001
		reloading = 0.0
	if lethal_t > 0.0:
		if lethal_cancel:
			lethal_t -= dt / 0.22 * 0.3
			if lethal_t <= 0.0:
				lethal_t = 0.0
				lethal_cancel = false
				lethal_holding = false
		elif lethal_holding:
			lethal_t = minf(lethal_t + dt / (0.06 if lethal == "wurfmesser" else 0.22) * 0.3, 0.3)
			if not held["lethal"] and lethal_t >= 0.3:
				lethal_holding = false
		else:
			var before := lethal_t
			lethal_t += dt / 0.42 * 0.7
			if before < 0.45 and lethal_t >= 0.45:
				var aim := -cam.global_transform.basis.z
				var speed := 30.0 if lethal == "wurfmesser" else 15.0
				var lift := Vector3.UP * (0.6 if lethal == "wurfmesser" else 3.2)
				var hand := cam.global_transform * Vector3(0.14, -0.05, -0.4)
				threw.emit(lethal, hand, aim * speed + lift + velocity * 0.6)
				lethal_left -= 1
				throws += 1
			if lethal_t >= 1.0:
				lethal_t = 0.0
	if tactical_t > 0.0:
		var before := tactical_t
		tactical_t += dt / 0.62
		if before < 0.5 and tactical_t >= 0.5:
			var aim := -cam.global_transform.basis.z
			var hand := cam.global_transform * Vector3(-0.18, -0.02, -0.45)
			threw.emit(tactical, hand, aim * 14.0 + Vector3.UP * 3.4 + velocity * 0.6)
			throws += 1
		if tactical_t >= 1.0:
			tactical_t = 0.0
	throw_t = maxf(lethal_t, tactical_t)
	var ready := sprint_amt < 0.05 and tac_amt < 0.05 and reloading <= 0.0 and not mantling and inspect_p < 0.3 and not busy and bolt_t == 0.0 and throw_t == 0.0
	var trigger: bool = held["fire"] if w["auto"] else _just("fire")
	if w["melee"]:
		if trigger and ready and fire_cd <= 0.0:
			fire_cd = w["interval"]
			melee_t = 0.001
			melee_hit = false
			melee_count += 1
			_play("knife", "knife_swing.wav", -8.0)
	elif trigger and ready and fire_cd <= 0.0 and ammo > 0:
		_fire()
	# Knife: the slash lands a third of the way through the swing.
	if melee_t > 0.0:
		melee_t += dt / 0.36
		if melee_t > 0.35 and not melee_hit:
			melee_hit = true
			var from := cam.global_position
			var hit := _ray(from, from - cam.global_transform.basis.z * 2.2)
			if not hit.is_empty():
				_impact(hit["position"], hit["normal"])
				_play("knife_hit", "knife_hit.wav", -6.0)
				var body: Object = hit["collider"]
				if body != null and body.has_method("hit"):
					body.call("hit", float(w["damage"]), hit["position"])
		if melee_t >= 1.0:
			melee_t = 0.0

	flash.light_energy = move_toward(flash.light_energy, 0.0, dt * 28.0)
	# Smoke stays where it was let out: turn away and it hangs in the air behind.
	heat = maxf(heat - dt * 0.45, 0.0)
	var muzzle_at := _apparent(w["muzzle"])
	smoke.emitting = heat > 0.25 and not w["melee"]
	smoke.global_position = muzzle_at
	puffs.emitting = clock - last_shot < 0.05 and not w["melee"]
	puffs.global_position = muzzle_at
	puffs.direction = -cam.global_transform.basis.z + Vector3(0, 0.15, 0)
	_update_laser()
	kick = move_toward(kick, 0.0, dt * 0.55)
	punch_roll = lerpf(punch_roll, 0.0, 1.0 - exp(-14.0 * dt))
	# The view settles back once the trigger is released, slowly while still firing.
	var settle := 6.0 if clock - last_shot > 0.13 else 1.2
	recoil = recoil.lerp(Vector2.ZERO, 1.0 - exp(-settle * dt))
	if clock - last_shot > 0.25:
		burst = 0


func _fire() -> void:
	fire_cd = w["interval"]
	ammo -= 1
	shots_fired += 1
	var hv := Vector2(velocity.x, velocity.z).length()
	var hip_spread := float(w["spread"]) * (0.65 if perk("hueftschuetze") else 1.0)
	var spread := deg_to_rad(lerpf(hip_spread + hv * 0.25, 0.05, ads_amt))
	var dir := -cam.global_transform.basis.z
	dir = dir.rotated(cam.global_transform.basis.x, randf_range(-spread, spread))
	dir = dir.rotated(cam.global_transform.basis.y, randf_range(-spread, spread))
	var from := cam.global_position
	var hit := _ray(from, from + dir * 300.0)
	shot_fired.emit(hit["position"] if not hit.is_empty() else from + dir * 120.0)
	if not hit.is_empty():
		_impact(hit["position"], hit["normal"])
		var body: Object = hit["collider"]
		if body != null and body.has_method("hit"):
			body.call("hit", float(w["damage"]), hit["position"])
	# Climb hard on the first rounds, then wander sideways as the burst goes on.
	var k := lerpf(2.3, 1.5, ads_amt) * (1.25 if burst < 3 else 1.0) * float(w["recoil"]) \
			* (0.8 if perk("ruhige_hand") else 1.0)
	recoil.x += deg_to_rad(k)
	recoil.y += deg_to_rad((randf_range(-0.4, 0.4) + 0.3 * sin(burst * 0.55 + 0.6)) * k)
	recoil.x = minf(recoil.x, deg_to_rad(15.0))
	# "kick": how hard the weapon punches back into the shoulder (the MP5 more than most).
	var punch := float(w.get("kick", 1.0))
	kick = minf(kick + 0.05 * minf(float(w["recoil"]), 1.8) * punch, 0.11 * punch)
	punch_roll += deg_to_rad(randf_range(-0.9, 0.9))
	burst += 1
	last_shot = clock
	flash.light_energy = 3.2 * minf(vmodel.flash_size, 1.4) * float(w.get("flash_bright", 1.0))
	flash.light_color = Color(1.0, randf_range(0.62, 0.78), randf_range(0.3, 0.42))
	vmodel.fire_flash(bool(w.get("side_flash", false)), float(w.get("flash_bright", 1.0)))
	last_shot_silent = false
	if w["auto"]:
		shake = minf(shake + 0.32, 1.0)
	vmodel.hand_shot(float(w.get("kick", 1.0)) * minf(float(w["recoil"]), 2.0))
	heat = minf(heat + (0.9 if w.has("bolt") else 0.12), 3.0)
	var sfx := str(w.get("sfx", ""))
	if sfx != "":
		var level: float = {"sniper": 0.0, "ar": -2.0, "smg": -3.5, "pistol": -3.0}.get(sfx, -3.0)
		_play("shot", sfx + ("_shot_sup.wav" if w.get("suppressed", false) else "_shot.wav"), level)
	if w.has("bolt"):
		# Bolt action: the case only comes out when the bolt is pulled back.
		bolt_t = -BOLT_DELAY
	else:
		_eject_shell()
		if str(w.get("id", "")) == "smg":
			# A bright, glassy ting as the case leaves the port.
			_play("shell", "shell_ting.wav", -15.0)
		else:
			_play("shell", "shell_small.wav", -20.0, 0.4)


# The knife key straight after a sniper shot: the rifle is cycled out of sight
# while the knife comes up and the view tips a little.
func _silent_shot() -> void:
	silent_shots += 1
	bolt_t = 0.0
	bolt_cycles += 1
	_eject_shell()
	# Remembered for the killcam later on: a silent shot plays there without its report.
	last_shot_silent = true
	punch_roll += deg_to_rad(4.5)
	silent_shot.emit()


# Plays one of the weapon's sounds on its own channel (so the shot's echo isn't
# cut short by the bolt), optionally after a delay.
func _play(channel: String, file: String, volume_db: float, delay := 0.0) -> void:
	if not _sfx.has(channel):
		var p := AudioStreamPlayer.new()
		if channel == "shot" or channel == "shell":
			p.max_polyphony = 8
		add_child(p)
		_sfx[channel] = p
	var player: AudioStreamPlayer = _sfx[channel]
	sound_played.emit(file, volume_db)
	# Each sound exists in a few takes; pick one (never the same twice running)
	# and vary pitch and level a little on top, so no two shots sound identical.
	var take := randi() % SOUND_TAKES
	if take == int(_last_take.get(file, -1)):
		take = (take + 1) % SOUND_TAKES
	_last_take[file] = take
	var stream := Assets.sound(file.replace(".wav", "_%d.wav" % take))
	if stream == null:
		return
	volume_db += randf_range(-1.5, 1.5)
	var pitch := randf_range(0.97, 1.03)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			player.stream = stream
			player.volume_db = volume_db
			player.pitch_scale = pitch
			player.play())
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


const MELEE_ELBOW := Vector3(0.17, -0.3, 0.46)


# Offset [position, rotation] of the knife swing at t (0-1).
func _melee_pose(t: float, stab: bool) -> Array:
	if stab:
		var k := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.45, 1.0, t))
		var wind := sin(clampf(t / 0.3, 0.0, 1.0) * PI) * (1.0 - smoothstep(0.0, 0.3, t))
		return [Vector3(-0.05, 0.035, -0.2) * k + Vector3(0.0, -0.01, 0.04) * wind,
				Vector3(deg_to_rad(-12.0), deg_to_rad(10.0), 0.0) * k]
	# Slash: wind out to the left, cut across to the right, come back.
	var wind_k := smoothstep(0.0, 0.22, t) * (1.0 - smoothstep(0.22, 0.5, t))
	var cut_k := smoothstep(0.22, 0.5, t) * (1.0 - smoothstep(0.55, 1.0, t))
	var p := Vector3(-0.1, 0.05, -0.06) * wind_k + Vector3(0.06, -0.01, -0.1) * cut_k
	var r := Vector3(deg_to_rad(8.0), deg_to_rad(38.0), deg_to_rad(-30.0)) * wind_k \
			+ Vector3(deg_to_rad(-6.0), deg_to_rad(-34.0), deg_to_rad(28.0)) * cut_k
	return [p, r]


# Laser: the beam shows from the hip, and a red spot where it lands.
func _update_laser() -> void:
	var on := w.has("laser_beam") and ads_amt < 0.6 and sprint_amt < 0.3 and not mantling and throw_t == 0.0
	vmodel.laser_beam.visible = on
	laser_dot.visible = false
	if not on:
		return
	var from := cam.global_position
	var hit := _ray(from, from - cam.global_transform.basis.z * 80.0)
	if not hit.is_empty():
		laser_dot.global_position = hit["position"] + (hit["normal"] as Vector3) * 0.01
		laser_dot.visible = true


# Head movement during a reload: a slow lean towards the magazine, a little
# rocking while the hands work, and short jolts (springs) when the magazine
# comes out, slams home and the action is worked.
func _reload_cam(dt: float) -> Vector3:
	var r := 0.0 if reloading <= 0.0 else clampf(1.0 - reloading / maxf(reload_time(), 0.01), 0.0, 1.0)
	var lean_in := smoothstep(0.0, 0.18, r) * (1.0 - smoothstep(0.82, 1.0, r))
	var base := Vector3(deg_to_rad(-1.8), deg_to_rad(1.0), deg_to_rad(-3.0)) * lean_in
	base.z += deg_to_rad(0.7) * sin(r * TAU * 1.5) * lean_in
	base.x += deg_to_rad(0.4) * sin(r * TAU * 2.3 + 1.0) * lean_in
	rcam_vel += (-rcam * 150.0 - rcam_vel * 13.0) * dt
	rcam += rcam_vel * dt
	return (base + rcam) * (1.0 - 0.6 * ads_amt)


func _jolt(pitch_deg: float, yaw_deg: float, roll_deg: float) -> void:
	rcam_vel += Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), deg_to_rad(roll_deg))


# A spent case flips out of the ejection port, bounces and lies there for a few seconds.
func _eject_shell() -> void:
	shells_ejected += 1
	var body := RigidBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	body.mass = 0.01
	var bounce := PhysicsMaterial.new()
	bounce.bounce = 0.45
	bounce.friction = 0.6
	body.physics_material_override = bounce
	var shape := CylinderShape3D.new()
	shape.radius = 0.005
	shape.height = 0.019
	var col_shape := CollisionShape3D.new()
	col_shape.shape = shape
	body.add_child(col_shape)
	var mesh := MeshInstance3D.new()
	var case := CylinderMesh.new()
	case.top_radius = 0.0048
	case.bottom_radius = 0.0048
	case.height = 0.019
	case.radial_segments = 10
	case.rings = 1
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.9, 0.62, 0.22)
	brass.metallic = 1.0
	brass.roughness = 0.3
	case.material = brass
	mesh.mesh = case
	body.add_child(mesh)
	get_tree().current_scene.add_child(body)
	var basis := cam.global_transform.basis
	body.global_transform = Transform3D(basis * Basis(Vector3.RIGHT, PI / 2.0), _apparent(w["port"]))
	body.linear_velocity = velocity + basis * Vector3(randf_range(1.8, 2.8), randf_range(1.2, 2.2), randf_range(0.2, 0.9))
	body.angular_velocity = basis * Vector3(randf_range(-30.0, 30.0), randf_range(-10.0, 10.0), randf_range(20.0, 45.0))
	shells.append(body)
	if shells.size() > MAX_SHELLS:
		var old: RigidBody3D = shells.pop_front()
		if is_instance_valid(old):
			old.queue_free()


# A hit leaves a small dark mark and kicks a puff of dust off the surface.
func _impact(pos: Vector3, normal: Vector3) -> void:
	var scene := get_tree().current_scene
	var facing := Basis.looking_at(normal, Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT)

	var mark := MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.014
	dot.height = 0.028
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.02)
	mat.roughness = 0.9
	dot.material = mat
	mark.mesh = dot
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mark)
	# Flattened against the surface so it reads as a hole, not a ball.
	mark.global_transform = Transform3D(facing.scaled(Vector3(1.0, 1.0, 0.15)), pos + normal * 0.001)
	get_tree().create_timer(8.0).timeout.connect(mark.queue_free)

	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.amount = 10
	dust.lifetime = 0.5
	dust.explosiveness = 0.95
	dust.direction = normal
	dust.spread = 38.0
	dust.gravity = Vector3(0, -2.5, 0)
	dust.initial_velocity_min = 0.6
	dust.initial_velocity_max = 2.4
	dust.damping_min = 2.0
	dust.damping_max = 4.0
	dust.scale_amount_min = 0.35
	dust.scale_amount_max = 0.9
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.7, 0.66, 0.6, 0.35), Color(0.6, 0.57, 0.52, 0.0)])
	dust.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2(0.14, 0.14)
	puff.material = dust_mat
	dust.mesh = puff
	scene.add_child(dust)
	dust.global_position = pos + normal * 0.02
	dust.emitting = true
	get_tree().create_timer(1.2).timeout.connect(dust.queue_free)


func _pose(eye: float, cam_rot: Vector3, gun: Vector3, gun_rot: Vector3, bob: float, stride: float,
		swing: float, lag: float, fov: float, blend: float, left_free := 0.0) -> Pose:
	var p := Pose.new()
	p.eye = eye
	p.cam_rot = cam_rot
	p.gun = gun
	p.gun_rot = gun_rot
	p.bob = bob
	p.stride = stride
	p.swing = swing
	p.lag = lag
	p.fov = fov
	p.blend = blend
	p.left_free = left_free
	return p


# One pose per movement state: camera height, camera tilt (pitch, yaw, roll),
# weapon position and rotation, step size, stride, arm swing, weapon lag,
# field-of-view change and the time to blend in.
func _fit(old: Vector3) -> Vector3:
	return GUN_HIP + (old - OLD_HIP) * Vector3(0.72, 0.72, 1.0)


func _build_poses() -> void:
	var g := GUN_HIP
	poses[Pov.IDLE] = _pose(EYE_STAND, Vector3.ZERO, g, Vector3(0, 2.5, -2.0), 0.0, 1.9, 0.0, 1.0, 0.0, 0.24)
	poses[Pov.WALK] = _pose(EYE_STAND, Vector3.ZERO, g + Vector3(0, -0.004, 0.006), Vector3(0, 2.5, -2.0), 0.02, 1.9, 1.3, 1.0, 0.0, 0.2)
	poses[Pov.SPRINT] = _pose(EYE_STAND - 0.02, Vector3(-1.0, 0, 0), _fit(Vector3(0.04, -0.2, -0.46)), Vector3(-8, 38, 8), 0.042, 1.6, 4.5, 1.4, 3.0, 0.22)
	poses[Pov.TAC_SPRINT] = _pose(EYE_STAND - 0.04, Vector3(-2.2, 0, 0), _fit(Vector3(0.17, -0.08, -0.42)), Vector3(52, 10, -14), 0.06, 1.45, 7.0, 1.6, 6.0, 0.3, 1.0)
	poses[Pov.JUMP] = _pose(EYE_STAND, Vector3(0.6, 0, 0), g + Vector3(0, -0.028, 0.012), Vector3(4, 0, 2), 0.0, 1.9, 0.0, 1.5, 1.0, 0.12)
	poses[Pov.FALL] = _pose(EYE_STAND, Vector3(-0.8, 0, 0), g + Vector3(0, 0.014, 0.0), Vector3(-3, 0, -2), 0.0, 1.9, 0.0, 1.5, 1.0, 0.26)
	poses[Pov.LAND] = _pose(EYE_STAND - 0.03, Vector3(-1.2, 0, 0), g + Vector3(0, -0.036, 0.004), Vector3(6, 0, 3), 0.0, 1.9, 0.0, 1.3, 0.0, 0.08)
	poses[Pov.SLIDE_ENTER] = _pose(0.96, Vector3(3.0, 0, -7.0), _fit(Vector3(0.13, -0.155, -0.43)), Vector3(7, 6, 24), 0.0, 1.9, 0.0, 1.3, 8.0, 0.13)
	poses[Pov.SLIDE_LOOP] = _pose(0.82, Vector3(1.5, 0, -5.0), _fit(Vector3(0.12, -0.12, -0.47)), Vector3(2, 4, 18), 0.0, 1.9, 0.0, 1.2, 6.0, 0.2)
	poses[Pov.SLIDE_EXIT] = _pose(EYE_CROUCH, Vector3(-2.0, 0, 1.5), g + Vector3(0, -0.05, 0.02), Vector3(-8, 0, -4), 0.0, 1.9, 0.0, 1.2, 1.0, 0.2)
	poses[Pov.CROUCH_IDLE] = _pose(EYE_CROUCH, Vector3.ZERO, _fit(Vector3(0.095, -0.104, -0.47)), Vector3(0, 0, 4), 0.0, 2.6, 0.0, 1.0, 0.0, 0.24)
	poses[Pov.CROUCH_WALK] = _pose(EYE_CROUCH, Vector3.ZERO, _fit(Vector3(0.095, -0.108, -0.465)), Vector3(0, 0, 4), 0.013, 2.6, 0.9, 1.0, 0.0, 0.2)
	poses[Pov.PRONE_ENTER] = _pose(0.62, Vector3(-9.0, 0, 2.0), _fit(Vector3(0.06, -0.16, -0.42)), Vector3(-14, 12, 10), 0.0, 3.5, 0.0, 1.2, 0.0, 0.3)
	poses[Pov.PRONE_IDLE] = _pose(EYE_PRONE, Vector3.ZERO, _fit(Vector3(0.07, -0.076, -0.46)), Vector3(0, 3, 12), 0.007, 3.5, 2.5, 0.8, 0.0, 0.32)
	poses[Pov.PRONE_EXIT] = _pose(0.75, Vector3(-6.0, 0, -2.0), _fit(Vector3(0.1, -0.17, -0.45)), Vector3(-12, 6, -6), 0.0, 3.5, 0.0, 1.2, 0.0, 0.28)
	poses[Pov.MANTLE] = _pose(EYE_STAND - 0.12, Vector3(-6.0, 0, 4.0), _fit(Vector3(0.1, -0.34, -0.45)), Vector3(-20, 10, 0), 0.0, 1.9, 0.0, 1.0, 0.0, 0.15)
	pov_cur = poses[Pov.IDLE]
	pov_from = pov_cur
	pov_to = pov_cur
	pov_seen[POV_NAMES[Pov.IDLE]] = true


# The state follows what the body is really doing, not the keys held.
func _pick_pov() -> Pov:
	if mantling:
		return Pov.MANTLE
	if sliding:
		return Pov.SLIDE_ENTER if slide_t < 0.16 else Pov.SLIDE_LOOP
	if clock - slide_end_t < 0.24:
		return Pov.SLIDE_EXIT
	if stance == Stance.PRONE:
		return Pov.PRONE_ENTER if clock - prone_enter_t < 0.42 else Pov.PRONE_IDLE
	if clock - prone_exit_t < 0.4:
		return Pov.PRONE_EXIT
	if air_t > 0.06:
		return Pov.JUMP if velocity.y > 0.6 else Pov.FALL
	if clock - land_t < 0.1 + 0.014 * land_impact:
		return Pov.LAND
	var hv := speed_h()
	if stance == Stance.CROUCH:
		return Pov.CROUCH_WALK if hv > 0.4 else Pov.CROUCH_IDLE
	if tac:
		return Pov.TAC_SPRINT
	if sprinting and hv > 1.0:
		return Pov.SPRINT
	return Pov.WALK if hv > 0.4 else Pov.IDLE


func _set_pov(next: Pov) -> void:
	if next == pov:
		return
	pov = next
	pov_from = pov_cur
	pov_to = poses[next]
	if next == Pov.SLIDE_EXIT or next == Pov.PRONE_EXIT:
		# The way out depends on what comes next: rise to standing or stay low.
		var goal := EYE_STAND if stance == Stance.STAND else EYE_CROUCH
		var p: Pose = pov_to.mixed(pov_to, 1.0)
		p.eye = lerpf(pov_cur.eye, goal, 0.6)
		pov_to = p
	pov_t = 0.0
	pov_seen[POV_NAMES[next]] = true


func _update_view(dt: float) -> void:
	var hv := speed_h()

	# Blend camera, arms and weapon together on one clock, so nothing arrives early.
	_set_pov(_pick_pov())
	pov_t += dt
	pov_cur = pov_from.mixed(pov_to, smoothstep(0.0, 1.0, pov_t / maxf(pov_to.blend, 0.01)))
	var p := pov_cur
	# A scoped rifle keeps swaying with your steps, so the whole scope moves in the picture.
	var hip := 1.0 - ads_amt * (0.78 if w["scope"] else 0.85)
	var look_now := Vector2(yaw, pitch)
	turn = turn.lerp((look_now - last_look) / maxf(dt, 0.0001), 1.0 - exp(-14.0 * dt))
	last_look = look_now

	# Step phase advances with the ground actually covered, never with time alone.
	var grounded := is_on_floor() and not sliding and not mantling
	if grounded:
		bob_t += hv * dt * p.stride
	var amp := p.bob * lerpf(1.0, 0.15, ads_amt) * clampf(hv / 1.2, 0.0, 1.0)
	# Footfalls: a quick drop when the foot lands and a slower rise, never two steps alike.
	var step := fposmod(bob_t / PI, 1.0)
	var fall := smoothstep(0.0, 0.28, step) * (1.0 - smoothstep(0.28, 1.0, step))
	var uneven := 1.0 + 0.22 * noise.get_noise_2d(bob_t * 0.31, 40.0)
	var bob := Vector3(sin(bob_t) * amp * 0.55, -fall * amp * 1.5, 0.0) * uneven

	# Landing dip as a damped spring.
	dip_vel += (-dip * 120.0 - dip_vel * 16.0) * dt
	dip += dip_vel * dt

	# Standing still is never perfectly still: slow breathing and a little drift.
	var breath := sin(clock * 1.55 + 1.3 * noise.get_noise_2d(clock * 0.21, 3.0))
	var drift := Vector2(noise.get_noise_2d(clock * 0.37, 11.0), noise.get_noise_2d(clock * 0.43, 17.0))

	# Camera: height and tilt from the pose, steps and landing on top.
	head.position.y = lerpf(head.position.y, p.eye, 1.0 - exp(-30.0 * dt))
	cam.position = cam.position.lerp(p.cam + bob + Vector3(0, dip, 0), 1.0 - exp(-25.0 * dt))
	var want_roll := deg_to_rad(p.cam_rot.z) * (1.0 - ads_amt * 0.5)
	if grounded:
		want_roll -= move.x * deg_to_rad(1.2)
	roll = lerpf(roll, want_roll, 1.0 - exp(-12.0 * dt))
	head.rotation = Vector3(pitch + recoil.x + deg_to_rad(0.07) * breath, recoil.y + deg_to_rad(0.06) * drift.x, 0.0)
	var lean := deg_to_rad(p.cam_rot.x) * (1.0 - ads_amt) + dip * 0.3
	cam.rotation = Vector3(lean, deg_to_rad(p.cam_rot.y), roll + punch_roll + deg_to_rad(0.08) * drift.y)
	# Full-auto fire makes the picture tremble a little; it settles as soon as you let go.
	shake = maxf(shake - dt * 5.0, 0.0)
	if shake > 0.0:
		var n := Vector3(noise.get_noise_2d(clock * 85.0, 3.0), noise.get_noise_2d(clock * 85.0, 7.0), noise.get_noise_2d(clock * 85.0, 13.0))
		cam.rotation += n * deg_to_rad(0.5) * shake * (1.0 - 0.45 * ads_amt)
		cam.position += Vector3(n.x, n.y, 0.0) * 0.003 * shake
	# The head goes with the hands while reloading.
	cam.rotation += _reload_cam(dt)
	cam.fov = lerpf(cam.fov, lerpf(base_fov, base_fov * float(w["ads_zoom"]), ads_amt) + p.fov * (1.0 - ads_amt), 1.0 - exp(-12.0 * dt))

	# Weapon: pose first, then aiming, inspecting and reloading on top.
	var pos := p.gun + Vector3(0, 0, -float(w.get("forward", 0.0)))
	if not w["melee"]:
		pos += HOLD_CLOSER
	var hip_rot: Vector3 = w["hip_rot"]
	var rot: Vector3 = (p.gun_rot + hip_rot) * PI / 180.0
	if w["two_handed"]:
		rot += HIP_TURN
	pos = pos.lerp(Vector3(0.0, -float(w["sight_y"]), float(w["ads_z"])), ads_amt)
	rot = rot.lerp(Vector3.ZERO, ads_amt)
	# Inspect runs in three steps while the key is held and backwards when it is let go:
	# 0-1 raise the weapon, 1-2 the support hand reaches the magazine, 2-3 it shows the magazine.
	var want_inspect: bool = held["inspect"] and not sprinting and not mantling and not sliding \
			and not held["ads"] and not held["fire"] and reloading <= 0.0 and stance != Stance.PRONE and swap_t <= 0.0
	var step_time: float = [0.32, 0.26, 0.42][clampi(int(inspect_p if want_inspect else inspect_p - 0.001), 0, 2)]
	# One-handed weapons are only turned over; there is no magazine for the other hand to pull.
	var inspect_end := 3.0 if w["two_handed"] else 1.0
	inspect_p = move_toward(inspect_p, inspect_end if want_inspect else 0.0, dt / step_time)
	var ins := smoothstep(0.0, 1.0, clampf(inspect_p, 0.0, 1.0))
	pos = pos.lerp(INSPECT_POS, ins)
	# Reloading: the weapon is canted so the magazine well turns towards the support
	# hand, held there while the magazines are swapped, and jolts when the new one seats.
	var reload_r := 0.0 if reloading <= 0.0 else clampf(1.0 - reloading / maxf(reload_time(), 0.01), 0.001, 1.0)
	var sfx := str(w.get("sfx", ""))
	if sfx != "" and sfx != "knife":
		if _reload_prev < 0.22 and reload_r >= 0.22:
			_play("mag", sfx + "_mag_out.wav", -6.0)
			_jolt(7.0, -2.0, -5.0)
		if _reload_prev < 0.8 and reload_r >= 0.8:
			_play("mag", sfx + "_mag_in.wav", -4.0)
			_jolt(-16.0, 3.0, 9.0)
		if reload_empty and not w.has("bolt") and _reload_prev < 0.9 and reload_r >= 0.9:
			_play("bolt", sfx + "_charge.wav", -5.0)
			_jolt(9.0, 1.5, -7.0)
	_reload_prev = reload_r
	# While the bolt is worked the rifle rolls a little towards the hand, and through
	# the scope that shows as a short rock of the picture.
	if lethal_t > 0.0:
		var down := smoothstep(0.0, 0.25, lethal_t) * (1.0 - smoothstep(0.75, 1.0, lethal_t))
		pos += Vector3(-0.05, -0.34, 0.06) * down
		rot.x -= deg_to_rad(40.0) * down
	if tactical_t > 0.0:
		var nudge := sin(clampf(tactical_t, 0.0, 1.0) * PI)
		pos += Vector3(0.02, -0.025, 0.0) * nudge
		rot.z -= deg_to_rad(6.0) * nudge
	if bolt_t > 0.0:
		var rock := sin(clampf(bolt_t, 0.0, 1.0) * PI)
		rot.z += deg_to_rad(9.0 if ads_amt < 0.5 else 2.5) * rock
		rot.x += deg_to_rad(3.0 if ads_amt < 0.5 else 0.8) * sin(clampf(bolt_t, 0.0, 1.0) * TAU)
		pos.y -= (0.012 if ads_amt < 0.5 else 0.002) * rock
	if reload_r > 0.0 and not w["two_handed"]:
		# One-handed: the weapon drops out of view while it is reloaded.
		var dip := sin(reload_r * PI)
		pos.y -= 0.2 * dip
		rot.x -= deg_to_rad(30.0) * dip
	elif reload_r > 0.0:
		var canted := smoothstep(0.0, 0.14, reload_r) * (1.0 - smoothstep(0.86, 1.0, reload_r))
		var seat := exp(-pow((reload_r - 0.82) / 0.03, 2.0))
		if reload_style == 1:
			# Second way: rolled the other way, held by the grip, and the palm slaps the
			# magazine home so the whole rifle bucks up.
			pos += Vector3(0.012, 0.018 + 0.016 * seat, 0.035) * canted
			rot += Vector3(deg_to_rad(8.0 + 4.0 * seat), deg_to_rad(-4.0), deg_to_rad(14.0)) * canted
		else:
			pos += Vector3(-0.012, 0.022 + 0.006 * seat, 0.03) * canted
			rot += Vector3(deg_to_rad(11.0 + 1.5 * seat), deg_to_rad(5.0), deg_to_rad(-22.0)) * canted

	# The weapon trails the view when you turn.
	var sway_target := Vector2(clampf(-mouse_delta.x, -40.0, 40.0), clampf(mouse_delta.y, -40.0, 40.0)) * 0.00125 * p.lag
	mouse_delta = Vector2.ZERO
	sway = sway.lerp(sway_target, 1.0 - exp(-9.0 * dt))
	pos += Vector3(sway.x, sway.y, 0.0) * hip
	rot += Vector3(-sway.y * 1.6, sway.x * 1.6, sway.x * 2.4) * hip

	# Arms swing with the stride; bigger and faster the harder you run.
	var sw := deg_to_rad(p.swing) * hip * clampf(hv / 3.0, 0.0, 1.0) * uneven
	rot += Vector3(-fall * sw * 0.6, sin(bob_t) * sw, cos(bob_t) * sw * 0.5)
	pos += Vector3(sin(bob_t - 0.5) * amp * 0.5 + sin(bob_t) * sw * 0.05, (fall - 0.3) * amp * 0.7, 0.0) * uneven * hip

	# Inertia: every change of speed or direction pushes the weapon the other way,
	# and a damped spring brings it back with one short overshoot.
	var local_v := Basis(Vector3.UP, yaw).inverse() * velocity
	var dv := (local_v - prev_local_v).limit_length(8.0)
	prev_local_v = local_v
	w_vel -= dv * 0.05 * p.lag
	w_vel += (-140.0 * w_pos - 16.0 * w_vel) * dt
	w_pos = (w_pos + w_vel * dt).limit_length(0.05)
	pos += Vector3(w_pos.x, w_pos.y, w_pos.z * 0.6) * hip
	rot += Vector3(w_pos.y * 2.2, -w_pos.x * 1.2, -w_pos.x * 3.0) * hip

	# Breathing and drift, calmer while aiming and drowned out while running.
	var calm := (1.0 - 0.6 * ads_amt) * clampf(1.0 - hv / 6.0, 0.25, 1.0) * float(w.get("sway", 1.0))
	pos += Vector3(drift.x * 0.0014, breath * 0.0017 + drift.y * 0.0011, 0.0) * calm
	rot += Vector3(deg_to_rad(0.3) * breath, deg_to_rad(0.2) * drift.x, deg_to_rad(0.35) * drift.y) * calm

	# Swapping: the weapon drops below the picture and its replacement rises.
	var wipe_roll := 0.0
	if swap_t > 0.0:
		var down := _swap_down()
		# MP5 in a tactical sprint: no drop out of the picture, but a wiper swing. The
		# gun turns about the grip and the muzzle sweeps over towards the lower left
		# corner, like a phone standing on its edge tipping over onto its screen.
		var wipe := 1.0 if swap_wipe else 0.0
		pos += Vector3(0.03, -0.32, 0.05) * down * (1.0 - wipe)
		rot.x -= deg_to_rad(35.0) * down * (1.0 - wipe)
		if wipe > 0.0:
			pos += Vector3(-0.04, -0.08, 0.0) * down * wipe
			wipe_roll = deg_to_rad(70.0) * down * wipe
	# Knife: every other swing is a straight stab, the rest slash from left to right.
	# The turn is about the elbow, so the arm never swings out to the side.
	if melee_t > 0.0:
		var extra := _melee_pose(melee_t, melee_count % 2 == 0)
		var turn_b := Basis.from_euler(extra[1])
		pos += extra[0] + (MELEE_ELBOW - turn_b * MELEE_ELBOW)
		rot += extra[1]
	# The muzzle only lifts a little; most of the recoil is the push straight back.
	# With the eye at a scope the push is damped, or the rifle would hit the camera.
	pos.z += kick * (1.0 - ads_amt * (0.85 if w["scope"] else 0.3))
	rot.x += kick * 0.3
	rot.z += punch_roll * 2.0
	vm.position = vm.position.lerp(pos, 1.0 - exp(-30.0 * dt))
	# Rotations are blended as quaternions so the big turn into the inspect stays clean.
	var held_up := Basis(Vector3.BACK, deg_to_rad(INSPECT_ROLL)) * Basis(Vector3.UP, deg_to_rad(INSPECT_YAW))
	held_up = held_up * Basis.from_euler(Vector3(drift.y * 0.05, drift.x * 0.07, breath * 0.012))
	var facing := Basis.from_euler(rot).slerp(held_up, ins)
	# The wiper swing turns the gun in the plane of the screen only: it keeps showing its side.
	facing = Basis(Vector3.BACK, wipe_roll) * facing
	vm.quaternion = vm.quaternion.slerp(facing.get_rotation_quaternion(), 1.0 - exp(-30.0 * dt))
	# A sniper rifle is too heavy to carry one-handed: both hands stay on it in a tactical sprint.
	vmodel.left_throw = tactical_t
	vmodel.left_item = tactical
	vmodel.pose_left(dt, 0.0 if w["scope"] else p.left_free, bob_t, inspect_p, drift, reload_r)
	vmodel.pose_right_throw(lethal_t, lethal)
	vmodel.hand_life(dt)
	# Bolt-action reload: the right hand moves forward onto the fore-end meanwhile.
	if w.has("bolt") and reload_r > 0.0 and reload_style == 0:
		vmodel.pose_right_reload(smoothstep(0.0, 0.16, reload_r) * (1.0 - smoothstep(0.84, 1.0, reload_r)))

	# Legs: they point where the body travels in a slide, even if you look elsewhere.
	var turn := 0.0
	if sliding:
		var along := Basis(Vector3.UP, yaw).inverse() * slide_dir
		turn = atan2(-along.x, -along.z)
	legs.update(dt, POV_NAMES[pov], bob_t, hv, dip, turn, head.position.y)


func speed_h() -> float:
	return Vector2(velocity.x, velocity.z).length()


func state_name() -> String:
	return POV_LABELS[pov]
