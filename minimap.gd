extends Control

# Minimap in the corner of the HUD. It turns with the player, so up is always
# the way you are facing. Containers are drawn from the arena's layout tables;
# the enemy only shows while `reveal` is set (the Ratte streak, or when it fires).

const Arena := preload("res://arena.gd")
const PIXELS_PER_METRE := 4.6

var player: Node3D
var enemy: Node3D
var reveal := false
var sweep := 0.0          # 0-1, the Ratte's scan ring
var boxes: Array = []     # [centre, half length, half width, yaw, stacked]
var dots: Array = []      # [world position, colour]: team-mates, enemies firing, the bomb


func _init() -> void:
	custom_minimum_size = Vector2(200, 200)
	size = Vector2(200, 200)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Array in Arena.LAYOUT:
		boxes.append([Vector2(c[1], c[2]), float(c[0]) / 2.0, Arena.W / 2.0, deg_to_rad(float(c[3])), int(c[4]) > 0])
	for w: Array in Arena.WALLS:
		boxes.append([Vector2(w[1], w[2]), float(w[0]) / 2.0, Arena.W / 2.0, deg_to_rad(float(w[3])), false])


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var mid := size / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.05, 0.74))
	if player == null:
		return
	var yaw: float = player.get("yaw")
	var here := Vector2(player.global_position.x, player.global_position.z)
	# Ground-level boxes first, the stacked ones lighter on top.
	for pass_stacked: bool in [false, true]:
		for b: Array in boxes:
			if b[4] != pass_stacked or (b[0] as Vector2).distance_to(here) > 40.0:
				continue
			var along := Vector2(cos(b[3]), -sin(b[3])) * float(b[1])
			var across := Vector2(sin(b[3]), cos(b[3])) * float(b[2])
			var pts := PackedVector2Array()
			for corner: Vector2 in [along + across, along - across, -along - across, -along + across]:
				pts.append(((b[0] as Vector2) + corner - here).rotated(yaw) * PIXELS_PER_METRE + mid)
			draw_colored_polygon(pts, Color(0.62, 0.66, 0.7, 0.5) if pass_stacked else Color(0.36, 0.4, 0.44, 0.85))
	if sweep > 0.0:
		draw_arc(mid, sweep * size.x * 0.75, 0.0, TAU, 48, Color(0.95, 0.62, 0.16, 0.7 * (1.0 - sweep)), 2.0)
	for d: Array in dots:
		var p := (Vector2((d[0] as Vector3).x, (d[0] as Vector3).z) - here).rotated(yaw) * PIXELS_PER_METRE + mid
		draw_circle(p.clamp(Vector2(5, 5), size - Vector2(5, 5)), 4.0, d[1])
	if reveal and enemy != null:
		var at := (Vector2(enemy.global_position.x, enemy.global_position.z) - here).rotated(yaw) * PIXELS_PER_METRE + mid
		at = at.clamp(Vector2(6, 6), size - Vector2(6, 6))
		draw_circle(at, 5.0, Color(0.95, 0.15, 0.12))
		draw_arc(at, 7.5, 0.0, TAU, 20, Color(1, 1, 1, 0.5), 1.0)
	# You: an arrow in the middle, always pointing up.
	draw_colored_polygon(PackedVector2Array([mid + Vector2(0, -8), mid + Vector2(6, 6), mid + Vector2(0, 3), mid + Vector2(-6, 6)]),
			Color(1.0, 0.85, 0.3))
	draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color(1, 1, 1, 0.3), false, 2.0)
