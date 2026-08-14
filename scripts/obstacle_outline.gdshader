shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 outline_color : source_color = vec4(0.18, 0.09, 0.06, 1.0);
uniform float outline_width : hint_range(0.001, 0.04, 0.001) = 0.008;
uniform float line_art_enabled : hint_range(0.0, 1.0) = 1.0;
uniform vec4 line_art_color : source_color = vec4(0.32, 0.24, 0.20, 1.0);
uniform float line_art_strength : hint_range(0.0, 1.0) = 0.82;
// A completely uniform shell looks mechanical. Keep the upper silhouette
// lighter and let the lower/underside silhouette carry a little more ink.
uniform float top_outline_scale : hint_range(0.4, 1.2, 0.01) = 0.78;
uniform float bottom_outline_scale : hint_range(0.8, 1.6, 0.01) = 1.12;
uniform float sink_clip_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float sink_clip_plane_y = 0.0;
uniform float sink_clip_span = 1.0;

void vertex() {
	float enabled = step(0.5, line_art_enabled);
	float strength = clamp(line_art_strength, 0.0, 1.0);
	float width_strength = pow(strength, 1.8);
	float upward_facing = max(NORMAL.y, 0.0);
	float downward_facing = max(-NORMAL.y, 0.0);
	float line_weight = mix(1.0, top_outline_scale, upward_facing);
	line_weight = mix(line_weight, bottom_outline_scale, downward_facing);
	float art_width = outline_width * mix(0.015, 1.25, width_strength);
	VERTEX += NORMAL * art_width * line_weight * enabled;
}

void fragment() {
	float enabled = step(0.5, line_art_enabled);
	float strength = clamp(line_art_strength, 0.0, 1.0);
	if (enabled < 0.5 || strength <= 0.001) {
		discard;
	}
	if (sink_clip_enabled > 0.5) {
		float world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		float sink = clamp((sink_clip_plane_y - world_y) / max(sink_clip_span, 0.0001), 0.0, 1.0);
		float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
		if (sink > dither) {
			discard;
		}
	}
	ALBEDO = line_art_color.rgb * mix(0.45, 1.0, strength);
}
