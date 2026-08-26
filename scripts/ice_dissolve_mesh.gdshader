shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float side_edge_size : hint_range(0.02, 0.35) = 0.18;
uniform float vertical_edge_size : hint_range(0.02, 0.55) = 0.24;
uniform float noise_scale : hint_range(1.0, 32.0, 1.0) = 8.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.55;
uniform float noise_speed : hint_range(0.0, 1.0) = 0.08;
uniform float vertex_offset : hint_range(0.0, 0.2) = 0.06;
uniform float edge_gap : hint_range(0.0, 0.35, 0.005) = 0.14;
uniform float cartoon_edge_sharpness : hint_range(1.0, 20.0, 0.5) = 12.0;
uniform vec4 outer_edge_color : source_color = vec4(0.12, 0.48, 1.0, 1.0);
uniform vec4 inner_edge_color : source_color = vec4(1.0, 0.88, 0.52, 1.0);

vec3 hash33(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6))
	);
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453);
}

float perlin3(vec3 p) {
	vec3 cell = floor(p);
	vec3 local = fract(p);
	vec3 blend = local * local * (3.0 - 2.0 * local);
	vec3 c000 = mod(cell, 8.0);
	vec3 c100 = mod(cell + vec3(1.0, 0.0, 0.0), 8.0);
	vec3 c010 = mod(cell + vec3(0.0, 1.0, 0.0), 8.0);
	vec3 c110 = mod(cell + vec3(1.0, 1.0, 0.0), 8.0);
	vec3 c001 = mod(cell + vec3(0.0, 0.0, 1.0), 8.0);
	vec3 c101 = mod(cell + vec3(1.0, 0.0, 1.0), 8.0);
	vec3 c011 = mod(cell + vec3(0.0, 1.0, 1.0), 8.0);
	vec3 c111 = mod(cell + vec3(1.0), 8.0);
	float x00 = mix(dot(hash33(c000), local), dot(hash33(c100), local - vec3(1.0, 0.0, 0.0)), blend.x);
	float x10 = mix(dot(hash33(c010), local - vec3(0.0, 1.0, 0.0)), dot(hash33(c110), local - vec3(1.0, 1.0, 0.0)), blend.x);
	float x01 = mix(dot(hash33(c001), local - vec3(0.0, 0.0, 1.0)), dot(hash33(c101), local - vec3(1.0, 0.0, 1.0)), blend.x);
	float x11 = mix(dot(hash33(c011), local - vec3(0.0, 1.0, 1.0)), dot(hash33(c111), local - vec3(1.0)), blend.x);
	return mix(mix(x00, x10, blend.y), mix(x01, x11, blend.y), blend.z) * 0.5 + 0.5;
}

float seamless_noise(vec3 p) {
	float value = perlin3(p) * 0.57;
	value += perlin3(p * 2.0 + vec3(3.1, 1.7, 5.3)) * 0.29;
	value += perlin3(p * 4.0 + vec3(6.7, 4.9, 2.3)) * 0.14;
	return clamp(value, 0.0, 1.0);
}

float cartoon_band(float value, float center, float width, float softness) {
	float half_width = width * 0.5;
	return smoothstep(center - half_width - softness, center - half_width + softness, value)
		* (1.0 - smoothstep(center + half_width - softness, center + half_width + softness, value));
}

void vertex() {
	float mesh_noise = seamless_noise(vec3(UV * noise_scale, TIME * noise_speed));
	VERTEX += NORMAL * vertex_offset * dissolve_amount * mix(0.45, 1.0, mesh_noise);
}

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	float side_distance = min(screen_uv.x, 1.0 - screen_uv.x);
	float vertical_distance = min(screen_uv.y, 1.0 - screen_uv.y);
	float noise_value = seamless_noise(vec3(screen_uv * noise_scale, TIME * noise_speed));
	float edge_noise = mix(1.0, mix(0.88, 1.12, noise_value), noise_strength);
	float side_progress = min(side_distance / max(dissolve_amount * side_edge_size * edge_noise, 0.0001), 2.0);
	float vertical_progress = min(vertical_distance / max(dissolve_amount * vertical_edge_size * edge_noise, 0.0001), 2.0);
	float edge_progress = -log(exp(-8.0 * side_progress) + exp(-8.0 * vertical_progress)) / 8.0;
	float edge_softness = 0.12 / cartoon_edge_sharpness;
	float inner_edge = cartoon_band(edge_progress, 1.0 - edge_gap, 0.17, edge_softness);
	float outer_edge = cartoon_band(edge_progress, 1.0 + edge_gap, 0.14, edge_softness);
	float body = 1.0 - smoothstep(1.0 + edge_gap + 0.05, 1.0 + edge_gap + 0.15, edge_progress);
	float coverage = max(body, outer_edge);
	if (coverage < 0.01) {
		discard;
	}
	vec3 outer = outer_edge_color.rgb * (0.45 + outer_edge * 0.8);
	vec3 inner = inner_edge_color.rgb * inner_edge * 2.8;
	ALBEDO = mix(outer_edge_color.rgb * 0.38, outer, outer_edge) + inner * 0.18;
	EMISSION = outer + inner;
	ALPHA = coverage * mix(0.42, 0.88, noise_value);
}
