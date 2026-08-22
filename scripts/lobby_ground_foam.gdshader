shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, fog_disabled;

group_uniforms shoreline_foam;
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float foam_uv_center : hint_range(0.0, 1.0, 0.0001) = 0.080000;
uniform float foam_uv_half_width : hint_range(0.001, 0.1, 0.0001) = 0.011;
uniform float wave_amplitude : hint_range(0.0, 0.1, 0.0001) = 0.0045;
uniform float wave_scale_a : hint_range(1.0, 80.0, 0.1) = 11.0;
uniform float wave_speed_a : hint_range(0.0, 5.0, 0.01) = 0.7;
uniform float wave_scale_b : hint_range(1.0, 80.0, 0.1) = 17.0;
uniform float wave_speed_b : hint_range(0.0, 5.0, 0.01) = 0.44;
group_uniforms;

void fragment() {
	float wave = sin(UV.x * wave_scale_a + TIME * wave_speed_a) * 0.68;
	wave += sin(UV.x * wave_scale_b - TIME * wave_speed_b) * 0.32;
	float shore_distance = abs(UV.y - (foam_uv_center + wave * wave_amplitude));
	float foam = 1.0 - smoothstep(foam_uv_half_width * 0.45, foam_uv_half_width, shore_distance);
	if (foam < 0.16) {
		discard;
	}

	ALBEDO = foam_color.rgb;
	EMISSION = foam_color.rgb * 0.16;
}
