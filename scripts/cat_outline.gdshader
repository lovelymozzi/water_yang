shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.18, 0.09, 0.06, 1.0);
uniform float outline_width : hint_range(0.001, 0.04, 0.001) = 0.008;
// A completely uniform shell looks mechanical. Keep the upper silhouette
// lighter and let the lower/underside silhouette carry a little more ink.
uniform float top_outline_scale : hint_range(0.4, 1.2, 0.01) = 0.78;
uniform float bottom_outline_scale : hint_range(0.8, 1.6, 0.01) = 1.12;

void vertex() {
	float upward_facing = max(NORMAL.y, 0.0);
	float downward_facing = max(-NORMAL.y, 0.0);
	float line_weight = mix(1.0, top_outline_scale, upward_facing);
	line_weight = mix(line_weight, bottom_outline_scale, downward_facing);
	VERTEX += NORMAL * outline_width * line_weight;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
