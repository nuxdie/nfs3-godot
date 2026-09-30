shader_type spatial;
// High Stakes' car windows (the triangles its FCE4 flags as windows): the skin's dark
// glass texels, see-through so the driver and cockpit show behind them, turning to a
// mirror of the sky at grazing angles.
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float clarity = 0.5;   // how see-through the glass is face-on

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = c.rgb * 0.6;
	ALPHA = clamp(1.0 - clarity + fresnel * 0.5, 0.0, 0.95);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.9;
}
