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
// Panel shut lines: how deep (model units) the dark lines drawn in the paint are cut.
uniform float seam_depth = 0.006;
// SkinHD's upscaled skins: log2 of their scale (0 the game's own). Their cut-outs' contours are
// smooth already, and the tests on "the skin round a texel" look that many mips further up.
uniform int skin_lod = 0;
// High Stakes' cockpit (the in-car view's dash, seats and doors): shut in under the roof, it
// sees neither the sky nor the reflection probe's open road, so it takes no clearcoat and
// only a faint sheen instead of mirroring them as a blue-grey film.
uniform bool interior = false;
// Porsche Unleashed's cabin trim and leather: skin texels at alpha 224 (Nfs5Car.CABIN_ALPHA)
// take this colour, at double strength as the paint does. Transparent (other cars): unused.
uniform vec4 interior_paint = vec4(0.0);
// High Stakes' driver: the vertices marked in UV2.x (steering wheel and hands) turn by
// `steer_angle` about the column through `steer_pivot`, mesh-local.
uniform float steer_angle = 0.0;
uniform vec3 steer_pivot = vec3(0.0);
uniform vec3 steer_axis = vec3(0.0, 0.0, 1.0);
// Porsche Unleashed's finishes, per vertex from its material (Nfs5Car.MAT_ENV_FROM_END):
// COLOR.b 0 marks them there (the other cars' meshes have no colours: white), COLOR.r how
// much it mirrors (0 matte, 0.5 gloss, 1 chrome), COLOR.g 1 on a lamp's lens. The lenses
// light with their lamps (Car sets these): the front ones' clear glass with the headlights,
// the back ones' red with the tail lamps and brakes, the white with reversing, the amber
// with the indicators on their side (+X the left).
uniform float head_lit = 0.0;
uniform float tail_lit = 0.0;
uniform float brake_lit = 0.0;
uniform float reverse_lit = 0.0;
uniform float indicator_left = 0.0;
uniform float indicator_right = 0.0;

varying vec3 model_pos;

// A Porsche Unleashed door window's belt line (see the fragment): off by default.
instance uniform vec4 window_belt = vec4(-1e6, 0.0, 0.0, 0.0);

// A Porsche Unleashed window page's see-through pane: its texel's alpha exactly 128 (nearest,
// as filtering would blend it with the seal's 255 and the rim's paint 117 into its range).
float min4(vec4 v) {
	return min(min(v.x, v.y), min(v.z, v.w));
}

// How far the skin at uv falls below the paint round it (`around`, its luminance a few mips
// up): 0 plain paint .. 1 a shut line drawn in it.
float seam_at(sampler2D tex, vec2 uv, float around) {
	float l = dot(texture(tex, uv).rgb, vec3(0.2126, 0.7152, 0.0722));
	return 1.0 - smoothstep(0.5, 0.9, l / max(around, 0.01));
}

bool pu_pane(sampler2D tex, vec2 uv) {
	ivec2 size = textureSize(tex, 0);
	float a = texelFetch(tex, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1), 0).a;
	return abs(a - 128.0 / 255.0) < 0.01;
}

// Porsche Unleashed's share of the texels round UV whose alpha is `a` (paint 117, cabin 224),
// among the visible ones: at a cut-out's edge (the dials' faces, the handles) the filtered
// alpha fades from 0 up to the opaque 255 through those, which would tint the rim.
float pu_alpha_share(sampler2D tex, vec2 uv, float a) {
	vec2 f = fract(uv * vec2(textureSize(tex, 0)) - 0.5);
	vec4 w = vec4((1.0 - f.x) * f.y, f.x * f.y, f.x * (1.0 - f.y), (1.0 - f.x) * (1.0 - f.y));
	vec4 g = textureGather(tex, uv, 3);
	vec4 seen = w * step(0.08, g);
	vec4 hit = seen * (1.0 - step(0.02, abs(g - a)));
	return dot(hit, vec4(1.0)) / max(dot(seen, vec4(1.0)), 1e-5);
}

