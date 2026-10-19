extends RefCounted

# Every weapon of the class system. A class is one primary and one secondary.
# All firearms share the pistol grip position, and the long guns share the
# foregrip and magazine position, so one set of hand models fits them all.
#
# interval: seconds between shots. recoil: multiplier on the view kick.
# spread: hip-fire cone in degrees. ads_zoom: share of the field of view left
# when aiming. sight_y / ads_z: where the sight line sits and how far the
# weapon is held from the eye when aiming. two_handed = false hides the support arm.

const PRIMARY := ["smg", "ar", "sniper"]
const SECONDARY := ["pistol", "knife"]

const ALL := {
	"smg": {
		"name": "MP5", "kind": "Maschinenpistole", "damage": 24.0, "mesh": "smg_body.bin", "sfx": "smg", "kick": 1.6, "mag": "mag.bin", "mag_size": 30,
		"interval": 0.075, "auto": true, "recoil": 1.0, "spread": 2.2, "reload": 2.2,
		"ads_zoom": 0.72, "ads_time": 0.25, "sight_y": 0.066, "ads_z": -0.4,
		"muzzle": Vector3(0, 0.0, -0.47), "port": Vector3(0.026, 0.017, -0.03),
		"two_handed": true, "scope": false, "melee": false, "hip_rot": Vector3.ZERO, "flash": 1.0,
	},
	"ar": {
		"name": "KR-4", "kind": "Sturmgewehr", "damage": 30.0, "forward": 0.03, "mesh": "ar_body.bin", "sfx": "ar", "mag": "mag.bin", "mag_size": 30,
		"interval": 0.086, "auto": true, "recoil": 1.25, "spread": 2.8, "reload": 2.4,
		"ads_zoom": 0.68, "ads_time": 0.3, "sight_y": 0.066, "ads_z": -0.38,
		"muzzle": Vector3(0, 0.012, -0.565), "port": Vector3(0.024, 0.018, -0.03),
		"two_handed": true, "scope": false, "melee": false, "hip_rot": Vector3.ZERO, "flash": 1.6,
	},
	"sniper": {
		"name": "FJ50", "kind": "Scharfschützengewehr", "damage": 120.0, "forward": 0.04, "scope_zoom": 0.13, "mesh": "sniper.bin", "nogrip_mesh": "sniper_nogrip.bin", "sfx": "sniper", "bolt": "sniper_bolt.bin", "mag": "sniper_mag.bin", "mag_size": 7,
		"interval": 1.25, "auto": false, "recoil": 3.4, "spread": 5.0, "reload": 2.8,
		"ads_zoom": 0.6, "ads_time": 0.42, "sight_y": 0.078, "ads_z": -0.199,
		"muzzle": Vector3(0, 0.016, -0.86), "port": Vector3(0.026, 0.02, -0.03),
		"two_handed": true, "scope": true, "melee": false, "hip_rot": Vector3.ZERO, "flash": 2.2, "flash_bright": 1.8,
	},
	"pistol": {
		"name": "P9", "kind": "Pistole", "damage": 34.0, "mesh": "pistol.bin", "sfx": "pistol", "mag": "", "mag_size": 15,
		"interval": 0.13, "auto": false, "recoil": 1.1, "spread": 1.8, "reload": 1.5,
		"ads_zoom": 0.8, "ads_time": 0.18, "sight_y": 0.017, "ads_z": -0.42,
		"muzzle": Vector3(0, -0.002, -0.09), "port": Vector3(0.016, 0.004, 0.0),
		"two_handed": false, "scope": false, "melee": false, "hip_rot": Vector3.ZERO, "flash": 1.2,
	},
	"knife": {
		"name": "Kampfmesser", "kind": "Nahkampf", "damage": 120.0, "mesh": "knife.bin", "mag": "", "mag_size": 0,
		"interval": 0.55, "auto": false, "recoil": 0.0, "spread": 0.0, "reload": 0.0,
		"ads_zoom": 1.0, "ads_time": 0.2, "sight_y": 0.0, "ads_z": -0.4,
		"muzzle": Vector3.ZERO, "port": Vector3.ZERO,
		"two_handed": false, "scope": false, "melee": true, "hip_rot": Vector3(-30, 4, -6), "flash": 0.0,
	},
}


