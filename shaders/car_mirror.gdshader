shader_type spatial;
// An in-car side mirror's glass (CarMirrors): the view from the driver's eye reflected in
// its plane, projected onto it. `mirror_mvp` takes the glass's own vertices to that view's
// clip space; interpolated in the car's space and divided here, it's exact across the glass.
render_mode unshaded, cull_disabled, fog_disabled;

uniform sampler2D mirror_tex : source_color, filter_linear, repeat_disable;
uniform mat4 mirror_mvp;
uniform vec3 tint = vec3(0.82, 0.84, 0.86);

varying vec3 mirror_clip;

void vertex() {
	vec4 c = mirror_mvp * vec4(VERTEX, 1.0);
	mirror_clip = c.xyw;
}

void fragment() {
	vec2 uv = mirror_clip.xy / mirror_clip.z * 0.5 + 0.5;
	ALBEDO = texture(mirror_tex, vec2(uv.x, 1.0 - uv.y)).rgb * tint;
}
