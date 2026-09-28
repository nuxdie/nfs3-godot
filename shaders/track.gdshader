shader_type spatial;
// NFS3 scenery carries pre-baked lighting in its vertex colours, so draw it
// unshaded: texture * vertex shade. One Texture2DArray per track; UV2.x picks the layer.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2DArray textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float brightness = 1.35;
// Night: the baked shading is scaled by `night_tint`, and the nearest cars' headlights
// (set each frame by the race) add cones of light. Unshaded, so real lights can't do it.
const int MAX_BEAMS = 16;   // MAX_LIGHT_CONES in race.gd
uniform vec3 night_tint = vec3(1.0);
uniform int beam_count = 0;
uniform vec3 beam_pos[MAX_BEAMS];
uniform vec3 beam_dir[MAX_BEAMS];
uniform vec3 beam_shape[MAX_BEAMS];   // reach (m), cos(outer cone angle), strength

varying flat float layer;
// 1 on a front/back quad pair sharing the same corners (road signs): cull the back face
// so the pair doesn't z-fight.
varying flat float one_sided;
varying vec3 world_pos;
// Rate of the game clock that animated textures (fire, water) step on.
const float TICKS_PER_SECOND = 60.0;

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
	one_sided = mod(UV2.y, 2.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (one_sided > 0.5 && !FRONT_FACING) {
		discard;
	}
	vec4 c = texture(textures, vec3(UV, layer));
	vec3 light = COLOR.rgb * brightness * night_tint;
	for (int i = 0; i < beam_count; i++) {
		vec3 d = world_pos - beam_pos[i];
		float dist = length(d);
		vec3 shape = beam_shape[i];
		float cone = smoothstep(shape.y, mix(shape.y, 1.0, 0.7), dot(d, beam_dir[i]) / max(dist, 0.01));
		float fall = clamp(1.0 - dist / shape.x, 0.0, 1.0);
		light += vec3(1.0, 0.95, 0.85) * cone * fall * fall * shape.z;
	}
	ALBEDO = c.rgb * light;
	// Alpha-tested foliage and fences, with alpha-to-coverage under MSAA so the cut-out
	// edges of the low-res textures aren't stair-stepped.
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(textures, 0).xy);
}
