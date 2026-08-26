shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 edge_distance = min(UV, vec2(1.0) - UV);
	float nearest_edge = min(edge_distance.x, edge_distance.y);
	float edge = 1.0 - smoothstep(0.0, 0.12, nearest_edge);
	COLOR = vec4(1.0, 0.04, 0.04, edge * strength * 0.72);
}
