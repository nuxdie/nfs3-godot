shader_type spatial;
// Hot Pursuit 2's sky dome (Nfs6Track.sky: kilometres across round the origin), kept round the
// camera and pushed to the far plane, behind everything: drawn first of the transparent pass
// (render_priority), where it fills only what the opaque scene left empty. Its parts are
// layered in the game's draw order (clouds, sun glow over the sky).
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform sampler2DArray textures : source_color, filter_linear_mipmap, repeat_enable;
uniform float brightness = 1.0;
// 1 at night (TrackWorld sets it, the material being among the track's night_materials): the
// game has no night sky, so the day's goes dark and blue.
uniform float night = 0.0;
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
	vec3 day = c.rgb * COLOR.rgb * brightness;
	ALBEDO = mix(day, dot(day, vec3(0.3, 0.5, 0.2)) * vec3(0.05, 0.07, 0.14), night);
	ALPHA = c.a * COLOR.a;
}
