shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

uniform vec4 light_color : source_color = vec4(1.0, 0.94, 0.76, 1.0);
uniform sampler2D ray_sheet : filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 0.8) = 0.42;
uniform vec2 direction = vec2(0.48, 1.0);
uniform float motion_speed : hint_range(0.0, 0.5) = 0.22;
uniform vec2 vertical_fade = vec2(0.22, 0.34);
uniform float sunlight_time = 0.0;
uniform bool dust_pass = false;
uniform float dust_strength : hint_range(0.0, 2.0) = 0.95;

void vertex() {
	// Camera-child quad: clip-space placement keeps the rays inside the lobby
	// viewport. Node3D visibility hides them immediately when the host swaps scenes.
	if (dust_pass) {
		POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	} else {
		POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	}
}

void fragment() {
	// Height units preserve the diagonal angle on narrow and wide viewports.
	vec2 point = SCREEN_UV * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0);
	vec2 axis = normalize(direction);
	vec2 from_source = point - vec2(-0.16, -0.24);
	float along = dot(from_source, axis);
	float across = dot(from_source, vec2(axis.y, -axis.x));
	float time = sunlight_time * motion_speed;
	// Keep the ray coordinates steady. Warping UVs along a shaft made sunlight
	// look like a bent ribbon. Only the source frames and light density evolve.
	float curtain_width = 0.78 + 0.08 * along;
	vec2 sheet_uv = vec2(0.5 + across / curtain_width, 0.08 + along / 1.55);
	float side_fade = smoothstep(0.0, 0.10, sheet_uv.x)
		* (1.0 - smoothstep(0.90, 1.0, sheet_uv.x));
	// The library supplies 16 images, with no known original FPS or loop mode.
	// Slow forward/reverse playback avoids assuming its last/first frames join.
	// Interpolating adjacent frames removes discrete sheet changes.
	float frame = 7.5 * (1.0 - cos(time * 0.85));
	float frame_a = floor(frame);
	float frame_b = min(frame_a + 1.0, 15.0);
	vec2 inside_cell = clamp(sheet_uv, vec2(0.5 / 128.0), vec2(127.5 / 128.0));
	vec2 uv_a = (vec2(mod(frame_a, 4.0), floor(frame_a / 4.0)) + inside_cell) / 4.0;
	vec2 uv_b = (vec2(mod(frame_b, 4.0), floor(frame_b / 4.0)) + inside_cell) / 4.0;
	float shafts = mix(texture(ray_sheet, uv_a).a, texture(ray_sheet, uv_b).a, fract(frame));
	// Broad, low-contrast transmission changes flow down the rays without
	// displacing their centerlines or switching whole shafts on and off.
	float transmission = 0.86
		+ 0.09 * sin(along * 4.8 - time * 0.8 + across * 6.0)
		+ 0.05 * sin(along * 8.0 - time * 0.55 - across * 11.0);
	// Lift the library's faint alpha shoulders into a broad, translucent veil.
	shafts = pow(max(shafts, 0.0), 0.70);
	float distance_fade = 1.0 - smoothstep(0.65, 1.60, along);
	// The upper grass projects to y=0.32–0.33 in the lobby camera.
	float bottom_fade = 1.0 - smoothstep(vertical_fade.x, vertical_fade.y, point.y);
	// Stylized light scattering overlay; no volumetric occlusion or scene relighting.
	ALBEDO = light_color.rgb;
	float illumination = transmission * side_fade * distance_fade * bottom_fade;
	if (dust_pass) {
		// Small soft motes share the exact animated beam mask and grass cutoff.
		// Particle color/size curves supply separate twinkles over each lifetime.
		vec2 mote_uv = (UV - vec2(0.5)) * 2.0;
		float radius_sq = dot(mote_uv, mote_uv);
		float mote = (exp(-18.0 * radius_sq) + 0.20 * exp(-4.0 * radius_sq))
			* (1.0 - smoothstep(0.65, 1.0, radius_sq));
		ALBEDO *= COLOR.rgb;
		ALPHA = clamp(mote * COLOR.a * smoothstep(0.02, 0.12, shafts)
			* illumination * smoothstep(0.0, 0.12, strength) * dust_strength, 0.0, 1.0);
	} else {
		ALPHA = clamp(shafts * illumination * strength, 0.0, 0.24);
	}
}
