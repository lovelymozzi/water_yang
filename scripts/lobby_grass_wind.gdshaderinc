// grass1.fbx grows along local +Z, with its roots at Z = 0.
// Run before outline extrusion so the two passes have identical silhouettes.
if (grass_wind_strength > 0.0) {
	float blade_height = clamp(VERTEX.z / 0.024298, 0.0, 1.0);
	float bend_weight = smoothstep(0.08, 1.0, blade_height);
	bend_weight *= bend_weight;
	vec2 clump_position = MODEL_MATRIX[3].xz;
	float phase = dot(clump_position, vec2(1.73, 2.31));
	float wind_time = grass_wind_use_engine_time ? TIME : grass_wind_time;
	float breeze = sin(wind_time * 2.25 - dot(clump_position, vec2(0.37, 0.24)));
	breeze += 0.26 * sin(wind_time * 3.47 + phase);
	vec3 wind_offset = vec3(0.91 * breeze, -0.10 * breeze * breeze, 0.41 * breeze);
	wind_offset *= grass_wind_strength * bend_weight;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * wind_offset;
}
