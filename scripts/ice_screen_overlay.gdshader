shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float dissolve_value : hint_range(0.0, 1.0) = 0.0;
uniform float edge_size : hint_range(0.05, 0.4) = 0.22;
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
	float distance_to_edge = min(min(UV.x * aspect, (1.0 - UV.x) * aspect), min(UV.y, 1.0 - UV.y));
	float noisy_edge = dissolve_value * edge_size * mix(0.72, 1.22, frost_noise(UV * 18.0));
	float ice = 1.0 - smoothstep(noisy_edge, noisy_edge + 0.018, distance_to_edge);
	float glow = 1.0 - smoothstep(0.0, 0.025, abs(distance_to_edge - noisy_edge));
	vec3 color = mix(ice_color.rgb, glow_color.rgb, glow * 0.72);
	COLOR = vec4(color, ice * (0.58 + frost_noise(UV * 46.0 + TIME * 0.08) * 0.34));
}
