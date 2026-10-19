extends CanvasLayer

# Main menu with four pages across the top: play, weapons, perks, settings.
# The choices themselves are kept (and saved) by the pause menu, here called
# the store, so both menus always agree.

signal play(mode: String)
signal lan_host
signal lan_join(address: String)

const Weapons := preload("res://weapons.gd")
const Perks := preload("res://perks.gd")
const Controls := preload("res://controls.gd")
const Projectile := preload("res://projectile.gd")
const Assets := preload("res://assets.gd")
const SdMode := preload("res://sd_mode.gd")
const Icons := preload("res://icons.gd")
const TAB_ICONS := ["play", "rifle", "grenade", "perk", "lan", "pad", "gear"]

const ACCENT := Color(0.95, 0.62, 0.16)
const DIM := Color(0.62, 0.66, 0.7)
const TABS := ["SPIELEN", "WAFFEN", "AUSRÜSTUNG", "PERKS", "LAN", "CONTROLLER", "EINSTELLUNGEN"]
const LAN_PORT := 24565

var store: Node                 # the pause menu
var is_open := false
var frozen := false

var tab_buttons: Array[Button] = []
var pages: Array[Control] = []
var summary: Label
var weapon_buttons := {}        # weapon id -> Button
var skin_buttons: Array[Button] = []
var perk_buttons := {}          # perk id -> Button
var stat_title: Label
var stat_bars := {}
var stat_note: Label
var sliders := {}
var search: Control
var lan_address: LineEdit
var lan_note: Label
var grip_button: Button
var tab_lines: Array[ColorRect] = []
var showcase_root: Node3D
var showcase_parts: Array[MeshInstance3D] = []
var showcase_metal: StandardMaterial3D
var showcase_name: Label
var lobby: Control
var music_slider: HSlider
var play_info: Control
var attach_note: Label         # shown instead of the editor button for weapons without attachments
# Class editor (gunsmith) for the weapons that take attachments.
var editor: Control
var weapons_row: Control
var editor_buttons := {}        # "slot/option" -> Button
var editor_desc: Label
var editor_bars := {}
var editor_note: Label
var zoom_row: Control
var zoom_slider: HSlider
var zoom_label: Label
var preview_root: Node3D
var preview_parts: Array[MeshInstance3D] = []
var preview_cam: Camera3D
var preview_metal: StandardMaterial3D
var editor_title: Label
var editor_right: VBoxContainer
var editor_weapon := "sniper"
var stats_weapon := ""           # the weapon whose stats are shown (its editor button opens it)
var equip_buttons := {}         # equipment id -> Button
var settings_checks := {}
var bind_buttons := {}          # action -> Button
var rebinding := ""             # action waiting for a button press
var preset_pick: OptionButton
var pad_note: Label
var pad_widgets := {}

# Behind the menu a camera circles the map slowly.
var backdrop: Camera3D
var game_cam: Camera3D
var orbit_centre := Vector3.ZERO
var orbit := 0.6
var search_label: Label
var search_t := -1.0
var search_mode := ""


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.03, 0.04, 0.5)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	# Darker towards the left, where the text sits.
	var fade := TextureRect.new()
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0, 0, 0, 0.75), Color(0, 0, 0, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	fade.texture = gt
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 90)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_bottom", 50)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	var bar := ColorRect.new()
	bar.color = ACCENT
	bar.custom_minimum_size = Vector2(8, 70)
	head.add_child(bar)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -6)
	head.add_child(names)
	names.add_child(_label("TAC SPRINT", 54, Color.WHITE))
	names.add_child(_label("TAKTISCHER  SHOOTER   ·   PROTOTYP", 15, DIM))

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	col.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.icon = Icons.tex(TAB_ICONS[i], 40)
		b.add_theme_constant_override("icon_max_width", 20)
		b.add_theme_constant_override("h_separation", 8)
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(0, 46)
		b.pressed.connect(show_tab.bind(i))
		tabs.add_child(b)
		tab_buttons.append(b)
		# Underline of the open tab.
		var line := ColorRect.new()
		line.color = ACCENT
		line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		line.offset_top = -3
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(line)
		tab_lines.append(line)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.14)
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)

	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(holder)
	for build: Callable in [_page_play, _page_weapons, _page_equipment, _page_perks, _page_lan, _page_controller, _page_settings]:
		var page: Control = build.call()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(page)
		pages.append(page)

	col.add_child(_label("Q / E  Seite wechseln      Mausklick  auswählen", 15, DIM))
	_build_search()
	show_tab(0)


