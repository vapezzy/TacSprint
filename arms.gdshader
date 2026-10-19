shader_type spatial;

#include "res://viewmodel.gdshaderinc"

// Gloves and sleeves. The mesh carries a material zone in UV.x, baked ambient
// occlusion in UV.y, and in UV2 how raised (x) or recessed (y) each spot is.
// Textures are projected from three sides in object space, so nothing
// stretches and no UV seams show.
// Zones: 0 sleeve cloth, 1 glove textile, 2 grippy palm, 3 moulded rubber.

uniform sampler2D camo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloth_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloth_r : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D weave_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leather_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D leather_r : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rubber_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime : filter_linear_mipmap_anisotropic, repeat_enable;

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

void fragment() {
	vec3 n = normalize(on);
	vec3 w = tri_weights(n);
	float ao = UV.y;
	float raised = worn.x;
	float recess = worn.y;
	float blotch = tri(grime, op * 5.0, w).r;
	float fine = tri(grime, op * 34.0 + 1.7, w).r;

	vec3 albedo;
	vec3 nn;
	float rough;
	float rim = 0.0;
	if (zone < 0.5) {
		// Sleeve: printed camouflage, soft creases, fine weave, faded on the folds.
		float wear = tri(cloth_r, op * 2.6, w).r;
		albedo = tri(camo, op * 2.3, w).rgb * mix(0.8, 1.1, wear);
		albedo = mix(albedo, albedo * 1.35 + 0.012, raised * 0.5);
		albedo *= mix(1.0, 0.72, recess);
		nn = tri_normal(cloth_n, op * 2.6, n, w, 0.5);
		nn = tri_normal(weave_n, op * 26.0, nn, w, 0.45);
		rough = mix(0.86, 0.98, wear);
		rim = 0.35;
	} else if (zone < 1.5) {
		// Back of the glove: black stretch textile, greyed where it has rubbed.
		albedo = vec3(0.013, 0.013, 0.014) * mix(0.8, 1.25, blotch);
		albedo = mix(albedo, vec3(0.04, 0.04, 0.042), raised * 0.45 + fine * 0.08);
		albedo *= mix(1.0, 0.6, recess);
		nn = tri_normal(weave_n, op * 21.0, n, w, 0.7);
		rough = mix(0.8, 0.92, blotch);
		rim = 0.5;
	} else if (zone < 2.5) {
		// Palm and finger insides: synthetic leather, worn smoother on the pads.
		float grain = tri(leather_r, op * 8.0, w).r;
		albedo = vec3(0.016, 0.015, 0.014) * mix(0.8, 1.2, grain);
		albedo = mix(albedo, vec3(0.045, 0.042, 0.04), raised * 0.4);
		nn = tri_normal(leather_n, op * 8.0, n, w, 0.75);
		rough = mix(0.42, 0.66, grain);
		rough = mix(rough, 0.34, raised * 0.6);
		rim = 0.15;
	} else {
		// Knuckle guard, finger pads and strap: moulded rubber with a slight sheen.
		albedo = vec3(0.009) * mix(0.85, 1.3, blotch);
		albedo = mix(albedo, vec3(0.03), raised * 0.35);
		albedo = mix(albedo, vec3(0.05, 0.045, 0.038), recess * 0.5);
		nn = tri_normal(rubber_n, op * 11.0, n, w, 0.22);
		rough = mix(0.3, 0.46, blotch);
		rough = mix(rough, 0.8, recess * 0.7);
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	SPECULAR = 0.32;
	// Cloth catches light at grazing angles.
	RIM = rim;
	RIM_TINT = 0.7;
	AO = ao;
	AO_LIGHT_AFFECT = 0.7;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nn, 0.0)).xyz);
}
