extends CanvasLayer

# Pause menu, opened with Esc. It stops the game, frees the mouse and offers
# the view settings; they are remembered between sessions.

signal fov_changed(value: float)
signal weapon_fov_changed(value: float)
signal sensitivity_changed(value: float)
signal loadout_changed(primary: String, secondary: String)
signal perks_changed(a: String, b: String, c: String)
signal main_menu_requested
signal skin_changed(index: int)
signal sniper_grip_changed(on: bool)
signal attachments_changed(picks: Dictionary)
signal equipment_changed(lethal: String, tactical: String)
signal motion_blur_changed(on: bool)
signal music_volume_changed(value: float)

const Perks := preload("res://perks.gd")

const Weapons := preload("res://weapons.gd")

const SAVE := "user://settings.cfg"
const DEFAULTS := {"fov": 100.0, "weapon_zoom": 0.0, "sensitivity": 1.0}
const SKINS := ["Standard", "Wüste", "Wald", "Gold", "Arktis"]

var enabled := true        # false in the automated tests, so Esc and saved settings stay out of the way
var is_open := false
var frozen := false
var sliders := {}
var readouts := {}
var blocked := false		# true while the main menu is up
var perk_ids: Array[String] = ["", "", ""]
var skin := 0
var sniper_grip := true
var motion_blur := true
var music_volume := 0.45
# Class editor picks for the sniper rifle: slot -> option, and the zoom of each scope.
var attach := {
	"sniper": {"griff": "vertikal", "lauf": "standard", "visier": "zielfernrohr", "zoom_zielfernrohr": 8.0, "zoom_kompakt": 4.0},
	"smg": {},
	"ar": {},
}
var lethal := "granate"
var tactical := "blend"
var picks := {}			# "primary" / "secondary" -> OptionButton


func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.07, 0.08, 0.09, 0.96)
	box.border_color = Color(0.85, 0.62, 0.2)
	box.border_width_left = 3
	box.set_content_margin_all(34)
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(620, 0)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title := Label.new()
	title.text = "PAUSE"
	title.add_theme_font_size_override("font_size", 40)
	col.add_child(title)
	var hint := Label.new()
	hint.text = "Esc setzt das Spiel fort."
	hint.add_theme_color_override("font_color", Color(0.65, 0.68, 0.7))
	col.add_child(hint)
	col.add_child(HSeparator.new())

	_slider(col, "fov", "Sichtfeld (FOV)", 60.0, 120.0, 1.0, "%d")
	_slider(col, "weapon_zoom", "Waffe weiter weg", 0.0, 30.0, 1.0, "%d")
	_slider(col, "sensitivity", "Maus-Empfindlichkeit", 0.2, 3.0, 0.05, "%.2f")
	var note := Label.new()
	note.text = "0 = Waffe nah und groß, 30 = weiter weg und kleiner."
	note.add_theme_color_override("font_color", Color(0.65, 0.68, 0.7))
	note.add_theme_font_size_override("font_size", 14)
	col.add_child(note)
	col.add_child(HSeparator.new())

	# Create a class: one primary and one secondary weapon.
	var heading := Label.new()
	heading.text = "KLASSE"
	heading.add_theme_font_size_override("font_size", 24)
	col.add_child(heading)
	_pick(col, "primary", "Primärwaffe", Weapons.PRIMARY)
	_pick(col, "secondary", "Sekundärwaffe", Weapons.SECONDARY)
	var class_note := Label.new()
	class_note.text = "Im Spiel: 1 und 2 oder Mausrad wechseln die Waffe."
	class_note.add_theme_color_override("font_color", Color(0.65, 0.68, 0.7))
	class_note.add_theme_font_size_override("font_size", 14)
	col.add_child(class_note)
	col.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	_button(row, "Weiter", close)
	_button(row, "Hauptmenü", func() -> void:
		close()
		main_menu_requested.emit())
	_button(row, "Standardwerte", _reset)
	_button(row, "Beenden", func() -> void: get_tree().quit())

	if enabled:
		for i in 3:
			perk_ids[i] = Perks.DEFAULTS[i]
		_load()
	apply()


