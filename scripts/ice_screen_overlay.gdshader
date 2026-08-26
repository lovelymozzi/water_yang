shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float dissolve_value : hint_range(0.0, 1.0) = 0.0;
uniform float side_edge_size : hint_range(0.05, 0.4) = 0.22;
uniform float vertical_edge_size : hint_range(0.05, 0.4) = 0.22;
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
	float edge_noise = mix(1.0, mix(0.72, 1.22, frost_noise(UV * noise_scale)), noise_strength);
	float side_edge = dissolve_value * side_edge_size * edge_noise;
	float vertical_edge = dissolve_value * vertical_edge_size * edge_noise;
	float side_ice = 1.0 - smoothstep(side_edge, side_edge + 0.018, side_distance);
	float vertical_ice = 1.0 - smoothstep(vertical_edge, vertical_edge + 0.018, vertical_distance);
	float ice = max(side_ice, vertical_ice);
	float side_glow = 1.0 - smoothstep(0.0, 0.025, abs(side_distance - side_edge));
	float vertical_glow = 1.0 - smoothstep(0.0, 0.025, abs(vertical_distance - vertical_edge));
	float glow = max(side_glow, vertical_glow);
	vec3 color = mix(ice_color.rgb, glow_color.rgb, glow * 0.72);
	float alpha_noise = mix(0.5, frost_noise(UV * noise_scale * 2.55 + TIME * 0.08), noise_strength);
	COLOR = vec4(color, ice * (0.58 + alpha_noise * 0.34));
}