# --- small building blocks ---------------------------------------------------

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _box(bg: Color, edge: Color, edge_width: int, angled := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.border_width_left = edge_width
	s.set_content_margin_all(18)
	s.content_margin_left = 22
	# Cut at a slant, with a soft shadow: the look of current shooter menus.
	s.skew = Vector2(angled, 0.0)
	s.shadow_color = Color(0, 0, 0, 0.28)
	s.shadow_size = 6
	s.anti_aliasing = true
	return s


# A wide menu entry: dark, with an amber bar on the left when chosen or hovered.
func _entry(text: String, size: Vector2, font: int, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = size
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_stylebox_override("normal", _box(Color(0.05, 0.06, 0.08, 0.74), Color(1, 1, 1, 0.14), 3, 0.14))
	b.add_theme_stylebox_override("hover", _box(Color(0.13, 0.14, 0.17, 0.92), ACCENT, 6, 0.14))
	b.add_theme_stylebox_override("pressed", _box(Color(0.32, 0.21, 0.07, 0.92), ACCENT, 8, 0.14))
	b.add_theme_stylebox_override("hover_pressed", _box(Color(0.36, 0.24, 0.08, 0.95), ACCENT, 8, 0.14))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


func _panel(min_size: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	var glass := _box(Color(0.03, 0.04, 0.06, 0.78), ACCENT, 0)
	glass.border_width_top = 3
	glass.corner_radius_bottom_left = 6
	glass.corner_radius_bottom_right = 6
	p.add_theme_stylebox_override("panel", glass)
	p.custom_minimum_size = min_size
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	p.set_meta("inner", v)
	v.set_meta("outer", p)
	return v


# --- pages -------------------------------------------------------------------

func _page_play() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 70)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	row.add_child(left)

	left.add_child(_mode_card("target", "SPIEL SUCHEN", "Freies Spiel  ·  Frachthof  ·  Zielscheiben", 92, 34, _start_search.bind("arena")))
	left.add_child(_mode_card("skull", "1V1 ME... BOT", "Du gegen einen Bot  ·  wer zuerst 10 hat, gewinnt", 84, 28, _start_search.bind("duel")))
	left.add_child(_mode_card("bomb", "SUCHEN & ZERSTÖREN", "Hafen  ·  Bombe legen oder entschärfen  ·  bis 6 gegen 6", 84, 28, func() -> void:
		play_info.visible = false
		lobby.visible = true))
	left.add_child(_mode_card("pin", "TRAININGSPLATZ", "Bewegung und Waffen ausprobieren", 68, 22, _start_search.bind("range")))
	var quit := _entry("BEENDEN", Vector2(600, 52), 20)
	quit.icon = Icons.tex("back", 40)
	quit.add_theme_constant_override("icon_max_width", 20)
	quit.pressed.connect(func() -> void: get_tree().quit())
	left.add_child(quit)

	var info := _panel(Vector2(560, 0))
	info.add_child(_label("AKTIVE KLASSE", 20, ACCENT))
	info.add_child(_build_showcase())
	summary = _label("", 18, Color.WHITE)
	info.add_child(summary)
	play_info = info.get_meta("outer")
	row.add_child(play_info)
	lobby = _build_lobby()
	lobby.visible = false
	row.add_child(lobby)
	return row


# A big mode button: icon, title and a line under it.
func _mode_card(icon: String, title: String, sub: String, height: float, font: int, action: Callable) -> Button:
	var b := _entry("", Vector2(600, height), 20)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 26
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(Icons.rect(icon, height * 0.46, ACCENT))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_label(title, font, Color.WHITE))
	col.add_child(_label(sub, 14, DIM))
	row.add_child(col)
	b.add_child(row)
	b.pressed.connect(action)
	return b


# The weapon you carry, in 3D: turning slowly on a lit pedestal.
func _build_showcase() -> Control:
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(540, 250)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	frame.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.45, 0.5, 0.58)
	env.environment.ambient_light_energy = 0.6
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.25
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.8
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-0.6, 0.35, -0.6)
	rim.light_color = ACCENT
	rim.light_energy = 2.5
	rim.omni_range = 2.5
	vp.add_child(rim)
	var cool := OmniLight3D.new()
	cool.position = Vector3(0.7, 0.1, 0.5)
	cool.light_color = Color(0.4, 0.6, 1.0)
	cool.light_energy = 1.2
	cool.omni_range = 2.5
	vp.add_child(cool)
	var cam := Camera3D.new()
	cam.fov = 28.0
	cam.position = Vector3(0.0, 0.32, 2.05)
	cam.rotation_degrees = Vector3(-9, 0, 0)
	vp.add_child(cam)
	# Pedestal: a dark disc with a glowing ring.
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.5
	dm.bottom_radius = 0.54
	dm.height = 0.04
	disc.mesh = dm
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.055, 0.065)
	dark.metallic = 0.6
	dark.roughness = 0.35
	disc.material_override = dark
	disc.position = Vector3(0, -0.2, 0)
	vp.add_child(disc)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.505
	rm.outer_radius = 0.512
	ring.mesh = rm
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = ACCENT * 1.15
	ring.material_override = glow
	ring.position = Vector3(0, -0.175, 0)
	vp.add_child(ring)
	showcase_root = Node3D.new()
	showcase_root.position = Vector3(0, 0.02, 0)
	vp.add_child(showcase_root)
	showcase_metal = StandardMaterial3D.new()
	showcase_metal.albedo_color = Color(0.12, 0.125, 0.13)
	showcase_metal.metallic = 0.65
	showcase_metal.roughness = 0.38
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(540, 250)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(frame)
	showcase_name = _label("", 24, Color.WHITE)
	showcase_name.position = Vector2(12, 4)
	holder.add_child(showcase_name)
	return holder


# Every mesh of a weapon as built: [file, offset].
func _weapon_meshes(w: Dictionary) -> Array:
	var meshes: Array = [[w["nogrip_mesh"] if (w.get("plain_hold", false) and w.has("nogrip_mesh")) else w["mesh"], Vector3.ZERO]]
	for key: String in ["mag", "barrel", "optic", "bolt"]:
		if w.has(key) and str(w[key]) != "":
			meshes.append([w[key], Vector3.ZERO])
	meshes.append_array(w.get("parts", []))
	return meshes


func _refresh_showcase() -> void:
	if showcase_root == null or store == null:
		return
	var id: String = store.weapon("primary")
	var w := Weapons.build(id, store.attach.get(id, {}))
	showcase_name.text = "%s   ·   %s" % [w["name"], w["kind"]]
	var meshes := _weapon_meshes(w)
	while showcase_parts.size() < meshes.size():
		var m := MeshInstance3D.new()
		m.material_override = showcase_metal
		showcase_root.add_child(m)
		showcase_parts.append(m)
	var box := AABB()
	for i in showcase_parts.size():
		var m: MeshInstance3D = showcase_parts[i]
		m.visible = i < meshes.size()
		if m.visible:
			m.mesh = Assets.mesh(meshes[i][0])
			var part_box := Transform3D(Basis.IDENTITY, meshes[i][1]) * m.mesh.get_aabb()
			box = part_box if i == 0 else box.merge(part_box)
	var mid := box.get_center()
	var fit := 1.35 / maxf(box.size.z, 0.3)
	for i in meshes.size():
		showcase_parts[i].position = ((meshes[i][1] as Vector3) - mid) * fit
		showcase_parts[i].scale = Vector3.ONE * fit