# Class editor: what can be fitted to which weapon. An option's "set" values
# replace the weapon's, its "mul" values are multiplied in. Scopes list the
# magnifications they can be set to.
const ATTACHMENTS := {
	"sniper": [
		{"slot": "griff", "label": "GRIFF", "options": [
			{"id": "vertikal", "name": "Vertikalgriff", "text": "Ruhiger im Anschlag, weniger Wackeln.",
				"set": {}, "mul": {"sway": 0.8}},
			{"id": "keiner", "name": "Kein Griff", "text": "Hand am Vorderschaft: etwas schneller im Anschlag, wackelt mehr.",
				"set": {"plain_hold": true}, "mul": {"ads_time": 0.92, "sway": 1.2}},
		]},
		{"slot": "lauf", "label": "LAUF", "options": [
			{"id": "standard", "name": "Standardlauf", "text": "Ausgewogen. Kopftreffer tötet, Körper braucht zwei.",
				"set": {"barrel": "sniper_barrel_standard.bin", "muzzle": Vector3(0, 0.016, -0.86), "side_flash": true}, "mul": {}},
			{"id": "lang", "name": "Langstreckenlauf", "text": "Mehr Schaden: ein Körpertreffer reicht. Schwerer, langsamer im Anschlag.",
				"set": {"barrel": "sniper_barrel_long.bin", "muzzle": Vector3(0, 0.016, -1.01), "side_flash": true}, "mul": {"damage": 1.15, "ads_time": 1.15, "recoil": 0.9}},
			{"id": "schalldaempfer", "name": "Schalldämpfer", "text": "Leiser Schuss, kaum Mündungsfeuer. Etwas weniger Schaden.",
				"set": {"barrel": "sniper_barrel_sup.bin", "muzzle": Vector3(0, 0.016, -0.8), "suppressed": true}, "mul": {"damage": 0.9, "ads_time": 1.05, "flash": 0.25}},
		]},
		{"slot": "visier", "label": "VISIER", "options": [
			{"id": "zielfernrohr", "name": "Zielfernrohr", "text": "Starke Vergrößerung für große Distanzen.",
				"set": {"optic": "sniper_optic_scope.bin", "scope": true, "eye_z": 0.165, "eye_r": 0.0168}, "mul": {},
				"zoom": [6.0, 8.0, 10.0, 12.0], "zoom_default": 8.0},
			{"id": "kompakt", "name": "Kompaktvisier", "text": "Kürzer und leichter: schneller im Anschlag, weniger Zoom.",
				"set": {"optic": "sniper_optic_compact.bin", "scope": true, "eye_z": 0.115, "eye_r": 0.0152, "ads_z": -0.141}, "mul": {"ads_time": 0.82},
				"zoom": [3.0, 4.0, 5.0, 6.0], "zoom_default": 4.0},
			{"id": "rotpunkt", "name": "Reflexvisier", "text": "Kein Zoom, freie Sicht. Am schnellsten im Anschlag.",
				"set": {"optic": "sniper_optic_dot.bin", "scope": false, "sight_y": 0.066, "ads_z": -0.27, "ads_zoom": 0.78, "dot": Vector3(0, 0.066, -0.046)},
				"mul": {"ads_time": 0.65}},
		]},
	],
}


# Sights on the MP5 sit on a claw mount (top at y = 0.058), on the KR-4 straight
# on its rail (top at y = 0.050). Each optic's sight line is its own height above that.
const SMG_MOUNT := ["smg_mount.bin", Vector3.ZERO]

