shader_type spatial;
// NFS3 scenery carries pre-baked lighting in its vertex colours, so draw it
// unshaded: texture * vertex shade. One Texture2DArray per track; UV2.x picks the layer.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2DArray textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float brightness = 1.35;

varying flat float layer;

void vertex() {
	layer = UV2.x;
}

void fragment() {
	vec4 c = texture(textures, vec3(UV, layer));
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * COLOR.rgb * brightness;
}
