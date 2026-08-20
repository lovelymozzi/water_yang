shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 albedo_uv_scale = vec2(5.0, 5.0);

group_uniforms water_depth;
uniform float water_level = 0.0;
uniform float shoreline_fade_height : hint_range(0.0, 5.0, 0.01) = 0.55;
uniform float deep_fade_distance : hint_range(0.01, 10.0, 0.01) = 2.6;
uniform float water_tint_strength : hint_range(0.0, 1.0, 0.01) = 0.78;
uniform vec4 shallow_water_color : source_color = vec4(0.12, 0.62, 0.82, 1.0);
uniform vec4 deep_water_color : source_color = vec4(0.035, 0.23, 0.46, 1.0);
group_uniforms;

varying vec3 land_world_position;

void vertex() {
	land_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 land_color = texture(albedo_texture, UV * albedo_uv_scale).rgb;
	float height_from_water = land_world_position.y - water_level;
	float water_depth = 1.0 - smoothstep(-deep_fade_distance, shoreline_fade_height, height_from_water);
	vec3 water_color = mix(shallow_water_color.rgb, deep_water_color.rgb, water_depth);

	ALBEDO = mix(land_color, water_color, water_depth * water_tint_strength);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.72, 0.34, water_depth);
	SPECULAR = mix(0.35, 0.72, water_depth);
}