const ATTACHMENTS_SMG := [
	{"slot": "muendung", "label": "MÜNDUNG", "default": "schalldaempfer", "options": [
		{"id": "schalldaempfer", "name": "Schalldämpfer", "text": "Leise, kaum Mündungsfeuer, etwas weniger Rückstoß. Etwas schwerer.",
			"set": {"parts": [["muz_sup_small.bin", Vector3(0, 0, -0.305)]], "muzzle": Vector3(0, 0, -0.47), "suppressed": true},
			"mul": {"flash": 0.2, "recoil": 0.92, "ads_time": 1.04}},
		{"id": "keine", "name": "Ohne", "text": "Nackter Lauf: lautes, großes Mündungsfeuer.",
			"set": {"muzzle": Vector3(0, 0, -0.32)}, "mul": {}},
		{"id": "feuerdaempfer", "name": "Feuerdämpfer", "text": "Kleineres Mündungsfeuer, etwas weniger Rückstoß.",
			"set": {"parts": [["muz_hider.bin", Vector3(0, 0, -0.312)]], "muzzle": Vector3(0, 0, -0.36)}, "mul": {"flash": 0.45, "recoil": 0.95}},
		{"id": "kompensator", "name": "Kompensator", "text": "Drückt die Mündung runter: deutlich weniger Rückstoß, mehr Feuer.",
			"set": {"parts": [["muz_comp.bin", Vector3(0, 0, -0.312)]], "muzzle": Vector3(0, 0, -0.365)}, "mul": {"recoil": 0.82, "flash": 1.15}},
	]},
	{"slot": "laser", "label": "LASER", "default": "kein", "options": [
		{"id": "kein", "name": "Kein Laser", "text": "Nichts an der Seite.", "set": {}, "mul": {}},
		{"id": "laser", "name": "Laser", "text": "Sichtbarer Laser: Hüftfeuer streut deutlich weniger.",
			"set": {"parts": [["laser.bin", Vector3(0.0305, -0.004, -0.2)]], "laser_beam": Vector3(0.0305, 0.0, -0.224)}, "mul": {"spread": 0.7}},
		{"id": "kombi", "name": "Laser + Lampe", "text": "Laser mit Waffenlicht: weniger Streuung, etwas schwerer.",
			"set": {"parts": [["laser_light.bin", Vector3(0.0305, -0.004, -0.2)]], "laser_beam": Vector3(0.0305, 0.0, -0.224)}, "mul": {"spread": 0.65, "ads_time": 1.05}},
	]},
	{"slot": "griff", "label": "GRIFF", "default": "vertikal", "options": [
		{"id": "vertikal", "name": "Vertikalgriff", "text": "Ruhiger im Dauerfeuer.",
			"set": {"parts": [["grip_vertical_smg.bin", Vector3.ZERO]]}, "mul": {"recoil": 0.92}},
		{"id": "taktisch", "name": "Taktischer Griff", "text": "Dicker, geriffelt: noch weniger Rückstoß, etwas langsamer.",
			"set": {"parts": [["grip_tactical_smg.bin", Vector3.ZERO]]}, "mul": {"recoil": 0.85, "ads_time": 1.05}},
		{"id": "keiner", "name": "Kein Griff", "text": "Hand unterm Gehäuse: schneller im Anschlag, mehr Rückstoß.",
			"set": {"plain_hold": true, "hold_offset": Vector3(0, 0.0015, 0)}, "mul": {"ads_time": 0.92, "recoil": 1.1}},
	]},
	{"slot": "magazin", "label": "MAGAZIN", "default": "standard", "options": [
		{"id": "standard", "name": "30 Schuss", "text": "Standardmagazin.", "set": {}, "mul": {}},
		{"id": "erweitert", "name": "45 Schuss", "text": "Mehr Schuss, langsamer nachladen und zielen.",
			"set": {"mag": "mag_ext.bin"}, "mul": {"mag_size": 1.5, "reload": 1.2, "ads_time": 1.06}},
		{"id": "schnell", "name": "Schnellwechsel", "text": "Mit Zuglasche: deutlich schneller nachladen.",
			"set": {"mag": "mag_fast.bin"}, "mul": {"reload": 0.75}},
	]},
	{"slot": "schaft", "label": "SCHAFT", "default": "keiner", "options": [
		{"id": "keiner", "name": "Ohne Schaft", "text": "Kurz und schnell.", "set": {}, "mul": {}},
		{"id": "klapp", "name": "Klappschaft", "text": "Weniger Rückstoß, etwas langsamer im Anschlag.",
			"set": {"parts": [["smg_stock_fold.bin", Vector3.ZERO]]}, "mul": {"recoil": 0.86, "ads_time": 1.05}},
		{"id": "fest", "name": "Festschaft", "text": "Am ruhigsten, am langsamsten im Anschlag.",
			"set": {"parts": [["smg_stock_fixed.bin", Vector3.ZERO]]}, "mul": {"recoil": 0.76, "ads_time": 1.12}},
	]},
	{"slot": "visier", "label": "VISIER", "default": "kimme", "options": [
		{"id": "kimme", "name": "Kimme & Korn", "text": "Offene Visierung.", "set": {}, "mul": {}},
		{"id": "rotpunkt", "name": "Rotpunkt", "text": "Klarer Punkt, kaum Verdeckung.",
			"set": {"parts": [SMG_MOUNT, ["opt_dot.bin", Vector3(0, 0.058, -0.02)]], "sight_y": 0.08, "ads_z": -0.3, "ads_zoom": 0.7,
				"dot": Vector3(0, 0.08, -0.028)}, "mul": {"ads_time": 1.03}},
		{"id": "holo", "name": "Holo", "text": "Großes Fenster, Punkt im Ring.",
			"set": {"parts": [SMG_MOUNT, ["opt_holo.bin", Vector3(0, 0.058, -0.02)]], "sight_y": 0.084, "ads_z": -0.28, "ads_zoom": 0.7,
				"dot": Vector3(0, 0.084, -0.05), "dot_ring": true}, "mul": {"ads_time": 1.05}},
		{"id": "zielvisier", "name": "3x Zielvisier", "text": "3-fache Vergrößerung, langsamer im Anschlag.",
			"set": {"parts": [SMG_MOUNT, ["opt_acog.bin", Vector3(0, 0.058, -0.03)]], "sight_y": 0.09, "ads_z": -0.0685, "ads_zoom": 0.6,
				"scope": true, "eye_z": 0.0385, "eye_r": 0.0105, "scope_mag": 3.0}, "mul": {"ads_time": 1.15}},
	]},
]

