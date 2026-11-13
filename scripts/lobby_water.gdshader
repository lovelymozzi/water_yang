shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// Illustration colors stay stable in both the editor and WebGL. The same
// seamless field drives broad color patches and narrow flowing contours.
uniform sampler2D wave_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 shallow_color : source_color = vec4(0.35, 0.76, 0.78, 1.0);
uniform vec4 deep_color : source_color = vec4(0.16, 0.60, 0.67, 1.0);
uniform vec4 ripple_color : source_color = vec4(0.78, 0.96, 0.92, 1.0);
uniform float wave_scale : hint_range(0.01, 0.3, 0.005) = 0.024;
uniform float wave_speed : hint_range(0.0, 0.1, 0.001) = 0.012;
uniform float ripple_strength : hint_range(0.0, 1.0, 0.01) = 0.38;
uniform float ripple_width : hint_range(0.001, 0.03, 0.001) = 0.003;
uniform float sparkle_strength : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform float sparkle_density : hint_range(0.1, 2.0, 0.05) = 0.65;

varying vec3 water_world_position;

void vertex() {
	water_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 flow_uv = water_world_position.xz * wave_scale * vec2(0.75, 1.6);
	vec2 drift = vec2(TIME * wave_speed, -TIME * wave_speed * 0.37);
	float warp = texture(wave_noise, flow_uv * 0.61 - drift * 0.4).r;
	vec2 warped_uv = flow_uv + vec2((warp - 0.5) * 0.22, sin(warp * 6.283) * 0.04);
	float field = texture(wave_noise, warped_uv + drift).r;
	float crossing_field = texture(wave_noise, warped_uv * 1.23 - drift * 0.55 + vec2(0.36, 0.71)).r;
	field = mix(field, crossing_field, 0.25);

	float pale_patch = smoothstep(0.30, 0.72, field);
	vec3 surface_color = mix(deep_color.rgb, shallow_color.rgb, pale_patch);
	float contour = abs(field - (0.5 + sin(TIME * 0.12) * 0.015));
	float edge_width = max(fwidth(field) * 0.65, 0.0005);
	float ripple = 1.0 - smoothstep(ripple_width, ripple_width + edge_width, contour);
	float secondary_contour = abs(field - 0.55);
	float secondary_ripple = 1.0 - smoothstep(ripple_width * 0.5, ripple_width * 0.5 + edge_width, secondary_contour);
	surface_color = mix(surface_color, ripple_color.rgb, max(ripple, secondary_ripple * 0.28) * ripple_strength);

	vec2 sparkle_uv = water_world_position.xz * sparkle_density;
	vec2 cell = floor(sparkle_uv);
	float seed = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	vec2 center = vec2(0.22 + seed * 0.56, 0.25 + fract(seed * 7.13) * 0.50);
	vec2 local = fract(sparkle_uv) - center;
	float glint = 1.0 - smoothstep(0.3, 1.0, length(local / vec2(0.09, 0.035)));
	float twinkle = pow(max(sin(TIME * 1.25 + seed * 31.4), 0.0), 6.0);
	float sparkle = glint * twinkle * step(0.72, seed) * sparkle_strength;
	ALBEDO = mix(surface_color, vec3(0.96, 1.0, 0.97), sparkle);
}
