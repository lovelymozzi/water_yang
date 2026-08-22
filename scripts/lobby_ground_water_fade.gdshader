shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;

group_uniforms underwater_fade;
uniform vec4 underwater_color : source_color = vec4(0.10, 0.65, 0.78, 1.0);
uniform float underwater_fade_start : hint_range(0.0, 1.0, 0.0001) = 0.110;
uniform float underwater_fade_end : hint_range(0.0, 1.0, 0.0001) = 0.280073;
uniform float underwater_fade_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
group_uniforms;

void fragment() {
	vec3 wall_color = texture(albedo_texture, UV).rgb;
	float underwater_fade = smoothstep(underwater_fade_start, underwater_fade_end, UV.y);
	underwater_fade *= underwater_fade_strength;
	float dissolve = smoothstep(0.55, 1.0, underwater_fade);
	float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	if (dither < dissolve) {
		discard;
	}

	ALBEDO = mix(wall_color, underwater_color.rgb, underwater_fade);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.72, 0.34, underwater_fade);
	SPECULAR = mix(0.35, 0.72, underwater_fade);
}
