shader_type spatial;
// High Stakes' track glows (see TrackGlows): a camera-facing sprite per light source, added
// over the scene as the game draws them. Per instance: COLOR is the glow's colour and alpha;
// CUSTOM is (size, blink, cycle on, cycle off), blink = shift * 256 + phase or -1 (steady),
// the cycle in ticks (0: none).
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
// glw0 keeps its size on screen, a fraction of the view's focal length; glw3 is a halo of a
// fixed size in the world, drawn a little nearer (the game raises its 1/z by 5 %).
uniform bool screen_sized = false;
uniform float ticks_per_second = 64.0;
uniform float scale = 1.3;     // game units to metres
uniform float reach = 256.0;   // game units: dimmed linearly to nothing by here

varying vec4 tint;

void vertex() {
	vec4 centre = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float depth = -centre.z / scale;
	float ticks = floor(TIME * ticks_per_second);
	float lit = 1.0;
	if (INSTANCE_CUSTOM.y >= 0.0) {
		// Off while bit `shift` of the tick count plus the phase is set.
		float shift = floor(INSTANCE_CUSTOM.y / 256.0);
		float phase = mod(INSTANCE_CUSTOM.y, 256.0);
		lit = 1.0 - mod(floor((ticks + phase) / exp2(shift)), 2.0);
	}
	float on = INSTANCE_CUSTOM.z;
	float off = INSTANCE_CUSTOM.w;
	if (on > 0.0 && off > 0.0 && mod(ticks, on + off) >= on) {
		lit = 0.0;
	}
	float fade = depth >= 1.0 && depth <= reach ? (reach - depth) / reach : 0.0;
	tint = COLOR * fade * lit;
	// The two sprites turn opposite ways as the glow crosses the screen.
	float spin = (centre.x - centre.y) / max(-centre.z, 0.01) * 0.125 * (screen_sized ? -1.0 : 1.0);
	vec2 c = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * VERTEX.xy;
	float size = INSTANCE_CUSTOM.x;
	if (screen_sized) {
		POSITION = PROJECTION_MATRIX * centre;
		POSITION.xy += c * 0.025 * size * vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]) * POSITION.w;
	} else {
		POSITION = PROJECTION_MATRIX * vec4(centre.xyz / 1.05 + vec3(c * 0.25 * size * scale, 0.0), 1.0);
	}
}

void fragment() {
	vec4 s = texture(sprite, UV);
	ALBEDO = s.rgb * tint.rgb;
	ALPHA = s.a * tint.a;
}
