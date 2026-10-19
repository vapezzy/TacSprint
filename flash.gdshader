shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://viewmodel.gdshaderinc"

// Muzzle flash, drawn with the weapon's own field of view. Two kinds of quad:
// kind 0 is the fireball, always turned to face the camera; kind 1 is a flame
// tongue lying along its own +Y (forward out of the muzzle, or sideways out of
// a brake port). age runs 0 -> 1 over the flash; seed makes every shot differ.

instance uniform float age = 0.0;
instance uniform float seed = 0.0;
instance uniform float kind = 0.0;
instance uniform float power = 1.0;
instance uniform float bright = 1.0;   // per weapon: the sniper burns brighter

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// White-hot core through yellow and orange to a dull red rim.
vec3 fire(float h) {
	vec3 c = mix(vec3(0.55, 0.06, 0.0), vec3(1.0, 0.36, 0.04), smoothstep(0.0, 0.35, h));
	c = mix(c, vec3(1.0, 0.75, 0.25), smoothstep(0.35, 0.7, h));
	return mix(c, vec3(1.0, 0.97, 0.85), smoothstep(0.7, 1.0, h));
}

void vertex() {
	if (kind < 0.5) {
		// Billboard: keep the node's position and size, but face the camera.
		float s = length(MODEL_MATRIX[0].xyz);
		mat4 face = mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = VIEW_MATRIX * face;
	}
	float k = vm_scale(PROJECTION_MATRIX);
	PROJECTION_MATRIX[0][0] *= k;
	PROJECTION_MATRIX[1][1] *= k;
	if (vm_fov > 0.0 && PROJECTION_MATRIX[3][3] == 0.0) {
		PROJECTION_MATRIX[2][2] = PROJECTION_MATRIX[2][2] * VM_DEPTH + PROJECTION_MATRIX[2][3] * (1.0 - VM_DEPTH);
		PROJECTION_MATRIX[3][2] *= VM_DEPTH;
	}
}

void fragment() {
	vec2 uv = UV - 0.5;
	float fade = pow(clamp(1.0 - age, 0.0, 1.0), 1.6);
	float heat;
	if (kind < 0.5) {
		// Fireball: a ragged, boiling ball that swells and burns out.
		float r = length(uv) * 2.0;
		float ang = atan(uv.y, uv.x);
		float ragged = fbm(vec2(ang * 2.2 + seed * 13.0, r * 3.0 - age * 6.0 + seed * 5.0));
		float edge = 0.5 + 0.45 * ragged;
		float body = 1.0 - smoothstep(edge * 0.55, edge, r);
		float churn = fbm(uv * 7.0 + vec2(seed * 31.0, -age * 5.0));
		heat = body * (0.55 + 0.65 * churn) * (1.0 - r * 0.6);
		heat *= mix(1.25, 0.7, age);
	} else {
		// Tongue: thick at the muzzle (UV.y = 1), thin and broken at the tip.
		float along = 1.0 - UV.y;
		float wobble = (fbm(vec2(along * 5.0 - age * 9.0, seed * 17.0)) - 0.5) * 0.35;
		float width = 0.42 * pow(1.0 - along, 0.6) + 0.04;
		float across = abs(uv.x + wobble * along);
		float body = 1.0 - smoothstep(width * 0.35, width, across);
		float breakup = fbm(vec2(uv.x * 6.0 + seed * 7.0, along * 9.0 - age * 14.0));
		heat = body * (0.45 + 0.8 * breakup) * (1.0 - along * 0.75);
		heat *= smoothstep(1.0, 0.75, along + age * 0.3);
	}
	heat = clamp(heat * power, 0.0, 1.4);
	float glow = heat * fade;
	ALBEDO = fire(min(heat, 1.0)) * glow * 4.0 * bright;
	ALPHA = clamp(glow, 0.0, 1.0);
}
