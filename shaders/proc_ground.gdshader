shader_type spatial;
// The procedural track's land: grass that turns to rock on steep slopes and to snow high up
// on the far mountains, in world space so the terrain grid and the strips along the road
// match. Vertex colour R paints gravel verges, G paved pavements.

uniform sampler2D noise_fine : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_coarse : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.30, 0.42, 0.17);
uniform vec3 grass_b : source_color = vec3(0.45, 0.47, 0.22);
uniform vec3 dirt : source_color = vec3(0.47, 0.39, 0.29);
uniform vec3 rock_a : source_color = vec3(0.47, 0.43, 0.38);
uniform vec3 rock_b : source_color = vec3(0.62, 0.57, 0.5);
uniform vec3 gravel : source_color = vec3(0.56, 0.52, 0.46);
uniform vec3 pavement : source_color = vec3(0.62, 0.61, 0.58);
uniform float snow_line = 200.0;
uniform float water_line = -1000.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(vec3 p, vec3 w, float scale) {
	return texture(noise_fine, p.zy / scale).r * w.x + texture(noise_fine, p.xz / scale).r * w.y
		+ texture(noise_fine, p.xy / scale).r * w.z;
}

void fragment() {
	vec3 n = normalize(wnrm);
	float slope = 1.0 - n.y;
	float f1 = texture(noise_fine, wpos.xz / 6.0).r;
	float f2 = texture(noise_fine, wpos.xz / 1.3).r;
	float c1 = texture(noise_coarse, wpos.xz / 240.0).r;
	float c2 = texture(noise_coarse, wpos.xz / 45.0).r;

	vec3 grass = mix(grass_a, grass_b, smoothstep(0.35, 0.7, c1 * 0.7 + c2 * 0.4));
	grass *= 0.8 + 0.3 * f1;
	grass *= 0.9 + 0.15 * f2;
	grass = mix(grass, dirt * (0.85 + 0.3 * f2), smoothstep(0.66, 0.74, c2 + f1 * 0.15) * 0.8);
	// Mud and pebbles along the water's edge.
	grass = mix(grass, dirt * 0.8, 1.0 - smoothstep(0.4, 1.6, wpos.y - water_line));

	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
	float r1 = tri(wpos, bw, 7.0);
	float r2 = tri(wpos, bw, 1.9);
	vec3 rock = mix(rock_a, rock_b, r1);
	rock *= 0.78 + 0.35 * r2;
	// Bedding lines across the cut faces.
	rock *= 0.9 + 0.1 * sin(wpos.y * 2.3 + r1 * 6.0);
	float rockw = smoothstep(0.3, 0.42, slope + (f1 - 0.5) * 0.18);
	vec3 col = mix(grass, rock, rockw);

	col = mix(col, gravel * (0.75 + 0.4 * f2) * (0.9 + 0.2 * f1), COLOR.r);
	float slab = step(0.06, fract(wpos.x / 2.0)) * step(0.06, fract(wpos.z / 2.0));
	col = mix(col, pavement * (0.88 + 0.12 * f2) * (0.85 + 0.15 * slab), COLOR.g);

	float snow = smoothstep(snow_line, snow_line + 40.0, wpos.y + c2 * 60.0) * (1.0 - smoothstep(0.45, 0.7, slope));
	col = mix(col, vec3(0.9, 0.92, 0.95), snow);

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.25;
}
