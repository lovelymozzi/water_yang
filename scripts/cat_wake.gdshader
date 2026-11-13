shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 wake_color : source_color = vec4(0.88, 1.0, 0.96, 1.0);
uniform vec2 body_points[21];
uniform float body_scale = 9.0;
uniform float wave_time = 0.0;
uniform float water_y = 0.0;
varying vec2 water_position;

void vertex() {
	water_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float distance_to_body = 1000.0;
	float along_body = 0.0;
	for (int index = 0; index < 20; index++) {
		vec2 segment = body_points[index + 1] - body_points[index];
		float t = clamp(dot(water_position - body_points[index], segment) / max(dot(segment, segment), 0.0001), 0.0, 1.0);
		float along = (float(index) + t) / 20.0;
		float radius = mix(0.125, 0.095, smoothstep(0.0, 0.22, along)) * body_scale;
		float distance = length(water_position - mix(body_points[index], body_points[index + 1], t)) - radius;
		if (distance < distance_to_body) {
			distance_to_body = distance;
			along_body = along;
		}
	}

	// Two staggered ripples leave the moving body, spread, and fade away.
	float foam = 0.0;
	float edge_width = max(fwidth(distance_to_body), 0.012);
	for (int ring = 0; ring < 2; ring++) {
		float cycle = fract(wave_time / 6.283185 + float(ring) * 0.5);
		float wobble = sin(along_body * 17.0 - wave_time) * 0.045;
		float radius = 0.08 + cycle * 0.90 + wobble;
		float line = 1.0 - smoothstep(0.022, 0.022 + edge_width, abs(distance_to_body - radius));
		float breakup = smoothstep(-0.72, -0.10, sin(along_body * 23.0 + float(ring) * 2.3 - wave_time * 0.45));
		float fade = smoothstep(0.0, 0.14, cycle) * pow(1.0 - cycle, 1.4);
		foam = max(foam, line * breakup * fade);
	}
	float edge_fade = smoothstep(0.0, 0.08, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	ALBEDO = wake_color.rgb;
	ALPHA = foam * edge_fade * 0.68;
}
