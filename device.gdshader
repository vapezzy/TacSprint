shader_type spatial;

#include "res://viewmodel.gdshaderinc"

// Plain parts held in first person (the bomb while it is being planted): a
// colour, a finish and an optional glow, drawn with the viewmodel's own
// field of view and squeezed depth like the weapon and the arms.

uniform vec3 albedo : source_color = vec3(0.2, 0.2, 0.2);
uniform float roughness = 0.6;
uniform float metallic = 0.0;
uniform vec3 glow : source_color = vec3(0.0);
uniform float glow_energy = 0.0;

void vertex() {
	float k = vm_scale(PROJECTION_MATRIX);
	PROJECTION_MATRIX[0][0] *= k;
	PROJECTION_MATRIX[1][1] *= k;
	if (vm_fov > 0.0 && PROJECTION_MATRIX[3][3] == 0.0) {
		PROJECTION_MATRIX[2][2] = PROJECTION_MATRIX[2][2] * VM_DEPTH + PROJECTION_MATRIX[2][3] * (1.0 - VM_DEPTH);
		PROJECTION_MATRIX[3][2] *= VM_DEPTH;
	}
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = glow * glow_energy;
}
