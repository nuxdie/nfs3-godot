shader_type spatial;
// Additive pass for NFS3 effect textures (light shafts, glows, fire): black adds
// nothing, so they read as light rather than as solid dark slabs.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;

uniform sampler2DArray textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float brightness = 1.35;

varying flat float layer;
const float TICKS_PER_SECOND = 60.0;   // as in track.gdshader

// UV2.y packs one_sided (bit 0), animation frame count (x2) and ticks per frame (x16).
float anim_layer(float base, float packed) {
	float frames = mod(floor(packed / 2.0), 8.0);
	float period = floor(packed / 16.0);
	if (frames < 2.0) {
		return base;
	}
	return base + mod(floor(TIME * TICKS_PER_SECOND / period), frames);
}

void vertex() {
	layer = anim_layer(UV2.x, UV2.y);
}

void fragment() {
	vec4 c = texture(textures, vec3(UV, layer));
	ALBEDO = c.rgb * COLOR.rgb * brightness;
	ALPHA = c.a;
}
