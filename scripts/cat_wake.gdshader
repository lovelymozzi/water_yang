shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 wake_color : source_color = vec4(0.56, 0.86, 0.89, 1.0);
uniform float leg_wave : hint_range(-1.0, 1.0, 0.01) = 0.0;

void fragment() {
	float tail = smoothstep(0.02, 0.15, UV.x) * (1.0 - smoothstep(0.62, 0.78, UV.x));
	float drift = leg_wave * 0.055 + sin(UV.x * 12.0 - TIME * 2.7) * 0.035;
	float half_width = mix(0.42, 0.13, UV.x);
	float distance_from_center = abs(UV.y - 0.5 + drift);
	float soft_body = 1.0 - smoothstep(half_width * 0.52, half_width, distance_from_center);
	float ripple = 0.45 + 0.55 * sin(UV.x * 18.0 - TIME * 3.8 + distance_from_center * 20.0 + leg_wave * 2.4);
	float wake = tail * soft_body * mix(0.32, 0.78, ripple);
	ALBEDO = wake_color.rgb;
	EMISSION = wake_color.rgb * wake * 0.08;
	ALPHA = wake * 0.32;
}
