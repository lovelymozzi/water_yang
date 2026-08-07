shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.18, 0.09, 0.06, 1.0);
uniform float outline_width : hint_range(0.001, 0.04, 0.001) = 0.008;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
