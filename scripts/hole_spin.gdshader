shader_type spatial;
render_mode diffuse_burley, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float rotation_duration : hint_range(0.1, 60.0) = 4.0;

void fragment() {
	float angle = TAU * fract(TIME / rotation_duration);
	float cosine = cos(angle);
	float sine = sin(angle);
	vec2 centered_uv = UV - vec2(0.5);
	vec2 rotated_uv = vec2(
		centered_uv.x * cosine - centered_uv.y * sine,
		centered_uv.x * sine + centered_uv.y * cosine
	) + vec2(0.5);
	ALBEDO = texture(albedo_tex, rotated_uv).rgb;
	ROUGHNESS = 0.95;
}
