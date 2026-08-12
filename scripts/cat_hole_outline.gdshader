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

// The flower's flat silhouette reads slightly thicker than CatEntity's
// normal-based outline at the top-down camera angle.  Keep its Inspector
// control responsive while reducing the final width by a small amount.
const float FLAT_MESH_WIDTH_COMPENSATION = 0.82;

// The imported FBX keeps the flower's mesh node rotated (Z-up source), so this
// mesh's own local frame is NOT the world frame: local XY is the flat board
// plane and local +Z is world up. Expanding in local XZ pushed the hull along
// the thin axis and offset it sideways instead of downward, which let the
// enlarged copy cover the petals from the top-down camera. Use the real axes.
void vertex() {
	float upward_facing = max(NORMAL.z, 0.0);
	float downward_facing = max(-NORMAL.z, 0.0);
	float line_weight = mix(1.0, top_outline_scale, upward_facing);
	line_weight = mix(line_weight, bottom_outline_scale, downward_facing);

	vec2 radial = VERTEX.xy;
	if (length(radial) > 0.0001) {
		VERTEX.xy += normalize(radial) * outline_width * line_weight * FLAT_MESH_WIDTH_COMPENSATION;
	}
	// Local -Z is world down. Sink the copy so the flower depth-masks its middle.
	VERTEX.z -= 0.002;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
