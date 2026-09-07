// Mesh-friendly dissolve study of https://www.shadertoy.com/view/XdVBW1.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// The applied mesh is intentionally texture-free: the colour comes solely
// from Shader Admin's user-controlled picker.
uniform vec4 dissolve_color : source_color = vec4(1.0);
uniform float edge_emission : hint_range(0.0, 8.0, 0.1) = 2.0;
uniform float dissolve_speed : hint_range(0.0, 3.0, 0.01) = 1.0;

float value_noise(vec2 point) {
	return fract(sin(point.x * 1234.0 + point.y * 2413.0) * 5647.0);
}

float smooth_noise(vec2 point) {
	vec2 local = fract(point);
	vec2 cell = floor(point);
	local = local * local * (3.0 - 2.0 * local);
	float bottom = mix(value_noise(cell), value_noise(cell + vec2(1.0, 0.0)), local.x);
	float top = mix(value_noise(cell + vec2(0.0, 1.0)), value_noise(cell + vec2(1.0)), local.x);
	return mix(bottom, top, local.y);
}

float fbm(vec2 point) {
	float value = 0.5 * smooth_noise(point);
	point *= 2.01;
	value += 0.25 * smooth_noise(point + vec2(0.0, 1.0));
	point *= 2.02;
	value += 0.125 * smooth_noise(point + vec2(1.0, 0.0));
	point *= 2.03;
	value += 0.0625 * smooth_noise(point + vec2(1.0));
	return value / 0.9375;
}

void fragment() {
	float threshold = 0.5 + 0.5 * sin(TIME * dissolve_speed);
	float dissolve_noise = fbm(UV * 10.0);
	if (dissolve_noise > threshold) {
		discard;
	}
	float edge = smoothstep(threshold - 0.1, threshold, dissolve_noise);
	ALBEDO = dissolve_color.rgb;
	EMISSION = dissolve_color.rgb * edge * edge_emission;
}
