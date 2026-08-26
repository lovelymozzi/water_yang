shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;

uniform vec4 outline_color : source_color = vec4(0.18, 0.09, 0.06, 1.0);
uniform float outline_width : hint_range(0.001, 0.04, 0.001) = 0.008;
// A completely uniform shell looks mechanical. Keep the upper silhouette
// lighter and let the lower/underside silhouette carry a little more ink.
uniform float top_outline_scale : hint_range(0.4, 1.2, 0.01) = 0.78;
uniform float bottom_outline_scale : hint_range(0.8, 1.6, 0.01) = 1.12;
// 본체(cat_toon)와 같은 기준으로 잘라 낸다. 값이 다르면 껍데기만 남는다.
uniform float sink_clip_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float sink_clip_plane_y = 0.0;
uniform float sink_clip_span = 1.0;
// Move the shell's depth just behind the source mesh.  This makes normal depth
// testing remove the hull where a curved body folds over itself, while the
// shell remains visible where it extends past the true outer silhouette.
uniform float self_overlap_depth_scale : hint_range(1.0, 3.0, 0.01) = 2.0;
// Matches the optional lobby wave deformation in cat_toon.gdshader.
uniform float water_wave_time = 0.0;
uniform float water_wave_phase = 0.0;
uniform float water_wave_amplitude : hint_range(0.0, 0.08, 0.001) = 0.0;
// 본체(cat_toon)와 같은 값으로 줄어든다. 값이 다르면 얇은 몸에 두꺼운 외곽선이 남는다.
uniform float body_shrink = 0.0;

void vertex() {
	VERTEX -= NORMAL * body_shrink;
	if (water_wave_amplitude > 0.0) {
		float wave = VERTEX.y * 3.2 + water_wave_time * 2.1 + water_wave_phase;
		VERTEX.z += sin(wave) * water_wave_amplitude;
		VERTEX.x += cos(wave) * water_wave_amplitude * 0.22;
	}
	float upward_facing = max(NORMAL.y, 0.0);
	float downward_facing = max(-NORMAL.y, 0.0);
	float line_weight = mix(1.0, top_outline_scale, upward_facing);
	line_weight = mix(line_weight, bottom_outline_scale, downward_facing);
	VERTEX += NORMAL * outline_width * line_weight;
}

void fragment() {
	// Derive the bias from this cat's actual uniform model scale, so the same
	// Inspector width behaves the same on every board tile.  Projecting the
	// farther view-space depth works with both regular and reverse-Z renderers.
	float model_scale = max(
		length(MODEL_MATRIX[0].xyz),
		max(length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz))
	);
	vec4 outline_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z, 1.0);
	float outline_depth = -outline_view.z / outline_view.w;
	float shell_depth_bias = outline_width * model_scale * self_overlap_depth_scale;
	vec4 biased_clip = PROJECTION_MATRIX * vec4(0.0, 0.0, -outline_depth - shell_depth_bias, 1.0);
	DEPTH = biased_clip.z / biased_clip.w;

	if (sink_clip_enabled > 0.5) {
		float world_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
		float sink = clamp((sink_clip_plane_y - world_y) / max(sink_clip_span, 0.0001), 0.0, 1.0);
		float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
		if (sink > dither) {
			discard;
		}
	}
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * 0.16;
}
