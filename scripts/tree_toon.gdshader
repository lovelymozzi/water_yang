shader_type spatial;
// Keep the tree's lighting response aligned with the movable cats.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.9;
uniform int shadow_steps = 3;
uniform float shadow_darkness : hint_range(0.0, 1.0) = 0.58;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.24;

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * tint_color.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float steps = float(max(shadow_steps, 1));
	float stepped = floor(ndotl * steps) / steps;
	float light_band = mix(shadow_darkness, 1.0, stepped);

	float view_term = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = pow(view_term, 2.5) * rim_strength;

	vec3 toon_diffuse = ALBEDO * LIGHT_COLOR.rgb * light_band * ATTENUATION;
	vec3 toon_rim = LIGHT_COLOR.rgb * rim * ATTENUATION;
	DIFFUSE_LIGHT += toon_diffuse + toon_rim;
}
