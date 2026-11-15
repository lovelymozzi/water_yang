uniform sampler2D source_texture : source_color, filter_linear, repeat_disable;
uniform vec4 source_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 source_pixels = vec2(128.0);
uniform vec4 borders = vec4(0.0);
uniform vec2 pivot = vec2(0.5);
uniform vec4 tint : source_color = vec4(1.0);
uniform float draw_width = 1.28;
uniform float draw_height = 1.28;
uniform float opacity = 1.0;
uniform float beam_height_scale = 1.0;
uniform float beam_top_spread = 0.0;

void vertex() {
	// Unity SpriteRenderer uses a bottom-left sprite pivot and 100 pixels/unit.
	VERTEX = vec3((UV.x - pivot.x) * draw_width,
		(1.0 - UV.y - pivot.y) * draw_height, 0.0);
	VERTEX.xy *= vec2(1.0 + beam_top_spread, beam_height_scale);
}

void fragment() {
	// Inverse-map a widening beam inside a rectangular quad. Moving only the
	// four corner vertices would skew the texture along its triangle diagonal.
	vec2 beam_uv = UV;
	beam_uv.x = (UV.x - 0.5) * (1.0 + beam_top_spread)
		/ (1.0 + beam_top_spread * (1.0 - UV.y)) + 0.5;
	vec2 destination = max(vec2(draw_width, draw_height) * 100.0, vec2(0.0001));
	vec2 pixel = vec2(beam_uv.x, 1.0 - beam_uv.y) * destination;
	vec2 lower = borders.xy;
	vec2 upper = borders.zw;
	vec2 mapped;
	// Preserve the source's 28px bottom / 98px top borders as height animates.
	for (int axis = 0; axis < 2; axis++) {
		float border_scale = min(1.0, destination[axis] / max(lower[axis] + upper[axis], 0.0001));
		float low = lower[axis] * border_scale;
		float high = upper[axis] * border_scale;
		if (pixel[axis] < low) {
			mapped[axis] = pixel[axis] / max(border_scale, 0.0001);
		} else if (pixel[axis] > destination[axis] - high) {
			mapped[axis] = source_pixels[axis] - (destination[axis] - pixel[axis]) / max(border_scale, 0.0001);
		} else {
			mapped[axis] = lower[axis] + (pixel[axis] - low)
				* (source_pixels[axis] - lower[axis] - upper[axis])
				/ max(destination[axis] - low - high, 0.0001);
		}
	}
	vec2 sprite_uv = vec2(mapped.x / source_pixels.x, 1.0 - mapped.y / source_pixels.y);
	vec4 texel = texture(source_texture, source_rect.xy + sprite_uv * source_rect.zw);
	ALBEDO = texel.rgb * tint.rgb;
	ALPHA = texel.a * clamp(opacity, 0.0, 1.0)
		* step(0.0, beam_uv.x) * step(beam_uv.x, 1.0);
	if (beam_top_spread > 0.0) {
		ALPHA *= smoothstep(0.0, 0.24, UV.y);
	}
}
