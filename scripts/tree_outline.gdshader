shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.12, 0.18, 0.10, 1.0);
uniform float outline_width : hint_range(0.001, 0.12, 0.001) = 0.018;
uniform float grass_wind_strength = 0.0;
uniform float grass_wind_time = 0.0;
uniform bool grass_wind_use_engine_time = false;
uniform bool grass_shadow_enabled = false;
uniform sampler2D grass_shadow_texture : filter_linear, repeat_disable;
uniform mat4 grass_shadow_inverse;
uniform vec2 grass_shadow_size = vec2(1.0);
uniform vec4 grass_shadow_tint : source_color = vec4(1.0);

varying vec3 outline_world_position;

void vertex() {
	#include "res://scripts/lobby_grass_wind.gdshaderinc"
	VERTEX += NORMAL * outline_width;
	outline_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	if (grass_shadow_enabled) {
		vec3 shadow_local = (grass_shadow_inverse * vec4(outline_world_position, 1.0)).xyz;
		vec2 shadow_uv = shadow_local.xy / grass_shadow_size * vec2(1.0, -1.0) + vec2(0.5);
		float inside = step(0.0, shadow_uv.x) * step(shadow_uv.x, 1.0) * step(0.0, shadow_uv.y) * step(shadow_uv.y, 1.0);
		float shadow_alpha = texture(grass_shadow_texture, shadow_uv).a * inside * step(0.0, shadow_local.z);
		ALBEDO *= mix(vec3(1.0), grass_shadow_tint.rgb, shadow_alpha * grass_shadow_tint.a);
	}
}
