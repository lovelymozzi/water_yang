shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec4 grid_color : source_color = vec4(0.42, 0.29, 0.12, 0.32);
uniform float grid_half_width : hint_range(0.0, 0.05, 0.001) = 0.006;

void fragment() {
	vec2 edge = min(UV, vec2(1.0) - UV);
	float distance_to_edge = min(edge.x, edge.y);
	float antialias = max(fwidth(distance_to_edge), 0.00001);
	float half_width = max(grid_half_width, antialias * 0.5);
	float line = 1.0 - smoothstep(half_width - antialias * 0.5, half_width + antialias * 0.5, distance_to_edge);
	ALBEDO = grid_color.rgb;
	ALPHA = grid_color.a * line;
}
