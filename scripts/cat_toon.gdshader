shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// Optional hand-painted line layer. Transparent pixels preserve the base
// texture; opaque pixels become ink after tinting and toon lighting.
uniform sampler2D line_art_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float line_art_enabled : hint_range(0.0, 1.0) = 0.0;
// cat1_mask.jpg: black is unaffected, white is the eye region.
uniform sampler2D line_art_eye_mask : filter_linear_mipmap, repeat_enable;
uniform float line_art_eyes_hidden : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_art_color : source_color = vec4(0.32, 0.24, 0.20, 1.0);
uniform float line_art_strength : hint_range(0.0, 1.0) = 0.82;
// White pixels preserve the original texture color; black pixels receive tint.
// This is data, not a color texture: 0 = full tint, 1 = no tint.
uniform sampler2D tint_exclusion_mask : filter_linear_mipmap, repeat_enable;
uniform float tint_exclusion_enabled : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0);
// Optional head-to-tail gradient applied to the tint.  It is evaluated from
// the live body polyline, rather than a skinned local axis or UVs.  A local
// axis collapses for the portion of the body that turns 90 degrees.
uniform float tint_gradient_enabled : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_gradient_top_color : source_color = vec4(1.0);
uniform vec4 tint_gradient_bottom_color : source_color = vec4(1.0);
const int TINT_GRADIENT_MAX_POINTS = 20;
uniform vec3 tint_gradient_points[TINT_GRADIENT_MAX_POINTS];
uniform int tint_gradient_point_count = 0;
uniform float tint_gradient_path_length = 1.0;
uniform int shadow_steps = 3;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.58;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.24;
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

varying float tint_gradient_path_t;

void vertex() {
	// VERTEX is evaluated after skinning.  Project it on the same world-space
	// polyline used to pose the bones, so the field remains continuous through
	// turns as well as through a stretched middle section.
	vec3 world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float nearest_distance_squared = 1e20;
	float nearest_arc = 0.0;
	float arc_start = 0.0;
	for (int index = 0; index < TINT_GRADIENT_MAX_POINTS - 1; index++) {
		if (index >= tint_gradient_point_count - 1) {
			break;
		}
		vec3 a = tint_gradient_points[index];
		vec3 segment = tint_gradient_points[index + 1] - a;
		float segment_length = length(segment);
		if (segment_length > 0.0001) {
			float segment_t = clamp(dot(world_vertex - a, segment) / (segment_length * segment_length), 0.0, 1.0);
			vec3 closest = a + segment * segment_t;
			float distance_squared = dot(world_vertex - closest, world_vertex - closest);
			if (distance_squared < nearest_distance_squared) {
				nearest_distance_squared = distance_squared;
				nearest_arc = arc_start + segment_length * segment_t;
			}
			arc_start += segment_length;
		}
	}
	tint_gradient_path_t = nearest_arc / max(tint_gradient_path_length, 0.0001);
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
	float gradient_t = clamp(tint_gradient_path_t, 0.0, 1.0);
	gradient_t = gradient_t * gradient_t * (3.0 - 2.0 * gradient_t);
	vec3 gradient_tint = mix(tint_gradient_top_color.rgb, tint_gradient_bottom_color.rgb, gradient_t);
	vec3 tint_multiplier = tint_color.rgb * mix(vec3(1.0), gradient_tint, tint_gradient_enabled);
	vec3 base_color = tex.rgb * mix(tint_multiplier, vec3(1.0), eye_mask);
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
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float stepped = floor(ndotl * float(max(shadow_steps, 1))) / float(max(shadow_steps, 1));
	float light_band = mix(shadow_darkness, 1.0, stepped);

	float view_term = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = pow(view_term, 2.5) * rim_strength;

	vec3 toon_diffuse = ALBEDO * LIGHT_COLOR.rgb * light_band * ATTENUATION;
	vec3 toon_rim = LIGHT_COLOR.rgb * rim * ATTENUATION;
	DIFFUSE_LIGHT += toon_diffuse + toon_rim;
}
