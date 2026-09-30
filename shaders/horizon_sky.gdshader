shader_type sky;
// NFS3 horizon: a Gouraud-shaded cylinder around the track. The sky runs from a base
// colour at the horizon (warmer toward the sun) up to `sky_top`; below the horizon the
// earth band runs from `earth_top` down to `earth_base`. On top of that go the sun (or
// moon), a cloud layer and the horizon panorama. Heights are given as the sine
// of their elevation seen from the car.

uniform vec3 sky_top : source_color;
uniform vec3 sky_sun : source_color;
uniform vec3 sky_away : source_color;
uniform vec3 earth_top : source_color;
uniform vec3 earth_base : source_color;
uniform vec3 sun_dir = vec3(0.0, 0.5, 0.86);  // toward the sun sprite
uniform float horizon = 0.0;
uniform float top = 0.3;
uniform float bottom = -0.4;
uniform float energy = 1.0;

uniform sampler2D sun_tex : source_color, filter_linear;
uniform bool has_sun = false;
uniform float sun_size = 0.1;   // half-width of the sprite (radians)

uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
uniform int cloud_type = 0;     // 0 none, 1 additive, 2 blended
uniform float cloud_bright = 0.5;
uniform float cloud_variance = 0.4;
uniform vec3 tint = vec3(1.0);  // the track's ambient light: dims clouds and panorama at night

uniform sampler2D panorama : source_color, filter_linear, repeat_enable;
uniform bool has_panorama = false;
uniform bool mirror = false;
uniform bool flip = false;  // the track's mirrored layout: the panorama the other way round
uniform float pano_rotation = 0.0;  // radians
uniform float pano_top = 0.14;
uniform float pano_bottom = -0.1;
uniform vec3 fog_color : source_color;
uniform float pano_fog = 0.0;

void sky() {
	vec3 d = EYEDIR;
	vec2 flat_dir = normalize(d.xz + vec2(1e-5));
	float toward = dot(flat_dir, normalize(sun_dir.xz + vec2(1e-5))) * 0.5 + 0.5;
	vec3 base = mix(sky_away, sky_sun, toward);
	vec3 c;
	if (d.y >= horizon) {
		c = mix(base, sky_top, smoothstep(horizon, top, d.y));
	} else {
		c = mix(earth_top, earth_base, smoothstep(horizon, bottom, d.y));
	}

	if (has_sun && dot(d, sun_dir) > 0.0) {
		vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), sun_dir));
		vec3 up = cross(sun_dir, right);
		vec2 uv = vec2(dot(d, right), -dot(d, up)) / (2.0 * sun_size) + 0.5;
		if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
			vec4 s = texture(sun_tex, uv);
			c = mix(c, s.rgb, s.a);
		}
	}

	if (cloud_type > 0 && d.y > horizon) {
		// A flat cloud layer overhead, thinning out toward the horizon.
		// Static: animating it would re-render the sky's radiance map every frame.
		vec2 uv = d.xz / (d.y + 0.15) * 0.6;
		float t = texture(cloud_tex, uv).r;
		float fade = smoothstep(horizon, horizon + 0.25, d.y);
		vec3 cloud = vec3(pow(cloud_bright - cloud_variance * (1.0 - t), 2.2)) * tint;
		if (cloud_type == 1) {
			c += cloud * t * fade;
		} else {
			c = mix(c, cloud, t * fade);
		}
	}

	if (has_panorama && d.y <= pano_top && d.y >= pano_bottom) {
		// Turning right moves right across the image; the track is mirrored in X, so
		// this keeps the panorama the right way round.
		float u = fract((atan(flip ? -d.x : d.x, -d.z) + pano_rotation) / TAU);
		if (mirror) {
			u = 1.0 - abs(u * 2.0 - 1.0);
		}
		float v = (pano_top - d.y) / (pano_top - pano_bottom);
		vec4 p = texture(panorama, vec2(u, v));
		vec3 pc = mix(p.rgb * tint, fog_color, pano_fog);
		c = mix(c, pc, p.a);
	}
	COLOR = c * energy;
}
