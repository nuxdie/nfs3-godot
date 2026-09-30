shader_type spatial;
// NFS3 scenery carries pre-baked lighting in its vertex colours, so draw it
// unshaded: texture * vertex shade. One Texture2DArray per track; UV2.x picks the layer.
render_mode unshaded, cull_disabled, depth_draw_opaque, alpha_to_coverage_and_one;

uniform sampler2DArray textures : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// The same array without wrapping, for UVs inside the texture: filtering at a repeat-wrapped
// edge blends in the opposite edge, which bites a gap out of a tree's trunk where its
// half-tree blades meet (the trunk runs down the texture's edge).
uniform sampler2DArray textures_clamped : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float brightness = 1.35;
// Night: the baked shading is scaled by `night_tint`, and the nearest cars' headlights
// (set each frame by the race) add cones of light. Unshaded, so real lights can't do it.
const int MAX_BEAMS = 16;   // MAX_LIGHT_CONES in race.gd
uniform vec3 night_tint = vec3(1.0);
uniform int beam_count = 0;
uniform vec3 beam_pos[MAX_BEAMS];
uniform vec3 beam_dir[MAX_BEAMS];
uniform vec3 beam_shape[MAX_BEAMS];   // reach (m), cos(outer cone angle), strength
// Cars' drop shadows (NFS3's `shad` sprite: a soft-edged rounded rectangle), set each frame by
// the race from Car.shadow_footprint(). The unshaded track can't take real shadow maps.
const int MAX_SHADOWS = 16;   // MAX_SHADOWS in race.gd
uniform float shadow_strength = 0.6;
uniform int shadow_count = 0;
uniform vec3 shadow_pos[MAX_SHADOWS];
uniform vec3 shadow_x[MAX_SHADOWS];   // the car's right axis / half width
uniform vec3 shadow_z[MAX_SHADOWS];   // its forward axis / half length
// Wet road (vertex alpha 1 marks drivable road), set by Reflections: it darkens and takes a
// Fresnel sheen of the sky, or on High of `mirror_tex`, the scene drawn from under the road
// and flipped left-right; the nearest cars' lamps glint on it as long streaks.
const int MAX_LAMPS = 16;   // Reflections.MAX_LAMPS
uniform float wetness = 0.0;
uniform vec3 sky_horizon = vec3(0.5);
uniform vec3 sky_zenith = vec3(0.4);
uniform int lamp_count = 0;
uniform vec3 lamp_pos[MAX_LAMPS];
uniform vec3 lamp_dir[MAX_LAMPS];     // the way it shines; zero for all round (sirens)
uniform vec3 lamp_color[MAX_LAMPS];   // colour x strength
uniform bool has_mirror = false;
uniform sampler2D mirror_tex : source_color, filter_linear, repeat_disable;
// The mirror camera's own copy of this material: `mirror_pass` drops everything under the
// mirror plane (xyz normal, w = distance), which would otherwise hide the view from below.
uniform bool mirror_pass = false;
uniform vec4 mirror_plane = vec4(0.0, 1.0, 0.0, 0.0);
// RainCover's height map (as in precipitation.gdshader): the road under a roof stays dry.
uniform sampler2D cover : filter_nearest;
uniform bool has_cover = false;
uniform vec4 cover_rect;
uniform float cover_y_min;
uniform float cover_y_range;

varying flat float layer;
// 1 on a front/back quad pair sharing the same corners (road signs): cull the back face
// so the pair doesn't z-fight.
varying flat float one_sided;
varying vec3 world_pos;
varying vec3 world_normal;
// Rate of the game clock that animated textures (fire, water) step on (High Stakes: 64).
uniform float ticks_per_second = 60.0;

// UV2.y packs one_sided (bit 0), animation frame count (x2) and ticks per frame (x16).
float anim_layer(float base, float packed) {
	float frames = mod(floor(packed / 2.0), 8.0);
	float period = floor(packed / 16.0);
	if (frames < 2.0) {
		return base;
	}
	return base + mod(floor(TIME * ticks_per_second / period), frames);
}