# Search and Destroy lobby: fill both teams with bots, pick how good they are.
func _build_lobby() -> Control:
	var box := _panel(Vector2(560, 0))
	box.add_child(_label("SUCHEN & ZERSTÖREN", 24, ACCENT))
	box.add_child(_label("Bombe auf A oder B legen, oder sie entschärfen.\nKein Respawn in der Runde  ·  Seitenwechsel alle 3 Runden  ·  4 Runden gewinnen.", 16, DIM))
	for row: Array in [["DEIN TEAM  (du + Bots)", "allies", 0, 5, "Mitspieler-Bots: %d   ·   %d gegen ..."], ["GEGNER-TEAM", "enemies", 1, 6, "Gegner-Bots: %d"]]:
		box.add_child(_label(row[0], 18, ACCENT))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var minus := _entry("−", Vector2(60, 50), 26)
		var value := _label("", 22, Color.WHITE)
		value.custom_minimum_size = Vector2(300, 0)
		var plus := _entry("+", Vector2(60, 50), 26)
		var key: String = row[1]
		var lo: int = row[2]
		var hi: int = row[3]
		var show := func() -> void:
			var mine: int = SdMode.allies + 1
			value.text = ("Bots: %d   (ihr seid %d)" % [SdMode.allies, mine]) if key == "allies" else ("Bots: %d" % SdMode.enemies)
		minus.pressed.connect(func() -> void:
			if key == "allies":
				SdMode.allies = clampi(SdMode.allies - 1, lo, hi)
			else:
				SdMode.enemies = clampi(SdMode.enemies - 1, lo, hi)
			show.call())
		plus.pressed.connect(func() -> void:
			if key == "allies":
				SdMode.allies = clampi(SdMode.allies + 1, lo, hi)
			else:
				SdMode.enemies = clampi(SdMode.enemies + 1, lo, hi)
			show.call())
		show.call()
		line.add_child(minus)
		line.add_child(value)
		line.add_child(plus)
		box.add_child(line)
	box.add_child(_label("KARTE", 18, ACCENT))
	var maps := HBoxContainer.new()
	maps.add_theme_constant_override("separation", 8)
	var map_group := ButtonGroup.new()
	for id: String in ["raffinerie", "hafen"]:
		var mb := _entry(SdMode.SdMap.MAP_NAMES[id], Vector2(258, 50), 20, true)
		mb.button_group = map_group
		mb.set_pressed_no_signal(SdMode.SdMap.current == id)
		mb.pressed.connect(func() -> void: SdMode.SdMap.current = id)
		maps.add_child(mb)
	box.add_child(maps)
	box.add_child(_label("BOT-STÄRKE", 18, ACCENT))
	var skills := HBoxContainer.new()
	skills.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for pick: Array in [["Leicht", 0.6], ["Normal", 1.0], ["Schwer", 1.35]]:
		var b := _entry(pick[0], Vector2(170, 50), 20, true)
		b.button_group = group
		b.set_pressed_no_signal(is_equal_approx(SdMode.skill, pick[1]))
		var value: float = pick[1]
		b.pressed.connect(func() -> void: SdMode.skill = value)
		skills.add_child(b)
	box.add_child(skills)
	var start := _entry("STARTEN", Vector2(0, 64), 28)
	start.pressed.connect(func() -> void:
		lobby.visible = false
		play_info.visible = true
		_start_search("snd"))
	box.add_child(start)
	var back := _entry("ZURÜCK", Vector2(0, 46), 18)
	back.pressed.connect(func() -> void:
		lobby.visible = false
		play_info.visible = true)
	box.add_child(back)
	return box.get_meta("outer")


func _page_weapons() -> Control:
	var page := Control.new()
	weapons_row = _weapons_list()
	weapons_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(weapons_row)
	editor = _build_editor()
	editor.set_anchors_preset(Control.PRESET_FULL_RECT)
	editor.visible = false
	page.add_child(editor)
	return page


func _weapons_list() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 70)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	for part: Array in [["PRIMÄRWAFFE", "primary", Weapons.PRIMARY], ["SEKUNDÄRWAFFE", "secondary", Weapons.SECONDARY]]:
		left.add_child(_label(part[0], 20, ACCENT))
		var group := ButtonGroup.new()
		for id: String in part[2]:
			var b := _entry("%s   ·   %s" % [Weapons.ALL[id]["name"], Weapons.ALL[id]["kind"]], Vector2(520, 56), 24, true)
			b.button_group = group
			b.pressed.connect(_choose_weapon.bind(part[1], id))
			b.mouse_entered.connect(_show_stats.bind(id))
			left.add_child(b)
			weapon_buttons[id] = b
		left.add_child(Control.new())

	var stats := _panel(Vector2(560, 0))
	stat_title = _label("", 28, Color.WHITE)
	stats.add_child(stat_title)
	for key: String in ["Feuerrate", "Rückstoß-Kontrolle", "Magazin", "Zielgeschwindigkeit", "Nachladen"]:
		stats.add_child(_label(key, 16, DIM))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		var fill := StyleBoxFlat.new()
		fill.bg_color = ACCENT
		bar.add_theme_stylebox_override("fill", fill)
		stats.add_child(bar)
		stat_bars[key] = bar
	stat_note = _label("", 16, DIM)
	stats.add_child(stat_note)
	# Weapon skins.
	stats.add_child(_label("TARNUNG", 18, ACCENT))
	var skins := HBoxContainer.new()
	skins.add_theme_constant_override("separation", 8)
	var skin_group := ButtonGroup.new()
	var skin_names: Array = ["Standard", "Wüste", "Wald", "Gold", "Arktis"]
	for i in skin_names.size():
		var sb := _entry(skin_names[i], Vector2(98, 44), 16, true)
		sb.button_group = skin_group
		sb.pressed.connect(func() -> void:
			store.set_skin(i)
			refresh())
		skins.add_child(sb)
		skin_buttons.append(sb)
	stats.add_child(skins)
	# Attachments: the sniper rifle opens the class editor.
	stats.add_child(_label("AUFSÄTZE", 18, ACCENT))
	attach_note = _label("", 16, DIM)
	stats.add_child(attach_note)
	grip_button = _entry("", Vector2(0, 48), 18)
	grip_button.pressed.connect(func() -> void: open_editor(stats_weapon))
	stats.add_child(grip_button)
	row.add_child(stats.get_meta("outer"))
	return row


