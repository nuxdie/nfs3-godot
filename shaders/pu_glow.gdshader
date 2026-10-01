shader_type spatial;
// Porsche Unleashed's light flares (see PuGlows): a camera-facing sprite per light and layer,
// added over the scene. Per instance: COLOR is the layer's colour and strength; CUSTOM is
// (half its width in m, the blink's phase, ticks on, ticks off; 0 on: steady).
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2D sprite : source_color, filter_linear_mipmap, repeat_disable;
uniform float ticks_per_second = 30.0;
uniform float reach = 600.0;   // m: dimmed to nothing by here

varying vec4 tint;

void vertex() {
	vec4 centre = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	float dist = -centre.z;
	float lit = 1.0;
	float on = INSTANCE_CUSTOM.z;
	float off = INSTANCE_CUSTOM.w;
	if (on > 0.0) {
		float ticks = floor(TIME * ticks_per_second) + INSTANCE_CUSTOM.y;
		lit = mod(ticks, on + off) < on ? 1.0 : 0.0;
	}
	float fade = clamp((reach - dist) / reach, 0.0, 1.0);
	tint = COLOR * fade * lit;
	// Drawn a little nearer, so a lamp's own glass doesn't hide its glow.
	POSITION = PROJECTION_MATRIX * vec4(centre.xyz * 0.97 + vec3(VERTEX.xy * INSTANCE_CUSTOM.x, 0.0), 1.0);
}

void fragment() {
	vec4 s = texture(sprite, UV);
	ALBEDO = s.rgb * tint.rgb;
	ALPHA = s.a * tint.a;
}
