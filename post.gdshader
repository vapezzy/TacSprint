shader_type canvas_item;

// Final pass over the rendered picture, the way a camera would see it:
// a touch of sharpening, colour fringing and darkening towards the corners,
// and fine film grain. All of it is subtle; none of it should be noticed.

uniform sampler2D screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float sharpen = 0.3;
uniform float fringe = 0.0018;
uniform float vignette = 0.36;
uniform float grain = 0.022;
uniform float halation = 0.4;
uniform vec2 blur = vec2(0.0);    // motion blur: screen movement per frame, in UV

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 from_centre = uv - 0.5;
	float r2 = dot(from_centre, from_centre);

	// Lens fringing grows towards the edges: red and blue part ways slightly.
	vec2 shift = from_centre * fringe * r2 * 4.0;
	vec3 c = vec3(texture(screen, uv + shift).r, texture(screen, uv).g, texture(screen, uv - shift).b);
	// Motion blur: average the picture along the way the view moved this frame.
	if (length(blur) > 0.0004) {
		vec3 sum = c;
		for (int i = 1; i <= 8; i++) {
			float k = float(i) / 8.0 - 0.5;
			sum += texture(screen, uv + blur * k).rgb;
		}
		c = sum / 9.0;
	}

	vec3 around = texture(screen, uv + vec2(px.x, 0.0)).rgb + texture(screen, uv - vec2(px.x, 0.0)).rgb
			+ texture(screen, uv + vec2(0.0, px.y)).rgb + texture(screen, uv - vec2(0.0, px.y)).rgb;
	c += (texture(screen, uv).rgb - around * 0.25) * sharpen;

	// Film grade: cool, slightly blue shadows and warm highlights.
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(c, c * vec3(0.93, 0.99, 1.07), (1.0 - smoothstep(0.0, 0.45, lum)) * 0.55);
	c = mix(c, c * vec3(1.06, 1.0, 0.92), smoothstep(0.55, 1.0, lum) * 0.45);
	// Halation: very bright spots bleed a faint warm glow into what is around them.
	vec3 wide = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		wide += texture(screen, uv + vec2(cos(a), sin(a)) * px * (i % 2 == 0 ? 6.0 : 12.0)).rgb;
	}
	wide /= 8.0;
	c += max(wide - vec3(0.8), vec3(0.0)) * vec3(1.0, 0.55, 0.3) * halation;

	c *= 1.0 - vignette * smoothstep(0.12, 0.55, r2);

	float noise = fract(sin(dot(uv * vec2(1731.0, 977.0) + fract(TIME) * 61.0, vec2(12.9898, 78.233))) * 43758.5453);
	c += (noise - 0.5) * grain;

	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
