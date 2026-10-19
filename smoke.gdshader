shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Gun smoke: soft, ragged grey puffs that always face the camera. Colour and
// opacity come from the particle system's colour ramp (COLOR).

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

varying float seed;

void vertex() {
	// Billboard: the particle's position and size, turned to the camera.
	mat4 face = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * face * mat4(vec4(s, 0.0, 0.0, 0.0), vec4(0.0, s, 0.0, 0.0), vec4(0.0, 0.0, s, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	seed = fract(MODEL_MATRIX[3].x * 13.7 + MODEL_MATRIX[3].z * 7.3);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv) * 2.0;
	float n = vnoise(uv * 5.0 + seed * 40.0) * 0.6 + vnoise(uv * 11.0 - seed * 23.0) * 0.4;
	float puff = (1.0 - smoothstep(0.25, 1.0, r + (n - 0.5) * 0.5)) * (0.55 + 0.45 * n);
	ALBEDO = COLOR.rgb * (0.9 + 0.2 * n);
	ALPHA = clamp(COLOR.a * puff, 0.0, 1.0);
}
