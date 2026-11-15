shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 wake_color : source_color = vec4(0.60, 0.96, 0.83, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.01, 0.22, 0.25, 1.0);
uniform float shadow_opacity = 0.36;
uniform vec2 shadow_offset = vec2(-0.10, 0.30);
uniform vec2 shadow_points[128];
uniform int shadow_point_count = 0;
#include "res://scripts/lobby_foam_mapping.gdshaderinc"
uniform float water_y = 0.0;
uniform sampler2D shore_distance_map : filter_linear, repeat_disable;
uniform vec2 water_origin;
uniform vec2 water_size;
uniform vec2 flow_origin = vec2(0.0);
uniform float side_ripple_strength : hint_range(0.0, 1.0, 0.05) = 1.0;
varying vec2 water_position;

void vertex() {
	water_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = (water_position - water_origin) / water_size;
	float shore_distance = texture(shore_distance_map, uv).r * 2.0;
	float water_mask = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	if (COLOR.b < 0.5) {
		// Geometry carries the evolving crest and its local material thickness.
		// No reference sprite or elapsed-time texture animation is involved.
		float edge = abs(UV.y * 2.0 - 1.0);
		float aa = max(fwidth(edge), 0.015);
		float foam_alpha = (1.0 - smoothstep(0.64 - aa, 1.0, edge)) * COLOR.a;
		// Material filaments carry longitudinal UVs; closed body-contact bands
		// keep UV.x=0.5. Fade filament tips instead of exposing a squared cut.
		foam_alpha *= smoothstep(0.0, 0.06, UV.x) * (1.0 - smoothstep(0.94, 1.0, UV.x));
		if (COLOR.r > 0.5) {
			// Body-local longitudinal phase: both flanks travel towards the
			// stern. No perimeter rotation, timer births or opacity cycling.
			vec2 heading = -flow_velocity / max(length(flow_velocity), 0.001);
			vec2 across = vec2(-heading.y, heading.x);
			vec2 local = (water_position - flow_origin) / body_width;
			float along = (dot(local, heading) + flow_distance / body_width * 1.35);
			float lateral = dot(local, across);
			float phase = along * 14.0 + lateral * 3.1;
			float crest = 0.56 + sin(phase + sin(along * 5.3 + lateral * 7.0) * 0.48) * 0.12;
			float band_width = 0.15 + sin(along * 9.7 - lateral * 3.7) * 0.035;
			float band_aa = max(fwidth(UV.y - crest), 0.02);
			float band = 1.0 - smoothstep(band_width - band_aa, band_width + band_aa, abs(UV.y - crest));
			float shoulder = (1.0 - smoothstep(0.05, 0.85, UV.y)) * 0.18;
			float envelope = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.88, 1.0, UV.y));
			foam_alpha = (band * 0.65 + shoulder) * envelope * COLOR.a * side_ripple_strength;
		}
		ALBEDO = wake_color.rgb;
		ALPHA = foam_alpha * smoothstep(0.05, 0.24, shore_distance) * water_mask;
	} else {
		vec2 shadow_position = water_position - shadow_offset * body_width;
		float shadow_distance = 1000.0;
		bool inside_shadow = false;
		for (int index = 0; index < 128; index++) {
			if (index >= shadow_point_count) { break; }
			vec2 a = shadow_points[index];
			vec2 b = shadow_points[(index + 1) % shadow_point_count];
			vec2 segment = b - a;
			float t = clamp(dot(shadow_position - a, segment) / max(dot(segment, segment), 0.000001), 0.0, 1.0);
			shadow_distance = min(shadow_distance, length(shadow_position - (a + segment * t)));
			if ((a.y > shadow_position.y) != (b.y > shadow_position.y)) {
				float crossing = a.x + (shadow_position.y - a.y) * segment.x / segment.y;
				if (shadow_position.x < crossing) { inside_shadow = !inside_shadow; }
			}
		}
		shadow_distance *= inside_shadow ? -1.0 : 1.0;
		float aa = max(fwidth(shadow_distance), body_width * 0.002);
		float shadow_alpha = (1.0 - smoothstep(-aa, body_width * 0.055 + aa, shadow_distance)) * shadow_opacity;
		ALBEDO = shadow_color.rgb;
		ALPHA = shadow_alpha * water_mask;
	}
}
