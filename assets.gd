extends RefCounted

# Shared texture loading. Scanned maps come from the textures folder
# (CC0, see textures/CREDITS.txt); each file is decoded once.

static var _cache := {}


static func tex(file: String, grey := false) -> ImageTexture:
	var key := file + ("|grey" if grey else "")
	if _cache.has(key):
		return _cache[key]
	var img := image("res://textures/" + file)
	if img == null:
		push_warning("Texture missing: " + file)
		return null
	if grey:
		img.adjust_bcs(1.0, 1.25, 0.0)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


# Reads a picture straight out of the game's files. JPEG and PNG decode from
# memory; other formats (the HDR sky) go through a copy in user://, since an
# exported app has no real folder to read them from.
static func image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var ext := path.get_extension().to_lower()
	var err := ERR_FILE_UNRECOGNIZED
	if ext == "jpg" or ext == "jpeg":
		err = img.load_jpg_from_buffer(bytes)
	elif ext == "png":
		err = img.load_png_from_buffer(bytes)
	else:
		var copy := "user://cache_" + path.get_file()
		if not FileAccess.file_exists(copy):
			var f := FileAccess.open(copy, FileAccess.WRITE)
			if f == null:
				return null
			f.store_buffer(bytes)
			f.close()
		return Image.load_from_file(ProjectSettings.globalize_path(copy))
	return img if err == OK else null


# A sound from the sounds folder (made by tools/make_sounds.py), decoded once.
static func sound(file: String) -> AudioStreamWAV:
	if _cache.has(file):
		return _cache[file]
	var bytes := FileAccess.get_file_as_bytes("res://sounds/" + file)
	if bytes.is_empty():
		push_warning("Sound missing: " + file)
		return null
	var s := AudioStreamWAV.load_from_buffer(bytes)
	_cache[file] = s
	return s


# Seamless greyscale cloud noise, used for stains, fading and rust masks.
static func grime() -> NoiseTexture2D:
	if _cache.has("grime"):
		return _cache["grime"]
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.008
	n.fractal_octaves = 5
	n.fractal_gain = 0.55
	var t := NoiseTexture2D.new()
	t.width = 1024
	t.height = 1024
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	_cache["grime"] = t
	return t


# Printed camouflage: blotches of four colours, shared by sleeves and trousers.
static func camo() -> NoiseTexture2D:
	if _cache.has("camo"):
		return _cache["camo"]
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.085, 0.095, 0.06), Color(0.085, 0.095, 0.06), Color(0.17, 0.18, 0.11),
			Color(0.17, 0.18, 0.11), Color(0.27, 0.245, 0.17), Color(0.27, 0.245, 0.17), Color(0.13, 0.11, 0.075)])
	ramp.offsets = PackedFloat32Array([0.0, 0.36, 0.385, 0.54, 0.565, 0.7, 0.725])
	var n := FastNoiseLite.new()
	n.seed = 21
	n.frequency = 0.011
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = n
	t.color_ramp = ramp
	_cache["camo"] = t
	return t


# The cloth, glove and boot material (arms.gdshader). weapon_fov = 0 draws it
# with the world's field of view, for the legs.
static func cloth(weapon_fov: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://arms.gdshader")
	m.set_shader_parameter("camo", camo())
	m.set_shader_parameter("cloth_n", tex("denim_fabric_nor_gl.jpg"))
	m.set_shader_parameter("cloth_r", tex("denim_fabric_rough.jpg"))
	m.set_shader_parameter("weave_n", tex("stretch_poplin_nor_gl.jpg"))
	m.set_shader_parameter("leather_n", tex("brown_leather_nor_gl.jpg"))
	m.set_shader_parameter("leather_r", tex("brown_leather_rough.jpg"))
	m.set_shader_parameter("rubber_n", tex("rubberized_track_nor_gl.jpg"))
	m.set_shader_parameter("grime", grime())
	m.set_shader_parameter("vm_fov", weapon_fov)
	return m


# A generated model from the models folder (see tools/sdf.py for the format).
static func mesh(file: String) -> ArrayMesh:
	if _cache.has("mesh:" + file):
		return _cache["mesh:" + file]
	var f := FileAccess.open("res://models/" + file, FileAccess.READ)
	if f == null:
		push_warning("Model missing: " + file + " (run the scripts in tools/)")
		return null
	var detailed := f.get_buffer(4).get_string_from_ascii() == "ARM2"
	var verts := f.get_32()
	var indices := f.get_32()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = f.get_buffer(verts * 12).to_vector3_array()
	arrays[Mesh.ARRAY_NORMAL] = f.get_buffer(verts * 12).to_vector3_array()
	arrays[Mesh.ARRAY_TEX_UV] = f.get_buffer(verts * 8).to_vector2_array()
	if detailed:
		arrays[Mesh.ARRAY_TEX_UV2] = f.get_buffer(verts * 8).to_vector2_array()
	arrays[Mesh.ARRAY_INDEX] = f.get_buffer(indices * 4).to_int32_array()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_cache["mesh:" + file] = m
	return m
