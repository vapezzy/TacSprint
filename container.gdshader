shader_type spatial;
render_mode cull_disabled;

// Weathered painted steel for shipping containers. One mesh, one material:
// the paint colour and a seed come per instance, so every container fades,
// rusts and scratches differently. Vertex colour: r = exposure to wear,
// g = surface kind (0 paint, 0.33 bare steel, 0.66 rubber, 1 wood).

instance uniform vec3 paint : source_color = vec3(0.2, 0.3, 0.5);
instance uniform float seed = 0.0;

uniform sampler2D grime : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scratch_d : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scratch_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 op;
varying vec3 on;

void vertex() {
	op = VERTEX;
	on = NORMAL;
}

vec3 weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

vec4 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

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

void fragment() {
	vec3 n = normalize(on);
	if (!FRONT_FACING) {
		n = -n;
	}
	vec3 w = weights(n);
	vec3 p = op + vec3(seed * 3.7, seed * 0.9, seed * 1.9);
	float wear = COLOR.r;
	float kind = COLOR.g;
	float h = op.y;

	float big = tri(grime, p * 0.09, w).r;
	float mid = tri(grime, p * 0.41 + 3.1, w).r;
	float fine = tri(grime, p * 1.7 + 7.3, w).r;
	// Rain streaks run down the walls, so the noise is stretched along the height.
	float streak = texture(grime, vec2((p.x + p.z) * 0.8, p.y * 0.05 + seed)).r;
	vec3 scratch_tex = tri(scratch_d, p * 0.33, w).rgb;
	float scratch = smoothstep(0.5, 0.78, scratch_tex.r);
	float low = 1.0 - smoothstep(0.0, 0.7, h);

	// Paint: uneven, sun-bleached in patches, never one flat colour.
	vec3 col = paint * mix(0.68, 1.1, big);
	float grey = dot(col, vec3(0.333));
	col = mix(col, vec3(grey) * 1.1 + 0.01, 0.13 * mid + 0.05 * fine);

	// Dust and road dirt: heavy near the ground, streaks from the roof edge.
	float dirt = clamp(low * 0.75 + streak * streak * 0.55 * (0.4 + mid), 0.0, 1.0);
	col = mix(col, vec3(0.085, 0.075, 0.06), dirt * 0.6);

	// Rust blooms at joints, edges and along the bottom.
	float rust_m = smoothstep(0.63, 0.76, mid * 0.42 + big * 0.26 + wear * 0.36 + low * 0.28 + streak * 0.08);
	vec3 rust = tri(rust_d, p * 0.45, w).rgb;
	col = mix(col, rust * vec3(0.42, 0.36, 0.33), rust_m * 0.88);

	// Scratches and chipped edges show bare metal.
	float bare = clamp(scratch * (0.08 + wear * 0.8), 0.0, 1.0) * (1.0 - rust_m);
	col = mix(col, vec3(0.1, 0.098, 0.095), bare * 0.65);

	float rough = mix(0.7, 0.92, mid);
	rough = mix(rough, 0.96, rust_m);
	rough = mix(rough, 0.42, bare);
	float metal = bare * 0.75;

	if (kind > 0.83) {
		// Plywood floor.
		col = tri(wood_d, p * 0.6, w).rgb * mix(0.5, 0.9, mid);
		rough = 0.9;
		metal = 0.0;
	} else if (kind > 0.5) {
		// Rubber seals and pocket openings.
		col = vec3(0.012) * mix(0.8, 1.4, fine);
		rough = 0.85;
		metal = 0.0;
	} else if (kind > 0.16) {
		// Galvanised locking gear, rusting where it rubs.
		float r2 = smoothstep(0.45, 0.62, mid * 0.6 + fine * 0.4);
		col = mix(vec3(0.12, 0.12, 0.115) * mix(0.7, 1.1, fine), rust * vec3(0.4, 0.35, 0.32), r2);
		rough = mix(0.5, 0.95, r2);
		metal = mix(0.8, 0.0, r2);
	}

	vec3 nn = tri_normal(scratch_n, p * 0.33, n, w, 0.45);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.45;
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nn, 0.0)).xyz);
}
