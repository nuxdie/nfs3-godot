// Additive pass for NFS3 effect textures (light shafts, glows, fire): black adds
// nothing, so they read as light rather than as solid dark slabs.
#ifdef SOFT_VOLUMES
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled, fog_disabled;
#else
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
#endif

uniform sampler2DArray textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// The same without wrapping (as in track.gdshader): a texture fading out toward one edge
// (the Dolphin Cove lighthouse beam) would otherwise pick up its opposite edge there.
uniform sampler2DArray textures_clamped : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float brightness = 1.35;
#ifdef SOFT_VOLUMES
// Scene depth, for a depth test of its own (see fragment()).
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// How far (m) in front of the light something may stand before it's hidden altogether.
uniform float see_through = 8.0;
#endif
// 1 at night: sunlight (vertex alpha 1, e.g. sun shafts) fades out; glows and fire stay.
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
	layer = anim_layer(UV2.x, UV2.y);
}

void fragment() {
	// Both sampled outside any branch so the mip derivatives stay valid.
	vec4 c_wrap = texture(textures, vec3(UV, layer));
	vec4 c_clamp = texture(textures_clamped, vec3(UV, layer));
	vec2 px = fwidth(UV);
	bool inside = all(greaterThanEqual(UV, -px)) && all(lessThanEqual(UV, 1.0 + px));
	vec4 c = inside ? c_clamp : c_wrap;
	float a = c.a * (1.0 - night * COLOR.a);
	float gain = brightness;
#ifdef SOFT_VOLUMES
	// Faded where a face turns edge-on, a flat shaft or the beam's six-sided tube reads as
	// a shaft of light rather than a slab.
	float facing = abs(dot(NORMAL, VIEW));
	a *= facing * facing;
	// The sun shafts hang just behind the first row of the forest's cut-out cards: a plain
	// depth test shows them only in the gaps, chopped along the leaves' edges. Instead
	// they fade out over the first see_through metres of whatever stands in front, so they
	// shine through the leaves but not through a hill.
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_texture, SCREEN_UV).r, 1.0);
	float in_front = scene.z / scene.w - VERTEX.z;   // > 0: the scene is nearer than the light
	a *= clamp(1.0 - in_front / see_through, 0.0, 1.0);
	gain = 1.0;
#endif
	ALBEDO = c.rgb * COLOR.rgb * gain;
	ALPHA = a;
}
