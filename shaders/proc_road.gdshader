shader_type spatial;
// The procedural track's asphalt. UV.x is metres across from the centre line (+ right), UV.y
// metres along the lap; UV2.x picks the centre marking (0 dashed white, 1 double yellow).
// Worn wheel tracks, patches and painted lines are drawn here rather than baked.

uniform sampler2D noise_fine : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_coarse : filter_linear_mipmap, repeat_enable;
uniform float half_width = 7.0;
uniform float lap_length = 1000.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;   // set by Reflections

varying vec3 wpos;
varying float style;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	style = UV2.x;
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

	// Paint: edge lines, the centre line, and the chequered start line; worn in places.
	float paint = band(ax, half_width - 0.45, half_width - 0.3);
	vec3 paint_col = vec3(0.92, 0.92, 0.88);
	float cl;
	vec3 centre_col;
	if (style > 0.5) {
		cl = band(ax, 0.1, 0.22);
		centre_col = vec3(0.95, 0.72, 0.12);
	} else {
		cl = band(ax, -1.0, 0.08) * step(fract(v / 12.0), 0.45);
		centre_col = paint_col;
	}
	float wear = smoothstep(0.15, 0.5, f2 * 0.6 + f1 * 0.6 - tracks * 0.25);
	float sv = mod(v + 0.8, lap_length);
	float start = step(sv, 1.6);
	vec2 chk = floor(vec2(x, sv) / 0.8);
	float checker = mod(chk.x + chk.y, 2.0);
	col = mix(col, paint_col, paint * wear);
	col = mix(col, centre_col, cl * wear * (1.0 - start));
	col = mix(col, mix(vec3(0.08), vec3(0.95), checker), start * band(ax, -1.0, half_width - 0.3));

	float wet = wetness * (0.8 + 0.2 * c2);
	// The colours above are sRGB.
	ALBEDO = pow(col, vec3(2.2)) * mix(1.0, 0.55, wet);
	ROUGHNESS = mix(0.88 - 0.12 * tracks - 0.1 * patch, 0.1, wet);
	SPECULAR = mix(0.4, 0.7, wet);
}
