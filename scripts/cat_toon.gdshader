shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// White pixels preserve the original texture color; black pixels receive tint.
// This is data, not a color texture: 0 = full tint, 1 = no tint.
uniform sampler2D tint_exclusion_mask : filter_linear_mipmap, repeat_enable;
uniform float tint_exclusion_enabled : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform int shadow_steps = 3;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.58;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.24;
uniform vec2 uv_tiling = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// Only UVs in the right-side tile region receive the V repeat transform.
// Material cat_tile also contains a small lower connection cap in the main
// cat UV area; keeping that cap untransformed prevents a repeated leg seam.
uniform float tile_uv_min_u : hint_range(0.0, 1.0) = 0.0;

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
	ALBEDO = tex.rgb * mix(tint_color.rgb, vec3(1.0), eye_mask);
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
