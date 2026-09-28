shader_type spatial;
// Skid marks: each segment's strength is in the instance colour's alpha and, with the
// NFS3 textures, which of the four skid textures it uses in INSTANCE_CUSTOM.x. Without
// game data it's plain dark rubber, soft across the tread (UV.x).
// The track's alpha-tested surfaces are drawn in the transparent pass, so these go after
// them (render_priority) and fade out with distance, which keeps marks just past a crest
// from showing through it.
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D skid_atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_atlas = false;
uniform float atlas_cells = 4.0;
uniform float fade_start = 45.0;
uniform float fade_end = 75.0;

varying float cell;
varying float repeats;

void vertex() {
	cell = INSTANCE_CUSTOM.x;
	// A whole number of square tiles along the segment, so segments join without seams.
	repeats = max(round(length(MODEL_MATRIX[2].xyz) / length(MODEL_MATRIX[0].xyz)), 1.0);
}

void fragment() {
	float a;
	if (use_atlas) {
		// Keep the lookup off the cell edges so neighbouring skid textures don't bleed in.
		float u = (cell + mix(0.02, 0.98, UV.x)) / atlas_cells;
		vec4 t = texture(skid_atlas, vec2(u, UV.y * repeats));
		ALBEDO = t.rgb;
		a = t.a;
	} else {
		ALBEDO = vec3(0.04);
		a = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);
	}
	ALPHA = COLOR.a * a * (1.0 - smoothstep(fade_start, fade_end, length(VERTEX)));
}