# --- class editor ------------------------------------------------------------
# One editor for every weapon that takes attachments: the left side shows the
# weapon as built, turning slowly, and its values; the right side has a row of
# choices per slot, filled in for the weapon being edited.

func _build_editor() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	editor_title = _label("", 26, Color.WHITE)
	left.add_child(editor_title)
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(640, 280)
	left.add_child(frame)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	frame.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.environment.ambient_light_energy = 0.7
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.6
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -150, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(1.0, 0.8, 0.55)
	vp.add_child(rim)
	preview_cam = Camera3D.new()
	preview_cam.fov = 30.0
	preview_cam.position = Vector3(0.0, 0.03, 1.5)
	vp.add_child(preview_cam)
	preview_root = Node3D.new()
	preview_root.rotation.y = PI * 0.5
	vp.add_child(preview_root)
	preview_metal = StandardMaterial3D.new()
	preview_metal.albedo_color = Color(0.13, 0.135, 0.14)
	preview_metal.metallic = 0.55
	preview_metal.roughness = 0.42
	for key: String in ["Schaden", "Zielgeschwindigkeit", "Rückstoß-Kontrolle", "Stabilität"]:
		left.add_child(_label(key, 15, DIM))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		var fill := StyleBoxFlat.new()
		fill.bg_color = ACCENT
		bar.add_theme_stylebox_override("fill", fill)
		left.add_child(bar)
		editor_bars[key] = bar
	editor_note = _label("", 16, Color.WHITE)
	left.add_child(editor_note)

	editor_right = VBoxContainer.new()
	editor_right.add_theme_constant_override("separation", 4)
	editor_right.custom_minimum_size = Vector2(640, 0)
	row.add_child(editor_right)
	return row


# Fills the right side with the slots of one weapon.
func _fill_editor(id: String) -> void:
	for child: Node in editor_right.get_children():
		child.queue_free()
	editor_buttons.clear()
	var many := Weapons.groups(id).size() > 3
	for group: Dictionary in Weapons.groups(id):
		editor_right.add_child(_label(group["label"], 14 if many else 20, ACCENT))
		var choices := HBoxContainer.new()
		choices.add_theme_constant_override("separation", 6)
		var bg := ButtonGroup.new()
		var options: Array = group["options"]
		var width := (640.0 - 6.0 * (options.size() - 1)) / maxf(options.size(), 3.0)
		for opt: Dictionary in options:
			var b := _entry(opt["name"], Vector2(width, 34 if many else 52), (13 if options.size() > 4 else 15) if many else 18, true)
			b.autowrap_mode = TextServer.AUTOWRAP_OFF
			b.clip_text = true
			if many:
				_tight(b)
			b.button_group = bg
			var slot: String = group["slot"]
			var option_id: String = opt["id"]
			b.pressed.connect(func() -> void:
				store.set_attachment(editor_weapon, slot, option_id)
				editor_desc.text = opt["text"]
				_refresh_editor())
			b.mouse_entered.connect(func() -> void: editor_desc.text = opt["text"])
			choices.add_child(b)
			editor_buttons[slot + "/" + option_id] = b
		editor_right.add_child(choices)
	editor_desc = _label("", 15, DIM)
	editor_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_desc.custom_minimum_size = Vector2(640, 34)
	editor_right.add_child(editor_desc)
	var zoom_box := VBoxContainer.new()
	zoom_box.add_child(_label("ZOOM", 18, ACCENT))
	var zoom_line := HBoxContainer.new()
	zoom_line.add_theme_constant_override("separation", 16)
	zoom_slider = HSlider.new()
	zoom_slider.custom_minimum_size = Vector2(440, 28)
	zoom_slider.step = 1.0
	zoom_slider.value_changed.connect(_zoom_picked)
	zoom_line.add_child(zoom_slider)
	zoom_label = _label("", 22, Color.WHITE)
	zoom_line.add_child(zoom_label)
	zoom_box.add_child(zoom_line)
	editor_right.add_child(zoom_box)
	zoom_row = zoom_box
	var back := _entry("‹   ZURÜCK ZUR WAFFENAUSWAHL", Vector2(640, 38), 16)
	back.pressed.connect(close_editor)
	_tight(back)
	editor_right.add_child(back)


