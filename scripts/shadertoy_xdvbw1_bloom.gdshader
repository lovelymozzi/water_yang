// Godot port of the Shadertoy Image pass's 21 × 21 bloom kernel.
shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec3 color = texture(TEXTURE, UV).rgb;
	for (int x_offset = -10; x_offset <= 10; x_offset++) {
		for (int y_offset = -10; y_offset <= 10; y_offset++) {
			vec2 offset = vec2(float(x_offset), float(y_offset));
			float falloff = min(0.1 / pow(max(length(offset), 0.0001), 1.5), 1.0);
			vec3 neighbor = texture(TEXTURE, UV + offset * TEXTURE_PIXEL_SIZE).rgb;
			float brightness = dot(neighbor, vec3(0.2126, 0.7152, 0.0722));
			color = mix(color, neighbor, falloff * brightness * brightness);
		}
	}
	COLOR = vec4(color, 1.0);
}
