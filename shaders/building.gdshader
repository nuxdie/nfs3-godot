shader_type spatial;
// The procedural track's building walls: the facade texture tinted by the instance colour,
// and at night a warm light in some of the windows. The texture's alpha marks the glass;
// each window (a `cells` share of a texture tile) is lit or not by a hash of where it is.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 cells = vec2(1.0);
uniform float lit_share = 0.45;
uniform float night = 0.0;
uniform vec3 lamp : source_color = vec3(1.0, 0.76, 0.42);

varying vec3 origin;

void vertex() {
	origin = MODEL_MATRIX[3].xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	// The instance colours are sRGB.
	ALBEDO = t.rgb * pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.8;
	float glass = 1.0 - t.a;
	float on = step(hash(floor(UV * cells) + floor(origin.xz * 0.5)), lit_share);
	EMISSION = lamp * glass * on * night * 1.8;
}
