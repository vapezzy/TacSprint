extends CanvasLayer

# The loading screen: dark backdrop with a faint grid and a big rifle silhouette,
# the title, a thin glowing progress bar with what is being loaded, rotating
# tips and a turning crosshair. main.gd feeds it progress and fades it out.

const Icons := preload("res://icons.gd")
const ACCENT := Color(0.95, 0.62, 0.16)
const DIM := Color(0.62, 0.66, 0.7)
const TIPS := [
	"Slide aus dem Sprint heraus und brich ihn mit Springen ab – das lädt den Tac-Sprint wieder auf.",
	"YY: zweimal schnell Waffe wechseln überspringt das Repetieren der Sniper.",
	"Silent Shot: direkt nach dem Sniper-Schuss das Wurfmesser ziehen.",
	"Halte das Wurfmesser, um zu zielen – loslassen wirft es.",
	"Suchen & Zerstören: E halten legt oder entschärft die Bombe.",
	"Im Büchsenmacher passt du Mündung, Laser, Griff, Magazin, Schaft und Visier an.",
	"Die Ratte zeigt nach drei Kills ohne Tod die Gegner auf der Minimap.",
	"Ein Kompensator hält die MP5 im Dauerfeuer deutlich ruhiger.",
]

var _bar: ProgressBar
var _glow: ColorRect
var _status: Label
var _percent: Label
var _tip: Label
var _spinner: TextureRect
var _tip_i := 0
var _tip_t := 0.0
var _root: Control
var _shown := 0.0
var _target := 0.0


func _init() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := TextureRect.new()
	bg.texture = _backdrop()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_root.add_child(bg)
	# A huge faint rifle across the right half.
	var rifle := Icons.rect("rifle", 720, Color(1, 1, 1, 0.045))
	rifle.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	rifle.position = Vector2(-820, -360)
	_root.add_child(rifle)

	var head := HBoxContainer.new()
	head.position = Vector2(110, 300)
	head.add_theme_constant_override("separation", 22)
	_root.add_child(head)
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.custom_minimum_size = Vector2(12, 128)
	head.add_child(bar)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -10)
	head.add_child(names)
	names.add_child(_label("TAC SPRINT", 104, Color.WHITE))
	names.add_child(_label("TAKTISCHER  SHOOTER", 24, DIM))

	_status = _label("Starte ...", 20, Color(0.85, 0.88, 0.92))
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(110, -170)
	_root.add_child(_status)
	_percent = _label("0 %", 20, ACCENT)
	_percent.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_percent.position = Vector2(-190, -170)
	_root.add_child(_percent)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.offset_left = 110
	_bar.offset_right = -110
	_bar.offset_top = -136
	_bar.offset_bottom = -130
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.08)
	_bar.add_theme_stylebox_override("background", back)
	_root.add_child(_bar)
	# A soft glow that rides on the bar's leading edge.
	_glow = ColorRect.new()
	_glow.color = Color(1.0, 0.75, 0.35, 0.55)
	_glow.size = Vector2(36, 14)
	_glow.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_root.add_child(_glow)
	var tip_row := HBoxContainer.new()
	tip_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tip_row.position = Vector2(110, -100)
	tip_row.add_theme_constant_override("separation", 12)
	_root.add_child(tip_row)
	tip_row.add_child(Icons.rect("perk", 22, ACCENT))
	_tip = _label("", 18, DIM)
	tip_row.add_child(_tip)
	_spinner = Icons.rect("target", 46, ACCENT)
	_spinner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_spinner.position = Vector2(-160, -100)
	_spinner.pivot_offset = Vector2(23, 23)
	_root.add_child(_spinner)
	_tip_i = randi() % TIPS.size()
	_tip.text = "Tipp: " + TIPS[_tip_i]


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


# Dark blue-grey, a fine grid, darker at the edges.
func _backdrop() -> Texture2D:
	var w := 480
	var h := 270
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var c := Color(0.035, 0.045, 0.06).lerp(Color(0.09, 0.1, 0.12), (1.0 - v) * 0.6 + u * 0.25)
			if x % 24 == 0 or y % 24 == 0:
				c = c.lightened(0.06)
			var d := Vector2(u - 0.5, v - 0.5).length()
			c = c.darkened(clampf((d - 0.3) * 1.2, 0.0, 0.6))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func set_progress(p: float, what: String) -> void:
	_target = clampf(p, 0.0, 1.0)
	_status.text = what


func _process(dt: float) -> void:
	_shown = move_toward(_shown, _target, dt * 1.6)
	_bar.value = _shown * 100.0
	_percent.text = "%d %%" % int(round(_shown * 100.0))
	var width := get_viewport().get_visible_rect().size.x - 220.0
	_glow.position = Vector2(110.0 + width * _shown - 30.0, -140.0)
	_spinner.rotation += dt * 2.2
	_tip_t += dt
	if _tip_t > 3.5:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = "Tipp: " + TIPS[_tip_i]


# Waits for the bar to catch up, then fades everything away.
func finish() -> void:
	_target = 1.0
	while _shown < 0.999:
		await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	await tw.finished
	queue_free()