const ATTACHMENTS_AR := [
	{"slot": "muendung", "label": "MÜNDUNG", "default": "feuerdaempfer", "options": [
		{"id": "feuerdaempfer", "name": "Feuerdämpfer", "text": "Standard: wenig Mündungsfeuer.",
			"set": {"parts": [["muz_hider.bin", Vector3(0, 0.012, -0.522)]], "muzzle": Vector3(0, 0.012, -0.567)}, "mul": {}},
		{"id": "keine", "name": "Ohne", "text": "Nackter Lauf: großes Mündungsfeuer.",
			"set": {"muzzle": Vector3(0, 0.012, -0.53)}, "mul": {"flash": 1.5}},
		{"id": "kompensator", "name": "Kompensator", "text": "Weniger Rückstoß nach oben.",
			"set": {"parts": [["muz_comp.bin", Vector3(0, 0.012, -0.522)]], "muzzle": Vector3(0, 0.012, -0.575)}, "mul": {"recoil": 0.85, "flash": 1.2}},
		{"id": "bremse", "name": "Bremse", "text": "Am wenigsten Rückstoß, Feuer schlägt seitlich raus.",
			"set": {"parts": [["muz_brake.bin", Vector3(0, 0.012, -0.522)]], "muzzle": Vector3(0, 0.012, -0.588), "side_flash": true},
			"mul": {"recoil": 0.78, "flash": 1.4}},
		{"id": "schalldaempfer", "name": "Schalldämpfer", "text": "Leise, kaum Feuer. Lang und schwer.",
			"set": {"parts": [["muz_sup_large.bin", Vector3(0, 0.012, -0.522)]], "muzzle": Vector3(0, 0.012, -0.722), "suppressed": true},
			"mul": {"flash": 0.15, "recoil": 0.9, "ads_time": 1.08}},
	]},
	{"slot": "laser", "label": "LASER", "default": "kein", "options": [
		{"id": "kein", "name": "Kein Laser", "text": "Nichts an der Seite.", "set": {}, "mul": {}},
		{"id": "laser", "name": "Laser", "text": "Sichtbarer Laser: Hüftfeuer streut deutlich weniger.",
			"set": {"parts": [["laser.bin", Vector3(0.0335, 0.012, -0.27)]], "laser_beam": Vector3(0.0335, 0.016, -0.294)}, "mul": {"spread": 0.7}},
		{"id": "kombi", "name": "Laser + Lampe", "text": "Laser mit Waffenlicht: weniger Streuung, etwas schwerer.",
			"set": {"parts": [["laser_light.bin", Vector3(0.0335, 0.012, -0.27)]], "laser_beam": Vector3(0.0335, 0.016, -0.294)}, "mul": {"spread": 0.65, "ads_time": 1.05}},
	]},
	{"slot": "griff", "label": "GRIFF", "default": "vertikal", "options": [
		{"id": "vertikal", "name": "Vertikalgriff", "text": "Ruhiger im Dauerfeuer.",
			"set": {"parts": [["grip_vertical_ar.bin", Vector3.ZERO]]}, "mul": {"recoil": 0.92}},
		{"id": "taktisch", "name": "Taktischer Griff", "text": "Dicker, geriffelt: noch weniger Rückstoß, etwas langsamer.",
			"set": {"parts": [["grip_tactical_ar.bin", Vector3.ZERO]]}, "mul": {"recoil": 0.85, "ads_time": 1.05}},
		{"id": "keiner", "name": "Kein Griff", "text": "Hand am Handschutz: schneller im Anschlag, mehr Rückstoß.",
			"set": {"plain_hold": true, "hold_offset": Vector3(0, 0.0135, 0)}, "mul": {"ads_time": 0.92, "recoil": 1.1}},
	]},
	{"slot": "magazin", "label": "MAGAZIN", "default": "standard", "options": [
		{"id": "standard", "name": "30 Schuss", "text": "Standardmagazin.", "set": {}, "mul": {}},
		{"id": "erweitert", "name": "45 Schuss", "text": "Mehr Schuss, langsamer nachladen und zielen.",
			"set": {"mag": "mag_ext.bin"}, "mul": {"mag_size": 1.5, "reload": 1.2, "ads_time": 1.06}},
		{"id": "schnell", "name": "Schnellwechsel", "text": "Mit Zuglasche: deutlich schneller nachladen.",
			"set": {"mag": "mag_fast.bin"}, "mul": {"reload": 0.75}},
	]},
	{"slot": "schaft", "label": "SCHAFT", "default": "standard", "options": [
		{"id": "standard", "name": "Standardschaft", "text": "Ausgewogen.",
			"set": {"parts": [["ar_stock_std.bin", Vector3.ZERO]]}, "mul": {}},
		{"id": "skelett", "name": "Skelettschaft", "text": "Leichter: schneller im Anschlag, etwas mehr Rückstoß.",
			"set": {"parts": [["ar_stock_skel.bin", Vector3.ZERO]]}, "mul": {"ads_time": 0.9, "recoil": 1.1}},
		{"id": "keiner", "name": "Nur Pufferrohr", "text": "Am schnellsten, springt am meisten.", "set": {}, "mul": {"ads_time": 0.82, "recoil": 1.3}},
	]},
	{"slot": "visier", "label": "VISIER", "default": "kimme", "options": [
		{"id": "kimme", "name": "Kimme & Korn", "text": "Offene Visierung.", "set": {}, "mul": {}},
		{"id": "rotpunkt", "name": "Rotpunkt", "text": "Klarer Punkt, kaum Verdeckung.",
			"set": {"parts": [["opt_dot.bin", Vector3(0, 0.05, -0.02)]], "sight_y": 0.072, "ads_z": -0.3, "ads_zoom": 0.68,
				"dot": Vector3(0, 0.072, -0.028)}, "mul": {"ads_time": 1.03}},
		{"id": "holo", "name": "Holo", "text": "Großes Fenster, Punkt im Ring.",
			"set": {"parts": [["opt_holo.bin", Vector3(0, 0.05, -0.02)]], "sight_y": 0.076, "ads_z": -0.28, "ads_zoom": 0.68,
				"dot": Vector3(0, 0.076, -0.05), "dot_ring": true}, "mul": {"ads_time": 1.05}},
		{"id": "zielvisier", "name": "3x Zielvisier", "text": "3-fache Vergrößerung, langsamer im Anschlag.",
			"set": {"parts": [["opt_acog.bin", Vector3(0, 0.05, -0.03)]], "sight_y": 0.082, "ads_z": -0.0685, "ads_zoom": 0.6,
				"scope": true, "eye_z": 0.0385, "eye_r": 0.0105, "scope_mag": 3.0}, "mul": {"ads_time": 1.15}},
	]},
]