func _slider(parent: Control, key: String, text: String, lo: float, hi: float, step: float, fmt: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(230, 0)
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = DEFAULTS[key]
	s.custom_minimum_size = Vector2(250, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var value := Label.new()
	value.custom_minimum_size = Vector2(60, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 20)
	value.text = fmt % s.value
	row.add_child(value)
	sliders[key] = s
	readouts[key] = [value, fmt]
	s.value_changed.connect(func(v: float) -> void:
		value.text = fmt % v
		_emit(key))


func _pick(parent: Control, key: String, text: String, ids: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(230, 0)
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(310, 40)
	o.add_theme_font_size_override("font_size", 20)
	for id: String in ids:
		o.add_item(Weapons.ALL[id]["name"])
		o.set_item_metadata(o.item_count - 1, id)
	row.add_child(o)
	picks[key] = o
	o.item_selected.connect(func(_i: int) -> void: _emit_loadout())


func weapon(key: String) -> String:
	var o: OptionButton = picks[key]
	return o.get_item_metadata(o.selected)


func set_weapon(key: String, id: String) -> void:
	var o: OptionButton = picks[key]
	for i in o.item_count:
		if o.get_item_metadata(i) == id:
			o.select(i)
	_emit_loadout()


func _emit_loadout() -> void:
	loadout_changed.emit(weapon("primary"), weapon("secondary"))


func set_equipment(l: String, t: String) -> void:
	lethal = l
	tactical = t
	equipment_changed.emit(lethal, tactical)


func set_motion_blur(on: bool) -> void:
	motion_blur = on
	motion_blur_changed.emit(on)
	_save()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	music_volume_changed.emit(music_volume)
	_save()


func set_sniper_grip(on: bool) -> void:
	set_attachment("sniper", "griff", "vertikal" if on else "keiner")


# Class editor: one pick for one weapon. picks of the weapon: slot -> option id.
func set_attachment(weapon_id: String, key: String, value: Variant) -> void:
	if not attach.has(weapon_id):
		attach[weapon_id] = {}
	attach[weapon_id][key] = value
	sniper_grip = str(attach["sniper"].get("griff", "vertikal")) != "keiner"
	attachments_changed.emit(attach.duplicate(true))


func set_skin(index: int) -> void:
	skin = clampi(index, 0, SKINS.size() - 1)
	skin_changed.emit(skin)


func set_perk(slot: int, id: String) -> void:
	perk_ids[slot] = id
	perks_changed.emit(perk_ids[0], perk_ids[1], perk_ids[2])


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(132, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(action)
	parent.add_child(b)


func _emit(key: String) -> void:
	var v: float = sliders[key].value
	match key:
		"fov":
			fov_changed.emit(v)
		"weapon_zoom":
			# 0 = close and large, 30 = held further out.
			weapon_fov_changed.emit(55.0 + v * 0.5)
		"sensitivity":
			sensitivity_changed.emit(v)


# Sends every current setting out, for whoever has just connected.
func apply() -> void:
	for key: String in sliders:
		_emit(key)
	_emit_loadout()
	perks_changed.emit(perk_ids[0], perk_ids[1], perk_ids[2])
	skin_changed.emit(skin)
	attachments_changed.emit(attach.duplicate(true))
	equipment_changed.emit(lethal, tactical)


func value(key: String) -> float:
	return sliders[key].value


func set_value(key: String, v: float) -> void:
	sliders[key].value = v


func _reset() -> void:
	for key: String in sliders:
		sliders[key].value = DEFAULTS[key]


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) != OK:
		return
	for key: String in sliders:
		sliders[key].value = float(cfg.get_value("view", key, DEFAULTS[key]))
	for key: String in picks:
		var id := str(cfg.get_value("class", key, ""))
		var o: OptionButton = picks[key]
		for i in o.item_count:
			if o.get_item_metadata(i) == id:
				o.select(i)
	skin = clampi(int(cfg.get_value("class", "skin", 0)), 0, SKINS.size() - 1)
	sniper_grip = bool(cfg.get_value("class", "sniper_grip", true))
	motion_blur = bool(cfg.get_value("view", "motion_blur", true))
	music_volume = float(cfg.get_value("audio", "music", 0.45))
	# Older saves kept only the sniper's picks, in one section.
	for key: String in attach["sniper"]:
		attach["sniper"][key] = cfg.get_value("attach", key, attach["sniper"][key])
	for weapon_id: String in attach:
		var section := "attach_" + weapon_id
		if cfg.has_section(section):
			for key: String in cfg.get_section_keys(section):
				attach[weapon_id][key] = cfg.get_value(section, key)
	attach["sniper"]["griff"] = "vertikal" if sniper_grip else "keiner"
	lethal = str(cfg.get_value("class", "lethal", "granate"))
	tactical = str(cfg.get_value("class", "tactical", "blend"))
	for i in 3:
		var saved := str(cfg.get_value("perks", "slot%d" % i, perk_ids[i]))
		if Perks.SLOTS[i]["ids"].has(saved):
			perk_ids[i] = saved


func _save() -> void:
	var cfg := ConfigFile.new()
	for key: String in sliders:
		cfg.set_value("view", key, sliders[key].value)
	for key: String in picks:
		cfg.set_value("class", key, weapon(key))
	cfg.set_value("class", "skin", skin)
	cfg.set_value("class", "sniper_grip", sniper_grip)
	cfg.set_value("view", "motion_blur", motion_blur)
	cfg.set_value("audio", "music", music_volume)
	for weapon_id: String in attach:
		for key: String in attach[weapon_id]:
			cfg.set_value("attach_" + weapon_id, key, attach[weapon_id][key])
	cfg.set_value("class", "lethal", lethal)
	cfg.set_value("class", "tactical", tactical)
	for i in 3:
		cfg.set_value("perks", "slot%d" % i, perk_ids[i])
	cfg.save(SAVE)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or blocked:
		return
	var esc: bool = event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	var touch_pause: bool = event is InputEventAction and event.action == "ui_cancel" and event.pressed
	if esc or touch_pause:
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


# freeze = false shows the menu without stopping the game (used by the self-test).
func open(freeze := true) -> void:
	is_open = true
	visible = true
	frozen = freeze
	if freeze:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	is_open = false
	visible = false
	if frozen:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if enabled:
		_save()
