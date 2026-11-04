shader_type spatial;
// The sun and its god rays, drawn over the whole view by a quad in front of the
// camera (main.gd). The depth buffer tells sky from everything else: the rays
// are the open sky smeared towards the sun, so walls, containers and the
// weapon cut dark shafts into them. A bright disc marks the sun itself.
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 sun_uv = vec2(-10.0);
uniform float sun_on = 0.0;
uniform float strength = 0.4;
uniform vec3 tint : source_color = vec3(1.0, 0.86, 0.64);

float sky(vec2 p) {
	if (p.x < 0.0 || p.y < 0.0 || p.x > 1.0 || p.y > 1.0) {
		return 0.6;      // off the picture: assume mostly sky (the sun is up there)
	}
	// Reverse Z: the far plane is 0.
	return texture(depth_tex, p).r < 0.000001 ? 1.0 : 0.0;
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	if (sun_on < 0.001) {
		discard;
	}
	vec2 uv = SCREEN_UV;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec2 to_sun = sun_uv - uv;
	float acc = 0.0;
	float decay = 1.0;
	vec2 p = uv;
	vec2 stepv = to_sun / 32.0;
	// A little jitter per pixel hides the steps.
	p += stepv * fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
	for (int i = 0; i < 32; i++) {
		acc += sky(p) * decay;
		decay *= 0.94;
		p += stepv;
	}
	acc /= 16.0;
	float dist = length((uv - sun_uv) * vec2(aspect, 1.0));
	float near = exp(-dist * 3.6);
	// Shafts live in the air between you and the sky: strongest over open sky,
	// only a faint veil over whatever stands in the way (so walls stay solid and
	// their silhouettes cut dark streaks into the light).
	float here = sky(uv);
	vec3 rays = tint * acc * near * strength * mix(0.3, 1.0, here);
	// The sun disc and its tight glow, only where the sky is open.
	float disc = smoothstep(0.016, 0.011, dist) * 2.5 + exp(-dist * dist * 900.0) * 0.8;
	vec3 sun = vec3(1.0, 0.97, 0.9) * disc * sky(uv);
	ALBEDO = (rays + sun) * sun_on;
}
