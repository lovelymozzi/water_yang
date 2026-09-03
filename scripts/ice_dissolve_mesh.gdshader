shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float side_edge_size : hint_range(0.02, 0.35) = 0.18;
uniform float vertical_edge_size : hint_range(0.02, 0.55) = 0.24;
uniform float vertical_edge_curve : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float noise_scale : hint_range(0.1, 32.0, 0.05) = 0.35;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.55;
uniform float noise_speed : hint_range(0.0, 1.0) = 0.08;
uniform float vertex_offset : hint_range(0.0, 0.2) = 0.06;
// Distance between the two stylised rims.
uniform float edge_gap : hint_range(0.0, 0.35, 0.005) = 0.14;
uniform float cartoon_edge_sharpness : hint_range(1.0, 20.0, 0.5) = 12.0;
uniform bool hide_edges = false;
uniform sampler2D fractal_noise_texture : repeat_enable, filter_linear;
uniform float inner_frost_size : hint_range(0.12, 0.7, 0.01) = 0.32;
uniform vec4 outer_edge_color : source_color = vec4(0.12, 0.48, 1.0, 1.0);
uniform bool hide_outer_edge = false;
uniform vec4 inner_edge_color : source_color = vec4(0.24, 0.9, 1.0, 1.0);
uniform bool hide_inner_edge = false;
uniform vec4 frost_core_color : source_color = vec4(0.86, 0.98, 1.0, 1.0);
uniform vec4 deep_frost_color : source_color = vec4(0.015, 0.07, 0.16, 1.0);
uniform sampler2D overlay_texture : source_color, repeat_enable, filter_linear_mipmap;
uniform int texture_blend_mode : hint_enum("Overlay", "Multiply") = 0;
uniform float texture_opacity : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform vec2 texture_tiling = vec2(2.0);

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

float fractal_noise(vec2 uv) {
	float broad = texture(fractal_noise_texture, fract(uv)).r;
	float detail = texture(fractal_noise_texture, fract(uv * 2.73 + vec2(0.37, 0.71))).r;
	// The source is a seamless FastNoiseLite FBM texture.  A small second octave
	// keeps the silhouette crystalline without turning it into pixel noise.
	return broad * 0.78 + detail * 0.22;
}

vec3 overlay_blend(vec3 base, vec3 layer) {
	return mix(2.0 * base * layer, 1.0 - 2.0 * (1.0 - base) * (1.0 - layer), step(vec3(0.5), base));
}

void vertex() {
	float mesh_noise = seamless_noise(vec3(UV * noise_scale, TIME * noise_speed));
	VERTEX += NORMAL * vertex_offset * dissolve_amount * mix(0.45, 1.0, mesh_noise);
}

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	float side_distance = min(screen_uv.x, 1.0 - screen_uv.x);
	float vertical_distance = min(screen_uv.y, 1.0 - screen_uv.y);
	vec2 noise_uv = screen_uv * noise_scale + vec2(TIME * noise_speed, TIME * noise_speed * 0.63);
	float noise_value = mix(seamless_noise(vec3(noise_uv, TIME * noise_speed)), fractal_noise(noise_uv), 0.78);
	// Only a gentle displacement is used here: it reads as an uneven crystal
	// front while preserving a smooth, joined corner silhouette.
	float edge_noise = mix(1.0, mix(0.94, 1.06, noise_value), noise_strength);
	float side_progress = min(side_distance / max(dissolve_amount * side_edge_size * edge_noise, 0.0001), 2.0);
	float horizontal_from_center = abs(screen_uv.x * 2.0 - 1.0);
	float vertical_curve_depth = (1.0 - horizontal_from_center * horizontal_from_center)
		* dissolve_amount * vertical_edge_size * vertical_edge_curve;
	float vertical_progress = min((vertical_distance + vertical_curve_depth)
		/ max(dissolve_amount * vertical_edge_size * edge_noise, 0.0001), 2.0);
	float edge_progress = -log(exp(-8.0 * side_progress) + exp(-8.0 * vertical_progress)) / 8.0;
	// Port the reference dissolve's moving noise threshold onto the frost front,
	// so the already-existing edge texture appears in irregular glowing fragments.
	float dissolve_noise = mix(
		seamless_noise(vec3(noise_uv * 11.0, TIME * noise_speed)),
		fractal_noise(noise_uv * 11.0),
		0.78
	);
	edge_progress += (dissolve_noise - 0.5) * noise_strength * 0.36;
	float edge_softness = 0.12 / cartoon_edge_sharpness;
	float edge_visibility = hide_edges ? 0.0 : 1.0;
	float outer_visibility = hide_outer_edge ? 0.0 : edge_visibility;
	float inner_visibility = hide_inner_edge ? 0.0 : edge_visibility;
	float inner_edge = cartoon_band(edge_progress, 1.0 - edge_gap, 0.17, edge_softness);
	float outer_edge = cartoon_band(edge_progress, 1.0 + edge_gap, 0.14, edge_softness);
	float dissolve_glow = cartoon_band(edge_progress, 1.0, 0.22, edge_softness * 1.5)
		* mix(0.45, 1.0, dissolve_noise);
	float body = 1.0 - smoothstep(1.0 + edge_gap + 0.05, 1.0 + edge_gap + 0.15, edge_progress);
	float coverage = max(body, outer_edge);
	if (coverage < 0.01) {
		discard;
	}
	float boundary_distance = clamp(1.0 - edge_progress, 0.0, 1.0);
	float white_rim = 1.0 - smoothstep(0.0, 0.028, boundary_distance);
	float crystal_rim = smoothstep(0.0, 0.028, boundary_distance)
		* (1.0 - smoothstep(0.028, 0.10, boundary_distance));
	float frost_fill = smoothstep(0.075, inner_frost_size, boundary_distance);
	vec3 frost = mix(deep_frost_color.rgb, outer_edge_color.rgb * 0.42, frost_fill);
	frost = mix(frost, outer_edge_color.rgb, min(1.0, outer_edge * outer_visibility + inner_edge * 0.35 * inner_visibility));
	frost = mix(frost, inner_edge_color.rgb, min(1.0, crystal_rim + inner_edge * 0.65) * inner_visibility);
	frost = mix(frost, frost_core_color.rgb, white_rim * inner_visibility);
	vec4 overlay = texture(overlay_texture, screen_uv * texture_tiling);
	vec3 textured_frost = texture_blend_mode == 0 ? overlay_blend(frost, overlay.rgb) : frost * overlay.rgb;
	frost = mix(frost, textured_frost, texture_opacity * overlay.a);
	ALBEDO = frost;
	EMISSION = frost_core_color.rgb * white_rim * inner_visibility * 2.2
		+ inner_edge_color.rgb * min(1.0, crystal_rim + inner_edge * 0.65) * inner_visibility * 1.3
		+ outer_edge_color.rgb * (
			outer_edge * outer_visibility + frost_fill * 0.3 * edge_visibility + dissolve_glow * edge_visibility
		) * 0.5;
	ALPHA = coverage * mix(0.76, 0.92, noise_value);
}
