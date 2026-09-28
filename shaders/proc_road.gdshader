shader_type spatial;
// The procedural track's asphalt. UV.x is metres across from the centre line (+ right), UV.y
// metres along the lap; UV2.x picks the centre marking (0 dashed yellow, 1 double yellow).
// UV2.y is 1 on a side street (UV.y from its mouth): a centre line and a stop line where it
// meets the road, no edge lines. Worn wheel tracks, patches, tar snakes and painted lines
// are drawn here rather than baked.

uniform sampler2D noise_fine : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_coarse : filter_linear_mipmap, repeat_enable;
uniform float half_width = 7.0;
uniform float lap_length = 1000.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;   // set by Reflections
// Along the lap (m): where the edge line breaks for a side road (from, to, side -1/+1), and
// the zebra crossings.
uniform vec4 gaps[32];
uniform float crossings[16];

varying vec3 wpos;
varying float style;
varying float street;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	style = UV2.x;
	street = UV2.y;
}

// 1 inside [a, b] with a pixel-wide soft edge.
float band(float x, float a, float b) {
	float w = fwidth(x) * 0.75 + 0.002;
	return smoothstep(a - w, a + w, x) * (1.0 - smoothstep(b - w, b + w, x));
}

void fragment() {
	float x = UV.x;
	float v = UV.y;
	float ax = abs(x);
	float f1 = texture(noise_fine, wpos.xz / 2.3).r;
	float f2 = texture(noise_fine, wpos.xz / 0.55).r;
	float c1 = texture(noise_coarse, wpos.xz / 70.0).r;
	float c2 = texture(noise_coarse, wpos.xz / 17.0).r;

	vec3 col = vec3(0.37, 0.36, 0.35) * (0.82 + 0.28 * f1) * (0.9 + 0.2 * f2);
	// Resurfaced patches, darker and smoother.
	float patch = smoothstep(0.66, 0.7, c2) * smoothstep(0.45, 0.6, c1);
	col = mix(col, vec3(0.3, 0.3, 0.31) * (0.9 + 0.2 * f2), patch * 0.6);
	// Tyres polish two dark tracks in each lane; oil down the middle of it.
	float lane = abs(ax - half_width * 0.5);
	float tracks = exp(-pow((lane - 0.85) / 0.4, 2.0));
	float oil = exp(-pow(lane / 0.35, 2.0)) * (0.5 + 0.5 * c2);
	col *= 1.0 - 0.14 * tracks - 0.1 * oil;
	col *= 0.9 + 0.2 * c1;
	// Tar snakes: sealed cracks wandering over the older stretches, a few cm wide (the
	// noise's contour, its distance from it taken from the noise's slope).
	vec2 tp = wpos.xz / 11.0;
	float tn = texture(noise_coarse, tp).r;
	vec2 tg = vec2(texture(noise_coarse, tp + vec2(0.02, 0.0)).r - texture(noise_coarse, tp - vec2(0.02, 0.0)).r,
		texture(noise_coarse, tp + vec2(0.0, 0.02)).r - texture(noise_coarse, tp - vec2(0.0, 0.02)).r) / (0.04 * 11.0);
	float td = abs(tn - 0.52) / max(length(tg), 0.002);
	float tpx = fwidth(wpos.x) + fwidth(wpos.z);
	float tar = (1.0 - smoothstep(0.012, 0.012 + tpx, td)) * smoothstep(0.62, 0.7, c1) * smoothstep(0.4, 0.6, c2);
	tar *= 1.0 - smoothstep(0.05, 0.12, tpx);   // gone before it would shimmer
	col = mix(col, vec3(0.14, 0.14, 0.15), tar * 0.6);

	// Paint: edge lines, the centre line, and the chequered start line; worn in places.
	vec3 paint_col = vec3(0.92, 0.92, 0.88);
	vec3 centre_col = vec3(0.95, 0.72, 0.12);
	float wear = smoothstep(0.15, 0.5, f2 * 0.6 + f1 * 0.6 - tracks * 0.25);
	if (street > 0.5) {
		// A side street: its centre line from past the pavement, and a stop line across the
		// lane coming out to the road.
		float cl = band(ax, -1.0, 0.07) * step(fract(v / 9.0), 0.5) * step(5.0, v);
		float stop = band(v, 3.0, 3.45) * band(x, -3.6, -0.1);
		col = mix(col, centre_col, cl * wear);
		col = mix(col, paint_col, stop * wear);
	} else {
		float sv = mod(v, lap_length);
		// The edge lines, broken where a side road joins.
		float edge_l = 1.0;
		float edge_r = 1.0;
		for (int k = 0; k < 32; k++) {
			float in_gap = step(gaps[k].x, sv) * step(sv, gaps[k].y);
			edge_r *= 1.0 - in_gap * step(0.0, gaps[k].z);
			edge_l *= 1.0 - in_gap * step(gaps[k].z, 0.0);
		}
		float paint = band(ax, half_width - 0.45, half_width - 0.3) * (x > 0.0 ? edge_r : edge_l);
		float cl;
		if (style > 0.5) {
			cl = band(ax, 0.1, 0.22);
		} else {
			cl = band(ax, -1.0, 0.07) * step(fract(v / 12.0), 0.4);
		}
		// Zebra crossings: bars along the road, 0.6 m wide.
		float zebra = 0.0;
		for (int k = 0; k < 16; k++) {
			zebra = max(zebra, band(sv, crossings[k] - 1.5, crossings[k] + 1.5));
		}
		zebra *= step(fract((x + 0.3) / 1.2), 0.5) * band(ax, -1.0, half_width - 0.5);
		float ss = mod(v + 0.8, lap_length);
		float start = step(ss, 1.6);
		vec2 chk = floor(vec2(x, ss) / 0.8);
		float checker = mod(chk.x + chk.y, 2.0);
		col = mix(col, paint_col, paint * wear);
		col = mix(col, centre_col, cl * wear * (1.0 - start) * (1.0 - zebra));
		col = mix(col, paint_col, zebra * wear);
		col = mix(col, mix(vec3(0.08), vec3(0.95), checker), start * band(ax, -1.0, half_width - 0.3));
	}

	float wet = wetness * (0.8 + 0.2 * c2);
	// The colours above are sRGB.
	ALBEDO = pow(col, vec3(2.2)) * mix(1.0, 0.55, wet);
	ROUGHNESS = mix(0.88 - 0.12 * tracks - 0.1 * patch, 0.1, wet);
	SPECULAR = mix(0.4, 0.7, wet);
}
