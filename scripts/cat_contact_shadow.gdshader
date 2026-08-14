shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform vec4 shadow_color : source_color = vec4(0.10, 0.06, 0.03, 0.82);
uniform float edge_softness : hint_range(0.01, 0.6) = 0.36;
uniform float width_boost : hint_range(0.5, 2.0) = 1.42;
uniform float end_taper : hint_range(0.2, 1.4) = 0.82;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float taper = mix(1.22, end_taper, smoothstep(0.0, 1.0, abs(uv.y)));
	float ellipse = length(vec2(uv.x / (width_boost * taper), uv.y / 1.08));
	float rim = 1.0 - smoothstep(1.0 - edge_softness, 1.0, ellipse);
	float core = 1.0 - smoothstep(0.0, 0.92, ellipse);
	ALBEDO = shadow_color.rgb;
	ALPHA = shadow_color.a * rim * mix(0.72, 1.0, core);
}
