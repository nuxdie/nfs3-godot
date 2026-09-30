shader_type spatial;
// High Stakes' officer (cop.fce): one rigid mesh with no limbs of its own, so his walk is
// faked here. The vertices below his hips swing about a hip pivot, the two legs opposite
// each other (split at leg_split in X), and the forward-going leg bends at the knee. Legs
// modelled wide apart are first brought in under him (splay). The body dips as the legs
// spread so his feet stay on the ground. Otherwise it's
// art_materials' cut-out material. See Officer.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float hip_y = 0.9;       // where the legs pivot
uniform float knee_y = 0.45;
uniform float leg_split = 0.0;   // X between the legs
uniform float pivot_z = 0.0;
uniform float splay = 0.0;       // rad each leg leans out in the model, taken out walking
uniform float phase = 0.0;       // PI a step
uniform float stride = 0.0;      // 0 standing .. 1 walking
uniform float swing = 0.38;      // rad, each way
uniform float knee_bend = 0.6;   // rad at most, beyond the model's own

// `v` turned by `a` about the X axis through (y, z).
vec3 pitch(vec3 v, float a, float y, float z) {
	float c = cos(a);
	float s = sin(a);
	vec2 p = v.yz - vec2(y, z);
	return vec3(v.x, y + p.x * c - p.y * s, z + p.x * s + p.y * c);
}

// `v` turned by `a` about the Z axis through (x, y).
vec3 roll(vec3 v, float a, float x, float y) {
	float c = cos(a);
	float s = sin(a);
	vec2 p = v.xy - vec2(x, y);
	return vec3(x + p.x * c - p.y * s, y + p.x * s + p.y * c, v.z);
}

void vertex() {
	// Full swing a little below the hip, fading to none at it, so the seam stretches
	// instead of tearing; the crotch between the legs swings less.
	float w = 1.0 - smoothstep(hip_y - 0.18, hip_y, VERTEX.y);
	float side = clamp((VERTEX.x - leg_split) / 0.05, -1.0, 1.0);
	float a = swing * stride * sin(phase) * side * w;
	// Knee bent while the leg swings forward (+Z, where he faces: a falling), shin back.
	float fwd = -side * cos(phase);
	float k = knee_bend * stride * max(fwd, 0.0) * abs(side) * (1.0 - smoothstep(knee_y - 0.08, knee_y + 0.04, VERTEX.y));
	float b = -splay * stride * side * w;
	vec3 v = roll(VERTEX, b, leg_split, hip_y);
	v = pitch(v, k, knee_y, pivot_z);
	v = pitch(v, a, hip_y, pivot_z);
	vec3 n = pitch(pitch(roll(NORMAL, b, 0.0, 0.0), k, 0.0, 0.0), a, 0.0, 0.0);
	// The planted leg's drop: a leg of hip_y at `swing` reaches hip_y * cos(swing); and the
	// rise from standing the leaning legs up straight.
	v.y -= hip_y * (1.0 - cos(swing * stride * sin(phase)));
	v.y += hip_y * (1.0 / cos(splay * stride) - 1.0);
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
