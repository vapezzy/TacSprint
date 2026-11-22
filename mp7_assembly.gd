extends RefCounted

const PART_ORDER := ["receiver", "barrel", "mag", "stock", "grip"]
# Receiver tag positions after applying their parent transforms and converting source units.
const MOUNTS := {
	"receiver": Vector3.ZERO,
	"barrel": Vector3.ZERO,
	"mag": Vector3(-0.119685, -0.103556, 0.0),
	"stock": Vector3(-0.288519, 0.024740, 0.0),
	"grip": Vector3(-0.144043, -0.066269, 0.0),
}
const MODEL_SCALE := 0.75
const RIGHT_WRIST := Vector3(0.036, -0.098, 0.13)
# Godot-converted tag positions from the receiver GLB; empty GLTF tag nodes
# are omitted by Godot's scene importer.
const RIGHT_IK := Vector3(-0.210718, -0.069418, 0.008179)
# ADS values keep V5's sight at the MP5's rear-sight depth. Muzzle and port
# points use the matching GLB tags, all in viewmodel space.
const SIGHT_Y := -0.014
const SIGHT_X := -0.029866
const ADS_Z := -0.4
const MUZZLE := Vector3(0.029866, -0.062087, -0.080943)
const PORT := Vector3(0.043220, -0.059515, 0.102032)
const MATERIAL_STYLES := {
	"weapon_vm_sm_mpapa7_v18_body": {"color": Color(0.075, 0.085, 0.08), "metallic": 0.55, "roughness": 0.48},
	"weapon_vm_sm_mpapa7_v18_body_01": {"color": Color(0.12, 0.14, 0.12), "metallic": 0.12, "roughness": 0.78},
	"weapon_vm_sm_mpapa7_v18_body_02": {"color": Color(0.09, 0.10, 0.095), "metallic": 0.2, "roughness": 0.72},
	"weapon_vm_sm_mpapa7_v18_sights": {"color": Color(0.035, 0.038, 0.04), "metallic": 0.35, "roughness": 0.48},
	"attachment_vm_laser_mount03_mpapa7_v18": {"color": Color(0.06, 0.065, 0.06), "metallic": 0.3, "roughness": 0.68},
	"weapon_wm_sm_mpapa7_v18_stockadapter": {"color": Color(0.10, 0.11, 0.105), "metallic": 0.35, "roughness": 0.62},
	"weapon_vm_sm_mpapa7_v18_mag": {"color": Color(0.085, 0.095, 0.09), "metallic": 0.12, "roughness": 0.82},
	"weapon_vm_sm_mpapa7_v18_stock": {"color": Color(0.11, 0.12, 0.105), "metallic": 0.05, "roughness": 0.84},
	"attachment_vm_muzzledefault04_mpapa7_v18": {"color": Color(0.12, 0.13, 0.14), "metallic": 0.72, "roughness": 0.42},
	"attachment_vm_griptape03_mpapa7_v18": {"color": Color(0.035, 0.04, 0.035), "metallic": 0.0, "roughness": 0.92},
}
static var _materials: Dictionary = {}
static var _device_shader: Shader
const VARIANTS := {
	"mp7_v5": {
		"receiver": preload("res://models/mp7/mp7_v5_receiver.glb"),
		"barrel": preload("res://models/mp7/mp7_v5_barrel.glb"),
		"mag": preload("res://models/mp7/mp7_v5_mag.glb"),
		"stock": preload("res://models/mp7/mp7_v5_stock.glb"),
		"grip": preload("res://models/mp7/mp7_v5_grip.glb"),
	},
}


static func build(variant: String) -> Node3D:
	if not VARIANTS.has(variant):
		push_error("Unknown MP7 assembly: " + variant)
		return null
	var assembly := Node3D.new()
	assembly.name = variant.to_upper()
	assembly.rotation.y = PI / 2.0
	assembly.scale = Vector3.ONE * MODEL_SCALE
	for part_name: String in PART_ORDER:
		var packed := VARIANTS[variant][part_name] as PackedScene
		var part := packed.instantiate() as Node3D
		if part == null:
			push_error("MP7 part is not a Node3D: " + part_name)
			assembly.free()
			return null
		part.position = MOUNTS[part_name]
		_apply_fallback_materials(part)
		assembly.add_child(part)

	var right_local := MOUNTS["receiver"] + RIGHT_IK
	assembly.position = RIGHT_WRIST - assembly.basis * right_local
	return assembly


static func _apply_fallback_materials(part: Node3D) -> void:
	if _device_shader == null:
		_device_shader = load("res://device.gdshader")
	for child: Node in part.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		mesh_instance.layers = 2
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.extra_cull_margin = 4.0
		var style_name := _material_style_for(mesh_instance.name)
		if style_name == "":
			var fallback := ShaderMaterial.new()
			fallback.shader = _device_shader
			fallback.set_shader_parameter("albedo", Color(0.1, 0.1, 0.1))
			fallback.set_shader_parameter("roughness", 0.6)
			fallback.set_shader_parameter("metallic", 0.3)
			fallback.set_shader_parameter("vm_fov", 55.0)
			mesh_instance.material_override = fallback
			continue
		if not _materials.has(style_name):
			var style: Dictionary = MATERIAL_STYLES[style_name]
			var mat := ShaderMaterial.new()
			mat.shader = _device_shader
			mat.set_shader_parameter("albedo", style["color"])
			mat.set_shader_parameter("roughness", float(style["roughness"]))
			mat.set_shader_parameter("metallic", float(style["metallic"]))
			mat.set_shader_parameter("vm_fov", 55.0)
			_materials[style_name] = mat
		mesh_instance.material_override = _materials[style_name]


static func _material_style_for(mesh_name: String) -> String:
	var best_match := ""
	for style_name: String in MATERIAL_STYLES:
		if mesh_name.begins_with(style_name) and style_name.length() > best_match.length():
			best_match = style_name
	return best_match


static func bounds(assembly: Node3D, relative_to: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var inverse := relative_to.global_transform.affine_inverse()
	for child: Node in assembly.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var transform := inverse * mesh_instance.global_transform
		var part_box := transform * mesh_instance.mesh.get_aabb()
		result = part_box if not found else result.merge(part_box)
		found = true
	if not found:
		push_error("MP7 assembly has no meshes: " + assembly.name)
	return result