# Smaller padding, so six rows of choices fit on the page.
func _tight(b: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := (b.get_theme_stylebox(state) as StyleBoxFlat).duplicate() as StyleBoxFlat
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		sb.content_margin_left = 12
		sb.content_margin_right = 6
		b.add_theme_stylebox_override(state, sb)


func open_editor(id := "sniper") -> void:
	if not Weapons.has_attachments(id):
		return
	editor_weapon = id
	editor_title.text = "BÜCHSENMACHER   ·   %s" % Weapons.ALL[id]["name"]
	_fill_editor(id)
	editor.visible = true
	weapons_row.visible = false
	_refresh_editor()


func close_editor() -> void:
	editor.visible = false
	weapons_row.visible = true


func _picks() -> Dictionary:
	return store.attach.get(editor_weapon, {})


func _zoom_picked(index: float) -> void:
	var opt := Weapons.option(editor_weapon, "visier", str(_picks().get("visier", "")))
	if not opt.has("zoom"):
		return
	var steps: Array = opt["zoom"]
	store.set_attachment(editor_weapon, "zoom_" + str(opt["id"]), float(steps[clampi(int(index), 0, steps.size() - 1)]))
	_refresh_editor()


func _preview_part(i: int) -> MeshInstance3D:
	while preview_parts.size() <= i:
		var m := MeshInstance3D.new()
		m.material_override = preview_metal
		preview_root.add_child(m)
		preview_parts.append(m)
	return preview_parts[i]


func _refresh_editor() -> void:
	if editor == null or store == null or not editor.visible:
		return
	var picks := _picks()
	for key: String in editor_buttons:
		var parts := key.split("/")
		var chosen := Weapons.option(editor_weapon, parts[0], str(picks.get(parts[0], "")))
		editor_buttons[key].set_pressed_no_signal(chosen.get("id", "") == parts[1])
	var w := Weapons.build(editor_weapon, picks)
	# Every mesh of the weapon as built, turned about its middle.
	var meshes: Array = [[w["nogrip_mesh"] if (w.get("plain_hold", false) and w.has("nogrip_mesh")) else w["mesh"], Vector3.ZERO]]
	for key: String in ["mag", "barrel", "optic", "bolt"]:
		if w.has(key) and str(w[key]) != "":
			meshes.append([w[key], Vector3.ZERO])
	meshes.append_array(w.get("parts", []))
	var box := AABB()
	for i in maxi(meshes.size(), preview_parts.size()):
		var m := _preview_part(i)
		m.visible = i < meshes.size()
		if not m.visible:
			continue
		m.mesh = Assets.mesh(meshes[i][0])
		var at: Vector3 = meshes[i][1]
		var part_box := Transform3D(Basis.IDENTITY, at) * m.mesh.get_aabb()
		box = part_box if i == 0 else box.merge(part_box)
	var mid := box.get_center()
	for i in meshes.size():
		preview_parts[i].position = (meshes[i][1] as Vector3) - mid
	preview_cam.position = Vector3(0.0, 0.03, maxf(box.size.z, box.size.y * 2.0) * 1.15 + 0.35)
	var optic := Weapons.option(editor_weapon, "visier", str(picks.get("visier", "")))
	zoom_row.visible = optic.has("zoom")
	if optic.has("zoom"):
		var steps: Array = optic["zoom"]
		var mag := float(w["scope_mag"])
		zoom_slider.min_value = 0
		zoom_slider.max_value = steps.size() - 1
		zoom_slider.set_value_no_signal(maxi(steps.find(mag), 0))
		zoom_label.text = "%dx" % int(mag)
	var damage := float(w["damage"])
	var ref: Dictionary = Weapons.ALL[editor_weapon]
	editor_bars["Schaden"].value = clampf(damage / maxf(float(ref["damage"]) * 1.25, 1.0) * 100.0, 3.0, 100.0)
	editor_bars["Zielgeschwindigkeit"].value = clampf((0.62 - float(w["ads_time"])) / 0.45 * 100.0, 3.0, 100.0)
	editor_bars["Rückstoß-Kontrolle"].value = clampf(100.0 - float(w["recoil"]) / 4.0 * 80.0, 3.0, 100.0)
	editor_bars["Stabilität"].value = clampf(100.0 - (float(w.get("sway", 1.0)) - 0.6) * 125.0 - float(w["spread"]) * 6.0, 3.0, 100.0)
	var note := "%d Schaden   ·   %d Schuss" % [int(damage), int(w["mag_size"])]
	if editor_weapon == "sniper":
		note = "%d Schaden   ·   %s" % [int(damage), "Körpertreffer: 1 Schuss" if damage >= 130.0 else "Körpertreffer: 2 Schüsse  ·  Kopf: 1"]
	if w.get("suppressed", false):
		note += "   ·   leise"
	editor_note.text = note


func _page_equipment() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	for part: Array in [["PRIMÄR-AUSRÜSTUNG   ·   G / R1", Projectile.LETHAL, true], ["TAKTISCHE AUSRÜSTUNG   ·   Q / L1", Projectile.TACTICAL, false]]:
		var colm := VBoxContainer.new()
		colm.add_theme_constant_override("separation", 10)
		colm.add_child(_label(part[0], 20, ACCENT))
		var group := ButtonGroup.new()
		for id: String in part[1]:
			var e: Dictionary = Projectile.ALL[id]
			var b := _entry("%s   ×%d\n%s" % [str(e["name"]).to_upper(), int(e["count"]), e["text"]], Vector2(560, 96), 18, true)
			b.button_group = group
			var is_lethal: bool = part[2]
			b.pressed.connect(func() -> void:
				if is_lethal:
					store.set_equipment(id, store.tactical)
				else:
					store.set_equipment(store.lethal, id)
				refresh())
			colm.add_child(b)
			equip_buttons[id] = b
		row.add_child(colm)
	return row


func _page_perks() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	for slot in Perks.SLOTS.size():
		var colm := VBoxContainer.new()
		colm.add_theme_constant_override("separation", 10)
		colm.add_child(_label(Perks.SLOTS[slot]["title"], 20, ACCENT))
		var group := ButtonGroup.new()
		for id: String in Perks.SLOTS[slot]["ids"]:
			var p: Dictionary = Perks.ALL[id]
			var b := _entry("%s\n%s" % [str(p["name"]).to_upper(), p["text"]], Vector2(440, 92), 17, true)
			b.button_group = group
			b.pressed.connect(_choose_perk.bind(slot, id))
			colm.add_child(b)
			perk_buttons[id] = b
		row.add_child(colm)
	return row


func _local_addresses() -> Array[String]:
	var found: Array[String] = []
	for a: String in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			found.append(a)
	return found


func _page_lan() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 70)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	row.add_child(left)

	var host := _entry("SPIEL HOSTEN", Vector2(560, 84), 30)
	host.pressed.connect(func() -> void: lan_host.emit())
	left.add_child(host)
	var mine := ", ".join(_local_addresses())
	left.add_child(_label("Deine Adresse im Netzwerk:  %s" % (mine if mine != "" else "nicht gefunden"), 18, Color.WHITE))
	left.add_child(_label("Der andere Spieler gibt diese Adresse bei sich ein.", 16, DIM))
	left.add_child(Control.new())

	left.add_child(_label("ADRESSE DES HOSTS", 18, ACCENT))
	lan_address = LineEdit.new()
	lan_address.placeholder_text = "z. B. 192.168.178.25"
	lan_address.custom_minimum_size = Vector2(560, 48)
	lan_address.add_theme_font_size_override("font_size", 24)
	left.add_child(lan_address)
	var join := _entry("BEITRETEN", Vector2(560, 84), 30)
	join.pressed.connect(func() -> void:
		var address := lan_address.text.strip_edges()
		if address == "":
			lan_status("Bitte zuerst die Adresse des Hosts eingeben.")
		else:
			lan_join.emit(address))
	left.add_child(join)
	lan_note = _label("", 18, ACCENT)
	left.add_child(lan_note)

	var info := _panel(Vector2(520, 0))
	info.add_child(_label("SO GEHT'S", 22, ACCENT))
	var steps := _label("1.  Beide PCs sind im selben WLAN oder Netzwerk.\n2.  Einer klickt auf SPIEL HOSTEN.\n"
			+ "3.  Windows fragt beim ersten Mal nach der Firewall:\n     Zugriff zulassen.\n"
			+ "4.  Der andere tippt die Adresse des Hosts ein\n     und klickt auf BEITRETEN.\n\n"
			+ "1 gegen 1 auf dem Frachthof, wer zuerst 10 hat, gewinnt.\nPort: %d (UDP)" % LAN_PORT, 18, Color.WHITE)
	info.add_child(steps)
	row.add_child(info.get_meta("outer"))
	return row


