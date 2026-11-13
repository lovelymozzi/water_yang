shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 wake_color : source_color = vec4(0.56, 0.86, 0.89, 1.0);
uniform float leg_wave : hint_range(-1.0, 1.0, 0.01) = 0.0;
uniform vec4 contact_color : source_color = vec4(0.10, 0.30, 0.38, 1.0);

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	centered.y += sin(UV.x * 8.0 - TIME * 1.1) * 0.035 + leg_wave * 0.02;
	float ellipse = length(centered / vec2(0.94, 0.70));
	float contact = (1.0 - smoothstep(0.35, 0.93, ellipse)) * 0.25;
	float line = 1.0 - smoothstep(0.012, 0.04, abs(ellipse - 0.94));
	float outer_line = 1.0 - smoothstep(0.008, 0.025, abs(ellipse - 1.14));
	float breakup = smoothstep(-0.6, 0.0, sin(UV.x * 17.0 - TIME * 0.65));
	float foam = max(line, outer_line * breakup * 0.45);
	ALBEDO = mix(contact_color.rgb, wake_color.rgb, foam);
	ALPHA = max(contact, foam * 0.65);
}
