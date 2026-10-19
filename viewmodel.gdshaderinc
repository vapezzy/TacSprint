// Shared by everything held in front of the camera (weapon, arms, flash).
//
// The world can be drawn with a wide field of view while the weapon keeps its
// own, narrower one, so it sits close and large instead of shrinking into the
// distance. Only the screen-space scale changes: depth, lighting and shadows
// still use the true position.

uniform float vm_fov = 55.0;

// Weapon and arms belong to the camera, not to the world: their depth is
// squeezed towards the lens, so they can never poke through legs or walls.
const float VM_DEPTH = 0.1;

// Factor to multiply the projection's x and y scale with. The sun's shadow
// maps are drawn with an orthographic projection and must stay untouched.
// vm_fov = 0 switches the override off (used for the legs, which are part of the world).
float vm_scale(mat4 proj) {
	if (proj[3][3] != 0.0 || vm_fov <= 0.0) {
		return 1.0;
	}
	return (1.0 / tan(radians(vm_fov) * 0.5)) / abs(proj[1][1]);
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

// Triplanar normal mapping ("whiteout" blend), result in object space.
vec3 tri_normal(sampler2D t, vec3 p, vec3 n, vec3 w, float strength) {
	vec3 tx = texture(t, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(t, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(t, p.xy).xyz * 2.0 - 1.0;
	tx.xy *= strength;
	ty.xy *= strength;
	tz.xy *= strength;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}
