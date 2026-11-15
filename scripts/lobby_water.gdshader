shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_toon, specular_disabled, fog_disabled;

uniform sampler2D wave_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 shallow_color : source_color = vec4(0.09, 0.70, 0.67, 1.0);
uniform vec4 deep_color : source_color = vec4(0.0, 0.46, 0.55, 1.0);
uniform vec4 ripple_color : source_color = vec4(0.58, 1.0, 0.88, 1.0);
uniform float surface_opacity : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float reflection_opacity : hint_range(0.0, 1.0, 0.01) = 0.98;
uniform float wave_scale : hint_range(0.01, 0.3, 0.005) = 0.024;
uniform float wave_speed : hint_range(0.0, 0.1, 0.001) = 0.009;
uniform float sparkle_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float sparkle_density : hint_range(0.1, 2.0, 0.05) = 0.85;
uniform float undulation_strength : hint_range(0.0, 0.25, 0.005) = 0.16;
uniform float water_motion_time = 0.0;
uniform float foam_reference_width = 2.26;
uniform vec2 shore_foam_width = vec2(0.035, 0.22);
uniform float shore_foam_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
// Linear distance to the actual terrain/water intersection, encoded / 2m.
uniform sampler2D shore_distance_map : filter_linear, repeat_disable;
uniform vec2 water_origin = vec2(-12.26392, -4.454312);
uniform vec2 water_size = vec2(24.58556, 10.92316);

varying vec3 water_world_position;

void vertex() {
	water_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wave_position = water_world_position.xz;
#include "res://scripts/lobby_water_motion.gdshaderinc"
	vec2 flow_uv = water_world_position.xz * wave_scale * vec2(0.75, 1.6);
	vec2 drift = vec2(TIME * wave_speed, -TIME * wave_speed * 0.37);
	float warp = texture(wave_noise, flow_uv * 0.61 - drift * 0.4).r;
	vec2 warped_uv = flow_uv + vec2((warp - 0.5) * 0.22, sin(warp * 6.283) * 0.04);
	float field = texture(wave_noise, warped_uv + drift).r;
	float crossing_field = texture(wave_noise, warped_uv * 1.23 - drift * 0.55 + vec2(0.36, 0.71)).r;
	field = mix(field, crossing_field, 0.25);

	float pale_patch = smoothstep(0.30, 0.72, field);
	vec3 surface_color = mix(deep_color.rgb, shallow_color.rgb, pale_patch);

	// Sparse, filled brush marks replace the fine noise contour network.
	vec2 stroke_position = mat2(vec2(0.78, -0.63), vec2(0.63, 0.78)) * water_world_position.xz;
	vec2 sparkle_uv = stroke_position / foam_reference_width * sparkle_density * vec2(0.75, 1.5) + vec2(-TIME * 0.08, TIME * 0.025);
	vec2 cell = floor(sparkle_uv);
	float seed = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	vec2 center = vec2(0.36 + seed * 0.28, 0.36 + fract(seed * 7.13) * 0.28);
	vec2 local = fract(sparkle_uv) - center;
	vec2 stroke_size = vec2(0.07 + fract(seed * 7.13) * 0.09, 0.026 + fract(seed * 13.7) * 0.035);
	vec2 brush = local / stroke_size;
	brush.y += sin(brush.x * 2.8 + seed * 17.0 + TIME * 2.0) * 0.22;
	brush.x += sin(brush.y * 2.3 + seed * 11.0) * 0.06;
	float brush_angle = atan(brush.y, brush.x);
	float brush_edge = length(brush) + sin(brush_angle * 3.0 + seed * 21.0 + TIME * 1.8) * 0.10 + sin(brush_angle * 5.0 - TIME * 2.1) * 0.06;
	float edge_width = max(fwidth(brush_edge), 0.025);
	float glint = 1.0 - smoothstep(0.88 - edge_width, 0.98 + edge_width, brush_edge);
	float reflection = glint * step(0.65, seed) * sparkle_strength;
	vec2 shore_uv = (water_world_position.xz - water_origin) / water_size;
	float shore_distance = texture(shore_distance_map, shore_uv).r * 2.0;
	vec2 shore_flow = water_world_position.xz / foam_reference_width * 0.14 - vec2(TIME * 0.055, 0.0);
	float shore_noise = texture(wave_noise, shore_flow).r;
	float shore_width = mix(shore_foam_width.x, shore_foam_width.y, smoothstep(0.20, 0.82, shore_noise));
	float shore_edge = max(fwidth(shore_distance), 0.012);
	float contact_foam = 1.0 - smoothstep(shore_width - shore_edge, shore_width + shore_edge, shore_distance);
	// Broad, soft slope highlights travel over the same waves that refract
	// the bottom. These are ambient waves, independent of a cat's movement.
	float slope_light = dot(water_gradient, vec2(0.8, 0.6));
	float soft_crest = 1.0 - smoothstep(0.025, 0.18, abs(slope_light - 0.26));
	float rolling_light = (soft_crest * 0.70 + smoothstep(0.1, 0.85, water_height) * 0.30)
		* undulation_strength * smoothstep(0.04, 0.35, shore_distance);
	// Shore contact only: no wall-generated outward travelling wave fronts.
	reflection = max(reflection, contact_foam * shore_foam_strength);
	ALBEDO = surface_color * (1.0 - reflection);
	EMISSION = ripple_color.rgb * reflection + mix(shallow_color.rgb, ripple_color.rgb, 0.6) * rolling_light;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = mix(surface_opacity + rolling_light * 0.65, reflection_opacity, reflection);
}
