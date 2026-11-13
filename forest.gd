extends "res://range_dressing.gd"

# A forest for maps that stand in the woods: the range's lawn and its trees,
# planted at the spots the map gives (nothing else of the range).
# spots: [[position, pine], ...]

var spots: Array = []


func _ready() -> void:
	rng.seed = 4242
	_materials()
	_lawn()
	for s: Array in spots:
		_tree(s[0], s[1])
