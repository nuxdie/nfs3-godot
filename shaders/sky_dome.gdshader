shader_type spatial;
// Hot Pursuit 2's sky dome (Nfs6Track.sky: kilometres across round the origin), kept round the
// camera and pushed to the far plane, behind everything: drawn first of the transparent pass
// (render_priority), where it fills only what the opaque scene left empty. Its parts are
// layered in the game's draw order (clouds, sun glow over the sky).
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2DArray textures : source_color, filter_linear_mipmap, repeat_enable;
uniform float brightness = 1.0;
varying flat float layer;

void vertex() {
	layer = UV2.x;
	vec3 world = VERTEX + CAMERA_POSITION_WORLD;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	// Reverse Z: 0 is the far plane.
	POSITION.z = POSITION.w * 1e-7;
}

void fragment() {
	vec4 c = texture(textures, vec3(UV, layer));
	ALBEDO = c.rgb * COLOR.rgb * brightness;
	ALPHA = c.a * COLOR.a;
}
