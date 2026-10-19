shader_type spatial;

// Worn concrete yard: scanned concrete at two scales so it never visibly
// tiles, with slab joints, dirt patches, oil stains and faded lane paint.
// Everything is placed in world space.

uniform sampler2D conc_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D conc_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D conc_r : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wp.xz;
	float m1 = texture(grime, uv * 0.019).r;
	float m2 = texture(grime, uv * 0.077 + 0.5).r;
	float m3 = texture(grime, uv * 0.31 + 0.2).r;

	vec3 near = texture(conc_d, uv * 0.31).rgb;
	vec3 far = texture(conc_d, uv * 0.067 + 0.37).rgb;
	vec3 col = mix(near, far, 0.4) * mix(0.8, 1.08, m1);

	// Each cast slab is a slightly different grey, with a dark joint between them.
	vec2 cell = floor(uv / 5.0);
	float tint = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	col *= mix(0.86, 1.05, tint);
	vec2 g = abs(fract(uv / 5.0) - 0.5) * 5.0;
	float joint = 1.0 - smoothstep(0.0, 0.03 + 0.02 * m3, 2.5 - max(g.x, g.y));

	// Packed dirt and sand collecting in patches.
	vec3 dirt = texture(dirt_d, uv * 0.19).rgb;
	float dirt_m = smoothstep(0.5, 0.7, m2 * 0.65 + m1 * 0.45);
	col = mix(col, dirt * 0.7, dirt_m * 0.38);

	// Faded yellow lane lines, mostly worn away.
	float lx = abs(mod(uv.x + 3.0, 12.2) - 6.1);
	float lz = abs(mod(uv.y + 8.0, 16.0) - 8.0);
	float line = max(1.0 - smoothstep(0.055, 0.075, lx), 1.0 - smoothstep(0.055, 0.075, lz));
	float kept = smoothstep(0.42, 0.6, m3) * (1.0 - dirt_m * 0.7);
	col = mix(col, vec3(0.42, 0.3, 0.035), line * kept * 0.75);

	// Old oil and hydraulic stains: darker and a little glossier.
	float oil = smoothstep(0.69, 0.79, texture(grime, uv * 0.11 + vec2(0.3, 0.7)).r);
	col *= mix(1.0, 0.45, oil);
	col *= mix(1.0, 0.4, joint);

	float rough = texture(conc_r, uv * 0.31).r;
	rough = mix(mix(0.82, 0.98, rough), 0.42, oil * 0.7);

	vec3 t = texture(conc_n, uv * 0.31).xyz * 2.0 - 1.0;
	vec3 world_n = normalize(vec3(t.x * 0.8, t.z, -t.y * 0.8));
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
}
