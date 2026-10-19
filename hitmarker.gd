extends Control

# Hitmarker at the crosshair: white for a hit, red for the kill, and a ring
# round it when it was a headshot.

var age := 1.0
var colour := Color.WHITE
var head := false
var shown := 0          # how many markers have been shown, read by the self-test
var last_kind := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func mark(killed: bool, headshot: bool) -> void:
	age = 0.0
	colour = Color(1.0, 0.16, 0.12) if killed else Color.WHITE
	head = headshot
	shown += 1
	last_kind = ("kill" if killed else "hit") + ("+head" if headshot else "")
	queue_redraw()


func _process(dt: float) -> void:
	if age < 1.0:
		age += dt / (0.5 if colour != Color.WHITE else 0.28)
		queue_redraw()


func _draw() -> void:
	if age >= 1.0:
		return
	var c := colour
	c.a = 1.0 - age * age
	# Four short strokes that open outwards a little as they fade.
	var inner := 7.0 + age * 3.0
	var outer := inner + (12.0 if colour != Color.WHITE else 9.0)
	for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var d := dir.normalized()
		draw_line(d * inner, d * outer, Color(0, 0, 0, c.a * 0.6), 4.5)
		draw_line(d * inner, d * outer, c, 2.5)
	if head:
		draw_arc(Vector2.ZERO, outer + 5.0, 0.0, TAU, 32, Color(0, 0, 0, c.a * 0.6), 4.0)
		draw_arc(Vector2.ZERO, outer + 5.0, 0.0, TAU, 32, c, 2.0)
