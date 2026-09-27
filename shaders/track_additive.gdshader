shader_type spatial;
// Additive pass for NFS3 effect textures (light shafts, glows, fire): black adds
// nothing, so they read as light rather than as solid dark slabs.
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;

uniform sampler2DArray textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float brightness = 1.35;

varying flat float layer;

void vertex() {
	layer = UV2.x;
}

void fragment() {
	vec4 c = texture(textures, vec3(UV, layer));
	ALBEDO = c.rgb * COLOR.rgb * brightness;
	ALPHA = c.a;
}
