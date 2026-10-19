extends Node3D

# A thrown piece of equipment. It flies on its own simple physics (a ray per
# step, so nothing tunnels through thin walls): knives stick where they land,
# grenades bounce and go off when their fuse runs out.
#
# Only the game whose player threw a knife deals its damage; a grenade's blast
# is worked out on every game for the players and bots that game controls.

const LETHAL := ["wurfmesser", "granate"]
const TACTICAL := ["blend", "betaeubung"]
const ALL := {
	"wurfmesser": {"name": "Wurfmesser", "text": "Fliegt gerade und schnell. Ein Treffer tötet.", "count": 1},
	"granate": {"name": "Splittergranate", "text": "Explodiert nach 2,5 s, prallt von Wänden ab.", "count": 1},
	"blend": {"name": "Blendgranate", "text": "Blendet alle, die hinsehen, für einige Sekunden.", "count": 2},
	"betaeubung": {"name": "Betäubungsgranate", "text": "Verlangsamt Laufen und Zielen im Umkreis.", "count": 2},
}
const KNIFE_DAMAGE := 150.0
const BLAST_RADIUS := 6.0
const BLAST_DAMAGE := 160.0

var kind := "granate"
var velocity := Vector3.ZERO
var thrower: Node3D
var local_throw := true       # thrown by this game's own player
var game: Node                # main.gd: players, bot and effects
var fuse := 2.5
var stuck := false
var age := 0.0
var spin := Vector3.ZERO


func _ready() -> void:
	fuse = {"granate": 2.5, "blend": 1.4, "betaeubung": 1.4}.get(kind, 0.0)
	spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.06, 0.07, 0.05)
	dark.roughness = 0.7
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.56, 0.58)
	steel.metallic = 0.9
	steel.roughness = 0.3
	match kind:
		"wurfmesser":
			_part(_box(Vector3(0.006, 0.026, 0.13)), steel, Vector3(0, 0, -0.07))
			_part(_box(Vector3(0.012, 0.024, 0.09)), dark, Vector3(0, 0, 0.04))
		"granate":
			var body := SphereMesh.new()
			body.radius = 0.042
			body.height = 0.09
			var olive := dark.duplicate()
			olive.albedo_color = Color(0.17, 0.2, 0.11)
			_part(body, olive, Vector3.ZERO)
			_part(_box(Vector3(0.02, 0.03, 0.02)), steel, Vector3(0, 0.05, 0))
		_:
			var can := CylinderMesh.new()
			can.top_radius = 0.03
			can.bottom_radius = 0.03
			can.height = 0.11
			var grey := dark.duplicate()
			grey.albedo_color = Color(0.32, 0.34, 0.33) if kind == "blend" else Color(0.18, 0.22, 0.3)
			_part(can, grey, Vector3.ZERO)
			_part(_box(Vector3(0.016, 0.03, 0.016)), steel, Vector3(0, 0.068, 0))


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _part(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)


func _physics_process(dt: float) -> void:
	age += dt
	if not stuck:
		velocity.y -= (3.0 if kind == "wurfmesser" else 14.0) * dt
		var to := global_position + velocity * dt
		var q := PhysicsRayQueryParameters3D.create(global_position, to)
		q.collision_mask = 1
		if thrower is CollisionObject3D:
			q.exclude = [(thrower as CollisionObject3D).get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			global_position = to
		elif kind == "wurfmesser":
			var target: Object = hit["collider"]
			if local_throw and target != null and target.has_method("hit"):
				target.call("hit", KNIFE_DAMAGE, hit["position"])
			stuck = true
			global_position = hit["position"]
		else:
			var n: Vector3 = hit["normal"]
			velocity = velocity.bounce(n) * 0.38
			global_position = hit["position"] + n * 0.05
			spin *= 0.5
		if kind == "wurfmesser":
			if velocity.length() > 0.5 and not stuck:
				look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
				rotate_object_local(Vector3.RIGHT, age * 30.0)
		else:
			rotation += spin * dt
	if kind == "wurfmesser":
		if age > 6.0:
			queue_free()
		return
	fuse -= dt
	if fuse <= 0.0:
		_detonate()
		queue_free()


func _clear_line(from: Vector3, target: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.15, target.global_position + Vector3.UP * 1.2)
	q.collision_mask = 1
	if target is CollisionObject3D:
		q.exclude = [(target as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _detonate() -> void:
	var at := global_position
	game.call("effect_blast", kind, at)
	var player: Node3D = game.get("player")
	var bot: Node3D = game.get("bot")
	var targets: Array[Node3D] = [player]
	if bot != null and bool(bot.get("alive")):
		targets.append(bot)
	if game.has_method("blast_targets"):
		for b: Node3D in game.call("blast_targets"):
			targets.append(b)
	for target: Node3D in targets:
		var d := at.distance_to(target.global_position + Vector3.UP * 0.9)
		if not _clear_line(at, target):
			continue
		match kind:
			"granate":
				if d < BLAST_RADIUS:
					var damage := BLAST_DAMAGE * (1.0 - d / BLAST_RADIUS) + 10.0
					if target == player:
						player.call("hurt", damage, at)
					else:
						target.call("hit", damage, Vector3.ZERO)
			"blend":
				if target == player and d < 22.0:
					var cam: Camera3D = player.get("cam")
					var facing := (-cam.global_transform.basis.z).dot((at - cam.global_position).normalized())
					var strength := clampf(1.0 - d / 22.0, 0.0, 1.0) * lerpf(0.35, 1.0, (facing + 1.0) / 2.0)
					player.call("flashed", 1.0 + 3.5 * strength)
				elif target != player and d < 16.0:
					target.call("blind", 3.5)
			"betaeubung":
				if d < 9.0:
					target.call("stun", 1.5 + 2.5 * (1.0 - d / 9.0))