// The skin's alpha at UV from mip `lod`, filtered with a cubic B-spline (four bilinear taps).
float bspline_alpha(sampler2D tex, vec2 uv, float lod) {
	vec2 size = vec2(textureSize(tex, int(lod)));
	vec2 p = uv * size - 0.5;
	vec2 i = floor(p);
	vec2 t = p - i;
	vec2 t2 = t * t;
	vec2 t3 = t2 * t;
	vec2 w0 = (1.0 - 3.0 * t + 3.0 * t2 - t3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * t2 + 3.0 * t3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * t + 3.0 * t2 - 3.0 * t3) / 6.0;
	vec2 w3 = t3 / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 lo = (i - 0.5 + w1 / g0) / size;
	vec2 hi = (i + 1.5 + w3 / g1) / size;
	return g0.y * (g0.x * textureLod(tex, lo, lod).a + g1.x * textureLod(tex, vec2(hi.x, lo.y), lod).a)
			+ g1.y * (g0.x * textureLod(tex, vec2(lo.x, hi.y), lod).a + g1.x * textureLod(tex, hi, lod).a);
}

void vertex() {
	model_pos = VERTEX;
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
	// A Porsche Unleashed door window wound down (Car._pose_lid): what's below the door's belt
	// line, y = x + y z in the door's frame (the pane's own, moved down by zw), is in the door.
	if (model_pos.y + window_belt.z < window_belt.x + window_belt.y * (model_pos.z + window_belt.w)) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV);
	// Cut out on the full-size skin's alpha, like the original's colour key. Traffic bodies
	// are big panels reaching down to the road whose lower edge and wheel arches are cut out
	// of the skin; the averaged alpha of the small mip levels shows those as strips on the road.
	// Porsche Unleashed's cut-outs (the wheel arches, round handles and flaps) are a hard step
	// from 0 to the paint's alpha (0.46) at a couple of cm a texel: cut halfway up the
	// filtered step. Their contours are drawn in stairs of several texels, which a bilinear
	// lookup of the full-size skin keeps: near a cut-out's edge (where the small mip differs)
	// the alpha is taken smoothed from the half-size one instead, whose contour runs in
	// curves, but only in the cells with a visible texel, so it doesn't spill into the
	// cut-out where it borders another piece of the skin.
	// Cut-outs from fully opaque texels (the tyres' inner discs, a 32-texel circle on a
	// square) are cut halfway up their own step, 0.5, from the full-size skin smoothed: at
	// the paint's 0.23 the smoothed contour lies outside the visible cells all round, which
	// clipped it back to the texel stairs; and the half-size one is too coarse for so small
	// a shape, bulging it into its neighbours.
	float cut = COLOR.b < 0.5 ? 0.23 : 0.08;
	float cut_alpha = textureLod(albedo_tex, UV, 0.0).a;
	if (skin_lod == 0 && abs(textureLod(albedo_tex, UV, 2.0).a - cut_alpha) > 0.01) {
		vec4 cell = textureGather(albedo_tex, UV, 3);
		float cell_max = max(max(cell.x, cell.y), max(cell.z, cell.w));
		float seen_min = min4(mix(vec4(1.0), cell, step(cut, cell)));
		if (cell_max < cut) {
			cut_alpha = 0.0;
		} else if (seen_min > 0.99) {
			cut_alpha = bspline_alpha(albedo_tex, UV, 0.0) * cut / 0.5;
		} else {
			cut_alpha = bspline_alpha(albedo_tex, UV, 1.0);
		}
	}
	if (cut_alpha < cut) {
		discard;
	}
	// Porsche Unleashed's lid undersides (UV2.x ONE_SIDED_MARK, Nfs5Car) face one way only.
	if (UV2.x < -2.5 && !FRONT_FACING) {
		discard;
	}
	// Porsche Unleashed's window triangles (COLOR.b WINDOW_MARK, Nfs5Car): the glass part draws
	// their pane (alpha 128 on the window page), this their seal and painted rim.
	if (abs(COLOR.b - 0.25) < 0.1 && pu_pane(albedo_tex, UV)) {
		discard;
	}
	float paint_area = 1.0 - smoothstep(0.7, 0.85, c.a);
	bool pu_edge = COLOR.b < 0.5 && textureLod(albedo_tex, UV, 0.0).a < 0.99 && min4(textureGather(albedo_tex, UV, 3)) < 0.08;
	if (pu_edge) {
		paint_area = pu_alpha_share(albedo_tex, UV, 117.0 / 255.0);
	}
	// Linear luminance; glass is ~0.1 in sRGB (0.01 linear), paint mostly above 0.3.
	float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	// (Porsche Unleashed's windows are parts of their own: its dark paint texels are the
	// panels' shut lines and the shadows drawn round handles and flaps, and stay paint.)
	float glass = paint_area * (1.0 - smoothstep(0.012, 0.05, luma)) * step(0.5, COLOR.b);
	float painted = paint_area - glass;
	// Shut lines: paint texels much darker than the skin round them (three mips up). They are
	// only drawn, so the clearcoat mirrored the sky straight across them and they vanished;
	// cut into the body here they break its reflections and catch the light on one edge.
	// (As the lines blur into their surroundings further off, they fade out by themselves.)
	float seam = 0.0;
	if (!wheel && !interior) {
		vec4 around = texture(albedo_tex, UV, 3.0 + float(skin_lod));
		float around_luma = dot(around.rgb, vec3(0.2126, 0.7152, 0.0722));
		float around_paint = 1.0 - smoothstep(0.7, 0.85, around.a);
		// (Not beside a cut-out, whose transparent texels darken the mips round its edge.)
		float solid = smoothstep(0.8, 0.95, around.a / max(c.a, 0.01)) * (pu_edge ? 0.0 : 1.0);
		// How many screen pixels a skin texel spans: a line a texel or two wide thinner than a
		// pixel only sparkles as the car moves, so the seams fade out below that (the bump,
		// which needs a few pixels across the groove to show its edges, sooner).
		vec2 texels = UV * vec2(textureSize(albedo_tex, 0));
		float texel_px = 1.0 / max(max(length(dFdx(texels)), length(dFdy(texels))), 1e-4);
		// The other cars' skins (256 texels square, with shading drawn in) mark far more than the
		// shut lines, a texel's width a hand across: only dim their mirror there, and gently.
		float bump = COLOR.b < 0.5 ? smoothstep(0.8, 2.0, texel_px) : 0.0;
		float keep = painted * around_paint * solid * smoothstep(0.3, 0.8, texel_px) * (COLOR.b < 0.5 ? 1.0 : 0.5);
		seam = keep * seam_at(albedo_tex, UV, around_luma);
		if (bump > 0.0) {
			// Bump without tangents (Mikkelsen's surface gradient): the groove's depth, taken a
			// pixel over each way from the skin itself (not the 2x2 blocks dFdx sees, which
			// step along a line's edge and crawl), tilts the normal into it.
			float d = -keep * bump * seam_depth;
			float h = seam * d / max(keep, 1e-4);
			float dhx = seam_at(albedo_tex, UV + dFdx(UV), around_luma) * d - h;
			float dhy = seam_at(albedo_tex, UV + dFdy(UV), around_luma) * d - h;
			vec3 dpdx = dFdx(VERTEX);
			vec3 dpdy = dFdy(VERTEX);
			vec3 r1 = cross(dpdy, NORMAL);
			vec3 r2 = cross(NORMAL, dpdx);
			float det = dot(dpdx, r1);
			if (abs(det) > 1e-12) {
				NORMAL = normalize(abs(det) * NORMAL - sign(det) * (dhx * r1 + dhy * r2));
			}
		}
	}
	vec3 body = min(c.rgb * paint.rgb, vec3(1.0));
	ALBEDO = mix(c.rgb, body, painted);
	if (interior_paint.a > 0.0) {
		float cabin = pu_edge ? pu_alpha_share(albedo_tex, UV, 224.0 / 255.0)
				: 1.0 - smoothstep(0.012, 0.03, abs(textureLod(albedo_tex, UV, 0.0).a - 224.0 / 255.0));
		ALBEDO = mix(ALBEDO, min(c.rgb * interior_paint.rgb, vec3(1.0)), cabin);
	}
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
	// In the gap: no mirror finish, and the sky and the probe's light kept out.
	SPECULAR *= 1.0 - 0.8 * seam;
