shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D scene_depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

group_uniforms water_color_and_depth;
uniform vec4 shallow_color : source_color = vec4(0.12, 0.62, 0.82, 1.0);
uniform vec4 deep_color : source_color = vec4(0.035, 0.23, 0.46, 1.0);
uniform float opacity_multiplier : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float shallow_depth : hint_range(0.0, 5.0, 0.01) = 0.08;
uniform float deep_depth : hint_range(0.01, 20.0, 0.01) = 2.2;
uniform float depth_color_strength : hint_range(0.0, 1.0, 0.01) = 0.82;
uniform float shallow_opacity : hint_range(0.0, 1.0, 0.01) = 0.42;
uniform float deep_opacity : hint_range(0.0, 1.0, 0.01) = 0.96;
uniform float depth_opacity_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
group_uniforms;

group_uniforms waves;
uniform vec2 wave_direction_a = vec2(1.0, 0.18);
uniform float wave_scale_a : hint_range(1.0, 40.0, 0.1) = 11.0;
uniform float wave_speed_a : hint_range(0.0, 5.0, 0.01) = 0.7;
uniform float wave_strength_a : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform vec2 wave_direction_b = vec2(-0.28, 1.0);
uniform float wave_scale_b : hint_range(1.0, 40.0, 0.1) = 17.0;
uniform float wave_speed_b : hint_range(0.0, 5.0, 0.01) = 0.44;
uniform float wave_strength_b : hint_range(0.0, 1.0, 0.01) = 0.2;
uniform float wave_brightness : hint_range(0.0, 1.0, 0.01) = 0.16;
group_uniforms;

group_uniforms ripple_noise;
uniform vec2 noise_direction = vec2(0.72, -0.46);
uniform float noise_scale : hint_range(1.0, 80.0, 0.1) = 26.0;
uniform float noise_speed : hint_range(0.0, 8.0, 0.01) = 1.15;
uniform float noise_strength : hint_range(0.0, 1.0, 0.01) = 0.16;
group_uniforms;

group_uniforms gloss_and_sparkle;
uniform float gloss_strength : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float gloss_roughness : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform vec4 sparkle_color : source_color = vec4(0.72, 0.94, 1.0, 1.0);
uniform float sparkle_strength : hint_range(0.0, 1.0, 0.01) = 0.3;
uniform float sparkle_density : hint_range(1.0, 20.0, 0.1) = 5.2;
group_uniforms;

group_uniforms shore_foam;
uniform vec4 foam_color : source_color = vec4(0.88, 0.98, 1.0, 1.0);
uniform float shore_foam_width : hint_range(0.01, 5.0, 0.01) = 0.45;
uniform float shore_foam_softness : hint_range(0.01, 5.0, 0.01) = 0.28;
uniform float foam_strength : hint_range(0.0, 2.0, 0.01) = 0.9;
uniform float foam_speed : hint_range(0.0, 5.0, 0.01) = 0.8;
uniform float foam_breakup : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float foam_pattern_scale : hint_range(1.0, 40.0, 0.1) = 9.0;
group_uniforms;

varying vec3 water_world_position;

void vertex() {
	water_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float primary_wave = sin(dot(UV * wave_scale_a, wave_direction_a) + TIME * wave_speed_a) * wave_strength_a;
	float secondary_wave = sin(dot(UV * wave_scale_b, wave_direction_b) - TIME * wave_speed_b) * wave_strength_b;
	float noise_primary = sin(dot(UV * noise_scale, noise_direction) + TIME * noise_speed);
	float noise_secondary = sin(dot(UV * noise_scale * 1.73, vec2(-noise_direction.y, noise_direction.x)) - TIME * noise_speed * 0.63);
	float ripple_noise = (noise_primary * 0.62 + noise_secondary * 0.38) * noise_strength;
	float surface_wave = primary_wave + secondary_wave + ripple_noise;
	float sparkle_pattern = sin(UV.x * sparkle_density * 2.8 - TIME * wave_speed_a * 1.7) * sin(UV.y * sparkle_density * 3.6 + TIME * wave_speed_b);
	float sparkle = smoothstep(0.84, 0.98, sparkle_pattern * 0.5 + 0.5) * sparkle_strength;

	float raw_scene_depth = texture(scene_depth_texture, SCREEN_UV).r;
	vec3 scene_ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_scene_depth);
	vec4 scene_view_position = INV_PROJECTION_MATRIX * vec4(scene_ndc, 1.0);
	scene_view_position.xyz /= scene_view_position.w;
	float scene_depth = -scene_view_position.z;
	float water_depth = -(VIEW_MATRIX * vec4(water_world_position, 1.0)).z;
	float depth_gap = max(scene_depth - water_depth, 0.0);
	// Keep the visual color blend independent from visibility.  Reducing the
	// color effect must not make deep, submerged geometry visible again.
	float raw_depth_mix = smoothstep(shallow_depth, deep_depth, depth_gap);
	float depth_mix = raw_depth_mix * depth_color_strength;
	float depth_opacity = mix(shallow_opacity, deep_opacity, clamp(raw_depth_mix * depth_opacity_strength, 0.0, 1.0));
	float shore_foam = 1.0 - smoothstep(shore_foam_width, shore_foam_width + shore_foam_softness, depth_gap);
	float moving_foam = sin((UV.x - UV.y) * foam_pattern_scale + TIME * foam_speed) * 0.5 + 0.5;
	float foam_coverage = mix(1.0, smoothstep(0.28, 0.76, moving_foam), foam_breakup);
	float foam = shore_foam * foam_coverage * foam_strength;

	ALBEDO = mix(shallow_color.rgb, deep_color.rgb, clamp(depth_mix, 0.0, 1.0));
	ALBEDO = clamp(ALBEDO + vec3(surface_wave * wave_brightness), 0.0, 1.0);
	ALBEDO = mix(ALBEDO, foam_color.rgb, clamp(foam, 0.0, 1.0));
	EMISSION = sparkle_color.rgb * sparkle + foam_color.rgb * foam;
	METALLIC = 0.12;
	ROUGHNESS = gloss_roughness;
	SPECULAR = 0.9;
	RIM = gloss_strength;
	RIM_TINT = 0.55;
	ALPHA = max(depth_opacity * opacity_multiplier, clamp(foam, 0.0, 1.0));
}
