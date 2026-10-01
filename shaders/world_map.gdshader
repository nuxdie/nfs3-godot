shader_type canvas_item;
// The track picker's world map: land as a field of dots (anchored to the map, so they ride
// along when it pans, and doubling up as it zooms), a faint coast and borders, a 10° grid,
// fading out at the edges into whatever is behind. data/world_map.png: red land, green borders,
// Miller projection; map units are radians across (0..2π) and down (0..π).

uniform sampler2D map_tex : filter_linear_mipmap, repeat_enable;
uniform vec2 center;            // map units at `origin`
uniform float zoom = 200.0;     // px per map unit
uniform vec2 origin;            // px, in the rect
uniform vec2 rect_size;
uniform float fade = 48.0;      // px of fade at the edges
uniform float top_fade = 0.0;   // extra px faded at the top (under the header)
uniform vec4 sea : source_color = vec4(0.03, 0.035, 0.05, 0.9);
uniform vec4 land : source_color = vec4(0.075, 0.085, 0.11, 1.0);
uniform vec4 dot_col : source_color = vec4(0.36, 0.39, 0.47, 1.0);
uniform vec4 coast : source_color = vec4(0.55, 0.6, 0.7, 1.0);

const float TOP = 2.0016178;    // miller(84°), as tools/bake_world_map.py

float land_at(vec2 m) {
	return texture(map_tex, vec2(m.x / (2.0 * PI), m.y / PI)).r;
}

// Dots on a grid `pitch` map units apart, sized by the land under each one's centre.
float dots(vec2 m, float pitch) {
	vec2 cell = floor(m / pitch);
	vec2 c = (cell + 0.5) * pitch;
	float l = textureLod(map_tex, vec2(c.x / (2.0 * PI), c.y / PI), 0.0).r;
	float r_px = pitch * zoom * 0.2 * smoothstep(0.25, 0.75, l);
	float d_px = length(m - c) * zoom;
	return 1.0 - smoothstep(r_px - 0.7, r_px + 0.7, d_px);
}

float grid_line(float v, float step) {
	float g = abs(fract(v / step + 0.5) - 0.5) * step;
	return 1.0 - smoothstep(0.0, fwidth(v) * 1.2, g);
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 m = (px - origin) / zoom + center;
	vec4 tex = texture(map_tex, vec2(m.x / (2.0 * PI), m.y / PI));
	float l = tex.r;
	// Off the bottom of the picture (Antarctica's rim): sea.
	if (m.y > PI || m.y < 0.0) { l = 0.0; tex.g = 0.0; }

	vec3 col = mix(sea.rgb, land.rgb, l);
	float a = mix(sea.a, land.a, l);

	// The grid: every 10° of longitude and latitude.
	float lon = degrees(m.x - PI);
	float lat = degrees(2.5 * atan(exp(0.8 * (TOP - m.y))) - 0.625 * PI);
	float g = max(grid_line(lon, 10.0), grid_line(lat, 10.0));
	col = mix(col, vec3(1.0), g * mix(0.05, 0.02, l));

	// Dots about 7 px apart, cross-fading between two pitches as the zoom changes.
	float lvl = log2(7.0 / zoom);
	float l0 = floor(lvl);
	float f = lvl - l0;
	float dt = mix(dots(m, exp2(l0)), dots(m, exp2(l0 + 1.0)), smoothstep(0.0, 1.0, f));
	col = mix(col, dot_col.rgb, dt * 0.85);

	// Coast: where the land mask changes, a thin bright line.
	float edge = clamp(fwidth(l) * 1.5, 0.0, 1.0) * (1.0 - abs(l - 0.5) * 2.0);
	col = mix(col, coast.rgb, clamp(edge * 2.2, 0.0, 0.7));
	// Borders, faint.
	col = mix(col, vec3(0.85, 0.88, 0.95), tex.g * 0.18 * l);

	// Fade out at the edges.
	float e = min(min(px.x, rect_size.x - px.x), rect_size.y - px.y);
	float fe = smoothstep(0.0, fade, e) * smoothstep(0.0, fade + top_fade, px.y);
	COLOR = vec4(col, a * fe);
}