#ifndef LOW_QUALITY
	CLEARCOAT *= 1.0 - seam;
#endif
	AO = 1.0 - 0.7 * seam;
	AO_LIGHT_AFFECT = 0.4;
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
	if (COLOR.b < 0.5 && !wheel) {
		float env = COLOR.r;
		float unpainted = 1.0 - paint_area;
		// Chrome: a mirror of its surroundings, tinted by the skin's drawn highlights.
		// (Not the flat near-white round a badge, drawn to pass for the paint.)
		float flat_white = smoothstep(0.55, 0.75, luma) * (1.0 - smoothstep(0.03, 0.08, max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b)));
		float chrome = smoothstep(0.75, 0.95, env) * unpainted * (1.0 - flat_white);
		ALBEDO = mix(ALBEDO, clamp(c.rgb * 1.35 + 0.08, 0.0, 1.0), chrome);
		METALLIC = mix(METALLIC, 0.95, chrome);
		ROUGHNESS = mix(ROUGHNESS, 0.1, chrome);
		// Matte: rubber, black trim, wheel wells, the underside.
		float matte = 1.0 - smoothstep(0.1, 0.3, env);
		ROUGHNESS = mix(ROUGHNESS, max(ROUGHNESS, 0.62), matte * unpainted);
		SPECULAR *= mix(1.0, 0.55, matte * unpainted);
