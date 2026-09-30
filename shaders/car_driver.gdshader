shader_type spatial;
// The people in the cars: High Stakes' driver (":OD") and Porsche Unleashed's driver and
// passenger. They share the car's skin, but car.gdshader would read their bright texels
// (a white suit, skin, a helmet) as chrome and lamps and gloss them, and clearcoat the
// rest. Here they are cloth and skin: matte, a faint sheen, shut in under the roof where
// neither the sky nor the reflection probe's open road reaches. Paint-alpha texels still
// take the paint (a helmet or suit in the car's colour), and `paint` keeps them in step
// with Car.set_paint.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 paint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
// The hands on the steering wheel (UV2.x) turn by `steer_angle` about the column through
// `steer_pivot`, mesh-local, as in car.gdshader.
uniform float steer_angle = 0.0;
uniform vec3 steer_pivot = vec3(0.0);
uniform vec3 steer_axis = vec3(0.0, 0.0, 1.0);

void vertex() {
	if (UV2.x > 0.5 && steer_angle != 0.0) {
		float c = cos(steer_angle);
		float s = sin(steer_angle);
		vec3 p = VERTEX - steer_pivot;
		VERTEX = steer_pivot + p * c + cross(steer_axis, p) * s + steer_axis * dot(steer_axis, p) * (1.0 - c);
		NORMAL = NORMAL * c + cross(steer_axis, NORMAL) * s + steer_axis * dot(steer_axis, NORMAL) * (1.0 - c);
	}
	// Porsche Unleashed's depth bias (UV2.y), as in car.gdshader: the interior's sits it a
	// little behind the glass and the panels it shows through.
	if (UV2.y != 0.0 && PROJECTION_MATRIX[3][3] == 0.0) {
		vec3 eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
		VERTEX += (eye - VERTEX) * UV2.y;
	}
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (textureLod(albedo_tex, UV, 0.0).a < 0.08) {
		discard;
	}
	float painted = 1.0 - smoothstep(0.7, 0.85, c.a);
	ALBEDO = mix(c.rgb, min(c.rgb * paint.rgb, vec3(1.0)), painted);
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	METALLIC = 0.0;
	if (!FRONT_FACING) {
		SPECULAR = 0.0;
	}
}
