shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

// ObstacleDecor shares this interface with the normal obstacle shader so an
// ice block can be placed through the same grid and preview path.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D line_art_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float line_art_enabled : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D tint_exclusion_mask : filter_linear_mipmap, repeat_enable;
uniform float tint_exclusion_enabled : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D line_art_eye_mask : filter_linear_mipmap, repeat_enable;
uniform float line_art_eyes_hidden : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_art_color : source_color = vec4(0.12, 0.36, 0.52, 1.0);
uniform float line_art_strength : hint_range(0.0, 1.0) = 0.82;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform int shadow_steps = 3;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.42;
uniform float shadow_receive_strength : hint_range(0.5, 4.0) = 1.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.42;
uniform vec4 specular_color : source_color = vec4(1.0);
uniform vec2 uv_tiling = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float tile_uv_min_u : hint_range(0.0, 1.0) = 0.0;
uniform float sink_clip_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float sink_clip_plane_y = 0.0;
uniform float sink_clip_span = 1.0;

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
	float exclusion = 0.0;
	if (tint_exclusion_enabled > 0.0) {
		exclusion = texture(tint_exclusion_mask, mapped_uv).r;
	}

	vec3 ice_color = tex.rgb * mix(tint_color.rgb, vec3(1.0), exclusion);
	float facing = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float fresnel = pow(facing, 3.0);
	float crystal_glint = pow(max(sin((mapped_uv.x + mapped_uv.y) * 30.0), 0.0), 12.0);
	ALBEDO = ice_color;
	ALPHA = tex.a * tint_color.a * opacity;
	ROUGHNESS = mix(0.24, 0.06, fresnel);
	METALLIC = 0.0;
	EMISSION = ice_color * (0.055 + fresnel * 0.12 + crystal_glint * 0.08);
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float stepped = floor(ndotl * float(max(shadow_steps, 1))) / float(max(shadow_steps, 1));
	float light_band = mix(shadow_darkness, 1.0, stepped);
	float shadow_attenuation = pow(clamp(ATTENUATION, 0.0, 1.0), max(shadow_receive_strength, 0.001));
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.5) * rim_strength;
	vec3 half_vector = normalize(LIGHT + VIEW);
	float sparkle = pow(max(dot(NORMAL, half_vector), 0.0), 48.0);

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR.rgb * light_band * shadow_attenuation;
	SPECULAR_LIGHT += specular_color.rgb * LIGHT_COLOR.rgb * (sparkle * 0.72 + rim * 0.28) * shadow_attenuation;
}
