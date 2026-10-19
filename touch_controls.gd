extends CanvasLayer

# On-screen controls for phones and tablets. Left half: a floating stick where
# the thumb lands (pushed all the way forward it sprints). Right half: drag to
# look. Buttons press the same actions a keyboard or controller would, so the
# player script does not care where the input came from. Shown only on touch
# screens, and hidden while a menu is open.

const Icons := preload("res://icons.gd")
const ACCENT := Color(0.95, 0.62, 0.16)
const STICK_RADIUS := 110.0
const LOOK_SPEED := 0.0042

var player: Node3D
var main: Node

# [action, icon, label, position from the bottom-right corner, radius]
const BUTTONS := [
	["fire", "target", "", Vector2(-150, -190), 78.0],
	["ads", "", "ZIEL", Vector2(-330, -120), 52.0],
	["jump", "", "SPRUNG", Vector2(-150, -380), 50.0],
	["crouch", "", "DUCK", Vector2(-300, -310), 46.0],
	["reload", "bullet", "", Vector2(-450, -150), 42.0],
	["swap", "rifle", "", Vector2(-460, -280), 42.0],
	["lethal", "grenade", "", Vector2(-320, -460), 38.0],
	["tactical", "flash", "", Vector2(-460, -410), 38.0],
	["interact", "bomb", "", Vector2(-600, -150), 38.0],
]

var _root: Control
var _buttons := []              # [Control, action, centre, radius]
var _touch_button := {}         # finger index -> action
var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_value := Vector2.ZERO
var _look_finger := -1
var _base: Control
var _knob: Control


static func wanted() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


func _init() -> void:
	layer = 15


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_base = _circle(STICK_RADIUS, Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.3))
	_knob = _circle(46.0, Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.6))
	_base.visible = false
	_knob.visible = false
	_root.add_child(_base)
	_root.add_child(_knob)
	for b: Array in BUTTONS:
		var c := _circle(b[4], Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.45) if b[0] != "fire" else ACCENT)
		if b[1] != "":
			var icon := Icons.rect(b[1], b[4] * 0.9)
			icon.position = Vector2(b[4], b[4]) - icon.size / 2.0
			c.add_child(icon)
		else:
			var l := Label.new()
			l.text = b[2]
			l.add_theme_font_size_override("font_size", 18)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.size = Vector2(b[4] * 2.0, b[4] * 2.0)
			c.add_child(l)
		_root.add_child(c)
		_buttons.append([c, b[0], b[3], b[4]])
	# Pause, top centre.
	var pause := _circle(30.0, Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.45))
	var bars := Label.new()
	bars.text = "II"
	bars.add_theme_font_size_override("font_size", 22)
	bars.size = Vector2(60, 60)
	bars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bars.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause.add_child(bars)
	_root.add_child(pause)
	_buttons.append([pause, "pause", Vector2(0, 0), 30.0])
	_layout()
	get_viewport().size_changed.connect(_layout)


# A round control drawn with a style box.
func _circle(radius: float, fill: Color, edge: Color) -> Control:
	var p := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(3)
	s.set_corner_radius_all(int(radius))
	p.add_theme_stylebox_override("panel", s)
	p.size = Vector2(radius, radius) * 2.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _layout() -> void:
	var view := _root.get_viewport_rect().size
	for b: Array in _buttons:
		var c: Control = b[0]
		var centre: Vector2 = view + b[2] if b[1] != "pause" else Vector2(view.x / 2.0, 60.0)
		c.position = centre - c.size / 2.0


func _menu_open() -> bool:
	if main == null:
		return false
	var mm: Node = main.get("main_menu")
	var pm: Node = main.get("menu")
	return (mm != null and bool(mm.get("is_open"))) or (pm != null and bool(pm.get("is_open")))


func _process(_dt: float) -> void:
	visible = not _menu_open()
	if not visible:
		_release_all()
	if player != null:
		player.set("touch_move", _stick_value if _stick_finger >= 0 else Vector2.ZERO)
		# Stick pushed all the way forward: sprint.
		if _stick_finger >= 0 and _stick_value.y > 0.92:
			Input.action_press("mv_sprint")
		elif not _touch_button.values().has("sprint"):
			Input.action_release("mv_sprint")


func _release_all() -> void:
	for f in _touch_button:
		_release(_touch_button[f])
	_touch_button.clear()
	_stick_finger = -1
	_look_finger = -1
	_stick_value = Vector2.ZERO
	_base.visible = false
	_knob.visible = false


func _press(action: String) -> void:
	if action == "pause":
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)
		return
	Input.action_press("mv_" + action)


func _release(action: String) -> void:
	if action != "pause":
		Input.action_release("mv_" + action)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			# A button?
			for b: Array in _buttons:
				var c: Control = b[0]
				var centre := c.position + c.size / 2.0
				if t.position.distance_to(centre) <= float(b[3]) * 1.15:
					_touch_button[t.index] = b[1]
					_press(b[1])
					c.modulate = Color(1.4, 1.2, 0.9)
					get_viewport().set_input_as_handled()
					return
			var half := _root.get_viewport_rect().size.x * 0.45
			if t.position.x < half and _stick_finger < 0:
				_stick_finger = t.index
				_stick_origin = t.position
				_base.position = t.position - _base.size / 2.0
				_knob.position = t.position - _knob.size / 2.0
				_base.visible = true
				_knob.visible = true
			elif _look_finger < 0:
				_look_finger = t.index
			get_viewport().set_input_as_handled()
		else:
			if _touch_button.has(t.index):
				_release(_touch_button[t.index])
				for b: Array in _buttons:
					if b[1] == _touch_button[t.index]:
						(b[0] as Control).modulate = Color.WHITE
				_touch_button.erase(t.index)
			if t.index == _stick_finger:
				_stick_finger = -1
				_stick_value = Vector2.ZERO
				_base.visible = false
				_knob.visible = false
			if t.index == _look_finger:
				_look_finger = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_finger:
			var off := d.position - _stick_origin
			off = off.limit_length(STICK_RADIUS)
			_knob.position = _stick_origin + off - _knob.size / 2.0
			_stick_value = Vector2(off.x, -off.y) / STICK_RADIUS
			get_viewport().set_input_as_handled()
		elif d.index == _look_finger and player != null:
			player.call("touch_look", d.relative * LOOK_SPEED)
			get_viewport().set_input_as_handled()
