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
uniform float hurt = 0.0;          // 0 healthy .. 1 nearly dead: the edges darken and redden, colour drains
uniform float stim = 0.0;          // a stim just went in: a cold flash from the edges, colours pop
uniform vec2 blur = vec2(0.0);
uniform vec2 sun_uv = vec2(-10.0);   // where the sun is on screen (may be a little off it)
uniform float sun_on = 0.0;          // 0 when the sun is behind the view or a menu is open
uniform float sun_clear = 0.0;       // how much of the sun is not hidden (0-1)    // motion blur: screen movement per frame, in UV

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

	// The sun's lens effects: glow, streak, halo and ghosts (the god rays and the
	// disc come from sun_rays.gdshader). sun_clear says how much of the sun is
	// not hidden behind something (main.gd casts rays to find out).
	if (sun_on > 0.001) {
		float aspect = px.y / px.x;
		float onscreen = 1.0 - smoothstep(0.0, 0.25, max(max(-sun_uv.x, sun_uv.x - 1.0), max(-sun_uv.y, sun_uv.y - 1.0)));
		float power = sun_on * onscreen;
		float clear = sun_clear;
		// Glow and the horizontal streak, only when the disc is clear.
		vec2 d = (uv - sun_uv) * vec2(aspect, 1.0);
		float dist = length(d);
		float flare = power * clear;
		c += vec3(1.0, 0.9, 0.72) * exp(-dist * dist * 90.0) * 0.4 * flare;
		c += vec3(1.0, 0.82, 0.6) * exp(-abs(d.y) * 260.0) * exp(-abs(d.x) * 3.5) * 0.35 * flare;
		// A faint rainbow halo round the sun.
		float ring = exp(-pow((dist - 0.22) * 55.0, 2.0));
		c += vec3(0.9 + 0.1 * sin(dist * 90.0), 0.7, 0.55 + 0.3 * cos(dist * 70.0)) * ring * 0.06 * flare;
		// Ghosts: soft discs on the line from the sun through the middle of the picture.
		vec2 axis = vec2(0.5) - sun_uv;
		for (int i = 0; i < 5; i++) {
			float t = 0.45 + float(i) * 0.38;
			float radius = 0.025 + 0.018 * float((i * 3) % 4);
			vec2 g = sun_uv + axis * t;
			float gd = length((uv - g) * vec2(aspect, 1.0));
			float disc = smoothstep(radius, radius * 0.7, gd);
			vec3 tint = i % 3 == 0 ? vec3(0.4, 0.7, 1.0) : (i % 3 == 1 ? vec3(1.0, 0.6, 0.3) : vec3(0.5, 1.0, 0.6));
			c += tint * disc * 0.07 * flare;
		}
	}

	c *= 1.0 - vignette * smoothstep(0.12, 0.55, r2);

	// Hurt: the world loses colour, the edges close in dark red and pulse with the heartbeat.
	if (hurt > 0.001) {
		float grey = dot(c, vec3(0.2126, 0.7152, 0.0722));
		c = mix(c, vec3(grey), hurt * 0.4);
		float beat = 0.8 + 0.2 * sin(TIME * 7.5) * sin(TIME * 7.5);
		float edge = smoothstep(0.17, 0.5, r2) * hurt * beat;
		c = mix(c, c * vec3(0.5, 0.06, 0.05) + vec3(0.1, 0.0, 0.0), edge * 0.85);
	}
	// Stim: a quick cold-white wash from the edges and a little extra saturation.
	if (stim > 0.001) {
		float grey2 = dot(c, vec3(0.2126, 0.7152, 0.0722));
		c = mix(vec3(grey2), c, 1.0 + stim * 0.35);
		c += vec3(0.55, 0.85, 0.75) * smoothstep(0.1, 0.5, r2) * stim * 0.45;
	}

	float noise = fract(sin(dot(uv * vec2(1731.0, 977.0) + fract(TIME) * 61.0, vec2(12.9898, 78.233))) * 43758.5453);
	c += (noise - 0.5) * grain;

	COLOR = vec4(max(c, vec3(0.0)), 1.0);
}
