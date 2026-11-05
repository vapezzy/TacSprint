shader_type sky;

// The whole sky, made from physics instead of a photo:
// - the air: single Rayleigh + Mie scattering through a curved atmosphere,
//   so the zenith is deep blue, the horizon pale and the sun's side bright;
// - the sun disc with limb darkening, dimmed by the air and by clouds;
// - cumulus clouds as a real volume between 1.5 and 3.7 km, raymarched
//   through 3D Perlin-Worley noise, lit by the sun with self-shadowing,
//   multiple-scattering octaves and a silver lining, and by the sky from above;
// - a thin cirrus veil high up.
// The sky does not change over time, so Godot renders its reflection cubemap
// only once; the cubemap pass uses fewer steps.

uniform sampler3D worley_tex : filter_linear, repeat_enable;
uniform sampler3D perlin_tex : filter_linear, repeat_enable;
uniform float coverage = 0.48;
uniform float cloud_extinction = 0.045;   // per metre at density 1
uniform float cloud_base = 1500.0;
uniform float cloud_top = 3700.0;
uniform float shape_scale = 9000.0;       // metres per tile of the base noise
uniform float detail_scale = 1300.0;      // metres per tile of the erosion noise
uniform vec2 wind_offset = vec2(1830.0, -2410.0);
uniform float cloud_light = 1.0;
uniform vec3 cloud_ambient : source_color = vec3(0.55, 0.64, 0.82);
uniform float cirrus = 0.5;
uniform float sky_energy = 0.11;
uniform float sun_disc_energy = 900.0;
uniform float sun_size_deg = 0.6;
uniform vec3 ground_albedo : source_color = vec3(0.28, 0.27, 0.23);
uniform float haze = 1.0;                 // scales the Mie (aerosol) amount

const float PLANET_R = 6360e3;
const float ATMO_R = 6420e3;
const vec3 BETA_R = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const float BETA_M = 12e-6;
const float H_R = 7994.0;
const float H_M = 1200.0;
const float SUN_I = 20.0;

