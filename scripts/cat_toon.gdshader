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
// Optional head-to-tail gradient applied to the tint. This is driven by the
// skinned vertex's local Y position, never by UV islands.
uniform float tint_gradient_enabled : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_gradient_top_color : source_color = vec4(1.0);
uniform vec4 tint_gradient_bottom_color : source_color = vec4(1.0);
uniform float tint_gradient_head_y = 1.0;
uniform float tint_gradient_tail_y = -1.0;
uniform int shadow_steps = 3;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.58;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.24;
uniform vec2 uv_tiling = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// Only UVs in the right-side tile region receive the V repeat transform.
// Material cat_tile also contains a small lower connection cap in the main
// cat UV area; keeping that cap untransformed prevents a repeated leg seam.
uniform float tile_uv_min_u : hint_range(0.0, 1.0) = 0.0;

varying float tint_gradient_vertex_y;

void vertex() {
	// VERTEX is evaluated after skinning, so the color field follows the
	// stretched body rather than repeating with each texture tile.
	tint_gradient_vertex_y = VERTEX.y;
}

void fragment() {
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
	// The denominator intentionally supports either bone-chain direction.
	// This also keeps feet and chest on their real position in the mesh even
	// when their UV islands occupy the same region of the texture.
	float axis_length = tint_gradient_tail_y - tint_gradient_head_y;
	float gradient_t = clamp(
		(tint_gradient_vertex_y - tint_gradient_head_y) / max(abs(axis_length), 0.0001)
		* sign(axis_length),
		0.0,
		1.0
	);
	gradient_t = gradient_t * gradient_t * (3.0 - 2.0 * gradient_t);
	vec3 gradient_tint = mix(tint_gradient_top_color.rgb, tint_gradient_bottom_color.rgb, gradient_t);
	vec3 tint_multiplier = tint_color.rgb * mix(vec3(1.0), gradient_tint, tint_gradient_enabled);
	vec3 base_color = tex.rgb * mix(tint_multiplier, vec3(1.0), eye_mask);
	vec4 line_art = texture(line_art_tex, mapped_uv);
	float line_alpha = line_art.a * line_art_enabled * line_art_strength;
	float line_art_eye_mask_value = texture(line_art_eye_mask, mapped_uv).r;
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
