# The procedural sky (sky.gdshader) with its cloud noise, and the colour grade
# (a 3D look-up table), all generated at start-up: nothing is loaded from disk.
extends RefCounted

const NOISE_SIZE := 64
const LUT_SIZE := 32


static func _noise_tex(n: FastNoiseLite, invert: bool) -> ImageTexture3D:
	var imgs := n.get_seamless_image_3d(NOISE_SIZE, NOISE_SIZE, NOISE_SIZE, invert, 0.1, true)
	var tex := ImageTexture3D.new()
	tex.create(imgs[0].get_format(), NOISE_SIZE, NOISE_SIZE, NOISE_SIZE, false, imgs)
	return tex


static func material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://sky.gdshader")
	# Billows: inverted cellular distance, three octaves.
	var w := FastNoiseLite.new()
	w.noise_type = FastNoiseLite.TYPE_CELLULAR
	w.seed = 7
	w.frequency = 5.0 / NOISE_SIZE
	w.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	w.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	w.fractal_type = FastNoiseLite.FRACTAL_FBM
	w.fractal_octaves = 3
	w.fractal_gain = 0.45
	mat.set_shader_parameter("worley_tex", _noise_tex(w, true))
	# Soft shapes: Perlin, four octaves.
	var p := FastNoiseLite.new()
	p.noise_type = FastNoiseLite.TYPE_PERLIN
	p.seed = 3
	p.frequency = 3.0 / NOISE_SIZE
	p.fractal_type = FastNoiseLite.FRACTAL_FBM
	p.fractal_octaves = 4
	p.fractal_gain = 0.5
	mat.set_shader_parameter("perlin_tex", _noise_tex(p, false))
	return mat


# The grade, applied after tonemapping (sRGB in, sRGB out): a gentle S-curve,
# cool shadows and warm highlights, greens pulled towards olive and slightly
# muted, everything a touch less saturated. Close to the look of a modern
# military shooter's daylight grade, without crushing anything.
static func _grade(c: Color) -> Color:
	var v := Vector3(c.r, c.g, c.b)
	# S-curve on each channel, pivot a little below the middle.
	for i in 3:
		var x: float = v[i]
		var s := x * x * (3.0 - 2.0 * x)
		v[i] = lerpf(x, s, 0.16)
	var luma := v.dot(Vector3(0.2126, 0.7152, 0.0722))
	var shadow := 1.0 - smoothstep(0.0, 0.42, luma)
	var high := smoothstep(0.55, 1.0, luma)
	v += Vector3(-0.010, 0.002, 0.016) * shadow
	v += Vector3(0.020, 0.008, -0.018) * high
	var g := Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))
	# Greens: towards olive and a little less vivid. Blues: a bit deeper.
	var h := g.h * 360.0
	var sat := g.s
	var val := g.v
	var green := smoothstep(60.0, 85.0, h) * (1.0 - smoothstep(150.0, 175.0, h))
	h -= 9.0 * green
	sat *= 1.0 - 0.22 * green
	var blue := smoothstep(185.0, 205.0, h) * (1.0 - smoothstep(235.0, 255.0, h))
	sat *= 1.0 + 0.06 * blue
	val *= 1.0 - 0.03 * blue
	sat *= 0.95
	return Color.from_hsv(fposmod(h, 360.0) / 360.0, clampf(sat, 0.0, 1.0), clampf(val, 0.0, 1.0))


static func grade_lut() -> ImageTexture3D:
	var imgs: Array[Image] = []
	for b in LUT_SIZE:
		var img := Image.create(LUT_SIZE, LUT_SIZE, false, Image.FORMAT_RGB8)
		for gy in LUT_SIZE:
			for r in LUT_SIZE:
				var c := Color(r / (LUT_SIZE - 1.0), gy / (LUT_SIZE - 1.0), b / (LUT_SIZE - 1.0))
				img.set_pixel(r, gy, _grade(c))
		imgs.append(img)
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RGB8, LUT_SIZE, LUT_SIZE, LUT_SIZE, false, imgs)
	return tex
