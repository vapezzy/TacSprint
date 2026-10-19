extends RefCounted

# Controller settings: which button does what, with the usual shooter layouts
# as presets, plus stick and aiming options. Every binding can be changed on
# top of a preset. Saved to user://controls.cfg.
#
# A binding is a joypad button number, or 100 / 101 for the left / right trigger.

const SAVE := "user://controls.cfg"
const L2 := 100
const R2 := 101

const ACTIONS := [
	["jump", "Springen"], ["crouch", "Ducken / Slide"], ["prone", "Hinlegen"], ["sprint", "Sprint / Tac-Sprint"],
	["reload", "Nachladen"], ["swap", "Waffe wechseln"], ["ads", "Zielen"], ["fire", "Schießen"],
	["inspect", "Waffe ansehen"], ["ratte", "Ratte (Streak)"], ["lethal", "Primär-Ausrüstung"], ["tactical", "Taktische Ausrüstung"],
]

const NAMES := {
	0: "A / Kreuz", 1: "B / Kreis", 2: "X / Viereck", 3: "Y / Dreieck", 4: "Back / Share", 6: "Start / Options",
	7: "L3", 8: "R3", 9: "L1", 10: "R1", 11: "Steuerkreuz hoch", 12: "Steuerkreuz runter",
	13: "Steuerkreuz links", 14: "Steuerkreuz rechts", 100: "L2", 101: "R2",
}

const STANDARD := {"jump": 0, "crouch": 1, "prone": 12, "sprint": 7, "reload": 2, "swap": 3, "ads": 100, "fire": 101,
		"inspect": 8, "ratte": 14, "lethal": 10, "tactical": 9}
# Each preset lists only what differs from Standard.
const PRESETS := {
	"Standard": {},
	"Tactical": {"crouch": 8, "inspect": 1},
	"Bumper Jumper": {"jump": 9, "tactical": 0},
	"Bumper Jumper Tactical": {"jump": 9, "tactical": 0, "crouch": 8, "inspect": 1},
	"Flipped": {"ads": 9, "fire": 10, "tactical": 100, "lethal": 101},
	"Bumper Jumper Flipped": {"jump": 100, "ads": 9, "fire": 10, "tactical": 0, "lethal": 101},
}

static var preset := "Standard"
static var bindings := STANDARD.duplicate()
static var deadzone := 0.15
static var stick_sens := 1.0
static var ads_mult := 0.6        # look speed while aiming, as a share of normal (mouse and stick)
static var auto_sprint := false
static var auto_tac := false


static func use_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	preset = name
	bindings = STANDARD.duplicate()
	for action: String in PRESETS[name]:
		bindings[action] = PRESETS[name][action]
	apply()


# Gives one action a new button. Whatever had that button before takes the old one, so nothing is lost.
static func bind(action: String, code: int) -> void:
	var old: int = bindings[action]
	for other: String in bindings:
		if other != action and bindings[other] == code:
			bindings[other] = old
	bindings[action] = code
	apply()


static func name_of(code: int) -> String:
	return NAMES.get(code, "Taste %d" % code)


# Writes the bindings into the input map (keyboard and mouse events stay as they are).
static func apply() -> void:
	for action: String in bindings:
		var id := "mv_" + action
		if not InputMap.has_action(id):
			InputMap.add_action(id)
		for ev: InputEvent in InputMap.action_get_events(id):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(id, ev)
		var code: int = bindings[action]
		if code >= 100:
			var trigger := InputEventJoypadMotion.new()
			trigger.axis = JOY_AXIS_TRIGGER_LEFT if code == L2 else JOY_AXIS_TRIGGER_RIGHT
			trigger.axis_value = 1.0
			InputMap.action_add_event(id, trigger)
		else:
			var button := InputEventJoypadButton.new()
			button.button_index = code as JoyButton
			InputMap.action_add_event(id, button)


# A stick position with the dead zone taken out, rescaled so it still reaches 1.
static func stick(x: float, y: float) -> Vector2:
	var v := Vector2(x, y)
	var amount := v.length()
	if amount <= deadzone:
		return Vector2.ZERO
	return v / amount * minf((amount - deadzone) / (1.0 - deadzone), 1.0)


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("pad", "preset", preset)
	for action: String in bindings:
		cfg.set_value("bindings", action, bindings[action])
	cfg.set_value("pad", "deadzone", deadzone)
	cfg.set_value("pad", "stick_sens", stick_sens)
	cfg.set_value("pad", "ads_mult", ads_mult)
	cfg.set_value("pad", "auto_sprint", auto_sprint)
	cfg.set_value("pad", "auto_tac", auto_tac)
	cfg.save(SAVE)


static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) == OK:
		preset = str(cfg.get_value("pad", "preset", "Standard"))
		for action: String in STANDARD:
			bindings[action] = int(cfg.get_value("bindings", action, STANDARD[action]))
		deadzone = float(cfg.get_value("pad", "deadzone", 0.15))
		stick_sens = float(cfg.get_value("pad", "stick_sens", 1.0))
		ads_mult = float(cfg.get_value("pad", "ads_mult", 0.6))
		auto_sprint = bool(cfg.get_value("pad", "auto_sprint", false))
		auto_tac = bool(cfg.get_value("pad", "auto_tac", false))
	apply()


# Settings by name, for the menu's sliders and switches.
static func value(key: String) -> Variant:
	match key:
		"deadzone":
			return deadzone
		"stick_sens":
			return stick_sens
		"ads_mult":
			return ads_mult
		"auto_sprint":
			return auto_sprint
		"auto_tac":
			return auto_tac
	return null


static func set_value(key: String, v: Variant) -> void:
	match key:
		"deadzone":
			deadzone = float(v)
		"stick_sens":
			stick_sens = float(v)
		"ads_mult":
			ads_mult = float(v)
		"auto_sprint":
			auto_sprint = bool(v)
		"auto_tac":
			auto_tac = bool(v)
