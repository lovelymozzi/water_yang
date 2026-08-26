shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float dissolve_value : hint_range(0.0, 1.0) = 0.0;
uniform float side_edge_size : hint_range(0.05, 0.4) = 0.22;
uniform float vertical_edge_size : hint_range(0.05, 0.65) = 0.22;
uniform float noise_scale : hint_range(1.0, 40.0) = 18.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ice_color : source_color = vec4(0.32, 0.78, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.9, 0.98, 1.0, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float frost_noise(vec2 p) {
	return noise(p) * 0.57 + noise(p * 2.13 + 7.0) * 0.28 + noise(p * 4.27 + 13.0) * 0.15;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float side_distance = min(UV.x * aspect, (1.0 - UV.x) * aspect);
	float vertical_distance = min(UV.y, 1.0 - UV.y);
	float noise_value = frost_noise(UV * noise_scale + vec2(0.0, TIME * 0.08));
	float edge_noise = mix(1.0, mix(0.88, 1.12, noise_value), noise_strength);
	float side_progress = min(side_distance / max(dissolve_value * side_edge_size * edge_noise, 0.0001), 2.0);
	float vertical_progress = min(vertical_distance / max(dissolve_value * vertical_edge_size * edge_noise, 0.0001), 2.0);
	float edge_progress = -log(exp(-8.0 * side_progress) + exp(-8.0 * vertical_progress)) / 8.0;
	float ice = 1.0 - smoothstep(0.92, 1.08, edge_progress);
	float glow = 1.0 - smoothstep(0.0, 0.12, abs(edge_progress - 1.0));
	vec3 color = mix(ice_color.rgb, glow_color.rgb, glow * 0.8);
	COLOR = vec4(color, ice * mix(0.75, 0.92, noise_value * noise_strength));
}
