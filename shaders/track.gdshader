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
	ALBEDO = c.rgb * COLOR.rgb * brightness;
	// Alpha-tested foliage and fences, with alpha-to-coverage under MSAA so the cut-out
	// edges of the low-res textures aren't stair-stepped.
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(textures, 0).xy);
}