func lan_status(text: String) -> void:
	lan_note.text = text


func _page_controller() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 50)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 5)
	row.add_child(left)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	var preset_label := _label("BELEGUNG", 20, ACCENT)
	preset_label.custom_minimum_size = Vector2(230, 0)
	top.add_child(preset_label)
	preset_pick = OptionButton.new()
	preset_pick.custom_minimum_size = Vector2(330, 38)
	preset_pick.add_theme_font_size_override("font_size", 20)
	for name: String in Controls.PRESETS:
		preset_pick.add_item(name)
	preset_pick.add_item("Eigene")
	preset_pick.item_selected.connect(func(i: int) -> void:
		if i < Controls.PRESETS.size():
			Controls.use_preset(preset_pick.get_item_text(i))
			Controls.save()
		_refresh_pad())
	top.add_child(preset_pick)
	left.add_child(top)

	for part: Array in Controls.ACTIONS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		var l := _label(part[1], 18, Color.WHITE)
		l.custom_minimum_size = Vector2(230, 0)
		line.add_child(l)
		var b := _entry("", Vector2(330, 32), 17)
		var action: String = part[0]
		b.pressed.connect(func() -> void:
			rebinding = action
			_refresh_pad())
		line.add_child(b)
		bind_buttons[action] = b
		left.add_child(line)
	pad_note = _label("", 16, DIM)
	left.add_child(pad_note)

	var v := _panel(Vector2(560, 0))
	v.add_child(_label("STICKS UND ZIELEN", 22, ACCENT))
	for part: Array in [["deadzone", "Totzone der Sticks", 0.0, 0.4, 0.01], ["stick_sens", "Stick-Empfindlichkeit", 0.3, 3.0, 0.05],
			["ads_mult", "Tempo beim Zielen", 0.2, 1.0, 0.05]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var l := _label(part[1], 18, Color.WHITE)
		l.custom_minimum_size = Vector2(210, 0)
		line.add_child(l)
		var s := HSlider.new()
		s.min_value = part[2]
		s.max_value = part[3]
		s.step = part[4]
		s.custom_minimum_size = Vector2(210, 26)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(s)
		var value := _label("", 18, Color.WHITE)
		value.custom_minimum_size = Vector2(56, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		var key: String = part[0]
		s.value_changed.connect(func(x: float) -> void:
			Controls.set_value(key, x)
			value.text = "%.2f" % x
			Controls.save())
		pad_widgets[key] = [s, value]
		v.add_child(line)
	v.add_child(_label("Tempo beim Zielen gilt für Maus und Stick: 1.0 = wie ohne Zielen.", 14, DIM))
	for part: Array in [["auto_sprint", "Automatischer Sprint"], ["auto_tac", "Automatischer Tac-Sprint"]]:
		var c := CheckButton.new()
		c.text = part[1]
		c.add_theme_font_size_override("font_size", 18)
		var key: String = part[0]
		c.toggled.connect(func(on: bool) -> void:
			Controls.set_value(key, on)
			Controls.save())
		pad_widgets[key] = [c]
		v.add_child(c)
	v.add_child(_label("Automatisch: Stick ganz nach vorn (oder W) genügt zum Sprinten.", 14, DIM))
	row.add_child(v.get_meta("outer"))
	return row


func _refresh_pad() -> void:
	if preset_pick == null:
		return
	# Does the layout still match its preset, or has something been changed by hand?
	var match_index := Controls.PRESETS.size()
	var names: Array = Controls.PRESETS.keys()
	for i in names.size():
		var want: Dictionary = Controls.STANDARD.duplicate()
		want.merge(Controls.PRESETS[names[i]], true)
		if want == Controls.bindings:
			match_index = i
	preset_pick.select(match_index)
	for action: String in bind_buttons:
		bind_buttons[action].text = "Taste drücken ..." if action == rebinding else Controls.name_of(Controls.bindings[action])
	for key: String in ["deadzone", "stick_sens", "ads_mult"]:
		(pad_widgets[key][0] as HSlider).set_value_no_signal(Controls.value(key))
		pad_widgets[key][1].text = "%.2f" % float(Controls.value(key))
	for key: String in ["auto_sprint", "auto_tac"]:
		(pad_widgets[key][0] as CheckButton).set_pressed_no_signal(Controls.value(key))
		if settings_checks.has(key):
			(settings_checks[key] as CheckButton).set_pressed_no_signal(Controls.value(key))
	var pads := Input.get_connected_joypads()
	pad_note.text = "Controller: %s" % Input.get_joy_name(pads[0]) if not pads.is_empty() else "Kein Controller verbunden. Anschließen genügt, er wird erkannt."


# While a binding waits for its button, the next controller press is taken for it.
func _input(event: InputEvent) -> void:
	if rebinding == "" or not is_open:
		return
	var code := -1
	if event is InputEventJoypadButton and event.pressed:
		code = event.button_index
	elif event is InputEventJoypadMotion and event.axis_value > 0.6:
		if event.axis == JOY_AXIS_TRIGGER_LEFT:
			code = Controls.L2
		elif event.axis == JOY_AXIS_TRIGGER_RIGHT:
			code = Controls.R2
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		rebinding = ""
		_refresh_pad()
		get_viewport().set_input_as_handled()
		return
	if code < 0:
		return
	Controls.bind(rebinding, code)
	Controls.save()
	rebinding = ""
	_refresh_pad()
	get_viewport().set_input_as_handled()


func _page_settings() -> Control:
	var v := _panel(Vector2(760, 0))
	v.add_child(_label("ANSICHT UND STEUERUNG", 22, ACCENT))
	for part: Array in [["fov", "Sichtfeld (FOV)", 60.0, 120.0, 1.0, "%d"], ["weapon_zoom", "Waffe weiter weg", 0.0, 30.0, 1.0, "%d"],
			["sensitivity", "Maus-Empfindlichkeit", 0.2, 3.0, 0.05, "%.2f"]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		var name_label := _label(part[1], 20, Color.WHITE)
		name_label.custom_minimum_size = Vector2(260, 0)
		line.add_child(name_label)
		var s := HSlider.new()
		s.min_value = part[2]
		s.max_value = part[3]
		s.step = part[4]
		s.custom_minimum_size = Vector2(320, 28)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(s)
		var value := _label("", 20, Color.WHITE)
		value.custom_minimum_size = Vector2(70, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		var key: String = part[0]
		var fmt: String = part[5]
		s.value_changed.connect(func(x: float) -> void:
			value.text = fmt % x
			if store != null and absf(store.value(key) - x) > 0.0001:
				store.set_value(key, x))
		sliders[key] = [s, value, fmt]
		v.add_child(line)
	v.add_child(_label("0 = Waffe nah und groß, 30 = weiter weg und kleiner.", 15, DIM))
	v.add_child(_label("SPRINT", 22, ACCENT))
	for part: Array in [["auto_sprint", "Automatischer Sprint"], ["auto_tac", "Automatischer Tac-Sprint"]]:
		var c := CheckButton.new()
		c.text = part[1]
		c.add_theme_font_size_override("font_size", 20)
		var key: String = part[0]
		c.toggled.connect(func(on: bool) -> void:
			Controls.set_value(key, on)
			Controls.save()
			_refresh_pad())
		settings_checks[key] = c
		v.add_child(c)
	v.add_child(_label("Automatisch: W (oder Stick ganz nach vorn) genügt, Tac-Sprint startet sofort.", 15, DIM))
	v.add_child(_label("GRAFIK & AUDIO", 22, ACCENT))
	var blur := CheckButton.new()
	blur.text = "Bewegungsunschärfe (Motion Blur)"
	blur.add_theme_font_size_override("font_size", 20)
	blur.toggled.connect(func(on: bool) -> void:
		if store != null and store.motion_blur != on:
			store.set_motion_blur(on))
	settings_checks["motion_blur"] = blur
	v.add_child(blur)
	var mline := HBoxContainer.new()
	mline.add_theme_constant_override("separation", 16)
	var mname := _label("Musik-Lautstärke", 20, Color.WHITE)
	mname.custom_minimum_size = Vector2(260, 0)
	mline.add_child(mname)
	music_slider = HSlider.new()
	music_slider.min_value = 0
	music_slider.max_value = 100
	music_slider.step = 1
	music_slider.custom_minimum_size = Vector2(320, 28)
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mline.add_child(music_slider)
	var mvalue := _label("", 20, Color.WHITE)
	mvalue.custom_minimum_size = Vector2(70, 0)
	mvalue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mline.add_child(mvalue)
	music_slider.value_changed.connect(func(x: float) -> void:
		mvalue.text = "%d" % int(x)
		if store != null and absf(store.music_volume * 100.0 - x) > 0.5:
			store.set_music_volume(x / 100.0))
	v.add_child(mline)
	var wrap := Control.new()
	var outer: Control = v.get_meta("outer")
	wrap.add_child(outer)
	return wrap


func _build_search() -> void:
	search = ColorRect.new()
	(search as ColorRect).color = Color(0.02, 0.025, 0.03, 0.94)
	search.set_anchors_preset(Control.PRESET_FULL_RECT)
	search.visible = false
	add_child(search)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	search.add_child(centre)
	search_label = _label("", 34, Color.WHITE)
	search_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(search_label)


# --- behaviour ---------------------------------------------------------------

func show_tab(index: int) -> void:
	for i in pages.size():
		pages[i].visible = i == index
		tab_buttons[i].add_theme_color_override("font_color", Color.WHITE if i == index else DIM)
		tab_buttons[i].add_theme_color_override("font_hover_color", Color.WHITE)
		tab_buttons[i].add_theme_color_override("icon_normal_color", ACCENT if i == index else DIM)
		tab_buttons[i].add_theme_color_override("icon_hover_color", ACCENT)
		tab_lines[i].visible = i == index
	set_meta("tab", index)
	refresh()


# Brings every page in line with what the store holds.
func refresh() -> void:
	if store == null:
		return
	var primary: String = store.weapon("primary")
	var secondary: String = store.weapon("secondary")
	for id: String in weapon_buttons:
		weapon_buttons[id].set_pressed_no_signal(id == primary or id == secondary)
	for i in skin_buttons.size():
		skin_buttons[i].set_pressed_no_signal(i == store.skin)
	for id: String in equip_buttons:
		equip_buttons[id].set_pressed_no_signal(id == store.lethal or id == store.tactical)
	_refresh_editor()
	_refresh_pad()
	var names: Array[String] = []
	for slot in 3:
		var chosen: String = store.perk_ids[slot]
		for id: String in Perks.SLOTS[slot]["ids"]:
			perk_buttons[id].set_pressed_no_signal(id == chosen)
		names.append(Perks.ALL[chosen]["name"] if Perks.ALL.has(chosen) else "–")
	summary.text = "Primär:      %s\nSekundär:  %s\nTarnung:   %s\n\nPerk 1:  %s\nPerk 2:  %s\nPerk 3:  %s" % [
			Weapons.ALL[primary]["name"], Weapons.ALL[secondary]["name"], store.SKINS[store.skin], names[0], names[1], names[2]]
	for key: String in sliders:
		var s: HSlider = sliders[key][0]
		s.set_value_no_signal(store.value(key))
		sliders[key][1].text = sliders[key][2] % store.value(key)
	_show_stats(primary)
	if settings_checks.has("motion_blur"):
		settings_checks["motion_blur"].set_pressed_no_signal(store.motion_blur)
	if music_slider != null:
		music_slider.set_value_no_signal(store.music_volume * 100.0)
		music_slider.value_changed.emit(store.music_volume * 100.0)
	_refresh_showcase()


func _choose_weapon(key: String, id: String) -> void:
	store.set_weapon(key, id)
	refresh()
	_show_stats(id)


func _choose_perk(slot: int, id: String) -> void:
	store.set_perk(slot, id)
	refresh()


func _show_stats(id: String) -> void:
	var w: Dictionary = Weapons.ALL[id]
	stat_title.text = w["name"]
	# Only weapons with attachments open the class editor.
	var editable := Weapons.has_attachments(id)
	stats_weapon = id
	grip_button.visible = editable
	var slots: Array[String] = []
	for group: Dictionary in Weapons.groups(id):
		slots.append(str(group["label"]).capitalize())
	grip_button.text = "%s ANPASSEN   ›   %s" % [w["name"], " · ".join(slots)]
	attach_note.visible = not editable
	attach_note.text = "Für die %s gibt es noch keine Aufsätze." % w["name"]
	var melee: bool = w["melee"]
	stat_bars["Feuerrate"].value = clampf(60.0 / float(w["interval"]) / 800.0 * 100.0, 3.0, 100.0)
	stat_bars["Rückstoß-Kontrolle"].value = 100.0 if melee else clampf(100.0 - float(w["recoil"]) / 3.4 * 80.0, 3.0, 100.0)
	stat_bars["Magazin"].value = clampf(float(w["mag_size"]) / 30.0 * 100.0, 0.0, 100.0)
	stat_bars["Zielgeschwindigkeit"].value = clampf((0.5 - float(w["ads_time"])) / 0.35 * 100.0, 3.0, 100.0)
	stat_bars["Nachladen"].value = 0.0 if melee else clampf((3.2 - float(w["reload"])) / 2.0 * 100.0, 3.0, 100.0)
	if melee:
		stat_note.text = "Nahkampf: Hieb mit etwa 2 m Reichweite."
	elif w["scope"]:
		stat_note.text = "Einzelschuss mit Zielfernrohr."
	else:
		stat_note.text = "Dauerfeuer." if w["auto"] else "Halbautomatisch: ein Schuss pro Klick."


func _start_search(mode: String) -> void:
	search_mode = mode
	search_t = 0.0
	search.visible = true


func _process(dt: float) -> void:
	if showcase_root != null and is_open:
		showcase_root.rotation.y += dt * 0.5
		showcase_root.position.y = 0.02 + sin(Time.get_ticks_msec() * 0.0015) * 0.012
	if editor != null and editor.visible and preview_root != null:
		preview_root.rotation.y += dt * 0.35
		preview_root.rotation.x = deg_to_rad(8.0)
	if is_open and frozen and backdrop != null:
		orbit += dt * 0.045
		backdrop.look_at_from_position(orbit_centre + Vector3(sin(orbit) * 30.0, 15.0, cos(orbit) * 30.0), orbit_centre + Vector3.UP * 1.5)
	if search_t < 0.0:
		return
	search_t += dt
	var place: String = {"arena": "Frachthof", "duel": "1v1 me... Bot", "range": "Trainingsplatz", "lan": "LAN 1v1", "snd": "Suchen & Zerstören · " + SdMode.SdMap.MAP_NAMES[SdMode.SdMap.current]}[search_mode]
	if search_t < 1.3:
		search_label.text = "SPIEL WIRD GESUCHT" + ".".repeat(1 + int(search_t * 3.0) % 3)
	else:
		search_label.text = "LOKALE PARTIE GEFUNDEN\n" + place.to_upper()
	if search_t > 2.2:
		search_t = -1.0
		search.visible = false
		play.emit(search_mode)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or search_t >= 0.0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var tab: int = get_meta("tab", 0)
		if event.physical_keycode == KEY_E:
			show_tab((tab + 1) % TABS.size())
		elif event.physical_keycode == KEY_Q:
			show_tab((tab + TABS.size() - 1) % TABS.size())
		get_viewport().set_input_as_handled()


# freeze = false shows the menu without stopping the game (used by the self-test).
func open(freeze := true) -> void:
	is_open = true
	visible = true
	frozen = freeze
	show_tab(0)
	if freeze:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if backdrop != null:
			backdrop.make_current()


func close() -> void:
	is_open = false
	visible = false
	rebinding = ""
	if frozen and game_cam != null:
		game_cam.make_current()
	if frozen:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
