shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

uniform sampler2D snow_texture : source_color, filter_linear_mipmap;
uniform vec4 snow_color : source_color = vec4(0.7, 0.92, 1.0, 1.0);
uniform float rotation_speed : hint_range(0.1, 12.0, 0.1) = 2.5;
uniform float flicker_speed : hint_range(0.1, 12.0, 0.1) = 6.0;

varying float particle_phase;

void vertex() {
	// INSTANCE_CUSTOM.y is each particle's 0..1 lifetime phase.  Rotating the
	// mesh (instead of only its symmetric snowflake UV) keeps the motion visible.
	particle_phase = INSTANCE_CUSTOM.y;
	float angle = TIME * rotation_speed + particle_phase * TAU;
	mat2 rotation = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));
	VERTEX.xy = rotation * VERTEX.xy;
}

void fragment() {
	vec4 snow = texture(snow_texture, UV);
	float flicker = 0.08 + 0.92 * (0.5 + 0.5 * sin(TIME * flicker_speed + particle_phase * TAU));
	ALBEDO = snow.rgb * snow_color.rgb * COLOR.rgb;
	EMISSION = snow.rgb * snow_color.rgb * COLOR.rgb * 1.35;
	ALPHA = snow.a * snow_color.a * COLOR.a * flicker;
}
