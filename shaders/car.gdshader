shader_type spatial;
// NFS3 car skins are greyscale where the body is painted; those texels carry a
// mid-range alpha. Opaque texels (lights, tyres, badges) keep their colour and
// near-zero alpha is cut out. `paint` is the FCE colour at double strength
// (the paint areas are mid-grey), so it can exceed 1.
// The windows share the paint alpha but are near-black in the skin: those stay
// unpainted and get a glossy glass finish instead of tinting to the body colour.
// The wheels sample the same skin with `wheel` set: unpainted texels there are
// tyre rubber (matte), and painted rims get a satin rather than a clearcoat finish.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 paint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float gloss = 0.4;
uniform bool wheel = false;

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	// Cut out on the full-size skin's alpha, like the original's colour key. Traffic bodies
	// are big panels reaching down to the road whose lower edge and wheel arches are cut out
	// of the skin; the averaged alpha of the small mip levels shows those as strips on the road.
	if (textureLod(albedo_tex, UV, 0.0).a < 0.08) {
		discard;
	}
	float paint_area = 1.0 - smoothstep(0.7, 0.85, c.a);
	// Linear luminance; glass is ~0.1 in sRGB (0.01 linear), paint mostly above 0.3.
	float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	float glass = paint_area * (1.0 - smoothstep(0.012, 0.05, luma));
	float painted = paint_area - glass;
	vec3 body = min(c.rgb * paint.rgb, vec3(1.0));
	ALBEDO = mix(c.rgb, body, painted);
	ROUGHNESS = mix(mix(0.6, 1.0 - gloss, painted), 0.08, glass);
	METALLIC = 0.15 * painted;
	SPECULAR = mix(0.5, 0.8, glass);
#ifndef LOW_QUALITY
	// (Low quality: no clearcoat, a second specular lobe on every car pixel.)
	CLEARCOAT = 0.5 * painted;
	CLEARCOAT_ROUGHNESS = 0.3;
#endif
	if (wheel) {
		float rubber = 1.0 - painted;
		ROUGHNESS = mix(ROUGHNESS, 0.9, rubber);
		SPECULAR = mix(SPECULAR, 0.3, rubber);
#ifndef LOW_QUALITY
		CLEARCOAT *= 0.3;
#endif
	}
	// Back faces are the insides of panels that tuck under the body, seen along the bottom
	// edges; reflecting the sky they flicker as bright specks, so light them matte.
	if (!FRONT_FACING) {
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		METALLIC = 0.0;
#ifndef LOW_QUALITY
		CLEARCOAT = 0.0;
#endif
	}
}
