shader_type spatial;
// NFS3 car skins are greyscale where the body is painted; those texels carry a
// mid-range alpha. Opaque texels (lights, tyres, badges) keep their colour and
// near-zero alpha is cut out. `paint` is the FCE colour at double strength
// (the paint areas are mid-grey), so it can exceed 1.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 paint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float gloss = 0.55;

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < 0.08) {
		discard;
	}
	float painted = 1.0 - smoothstep(0.7, 0.85, c.a);
	vec3 body = min(c.rgb * paint.rgb, vec3(1.0));
	ALBEDO = mix(c.rgb, body, painted);
	ROUGHNESS = mix(0.6, 1.0 - gloss, painted);
	METALLIC = 0.3 * painted;
	SPECULAR = 0.6;
}