vec2 ray_sphere(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float h = b * b - c;
	if (h < 0.0) {
		return vec2(-1.0);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

float hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.5663706 * pow(max(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5));
}

float remap(float v, float lo, float hi, float nlo, float nhi) {
	return nlo + (v - lo) / (hi - lo) * (nhi - nlo);
}

vec3 sun_transmittance(vec3 p, vec3 s) {
	if (ray_sphere(p, s, PLANET_R).x > 0.0) {
		return vec3(0.0);
	}
	float len = ray_sphere(p, s, ATMO_R).y;
	float ds = len / 6.0;
	float odr = 0.0;
	float odm = 0.0;
	for (int i = 0; i < 6; i++) {
		vec3 q = p + s * (ds * (float(i) + 0.5));
		float h = max(length(q) - PLANET_R, 0.0);
		odr += exp(-h / H_R) * ds;
		odm += exp(-h / H_M) * ds;
	}
	return exp(-(BETA_R * odr + BETA_M * haze * 1.1 * odm));
}

// In-scattered light along the view ray, and the transmittance of the air.
vec3 atmosphere(vec3 ro, vec3 rd, vec3 s, int steps, out vec3 trans) {
	float tmax = ray_sphere(ro, rd, ATMO_R).y;
	vec2 tg = ray_sphere(ro, rd, PLANET_R);
	if (tg.x > 0.0) {
		tmax = tg.x;
	}
	// Steps grow with distance: the low, dense air near the eye matters most.
	float mu = dot(rd, s);
	vec3 sr = vec3(0.0);
	vec3 sm = vec3(0.0);
	float odr = 0.0;
	float odm = 0.0;
	float prev = 0.0;
	for (int i = 0; i < steps; i++) {
		float f = (float(i) + 1.0) / float(steps);
		float t = tmax * f * f;
		float ds = t - prev;
		vec3 q = ro + rd * (prev + ds * 0.5);
		prev = t;
		float h = max(length(q) - PLANET_R, 0.0);
		float hr = exp(-h / H_R) * ds;
		float hm = exp(-h / H_M) * ds;
		odr += hr;
		odm += hm;
		vec3 tv = exp(-(BETA_R * odr + BETA_M * haze * 1.1 * odm));
		vec3 ts = sun_transmittance(q, s);
		sr += hr * ts * tv;
		sm += hm * ts * tv;
	}
	trans = exp(-(BETA_R * odr + BETA_M * haze * 1.1 * odm));
	float pr = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	return SUN_I * (sr * BETA_R * pr + sm * BETA_M * haze * hg(mu, 0.76));
}

float cloud_density(vec3 p, float hf, bool detail) {
	vec3 q = (p + vec3(wind_offset.x, 0.0, wind_offset.y)) / shape_scale;
	float weather = texture(perlin_tex, vec3(q.xz * 0.21, 0.37)).r;
	float pw = texture(perlin_tex, q * vec3(1.0, 1.6, 1.0)).r;
	float wr = texture(worley_tex, q * vec3(1.0, 1.3, 1.0)).r;
	// Perlin-Worley: soft Perlin blobs carved into round billows.
	float base = clamp(remap(pw, wr * 0.75 - 0.85, 1.0, 0.0, 1.0), 0.0, 1.0);
	// Cumulus profile: a flat, sharp base and rounded, narrowing tops.
	float prof = smoothstep(0.0, 0.07, hf) * smoothstep(1.0, 0.45, hf) * mix(1.0, 0.75, hf);
	float cov = clamp(coverage + (weather - 0.5) * 0.9, 0.0, 0.95);
	float d = remap(base * prof, 1.0 - cov, 1.0, 0.0, 1.0);
	if (d <= 0.0) {
		return 0.0;
	}
	if (detail) {
		// Small billows eat into the edges: wispy at the bottom, cauliflower on top.
		float det = texture(worley_tex, (p + vec3(wind_offset.x * 1.7, 0.0, wind_offset.y * 1.7)) / detail_scale).r;
		det = mix(det, 1.0 - det, smoothstep(0.1, 0.5, hf));
		d = remap(d, det * 0.32, 1.0, 0.0, 1.0);
	}
	return clamp(d, 0.0, 1.0) * smoothstep(0.0, 0.15, hf + 0.05);
}

// Returns the light scattered by the clouds (rgb) and their transmittance (a).
vec4 clouds(vec3 ro, vec3 rd, vec3 s, vec3 cam_xz, vec3 sun_col, vec3 amb, int steps, float jitter, out float depth) {
	depth = 1e6;
	if (rd.y < -0.01) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	float t0 = ray_sphere(ro, rd, PLANET_R + cloud_base).y;
	float t1 = ray_sphere(ro, rd, PLANET_R + cloud_top).y;
	if (t0 > 70000.0) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	t1 = min(t1, t0 + 22000.0);
	float dt = (t1 - t0) / float(steps);
	float t = t0 + dt * jitter;
	float mu = dot(rd, s);
	float trans = 1.0;
	vec3 light = vec3(0.0);
	float wsum = 0.0;
	float wt = 0.0;
	bool near = t0 < 30000.0;
	for (int i = 0; i < steps; i++) {
		vec3 p = ro + rd * t;
		float h = length(p) - PLANET_R;
		float hf = (h - cloud_base) / (cloud_top - cloud_base);
		vec3 pw = vec3(p.x + cam_xz.x, h, p.z + cam_xz.z);
		float d = cloud_density(pw, hf, near);
		if (d > 0.002) {
			float sigma = d * cloud_extinction;
			// Light reaching this point: march towards the sun.
			float od = 0.0;
			float ls = 70.0;
			vec3 lp = pw;
			for (int j = 0; j < 5; j++) {
				lp += s * ls;
				float lhf = (lp.y - cloud_base) / (cloud_top - cloud_base);
				od += cloud_density(lp, lhf, j < 2) * ls;
				ls *= 1.9;
			}
			od *= cloud_extinction;
			// Multiple scattering, approximated by octaves (Wrenninge).
			vec3 sun_s = vec3(0.0);
			float a = 1.0;
			float b = 1.0;
			float c = 1.0;
			for (int k = 0; k < 3; k++) {
				float ph = mix(hg(mu, 0.8 * c), hg(mu, -0.25 * c), 0.3);
				sun_s += a * exp(-od * b) * ph;
				a *= 0.5;
				b *= 0.35;
				c *= 0.5;
			}
			// Powder: the dark rims of thick clouds facing away from the sun.
			float powder = 1.0 - exp(-sigma * 2.0 * 120.0 - od * 0.6);
			sun_s *= mix(1.0, powder, 0.6) * 12.5663706;
			// Sky light from above: tops bright, bases dim.
			vec3 amb_s = amb * mix(0.35, 1.0, clamp(hf, 0.0, 1.0)) * (1.0 - 0.4 * clamp(d, 0.0, 1.0));
			vec3 S = sun_col * sun_s * cloud_light + amb_s;
			float tr = exp(-sigma * dt);
			light += trans * S * (1.0 - tr);
			wt += trans * (1.0 - tr) * t;
			wsum += trans * (1.0 - tr);
			trans *= tr;
			if (trans < 0.01) {
				break;
			}
		}
		t += dt;
	}
	if (wsum > 0.0) {
		depth = wt / wsum;
	}
	return vec4(light, trans);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void sky() {
	vec3 rd = normalize(EYEDIR);
	vec3 s = normalize(LIGHT0_DIRECTION);
	float alt = max(POSITION.y, 0.0) + 2.0;
	vec3 ro = vec3(0.0, PLANET_R + alt, 0.0);
	bool cube = AT_CUBEMAP_PASS;

	// The air. Below the horizon, the ground (only seen in reflections and
	// ambient light, the world hides it otherwise).
	vec3 view_rd = rd;
	if (rd.y < 0.0) {
		view_rd = normalize(vec3(rd.x, 0.0, rd.z));
	}
	vec3 trans;
	vec3 col = atmosphere(ro, view_rd, s, cube ? 10 : 16, trans);
	vec3 sun_ground = SUN_I * sun_transmittance(ro, s);
	if (rd.y < 0.0) {
		vec3 sky_up = atmosphere(ro, vec3(0.0, 1.0, 0.0), s, 6, trans);
		vec3 ground = ground_albedo * (sun_ground * max(s.y, 0.0) / PI + sky_up * 0.9);
		col = mix(col, ground, smoothstep(0.0, -0.08, rd.y));
		trans = vec3(0.0);
	}

	// Sun disc with limb darkening.
	float cos_sun = dot(rd, s);
	float r_sun = radians(sun_size_deg) * 0.5;
	float ang = acos(clamp(cos_sun, -1.0, 1.0));
	vec3 disc = vec3(0.0);
	if (!cube && ang < r_sun * 1.6) {
		float x = clamp(ang / r_sun, 0.0, 1.0);
		float limb = pow(max(1.0 - x * x, 0.0), 0.35);
		float edge = smoothstep(1.0, 0.9, ang / r_sun);
		disc = sun_ground * trans * sun_disc_energy * limb * edge / SUN_I;
	}

	// Clouds.
	vec3 sun_cloud = SUN_I * sun_transmittance(ro + vec3(0.0, cloud_base + 600.0, 0.0), s);
	vec3 amb = cloud_ambient * (0.35 + 0.65 * smoothstep(-0.05, 0.4, s.y)) * SUN_I * 0.09;
	float jitter = cube ? 0.5 : hash12(FRAGCOORD.xy);
	float cdepth;
	vec4 cl = clouds(ro, rd, s, vec3(POSITION.x, 0.0, POSITION.z), sun_cloud, amb, cube ? 24 : 64, jitter, cdepth);
	// Aerial perspective: distant clouds sink into the haze of the horizon.
	float fade = exp(-cdepth / 42000.0);
	fade *= smoothstep(-0.005, 0.04, rd.y);
	vec3 with_clouds = col * cl.a + cl.rgb * trans + col * (1.0 - cl.a) * (1.0 - trans) * 0.6;
	col = mix(col, with_clouds, fade);
	disc *= cl.a;

	// Cirrus: thin streaks at 9 km, seen through gaps between the cumulus.
	if (rd.y > 0.0 && cirrus > 0.0) {
		float tc = ray_sphere(ro, rd, PLANET_R + 9000.0).y;
		vec3 pc = ro + rd * tc + vec3(POSITION.x, 0.0, POSITION.z);
		vec2 uv = pc.xz / 26000.0;
		float n = texture(perlin_tex, vec3(uv.x * 0.6, uv.y * 3.5, 0.21)).r;
		n += texture(perlin_tex, vec3(uv.x * 2.4, uv.y * 9.0, 0.63)).r * 0.5;
		float ci = smoothstep(0.72, 1.25, n) * cirrus * smoothstep(0.0, 0.12, rd.y) * exp(-tc / 90000.0);
		vec3 cc = sun_ground * (0.12 + hg(cos_sun, 0.6) * 0.8) * 0.5;
		col = mix(col, col + cc, ci * cl.a);
	}

	COLOR = (col + disc) * sky_energy;
}
