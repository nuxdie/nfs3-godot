shader_type spatial;
// NFS3 car skins are greyscale where the body is painted; those texels carry a
// mid-range alpha. Opaque texels (lights, tyres, badges) keep their colour and
// near-zero alpha is cut out. `paint` is the FCE colour at double strength
// (the paint areas are mid-grey), so it can exceed 1.
// The windows share the paint alpha but are near-black in the skin: those stay
// unpainted and get a glossy glass finish instead of tinting to the body colour.
// The wheels sample the same skin with `wheel` set: unpainted texels there are
// tyre rubber (matte), and painted rims are polished alloy rather than clearcoated paint.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
// Porsche Unleashed's crumpled paint, in the skin's layout (transparent where it has none):
// shown as far as each vertex's panel is bent, which CarDamage writes as 1 - COLOR.a (the
// meshes carry no colours, which read as white).
uniform sampler2D damage_tex : source_color, hint_default_transparent, filter_linear_mipmap;
uniform vec4 paint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float gloss = 0.4;
uniform bool wheel = false;
// High Stakes' cockpit (the in-car view's dash, seats and doors): shut in under the roof, it
// sees neither the sky nor the reflection probe's open road, so it takes no clearcoat and
// only a faint sheen instead of mirroring them as a blue-grey film.
uniform bool interior = false;
// High Stakes' driver: the vertices marked in UV2.x (steering wheel and hands) turn by
// `steer_angle` about the column through `steer_pivot`, mesh-local.
uniform float steer_angle = 0.0;
uniform vec3 steer_pivot = vec3(0.0);
uniform vec3 steer_axis = vec3(0.0, 0.0, 1.0);

void vertex() {
	if (UV2.x > 0.5 && steer_angle != 0.0) {
		// Rodrigues: the same turn as Basis(steer_axis, steer_angle).
		float c = cos(steer_angle);
		float s = sin(steer_angle);
		vec3 p = VERTEX - steer_pivot;
		VERTEX = steer_pivot + p * c + cross(steer_axis, p) * s + steer_axis * dot(steer_axis, p) * (1.0 - c);
		NORMAL = NORMAL * c + cross(steer_axis, NORMAL) * s + steer_axis * dot(steer_axis, NORMAL) * (1.0 - c);
	}
	// Porsche Unleashed's depth bias (UV2.y): decals and badges lying on the bodywork slide
	// along the line to the eye by that share of their distance (the interior away from it),
	// which changes their depth but not where they're drawn, so they don't flicker against
	// the panel under them. (Perspective views only: in a directional light's shadow map
	// it would shift them.)
	if (UV2.y != 0.0 && PROJECTION_MATRIX[3][3] == 0.0) {
		vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		VERTEX += (eye - VERTEX) * UV2.y;
	}
}

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
	vec4 crumple = texture(damage_tex, UV);
	float bent = crumple.a * clamp((1.0 - COLOR.a) * 1.5, 0.0, 1.0);
	// The creases are grey about a third of the way up: darker than that shades, lighter lifts.
	ALBEDO *= mix(vec3(1.0), clamp(crumple.rgb * 2.6, 0.0, 1.6), bent);
	// Paint is two layers: the pigment, a plain dielectric with a soft sheen of its own, and
	// on top a clearcoat that mirrors the surroundings sharply but only strongly at grazing
	// angles. (A metallic or glossier base smears the whole sky over the body as an even
	// grey film: the "porcelain" look.)
	// Unpainted texels: bright ones are lamps, chrome and badges (glossy), dark ones
	// plastic trim and grilles (satin).
	float trim_rough = mix(0.65, 0.3, smoothstep(0.05, 0.4, luma));
	float paint_rough = 1.0 - gloss;   // 0.6 by default: the base coat, under the clear
#ifdef LOW_QUALITY
	paint_rough -= 0.2;                // no clearcoat to carry the shine: gloss the base a little
#endif
	ROUGHNESS = mix(mix(trim_rough, paint_rough, painted), 0.06, glass);
	METALLIC = 0.0;
	// Horizon occlusion: what a panel mirrors below the horizon is the road under the car and
	// the car's own shade, not the bright open road the sky or the reflection probe (taken from
	// above the road, without the cars) offers. Unchecked, a flank seen at a glancing angle
	// turns into a grey chrome mirror of it.
	vec3 refl = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
	float sky = smoothstep(-0.35, 0.15, refl.y);
	SPECULAR = mix(0.5 * mix(0.4, 1.0, sky), 0.8, glass);
#ifndef LOW_QUALITY
	// (Low quality: no clearcoat, a second specular lobe on every car pixel.)
	CLEARCOAT = painted * mix(0.1, 1.0, sky);
	CLEARCOAT_ROUGHNESS = 0.05;
#endif
	if (wheel) {
		// Painted rims: bright texels are alloy, dark ones tyre wall drawn in the paint area.
		float alloy = painted * smoothstep(0.1, 0.35, luma);
		float rubber = 1.0 - alloy;
		METALLIC = 0.5 * alloy;
		// The skins draw rubber mid-grey; real tyres are near black. Only the unsaturated
		// dark-to-mid texels: bright ones are unpainted rims and hub caps.
		float sat = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
		ALBEDO *= mix(1.0, 0.45, rubber * (1.0 - smoothstep(0.25, 0.5, luma)) * (1.0 - smoothstep(0.05, 0.15, sat)));
		ROUGHNESS = mix(0.35, 0.9, rubber);
		SPECULAR = mix(SPECULAR, 0.3, rubber);
#ifndef LOW_QUALITY
		CLEARCOAT = 0.0;
#endif
	}
	if (interior) {
		ROUGHNESS = max(ROUGHNESS, 0.7);
		SPECULAR *= 0.25;
#ifndef LOW_QUALITY
		CLEARCOAT = 0.0;
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
