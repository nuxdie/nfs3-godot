shader_type spatial;
// Rendered once, straight down with an orthographic camera: every pixel keeps the height of
// the topmost surface over it (the depth test does the picking), scaled to 0-1 over the
// track's height range. Rain and snow don't fall below it, and the road under it stays dry.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform float y_min = 0.0;
uniform float y_range = 1.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	ALBEDO = vec3(clamp((world_y - y_min) / y_range, 0.0, 1.0));
}
