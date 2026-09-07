shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.01, 0.02, 0.07);      // Deep Midnight Space
uniform vec3 sky_horizon_color : source_color = vec3(0.05, 0.09, 0.18);  // Atmospheric Horizon Glow
uniform vec3 moon_color : source_color = vec3(0.95, 0.97, 1.0);          // Bright Full Moon Disc
uniform vec3 moon_halo_color : source_color = vec3(0.2, 0.45, 0.85);      // Atmospheric Moon Bloom
uniform vec3 moon_direction = vec3(0.25, 0.5, -0.82);                     // Sky position of Moon
uniform float moon_size = 0.038;                                          // Realistic Moon Size
uniform float moon_glow = 0.35;                                           // Atmospheric Bloom Intensity

// Fast Hash Noise
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 2D Noise for Galaxy / Nebula
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 m_dir = normalize(moon_direction);

	// 1. Realistic Night Sky Base Gradient
	float horizon_factor = clamp(dir.y, 0.0, 1.0);
	vec3 col = mix(sky_horizon_color, sky_top_color, pow(horizon_factor, 0.6));

	if (dir.y > 0.01) {
		// 2. Milky Way Galaxy Band
		vec2 galaxy_uv = vec2(dir.x * 2.5 + dir.z * 1.5, dir.y * 3.0);
		float galaxy_noise = noise(galaxy_uv * 4.0) * noise(galaxy_uv * 8.0);
		vec3 galaxy_color = vec3(0.08, 0.12, 0.22) * galaxy_noise * smoothstep(0.1, 0.7, dir.y);
		col += galaxy_color;

		// 3. Dense Twinkling Stars
		vec2 star_uv = dir.xz / (dir.y + 0.2) * 90.0;
		float n = hash(floor(star_uv));
		if (n > 0.975) {
			float twinkle = sin(TIME * (2.0 + n * 5.0) + n * 200.0) * 0.4 + 0.6;
			float brightness = (n - 0.975) * 40.0 * twinkle;
			vec3 star_tint = mix(vec3(0.9, 0.95, 1.0), vec3(1.0, 0.8, 0.6), hash(floor(star_uv) + 1.0));
			col += star_tint * brightness;
		}
	}

	// 4. Full Moon & Atmospheric Halo
	float dist_to_moon = distance(dir, m_dir);

	// Atmospheric Moon Glow
	float halo = exp(-dist_to_moon * 6.5) * moon_glow;
	col += moon_halo_color * halo;

	// Moon Disc Shading
	if (dist_to_moon < moon_size) {
		float surface = smoothstep(moon_size, moon_size * 0.85, dist_to_moon);
		// Crater surface details
		vec2 moon_uv = (dir.xy - m_dir.xy) * 35.0;
		float craters = noise(moon_uv * 3.0) * 0.25;
		vec3 moon_surface = moon_color * (1.0 - craters);
		col = mix(col, moon_surface, surface);
	}

	COLOR = col;
}
