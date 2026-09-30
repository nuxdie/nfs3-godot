shader_type spatial;
// A lamp's glow (Car._lamp_glow()): a small camera-facing additive sprite, centred on the
// lamp. It is drawn `lift` m nearer the eye, scaled to look the same size, so the bodywork
// the lamp is set in doesn't cut it: only its depth moves, not where it's seen. A lamp that
// shines ahead (`facing` 1) or behind (-1) fades out as the eye goes round past its side, as
// its lens turns away; 0 shines all round.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D glow_tex : source_color, filter_linear;
uniform vec4 colour : source_color = vec4(1.0);
uniform float lift = 0.12;
uniform float facing = 0.0;

varying float fade;

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = max(length(centre), 1e-4);
	float k = (d - min(lift, d * 0.5)) / d;
	vec3 ahead = (MODELVIEW_MATRIX * vec4(0.0, 0.0, facing, 0.0)).xyz;
	fade = facing == 0.0 ? 1.0 : smoothstep(-0.15, 0.35, dot(normalize(ahead), -centre / d));
	VERTEX = (centre + vec3(VERTEX.xy * length(MODEL_MATRIX[0].xyz), 0.0)) * k;
}

void fragment() {
	vec4 t = texture(glow_tex, UV);
	// Porsche Unleashed's glare is opaque, its light in the colour: carry that in the alpha
	// instead (the same light added), else blend_add would make the showroom's transparent
	// viewport opaque black round every lamp.
	float l = max(max(t.r, t.g), max(t.b, 1e-4));
	ALBEDO = t.rgb / l * colour.rgb;
	ALPHA = t.a * l * colour.a * fade;
}
