shader_type spatial;
// A flat top face has no visible back hull when cull_front is used. Draw the
// enlarged copy without culling and place it just below the flower; the base
// flower depth-masks the middle, leaving only its outer silhouette.
render_mode unshaded, cull_disabled;

// CatHole shares color and width with Cat2. Its flat FBX needs a board-plane
// expansion instead of Cat2's normal-direction expansion.
uniform vec4 outline_color : source_color = vec4(0.18, 0.09, 0.06, 1.0);
uniform float outline_width : hint_range(0.001, 0.04, 0.001) = 0.008;
uniform float top_outline_scale : hint_range(0.4, 1.2, 0.01) = 1.0;
uniform float bottom_outline_scale : hint_range(0.8, 1.6, 0.01) = 1.0;

// The flower is a shallow, imported mesh displayed at a much larger node
// scale than Cat2. This keeps the *same shared outline_width value* at an
// equivalent on-screen line weight.
const float FLAT_MESH_WIDTH_COMPENSATION = 0.35;

void vertex() {
	float upward_facing = max(NORMAL.y, 0.0);
	float downward_facing = max(-NORMAL.y, 0.0);
	float line_weight = mix(1.0, top_outline_scale, upward_facing);
	line_weight = mix(line_weight, bottom_outline_scale, downward_facing);

	vec2 radial = VERTEX.xz;
	if (length(radial) > 0.0001) {
		VERTEX.xz += normalize(radial) * outline_width * line_weight * FLAT_MESH_WIDTH_COMPENSATION;
	}
	VERTEX.y -= 0.002;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
