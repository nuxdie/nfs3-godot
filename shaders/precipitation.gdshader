shader_type spatial;
// Rain or snow around the camera, all on the GPU: every quad is one drop or flake whose
// position is its seed (the vertex position, 0-1 per axis) spread over a box, moved by
// its fall velocity and wrapped to stay in the box centred on the camera. Drops are
// stretched along their velocity relative to the camera, so they streak past at speed.
// The mesh sits at the world origin; VERTEX is written in world space.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D sprite : source_color, filter_linear;
uniform vec3 tint : source_color = vec3(0.8);
uniform float opacity = 0.5;
uniform float amount = 1.0;         // 0-1: the fraction of drops showing
uniform vec3 box = vec3(30.0, 18.0, 30.0);
// How far the box reaches below the camera. The chase camera is only a few metres up, so a
// box centred on it would put half its drops underground, where the cover hides them.
uniform float box_below = 5.0;
uniform vec3 cam_pos;
uniform vec3 cam_vel;
uniform float fall_speed = 9.0;     // m/s
uniform vec2 wind = vec2(0.0);      // m/s in x/z
uniform float wobble = 0.0;         // m: snowflakes drift from side to side
uniform float width = 0.02;         // m
uniform float min_length = 0.3;     // m
uniform float streak_time = 0.03;   // s of motion blur
// The height of the topmost surface over each point (RainCover): nothing falls below it,
// so bridges, tunnels and overhangs stay dry and nothing falls through the ground.
uniform sampler2D cover : filter_nearest;
uniform bool has_cover = false;
uniform vec4 cover_rect;            // x, z, width, depth
uniform float cover_y_min;
uniform float cover_y_range;

varying float fade;

void vertex() {
	vec3 seed = VERTEX;
	if (UV2.x > amount) {
		VERTEX = cam_pos + vec3(0.0, -1000.0, 0.0);   // collapsed: nothing to draw
		fade = 0.0;
	} else {
		vec3 vel = vec3(wind.x, -fall_speed * (0.8 + 0.4 * UV2.y), wind.y);
		vec3 origin = cam_pos - vec3(box.x * 0.5, box_below, box.z * 0.5);
		vec3 p = origin + mod(seed * box + vel * TIME - origin, box);
		p.xz += wobble * vec2(sin(TIME * 1.3 + seed.x * 40.0), cos(TIME * 1.1 + seed.z * 40.0));
		bool hidden = false;
		if (has_cover) {
			vec2 uv = (p.xz - cover_rect.xy) / cover_rect.zw;
			if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThan(uv, vec2(1.0)))) {
				float h = textureLod(cover, uv, 0.0).r;
				hidden = h > 0.0 && p.y < cover_y_min + h * cover_y_range - 0.1;
			}
		}
		vec3 rel = vel - cam_vel;
		float speed = length(rel);
		vec3 axis = speed > 0.01 ? rel / speed : vec3(0.0, -1.0, 0.0);
		vec3 to_cam = cam_pos - p;
		float dist = length(to_cam);
		vec3 side = cross(axis, to_cam / max(dist, 0.01));
		side = length(side) > 0.001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
		// At least about a pixel wide so distant drops don't shimmer in and out.
		float w = max(width, dist * 0.002);
		float len = max(speed * streak_time, min_length);
		VERTEX = hidden ? cam_pos + vec3(0.0, -1000.0, 0.0)
				: p + side * w * (UV.x - 0.5) + axis * len * (UV.y - 0.5);
		fade = smoothstep(0.6, 2.5, dist) * (1.0 - smoothstep(box.x * 0.3, box.x * 0.48, dist));
	}
}

void fragment() {
	vec4 s = texture(sprite, UV);
	ALBEDO = tint;
	ALPHA = dot(s.rgb, vec3(0.333)) * fade * opacity;
}
