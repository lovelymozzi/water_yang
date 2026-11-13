shader_type spatial;
// Keep the tree's lighting response aligned with the movable cats.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.9;
uniform int shadow_steps = 3;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.58;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.24;
uniform vec4 foliage_color : source_color = vec4(0.46, 0.65, 0.37, 1.0);
uniform vec4 trunk_color : source_color = vec4(0.52, 0.32, 0.20, 1.0);

void fragment() {
	vec3 tex = textureLod(albedo_tex, UV, 3.0).rgb;
	float foliage = smoothstep(-0.02, 0.045, tex.g - tex.r);
	float paint_band = mix(0.92, 1.0, smoothstep(0.28, 0.40, dot(tex, vec3(0.3, 0.6, 0.1))));
	ALBEDO = mix(trunk_color.rgb, foliage_color.rgb, foliage) * paint_band * tint_color.rgb;
	ROUGHNESS = max(roughness, 0.95);
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float steps = float(max(shadow_steps, 2));
	float received_light = clamp(ndotl * ATTENUATION, 0.0, 0.9999);
	float stepped = floor(received_light * steps) / (steps - 1.0);
	float light_band = mix(shadow_darkness, 1.0, stepped);

	float view_term = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = pow(view_term, 3.0) * min(rim_strength, 0.08);

	vec3 shadow_tint = mix(vec3(0.64, 0.80, 1.0), vec3(1.0), stepped);
	vec3 toon_diffuse = ALBEDO * LIGHT_COLOR.rgb * light_band * shadow_tint;
	vec3 toon_rim = ALBEDO * LIGHT_COLOR.rgb * rim * ATTENUATION;
	DIFFUSE_LIGHT += (toon_diffuse + toon_rim) / PI;
}