void vertex() {
	// High Stakes' billboards (Nfs3TrackBuilder.BILLBOARD_XTYPE): CUSTOM0.y = 1, the vertex on
	// the upright axis and CUSTOM0.x its offset across; turned about the axis to face the camera.
	if (CUSTOM0.y > 0.5) {
		vec2 to_cam = CAMERA_POSITION_WORLD.xz - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
		vec2 dir = length(to_cam) > 0.001 ? normalize(to_cam) : vec2(0.0, 1.0);
		VERTEX.xz += vec2(dir.y, -dir.x) * CUSTOM0.x;
		NORMAL = vec3(dir.x, 0.0, dir.y);
	}
	// Porsche Unleashed's scrolling textures (water, waterfalls, conveyor treads): CUSTOM1.xy
	// is how far the UVs go a second.
	UV += fract(CUSTOM1.xy * TIME);
	layer = anim_layer(UV2.x, UV2.y);
	one_sided = mod(UV2.y, 2.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// 0 on merely damp tarmac - 1 in a puddle; the puddles spread as the road soaks.
float puddle(float wet) {
	float n = value_noise(world_pos.xz * 0.11) * 0.65 + value_noise(world_pos.xz * 0.47) * 0.35;
	return smoothstep(0.78 - 0.3 * wet, 0.9 - 0.3 * wet, n);
}

// How much of the light the cars' drop shadows leave here.
float car_shadows() {
	float lit = 1.0;
	for (int i = 0; i < shadow_count; i++) {
		vec3 d = world_pos - shadow_pos[i];
		vec3 x = shadow_x[i];
		vec3 z = shadow_z[i];
		// Height of this point below the car's tyres: the shadow fades and spreads as the car
		// leaves the ground, and never reaches a bridge deck far below or a roof above.
		float h = -dot(d, normalize(cross(z, x)));
		if (h < -0.6 || h > 4.0) {
			continue;
		}
		vec2 q = abs(vec2(dot(d, x), dot(d, z)));
		// Rounded-rectangle distance, in half-extents, with the corners of the sprite.
		const float R = 0.18;
		vec2 e = q - (1.0 - R);
		float sd = length(max(e, 0.0)) + min(max(e.x, e.y), 0.0) - R;
		float soft = 0.12 + 0.1 * max(h, 0.0);
		float a = clamp(0.5 - sd / soft, 0.0, 1.0);
		a *= 1.0 - smoothstep(0.3, 4.0, h);
		lit *= 1.0 - a * shadow_strength;
	}
	return lit;
}

// How wet the road is here: none off the road or under cover.
float wet_here(float road) {
	float wet = wetness * road;
	if (wet > 0.0 && has_cover) {
		vec2 uv = (world_pos.xz - cover_rect.xy) / cover_rect.zw;
		float h = textureLod(cover, uv, 0.0).r;
		if (h > 0.0 && world_pos.y < cover_y_min + h * cover_y_range - 1.0) {
			wet = 0.0;
		}
	}
	return wet;
}

// What the wet road mirrors toward the eye, and how strongly (Fresnel), from `screen_uv`.
vec4 wet_reflection(vec3 eye, vec2 screen_uv) {
	vec3 n = normalize(world_normal);
	n = n.y < 0.0 ? -n : n;
	vec3 v = normalize(eye - world_pos);
	vec3 r = reflect(-v, n);
	float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
	vec3 refl = mix(sky_horizon, sky_zenith, smoothstep(0.0, 0.6, r.y));
	if (has_mirror) {
		// A few taps down the screen: rain-pocked tarmac smears the image vertically. They
		// start at a random offset per pixel, or a bright lamp shows up as a row of dots.
		vec2 uv = vec2(1.0 - screen_uv.x, screen_uv.y);
		float jitter = hash(floor(screen_uv * 2048.0));
		vec3 m = vec3(0.0);
		for (int k = 0; k < 4; k++) {
			m += texture(mirror_tex, uv + vec2(0.0, (float(k) + jitter - 1.5) * 0.008)).rgb;
		}
		refl = m * 0.25;
	}
	// Streaks: a lamp glints where the mirror direction nearly meets it; the rough surface
	// spreads that far more in elevation than sideways, so the glint runs toward the eye.
	vec3 side = normalize(cross(r, n));
	vec3 up = cross(side, r);
	vec3 glint = vec3(0.0);
	for (int i = 0; i < lamp_count; i++) {
		vec3 to_l = lamp_pos[i] - world_pos;
		float dist = length(to_l);
		vec3 l = to_l / max(dist, 0.01);
		vec3 e = l - r;
		float eh = dot(e, side) / 0.03;
		float ev = dot(e, up) / 0.3;
		float g = exp(-eh * eh - ev * ev);
		vec3 d = lamp_dir[i];
		float face = dot(d, d) > 0.0 ? smoothstep(-0.2, 0.5, dot(d, -l)) : 1.0;
		glint += lamp_color[i] * g * face / (1.0 + dist * dist * 0.002);
	}
	return vec4(refl + glint / max(fres, 0.05) * 0.5, fres);
}

void fragment() {
	if (one_sided > 0.5 && !FRONT_FACING) {
		discard;
	}
	if (mirror_pass && dot(world_pos, mirror_plane.xyz) < mirror_plane.w + 0.3) {
		discard;
	}
	// Both sampled outside any branch so the mip derivatives stay valid.
	vec4 c_wrap = texture(textures, vec3(UV, layer));
	vec4 c_clamp = texture(textures_clamped, vec3(UV, layer));
	// Under MSAA a pixel only partly covered is still shaded at its centre, which can lie off
	// the quad: allow a pixel's worth of UV past the edge, or that pixel wraps round to the
	// see-through side (a dotted line of sky down the trunk where a tree's blades meet).
	vec2 px = fwidth(UV);
	bool inside = all(greaterThanEqual(UV, -px)) && all(lessThanEqual(UV, 1.0 + px));
	vec4 c = inside ? c_clamp : c_wrap;
	vec3 light = COLOR.rgb * brightness * night_tint * car_shadows();
	for (int i = 0; i < beam_count; i++) {
		vec3 d = world_pos - beam_pos[i];
		float dist = length(d);
		vec3 shape = beam_shape[i];
		float cone = smoothstep(shape.y, mix(shape.y, 1.0, 0.7), dot(d, beam_dir[i]) / max(dist, 0.01));
		float fall = clamp(1.0 - dist / shape.x, 0.0, 1.0);
		light += vec3(1.0, 0.95, 0.85) * cone * fall * fall * shape.z;
	}
	ALBEDO = c.rgb * light;
	float wet = mirror_pass ? 0.0 : wet_here(COLOR.a);
	if (wet > 0.001) {
		vec4 refl = wet_reflection(CAMERA_POSITION_WORLD, SCREEN_UV);
		// Soaked tarmac is darker, and mirrors more the flatter the view across it; the
		// puddles most of all.
		float p = puddle(wet);
		ALBEDO = mix(ALBEDO * (1.0 - (0.3 + 0.2 * p) * wet), refl.rgb, refl.a * wet * mix(0.3, 0.9, p));
	}
	// Alpha-tested foliage and fences, with alpha-to-coverage under MSAA so the cut-out
	// edges of the low-res textures aren't stair-stepped. That puts the scenery in the
	// transparent pass, which blends: `alpha_to_coverage_and_one` makes each covered sample
	// opaque, or a tree's soft rim, blended over the sky and then written to depth, would
	// hide a tree drawn behind it later and leave a pale outline.
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(textures, 0).xy);
}
