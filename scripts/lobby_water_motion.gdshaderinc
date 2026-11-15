// Shared fragment-local waves: wave_position is a world-space XZ position.
// The gradient drives both the surface reflection and bottom refraction.
vec3 water_phase = vec3(
    dot(wave_position, vec2(0.94, 0.34)) * 1.85 - water_motion_time * 2.55,
    dot(wave_position, vec2(-0.38, 0.925)) * 2.70 - water_motion_time * 3.09 + 1.7,
    dot(wave_position, vec2(0.64, -0.768)) * 0.82 - water_motion_time * 1.70 + 4.1
);
vec3 water_sine = sin(water_phase);
float water_height = dot(cos(water_phase), vec3(0.57, 0.24, 0.19));
vec2 water_gradient = -(
    vec2(0.94, 0.34) * water_sine.x * 0.57 +
    vec2(-0.38, 0.925) * water_sine.y * 0.35 +
    vec2(0.64, -0.768) * water_sine.z * 0.12
);
