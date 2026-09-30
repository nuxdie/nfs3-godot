shader_type spatial;
// Porsche Unleashed's glints (Nfs5Car.glints): the sun catching the chrome, a star (GLNT)
// on each rim, bumper, handle, badge and pipe the model marks. Each is a quad whose four
// corners sit at its point (NORMAL the way it faces, UV the corner, COLOR.r its own phase);
// it faces the camera and flares as the sun's reflection off it swings into the eye, a
// little rotating and twinkling. Drawn `lift` m nearer, like the lamps' glows, so the
// bodywork round it doesn't cut it.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

uniform sampler2D glint_tex : source_color, filter_linear_mipmap;
uniform vec3 sun_dir = vec3(0.3, 0.8, 0.5);   // towards the sun, world
uniform float sun_energy = 1.0;               // 0 at night or under cloud
uniform float size = 0.32;
uniform float lift = 0.1;

varying float strength;

void vertex() {
	vec3 centre = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float d = max(length(centre), 1e-4);
	vec3 to_eye = -centre / d;
	vec3 sun = normalize((VIEW_MATRIX * vec4(sun_dir, 0.0)).xyz);
	vec3 h = normalize(sun + to_eye);
	float seen = smoothstep(0.0, 0.25, dot(n, to_eye)) * smoothstep(-0.05, 0.2, dot(n, sun));
	strength = pow(max(dot(n, h), 0.0), 6.0) * seen * sun_energy;
	strength *= 0.7 + 0.3 * sin(TIME * 9.0 + COLOR.r * 40.0);
	float s = size * (0.35 + 0.65 * strength) * length(MODEL_MATRIX[0].xyz);
	float a = TIME * 0.6 + COLOR.r * 6.2832;
	vec2 corner = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * ((UV - 0.5) * s);
	float k = (d - min(lift, d * 0.5)) / d;
	VERTEX = (centre + vec3(corner, 0.0)) * k;
}

void fragment() {
	vec4 t = texture(glint_tex, UV);
	ALBEDO = t.rgb * vec3(1.0, 0.97, 0.9) * strength * 1.6;
	ALPHA = t.a * clamp(strength * 2.0, 0.0, 1.0);
}
