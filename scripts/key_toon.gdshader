shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Key counterpart to cat_toon.gdshader. Use the cat's painted albedo as the
// source texture, then keep an optional tint multiplier for direct tuning.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform int shadow_steps = 4;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.38;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.42;

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	ROUGHNESS = 0.82;
	METALLIC = 0.0;
	float view_rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.5);
	EMISSION = albedo_color.rgb * view_rim * rim_strength * 2.2;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float received_light = ndotl * clamp(ATTENUATION, 0.0, 1.0);
	float steps = float(max(shadow_steps, 2));
	float stepped = min(floor(received_light * steps), steps - 1.0) / (steps - 1.0);
	float light_band = mix(shadow_darkness, 1.0, stepped);

	float view_term = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = pow(view_term, 2.5) * rim_strength;

	vec3 toon_diffuse = ALBEDO * LIGHT_COLOR.rgb * light_band;
	vec3 toon_rim = LIGHT_COLOR.rgb * rim * clamp(ATTENUATION, 0.0, 1.0);
	DIFFUSE_LIGHT += toon_diffuse + toon_rim;
}
