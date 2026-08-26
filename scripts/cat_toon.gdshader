shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear, repeat_enable;
// Optional hand-painted line layer. Transparent pixels preserve the base
// texture; opaque pixels become ink after tinting and toon lighting.
uniform sampler2D line_art_tex : source_color, filter_linear, repeat_enable, hint_default_white;
uniform float line_art_enabled : hint_range(0.0, 1.0) = 0.0;
// cat1_mask.jpg: black is unaffected, white is the eye region.
uniform sampler2D line_art_eye_mask : filter_linear, repeat_enable;
uniform float line_art_eyes_hidden : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_art_color : source_color = vec4(0.32, 0.24, 0.20, 1.0);
uniform float line_art_strength : hint_range(0.0, 1.0) = 0.82;
// White pixels preserve the original texture color; black pixels receive tint.
// This is data, not a color texture: 0 = full tint, 1 = no tint.
uniform sampler2D tint_exclusion_mask : filter_linear, repeat_enable;
uniform float tint_exclusion_enabled : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform int shadow_steps = 3;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.58;
// Moves the toon-band boundaries toward the light. A positive value gives the
// darker bands more surface area while retaining the selected number of steps.
uniform float toon_shadow_spread : hint_range(0.0, 0.5) = 0.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.24;
uniform vec4 ambient_color : source_color = vec4(1.0);
uniform float ambient_energy : hint_range(0.0, 2.0) = 0.0;
uniform vec2 uv_tiling = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// Only UVs in the right-side tile region receive the V repeat transform.
// Material cat_tile also contains a small lower connection cap in the main
// cat UV area; keeping that cap untransformed prevents a repeated leg seam.
uniform float tile_uv_min_u : hint_range(0.0, 1.0) = 0.0;
// 구멍으로 빨려 들어가는 동안, 바닥 면보다 아래로 내려간 부분을 지운다.
// 알파 블렌딩이 아니라 디더 discard 라서 평소 불투명 렌더 경로가 그대로 유지된다.
uniform float sink_clip_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float sink_clip_plane_y = 0.0;
uniform float sink_clip_span = 1.0;
// Lobby-only water motion. Gameplay cats retain the default zero amplitude.
uniform float water_wave_time = 0.0;
uniform float water_wave_phase = 0.0;
uniform float water_wave_amplitude : hint_range(0.0, 0.08, 0.001) = 0.0;
// 중첩고양이(3_기믹.md 2). 마스크의 흰 영역을 안쪽 고양이 색으로 덧칠한다.
uniform sampler2D nest_mask1 : filter_linear, repeat_enable, hint_default_black;
uniform sampler2D nest_mask2 : filter_linear, repeat_enable, hint_default_black;
uniform vec4 nest_color1 : source_color = vec4(1.0);
uniform vec4 nest_color2 : source_color = vec4(1.0);
uniform float nest1_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float nest2_enabled : hint_range(0.0, 1.0) = 0.0;
// color_mask1/2 텍스처가 아직 없을 때 쓰는 임시 사선 줄무늬. 텍스처가 오면 자동 대체.
uniform float nest_procedural : hint_range(0.0, 1.0) = 0.0;
// 안쪽 고양이의 얇은 상태(모델 단위). 겉껍질이 다 빠지면 0으로 원복한다.
uniform float body_shrink = 0.0;

void vertex() {
	VERTEX -= NORMAL * body_shrink;
	if (water_wave_amplitude > 0.0) {
		float wave = VERTEX.y * 3.2 + water_wave_time * 2.1 + water_wave_phase;
		VERTEX.z += sin(wave) * water_wave_amplitude;
		VERTEX.x += cos(wave) * water_wave_amplitude * 0.22;
	}
}

