extends RefCounted

# Perks: one per slot. The effects themselves live in player.gd (search for perk("...")).

const SLOTS := [
	{"title": "PERK 1  ·  BEWEGUNG", "ids": ["dauerlaeufer", "leichtfuss", "gleiter"]},
	{"title": "PERK 2  ·  HANDHABUNG", "ids": ["flinke_finger", "aufgeputscht", "schnellzieher"]},
	{"title": "PERK 3  ·  KAMPF", "ids": ["ruhige_hand", "hueftschuetze", "erweitertes_magazin", "dickes_fell"]},
]

const DEFAULTS := ["dauerlaeufer", "flinke_finger", "ruhige_hand"]

const ALL := {
	"dauerlaeufer": {"name": "Dauerläufer", "text": "Tac-Sprint hält doppelt so lange. Geduckt 30 % schneller."},
	"leichtfuss": {"name": "Leichtfuß", "text": "Kein Tempoverlust bei der Landung, Sprünge ermüden nicht."},
	"gleiter": {"name": "Gleiter", "text": "Slides dauern 25 % länger und tragen dich weiter."},
	"flinke_finger": {"name": "Flinke Finger", "text": "Nachladen geht 30 % schneller."},
	"aufgeputscht": {"name": "Flinke Hände", "text": "Waffenwechsel mehr als doppelt so schnell."},
	"schnellzieher": {"name": "Schnellzieher", "text": "25 % schneller im Anschlag (Zielen)."},
	"ruhige_hand": {"name": "Ruhige Hand", "text": "20 % weniger Rückstoß."},
	"hueftschuetze": {"name": "Hüftschütze", "text": "35 % weniger Streuung aus der Hüfte."},
	"dickes_fell": {"name": "Dickes Fell", "text": "150 statt 130 Leben."},
	"erweitertes_magazin": {"name": "Erweitertes Magazin", "text": "30 % mehr Schuss pro Magazin."},
}
