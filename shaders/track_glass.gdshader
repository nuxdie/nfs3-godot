shader_type spatial;
// See-through pass for NFS3 scenery textures that are part transparent (Celtic Ruins' phone
// box glass, Dolphin Cove's surf): alpha-blended, where track.gdshader cuts out at half alpha
// and would drop the glass altogether.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2DArray textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float brightness = 1.35;
// 1 at night: dimmed like the opaque scenery's baked light (track_world's night tint).
uniform float night = 0.0;

varying flat float layer;
uniform float ticks_per_second = 60.0;   // as in track.gdshader

// UV2.y packs one_sided (bit 0), animation frame count (x2) and ticks per frame (x16).
float anim_layer(float base, float packed) {
	float frames = mod(floor(packed / 2.0), 8.0);
	float period = floor(packed / 16.0);
	if (frames < 2.0) {
		return base;
	}
	return base + mod(floor(TIME * ticks_per_second / period), frames);
}

void vertex() {
	// Porsche Unleashed's scrolling water (see track.gdshader).
	UV += fract(CUSTOM1.xy * TIME);
	layer = anim_layer(UV2.x, UV2.y);
}

void fragment() {
	vec4 c = texture(textures, vec3(UV, layer));
	ALBEDO = c.rgb * COLOR.rgb * brightness * mix(vec3(1.0), vec3(0.16, 0.18, 0.28), night);
	ALPHA = c.a;
}
