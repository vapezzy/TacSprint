shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://viewmodel.gdshaderinc"

// Laser beam: a thin red line out of the module, fading with distance.
// Drawn on two crossed quads along +Y; UV.y = 1 at the lens.

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
	float across = 1.0 - smoothstep(0.0, 0.5, abs(UV.x - 0.5));
	float along = pow(UV.y, 2.0);
	float glow = across * across * along;
	ALBEDO = vec3(1.0, 0.08, 0.05) * glow * 6.0;
	ALPHA = glow;
}
