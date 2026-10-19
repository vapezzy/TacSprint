shader_type spatial;
render_mode cull_disabled;

#include "res://viewmodel.gdshaderinc"

// Weapon surface. The mesh carries, per vertex: a material zone (UV.x),
// baked ambient occlusion (UV.y), how exposed an edge is (UV2.x) and how deep
// a recess is (UV2.y). From those the shader builds what a used firearm shows:
// a dark satin finish, bright steel where edges have rubbed through, fine
// scratches, shinier patches where hands have been, and dust in the recesses.
// Zones: 0 painted steel, 1 polymer, 2 bare steel, 4 brass, 5 copper.

uniform sampler2D grime : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scratch_d : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scratch_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D camo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// 0 black, 1 desert, 2 woodland, 3 gold, 4 arctic
uniform int skin = 0;
// In first person everything behind clip_z (and below clip_y) is left out: the
// shoulder stock sits beside your face and would only block the view.
uniform float clip_z = 100.0;
uniform float clip_y = 100.0;
uniform sampler2D grain_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 op;
varying vec3 on;
varying flat float zone;
varying vec2 worn;

void vertex() {
	op = VERTEX;
	on = NORMAL;
	zone = UV.x * 7.0;
	worn = UV2;
	float k = vm_scale(PROJECTION_MATRIX);
	PROJECTION_MATRIX[0][0] *= k;
	PROJECTION_MATRIX[1][1] *= k;
	if (vm_fov > 0.0 && PROJECTION_MATRIX[3][3] == 0.0) {
		PROJECTION_MATRIX[2][2] = PROJECTION_MATRIX[2][2] * VM_DEPTH + PROJECTION_MATRIX[2][3] * (1.0 - VM_DEPTH);
		PROJECTION_MATRIX[3][2] *= VM_DEPTH;
	}
}

// The finish the chosen skin gives a painted or polymer part.
vec3 skinned(vec3 base, vec3 p, vec3 w, float big) {
	if (skin == 1) {
		return vec3(0.36, 0.29, 0.18) * mix(0.8, 1.12, big);
	} else if (skin == 2) {
		return tri(camo, p * 7.0, w).rgb * 0.95;
	} else if (skin == 3) {
		return vec3(1.0, 0.72, 0.26) * mix(0.85, 1.0, big);
	} else if (skin == 4) {
		float patchy = tri(grime, p * 8.0 + 4.0, w).r;
		return mix(vec3(0.62, 0.64, 0.66), vec3(0.22, 0.25, 0.28), smoothstep(0.48, 0.52, patchy));
	}
	return base;
}

void fragment() {
	if (vm_fov > 0.0 && op.z > clip_z && op.y < clip_y) {
		discard;
	}
	vec3 n = normalize(on);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 w = tri_weights(n);
	float ao = UV.y;
	float edge = worn.x;
	float cavity = worn.y;

	float big = tri(grime, op * 1.3, w).r;
	float mid = tri(grime, op * 6.0 + 2.7, w).r;
	float fine = tri(grime, op * 31.0 + 5.1, w).r;
	float scratch = smoothstep(0.56, 0.82, tri(scratch_d, op * 4.5, w).r);
	// Edges wear through unevenly: some stretches stay sharp black, others go bright.
	float rubbed = smoothstep(0.62, 1.0, edge) * smoothstep(0.5, 0.74, mid * 0.6 + big * 0.4 + scratch * 0.15);
	float dust = clamp(cavity * (0.4 + 0.6 * fine) + (1.0 - ao) * 0.4, 0.0, 1.0);

	vec3 albedo;
	float rough;
	float metal = 0.0;
	vec3 nn = n;
	if (zone < 0.5) {
		// Black phosphate over steel.
		albedo = skinned(vec3(0.012, 0.012, 0.013) * mix(0.8, 1.3, big), op, w, big);
		rough = mix(0.5, 0.7, mid);
		// Handling leaves smoother, slightly oily patches.
		rough = mix(rough, 0.3, smoothstep(0.58, 0.8, big * 0.55 + fine * 0.45) * 0.55);
		float bare = max(rubbed * 0.55, scratch * 0.1);
		albedo = mix(albedo, vec3(0.3, 0.3, 0.31), bare);
		metal = bare;
		rough = mix(rough, 0.33, bare);
		albedo = mix(albedo, vec3(0.075, 0.066, 0.052), dust * 0.5);
		rough = mix(rough, 0.86, dust * 0.7);
		metal *= 1.0 - dust * 0.6;
		nn = tri_normal(scratch_n, op * 4.5, n, w, 0.22);
	} else if (zone < 1.5) {
		// Glass-filled polymer with a moulded grain, polished where it is gripped.
		albedo = skinned(vec3(0.014, 0.014, 0.015) * mix(0.85, 1.2, big), op, w, big);
		rough = mix(0.55, 0.72, mid);
		rough = mix(rough, 0.46, rubbed * 0.8);
		albedo = mix(albedo, vec3(0.024), rubbed * 0.5);
		albedo = mix(albedo, vec3(0.07, 0.062, 0.05), dust * 0.4);
		rough = mix(rough, 0.85, dust * 0.6);
		nn = tri_normal(grain_n, op * 26.0, n, w, 0.32 * (1.0 - rubbed * 0.7));
	} else if (zone < 2.5) {
		// Bare steel parts.
		albedo = vec3(0.36, 0.36, 0.37) * mix(0.72, 1.05, mid);
		metal = 1.0;
		rough = mix(0.26, 0.44, mid);
		albedo = mix(albedo, vec3(0.05, 0.045, 0.04), dust * 0.75);
		rough = mix(rough, 0.8, dust * 0.7);
		metal = 1.0 - dust * 0.7;
		nn = tri_normal(scratch_n, op * 7.0, n, w, 0.3);
	} else if (zone < 3.5) {
		// Dark glass (scope lenses).
		albedo = vec3(0.004, 0.006, 0.01);
		rough = 0.06;
		metal = 0.0;
	} else if (zone < 4.5) {
		// Brass cartridge cases.
		albedo = vec3(0.9, 0.62, 0.22) * mix(0.8, 1.0, mid);
		metal = 1.0;
		rough = mix(0.24, 0.4, fine);
	} else {
		// Copper-jacketed bullets.
		albedo = vec3(0.82, 0.42, 0.25) * mix(0.8, 1.0, mid);
		metal = 1.0;
		rough = mix(0.3, 0.45, fine);
	}

	if (skin == 3 && zone < 1.5) {
		metal = max(metal, 0.95);
		rough = min(rough, 0.3);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = mix(0.24, 0.5, metal);
	AO = ao;
	AO_LIGHT_AFFECT = 0.75;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nn, 0.0)).xyz);
}