void fragment() {
	if (sink_clip_enabled > 0.5) {
		float world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		float sink = clamp((sink_clip_plane_y - world_y) / max(sink_clip_span, 0.0001), 0.0, 1.0);
		float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
		if (sink > dither) {
			discard;
		}
	}
	vec2 mapped_uv = UV;
	if (UV.x >= tile_uv_min_u) {
		mapped_uv = UV * uv_tiling + uv_offset;
	}
	vec4 tex = texture(albedo_tex, mapped_uv);
	// cat1_mask.jpg supports a grayscale tint exclusion amount:
	// black = full tint, white = no tint, gray = partial tint.
	float eye_mask = 0.0;
	if (tint_exclusion_enabled > 0.0) {
		eye_mask = texture(tint_exclusion_mask, mapped_uv).r;
	}
	vec3 base_color = tex.rgb * mix(tint_color.rgb, vec3(1.0), eye_mask);
	// 중첩 색은 눈 영역을 피해서 얹고, mask2 가 mask1 보다 우선한다.
	if (nest1_enabled > 0.5) {
		float m1 = nest_procedural > 0.5
			? step(0.62, fract((mapped_uv.x + mapped_uv.y) * 5.0))
			: texture(nest_mask1, mapped_uv).r;
		base_color = mix(base_color, tex.rgb * nest_color1.rgb, m1 * (1.0 - eye_mask));
	}
	if (nest2_enabled > 0.5) {
		float m2 = nest_procedural > 0.5
			? step(0.78, fract((mapped_uv.x + mapped_uv.y) * 5.0 + 0.45))
			: texture(nest_mask2, mapped_uv).r;
		base_color = mix(base_color, tex.rgb * nest_color2.rgb, m2 * (1.0 - eye_mask));
	}
	vec4 line_art = texture(line_art_tex, mapped_uv);
	float line_alpha = line_art.a * line_art_enabled * line_art_strength;
	// The eye outlines in Cat_Line extend past the white eye areas of
	// cat1_mask.jpg. Dilate the mask in both axes so all of the eye ink is
	// removed during a blink, while the separate nose/mouth line art remains.
	const float eye_mask_sample_step = 12.0 / 1024.0;
	float line_art_eye_mask_value = 0.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 eye_mask_offset = vec2(float(x), float(y)) * eye_mask_sample_step;
			line_art_eye_mask_value = max(
				line_art_eye_mask_value,
				texture(line_art_eye_mask, mapped_uv + eye_mask_offset).r
			);
		}
	}
	line_alpha *= 1.0 - (line_art_eyes_hidden * line_art_eye_mask_value);
	ALBEDO = mix(base_color, line_art_color.rgb, line_alpha);
	ROUGHNESS = 0.82;
	METALLIC = 0.0;
	// The editor preview makes rim highlights bloom through its HDR
	// environment. Emit the same rim in Play View so the runtime glow pass
	// can reproduce that soft silhouette instead of only brightening diffuse.
	float view_rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.5);
	EMISSION = tint_color.rgb * view_rim * rim_strength * 2.2;
	EMISSION += ambient_color.rgb * ambient_energy;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	// ATTENUATION contains the DirectionalLight shadow-map result. Quantize
	// the final light amount, not only the surface normal, so cast shadows
	// and the three toon bands remain part of one lighting model.
	float received_light = clamp(
		ndotl * clamp(ATTENUATION, 0.0, 1.0) - toon_shadow_spread,
		0.0,
		1.0
	);
	float steps = float(max(shadow_steps, 2));
	float stepped = min(floor(received_light * steps), steps - 1.0) / (steps - 1.0);
	float light_band = mix(shadow_darkness, 1.0, stepped);

	float view_term = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = pow(view_term, 2.5) * rim_strength;

	vec3 toon_diffuse = ALBEDO * LIGHT_COLOR.rgb * light_band;
	vec3 toon_rim = LIGHT_COLOR.rgb * rim * clamp(ATTENUATION, 0.0, 1.0);
	DIFFUSE_LIGHT += toon_diffuse + toon_rim;
}