static func groups(id: String) -> Array:
	match id:
		"smg":
			return ATTACHMENTS_SMG
		"ar":
			return ATTACHMENTS_AR
	return ATTACHMENTS.get(id, [])


static func has_attachments(id: String) -> bool:
	return not groups(id).is_empty()


static func option(id: String, slot: String, pick: String) -> Dictionary:
	for group: Dictionary in groups(id):
		if group["slot"] != slot:
			continue
		var fallback: Dictionary = group["options"][0]
		for opt: Dictionary in group["options"]:
			if opt["id"] == pick:
				return opt
			if opt["id"] == group.get("default", ""):
				fallback = opt
		return fallback
	return {}


# The weapon with the chosen attachments fitted. picks: slot -> option id, plus
# "zoom_<optic>" -> magnification. Parts of every option are collected in "parts".
static func build(id: String, picks: Dictionary) -> Dictionary:
	var w: Dictionary = ALL[id].duplicate()
	w["id"] = id
	var parts: Array = []
	for group: Dictionary in groups(id):
		var opt := option(id, group["slot"], str(picks.get(group["slot"], "")))
		var set_values: Dictionary = opt["set"]
		for key: String in set_values:
			if key == "parts":
				parts.append_array(set_values[key])
			else:
				w[key] = set_values[key]
		var mul: Dictionary = opt["mul"]
		for key: String in mul:
			w[key] = float(w.get(key, 1.0)) * float(mul[key])
		if opt.has("zoom"):
			w["scope_mag"] = float(picks.get("zoom_" + str(opt["id"]), opt["zoom_default"]))
	w["mag_size"] = int(round(float(w["mag_size"])))
	w["parts"] = parts
	return w
