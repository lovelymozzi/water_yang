shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 albedo_uv_scale = vec2(5.0, 5.0);
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool grass_use_texture_color = false;
uniform vec4 grass_texture_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool grass_world_uv = false;
uniform bool cliff_surface = false;
uniform sampler2D cliff_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 underwater_color : source_color = vec4(0.03, 0.43, 0.49, 1.0);
uniform float cliff_water_fade_distance : hint_range(0.01, 2.0, 0.01) = 0.5;
uniform float underwater_fade_strength = 1.0;
// Lobby grass decorations use the lawn's lighting normal as well as its paint.
uniform bool ground_plane_normal = false;
uniform float grass_wind_strength = 0.0;
uniform float grass_wind_time = 0.0;
uniform bool grass_wind_use_engine_time = false;
uniform bool grass_shadow_enabled = false;
uniform sampler2D grass_shadow_texture : filter_linear, repeat_disable;
uniform mat4 grass_shadow_inverse;
uniform vec2 grass_shadow_size = vec2(1.0);
uniform vec4 grass_shadow_tint : source_color = vec4(1.0);

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
	#include "res://scripts/lobby_grass_wind.gdshaderinc"
	land_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (ground_plane_normal) {
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
	// The lawn and cliff lip share one world-space sample at their mesh seam.
	vec2 land_uv = (grass_world_uv ? land_world_position.xz : UV) * albedo_uv_scale;
	if (grass_use_texture_color) {
		land_uv = grass_texture_region.xy + fract(land_uv) * grass_texture_region.zw;
	}
	vec3 land_texture = textureLod(albedo_texture, land_uv, 3.0).rgb;
	float paint_band = mix(0.92, 1.0, smoothstep(0.4, 0.6, land_texture.g));
	vec3 land_color = albedo_tint.rgb * paint_band;
	if (grass_use_texture_color) {
		land_color = land_texture * albedo_tint.rgb;
	}
	float height_from_water = land_world_position.y - water_level;
	float water_depth = 1.0 - smoothstep(-deep_fade_distance, shoreline_fade_height, height_from_water);
	vec3 water_color = mix(shallow_water_color.rgb, deep_water_color.rgb, water_depth);

	ALBEDO = mix(land_color, water_color, water_depth * water_tint_strength);
	if (cliff_surface) {
		vec3 wall_color = texture(cliff_texture, UV).rgb;
		// Keep the source's irregular grass/soil edge, but replace its painted
		// green stripe with the exact same grass calculation as the lawn.
		float green_fraction = (wall_color.g - max(wall_color.r, wall_color.b)) / max(wall_color.g, 0.0001);
		float grass_mask = smoothstep(0.0, 0.15, green_fraction);
		// The actual shared mesh seam is UV.y=0.011737: use grass on both sides.
		grass_mask = max(grass_mask, 1.0 - smoothstep(0.012, 0.0192, UV.y));
		grass_mask *= 1.0 - smoothstep(0.04, 0.055, UV.y);
		// Submerged soil must follow the real water height, not the atlas UVs.
		float cliff_depth = smoothstep(0.0, cliff_water_fade_distance, water_level - land_world_position.y) * underwater_fade_strength;
		vec3 cliff_color = mix(wall_color, underwater_color.rgb, cliff_depth);
		ALBEDO = mix(cliff_color, ALBEDO, grass_mask);
	}
	if (grass_shadow_enabled) {
		vec3 shadow_local = (grass_shadow_inverse * vec4(land_world_position, 1.0)).xyz;
		vec2 shadow_uv = shadow_local.xy / grass_shadow_size * vec2(1.0, -1.0) + vec2(0.5);
		float inside = step(0.0, shadow_uv.x) * step(shadow_uv.x, 1.0) * step(0.0, shadow_uv.y) * step(shadow_uv.y, 1.0);
		// Below the sprite, its existing transparent pass already shades the grass.
		float shadow_alpha = texture(grass_shadow_texture, shadow_uv).a * inside * step(0.0, shadow_local.z);
		ALBEDO *= mix(vec3(1.0), grass_shadow_tint.rgb, shadow_alpha * grass_shadow_tint.a);
	}
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
