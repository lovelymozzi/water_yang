shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
// Optional hand-painted line layer. Transparent pixels preserve the base
// texture; opaque pixels become ink after tinting and toon lighting.
uniform sampler2D line_art_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float line_art_enabled : hint_range(0.0, 1.0) = 0.0;
// White pixels preserve the original texture color; black pixels receive tint.
// This is data, not a color texture: 0 = full tint, 1 = no tint.
uniform sampler2D tint_exclusion_mask : filter_linear_mipmap, repeat_enable;
uniform float tint_exclusion_enabled : hint_range(0.0, 1.0) = 0.0;
// Kept for parity with the cat shader so this file can be edited in the same
// way inside Godot even when the obstacle does not use blinking eyes.
uniform sampler2D line_art_eye_mask : filter_linear_mipmap, repeat_enable;
uniform float line_art_eyes_hidden : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_art_color : source_color = vec4(0.32, 0.24, 0.20, 1.0);
uniform float line_art_strength : hint_range(0.0, 1.0) = 0.82;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform int shadow_steps = 3;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.58;
uniform float shadow_receive_strength : hint_range(0.5, 4.0) = 1.0;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.24;
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
	vec3 base_color = tex.rgb * mix(tint_color.rgb, vec3(1.0), exclusion);
	// Obstacles expose the same line-art uniforms as the cat so the inspector
	// layout stays familiar, but the visible surrounding line is drawn by the
	// outline next pass rather than tinting this base surface.
	ALBEDO = base_color;
	ROUGHNESS = 0.82;
	METALLIC = 0.0;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float stepped = floor(ndotl * float(max(shadow_steps, 1))) / float(max(shadow_steps, 1));
	float light_band = mix(shadow_darkness, 1.0, stepped);
	float shadow_attenuation = pow(clamp(ATTENUATION, 0.0, 1.0), max(shadow_receive_strength, 0.001));

	float view_term = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = pow(view_term, 2.5) * rim_strength;

	vec3 toon_diffuse = ALBEDO * LIGHT_COLOR.rgb * light_band * shadow_attenuation;
	vec3 toon_rim = LIGHT_COLOR.rgb * rim * shadow_attenuation;
	DIFFUSE_LIGHT += toon_diffuse + toon_rim;
}
