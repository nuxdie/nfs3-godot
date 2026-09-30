shader_type spatial;
// High Stakes' car windows (the triangles its FCE4 flags as windows): the skin's dark
// glass texels, see-through so the driver and cockpit show behind them, turning to a
// mirror of the sky at grazing angles.
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float clarity = 0.5;   // how see-through the glass is face-on
// A Porsche Unleashed door window's belt line (see the fragment): off by default.
instance uniform vec4 window_belt = vec4(-1e6, 0.0, 0.0, 0.0);

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

void fragment() {
	// A Porsche Unleashed door window wound down (Car._pose_lid): what's below the door's belt
	// line, y = x + y z in the door's frame (the pane's own, moved down by zw), is in the door.
	if (model_pos.y + window_belt.z < window_belt.x + window_belt.y * (model_pos.z + window_belt.w)) {
		discard;
	}
	// Porsche Unleashed's window triangles (COLOR.b 0.25, Nfs5Car.WINDOW_MARK) are in the
	// bodywork too: here only their pane (alpha exactly 128, nearest), car.gdshader the rest.
	if (abs(COLOR.b - 0.25) < 0.1) {
		ivec2 size = textureSize(albedo_tex, 0);
		float a = texelFetch(albedo_tex, clamp(ivec2(UV * vec2(size)), ivec2(0), size - 1), 0).a;
		if (abs(a - 128.0 / 255.0) >= 0.01) {
			discard;
		}
	}
	vec4 c = texture(albedo_tex, UV);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = c.rgb * 0.6;
	ALPHA = clamp(1.0 - clarity + fresnel * 0.5, 0.0, 0.95);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.9;
}
