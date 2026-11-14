// Included inside body/outline fragment(): both use the same world-space entry.
// The mask stays on this cat's aperture as the skinned surface moves through it.
float absorb_light_weight = 0.0;
const vec3 absorb_light_color = vec3(1.0, 0.985, 0.58);
if (sink_clip_enabled > 0.5 && absorb_light_portal.w > 0.0) {
	vec3 light_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float entry_distance = length(light_world.xz - absorb_light_portal.xz);
	absorb_light_weight = 1.0 - smoothstep(
		absorb_light_portal.w * 0.65, absorb_light_portal.w * 1.2, entry_distance);
	// Keep the opaque cat surface and its depth. Removing it here exposes the
	// vortex behind the body. Only the normal below-floor sink clip may cut it;
	// entry light replaces color, then the foreground FX composites above it.
}
