shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

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
	float edge_width = max(fwidth(UV.y), 0.0001);
	float foam = 1.0 - smoothstep(foam_uv_half_width * 0.45, foam_uv_half_width + edge_width, shore_distance);
	float outer_distance = abs(UV.y - (foam_uv_center + 0.028 + wave * wave_amplitude * 1.5));
	float outer_foam = 1.0 - smoothstep(foam_uv_half_width * 0.2, foam_uv_half_width * 0.5 + edge_width, outer_distance);
	float breakup = smoothstep(-0.65, -0.05, sin(UV.x * 23.0 - TIME * 0.42));
	foam = max(foam * (0.45 + breakup * 0.55), outer_foam * breakup * 0.35);

	ALBEDO = foam_color.rgb;
	ALPHA = foam * 0.75;
}
