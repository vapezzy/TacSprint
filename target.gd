extends StaticBody3D

signal was_hit

var down := false


func _ready() -> void:
	var size := Vector3(0.55, 1.7, 0.1)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.25, 0.15)
	box.material = mat
	mesh.mesh = box
	mesh.position.y = size.y / 2.0
	add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position.y = size.y / 2.0
	add_child(col)


func hit(_damage := 0.0, _at := Vector3.ZERO) -> void:
	if down:
		return
	down = true
	was_hit.emit()
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", deg_to_rad(-85.0), 0.15)
	tw.tween_interval(2.0)
	tw.tween_property(self, "rotation:x", 0.0, 0.3)
	tw.tween_callback(func() -> void: down = false)