#ifndef LOW_QUALITY
		CLEARCOAT *= mix(1.0, 0.45, matte);
#endif
	}
	// A lamp's lens: clear, glossy glass over its reflector, lit with its lamp. Porsche
	// Unleashed's by their material (COLOR.g), the others' round their lamp dummies (COLOR
	// (0, 1, 1): Car._mark_lenses); unpainted texels only.
	float lens = (COLOR.b < 0.5 ? COLOR.g : step(0.5, COLOR.g) * (1.0 - step(0.5, COLOR.r))) * (1.0 - paint_area);
	if (lens > 0.0 && !wheel) {
		ROUGHNESS = mix(ROUGHNESS, 0.05, lens);
		SPECULAR = mix(SPECULAR, 0.75, lens);
		float sat = max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
		float red = smoothstep(0.12, 0.3, c.r - max(c.g, c.b) * 1.1) * (1.0 - smoothstep(0.35, 0.6, c.g));
		float amber = step(0.4, c.r) * smoothstep(0.18, 0.3, c.g) * (1.0 - smoothstep(0.7, 0.85, c.g / max(c.r, 0.01))) * (1.0 - smoothstep(0.25, 0.4, c.b / max(c.r, 0.01)));
		float clear = (1.0 - smoothstep(0.12, 0.25, sat)) * smoothstep(0.3, 0.65, luma);
		float front = step(0.0, model_pos.z);
		float ind = model_pos.x >= 0.0 ? indicator_left : indicator_right;
		vec3 glow = c.rgb * (front * clear * head_lit * 1.6
				+ (1.0 - front) * red * (tail_lit * 0.8 + brake_lit * 2.4)
				+ (1.0 - front) * clear * reverse_lit * 1.6
				+ amber * ind * 2.6);
		EMISSION = glow * lens;
	}
	if (interior) {
		ROUGHNESS = max(ROUGHNESS, 0.7);
		SPECULAR *= 0.25;
#ifndef LOW_QUALITY
		CLEARCOAT = 0.0;
#endif
	}
	// Specular antialiasing (Kaplanyan / Filament): where the normal turns a lot within a pixel
	// (tight curves of the low-poly body seen from afar, the grooves above), a sharp highlight
	// or mirrored edge only lands on some pixels and sparkles; widen the lobe to what the
	// pixel covers.
	vec3 dndx = dFdx(NORMAL);
	vec3 dndy = dFdy(NORMAL);
	float kernel = min(0.3 * (dot(dndx, dndx) + dot(dndy, dndy)), 0.2);
	float a = ROUGHNESS * ROUGHNESS;
	ROUGHNESS = sqrt(sqrt(a * a + kernel));
#ifndef LOW_QUALITY
	a = CLEARCOAT_ROUGHNESS * CLEARCOAT_ROUGHNESS;
	CLEARCOAT_ROUGHNESS = sqrt(sqrt(a * a + kernel));
#endif
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
