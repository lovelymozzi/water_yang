shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, fog_disabled;

uniform sampler2D illustration : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D shore_mask : filter_linear_mipmap, repeat_disable;
uniform vec4 water_color : source_color = vec4(0.03, 0.50, 0.56, 1.0);
uniform float illustration_strength : hint_range(0.0, 1.0, 0.01) = 0.48;
uniform vec2 illustration_scale = vec2(1.418, 0.42);
uniform vec2 illustration_offset = vec2(-0.209, 0.29);
uniform vec2 water_origin = vec2(-12.26392, -4.454312);
uniform vec2 water_size = vec2(24.58556, 10.92316);
uniform float refraction_strength : hint_range(0.0, 0.25, 0.005) = 0.16;
uniform float water_motion_time = 0.0;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 shore_uv = (world_position - water_origin) / water_size;
	float clearance = smoothstep(0.08, 0.85, texture(shore_mask, shore_uv).r);
	vec2 wave_position = world_position;
#include "res://scripts/lobby_water_motion.gdshaderinc"
	// Move the sample, not the painting plane or shoreline mask.
	vec2 refraction = water_gradient * refraction_strength * clearance / water_size * illustration_scale;
	vec3 painting = texture(illustration, UV * illustration_scale + illustration_offset + refraction).rgb;
	ALBEDO = mix(water_color.rgb, painting, clearance * illustration_strength);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
