// Godot-native study of https://www.shadertoy.com/view/XdVBW1 by Noxbuds.
// The original iChannel0 cubemap and iChannel1 texture are unavailable as
// distributable project assets, so the two source inputs are replaced by the
// procedural sky and surface pattern below. The SDF, reflection, dissolve,
// and timing structure mirror the reference.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

group_uniforms shadertoy_reference;
uniform vec2 camera_orbit = vec2(-1.0, -1.0);
uniform float viewport_aspect : hint_range(0.2, 3.0, 0.001) = 0.461;
uniform vec3 sky_horizon : source_color = vec3(0.08, 0.14, 0.24);
uniform vec3 sky_zenith : source_color = vec3(0.42, 0.72, 0.93);
uniform vec3 sphere_one_color : source_color = vec3(0.12, 0.38, 0.18);
uniform vec3 sphere_two_color : source_color = vec3(0.34, 0.25, 0.05);
uniform vec3 cyan_edge_color : source_color = vec3(0.3, 1.0, 1.0);
uniform vec3 yellow_edge_color : source_color = vec3(1.0, 1.0, 0.0);
uniform float edge_emission : hint_range(1.0, 8.0, 0.1) = 3.0;
group_uniforms;

const float REFERENCE_PI = 3.14159;
const float REFERENCE_PHI = 1.57080;
const vec3 LIGHT_DIRECTION = vec3(-0.485071, -0.727607, 0.485071);

float value_noise(vec2 point) {
	return fract(sin(point.x * 1234.0 + point.y * 2413.0) * 5647.0);
}

float smooth_noise(vec2 point) {
	vec2 local = fract(point);
	vec2 cell = floor(point);
	local = local * local * (3.0 - 2.0 * local);
	float bottom = mix(value_noise(cell), value_noise(cell + vec2(1.0, 0.0)), local.x);
	float top = mix(value_noise(cell + vec2(0.0, 1.0)), value_noise(cell + vec2(1.0)), local.x);
	return mix(bottom, top, local.y);
}

float fbm(vec2 point) {
	float value = 0.5 * smooth_noise(point);
	point *= 2.01;
	value += 0.25 * smooth_noise(point + vec2(0.0, 1.0));
	point *= 2.02;
	value += 0.125 * smooth_noise(point + vec2(1.0, 0.0));
	point *= 2.03;
	value += 0.0625 * smooth_noise(point + vec2(1.0));
	return value / 0.9375;
}

float max3(vec3 value) {
	return max(max(value.x, value.y), value.z);
}

float sphere_distance(vec3 point, float radius) {
	return length(point) - radius;
}

float box_distance(vec3 point, vec3 half_size) {
	vec3 distance = abs(point) - half_size;
	return length(max(distance, 0.0)) - max3(min(distance, 0.0));
}

vec2 scene_map(vec3 point) {
	float floor_distance = box_distance(point + vec3(0.0, 3.2, 0.0), vec3(10.0, 1.0, 10.0));
	float first_sphere_distance = sphere_distance(point + vec3(2.0, 0.0, 0.0), 2.0);
	float second_sphere_distance = sphere_distance(point - vec3(2.0, 0.0, 0.0), 2.0);
	vec2 closest = vec2(floor_distance, 0.0);
	if (first_sphere_distance < closest.x) {
		closest = vec2(first_sphere_distance, 1.0);
	}
	if (second_sphere_distance < closest.x) {
		closest = vec2(second_sphere_distance, 2.0);
	}
	return closest;
}

vec3 diffuse(vec3 color, vec3 normal) {
	return color * max(dot(-LIGHT_DIRECTION, normal), 0.0);
}

vec3 specular(vec3 color, vec3 normal, vec3 ray) {
	vec3 reflected_light = reflect(-LIGHT_DIRECTION, normal);
	float highlight = max(0.0, dot(reflected_light, ray));
	return diffuse(color, normal) * 0.5 + vec3(highlight * 0.5);
}

vec3 scene_normal(vec3 point) {
	const vec2 epsilon = vec2(0.002, 0.0);
	return normalize(vec3(
		scene_map(point + epsilon.xyy).x - scene_map(point - epsilon.xyy).x,
		scene_map(point + epsilon.yxy).x - scene_map(point - epsilon.yxy).x,
		scene_map(point + epsilon.yyx).x - scene_map(point - epsilon.yyx).x
	));
}

float soft_shadow(vec3 origin, vec3 ray, float minimum_distance, float maximum_distance, float sharpness) {
	float result = 1.0;
	for (float travel = minimum_distance; travel < maximum_distance;) {
		float distance = scene_map(origin + ray * travel).x;
		if (distance < 0.001) {
			return 0.0;
		}
		result = min(result, sharpness * distance / travel);
		travel += distance;
	}
	return result;
}

vec4 material_data(float object_id, vec3 point, vec3 normal, vec3 ray, out bool transparent) {
	transparent = false;
	if (object_id == 1.0 || object_id == 2.0) {
		vec2 cylindrical_uv = vec2(atan(normal.x, normal.z) / (2.0 * REFERENCE_PI) + 0.5, point.y * 0.5 + 0.5);
		cylindrical_uv.x = mod((cylindrical_uv.x + 0.22) * 2.0, 1.0);
		vec3 base_color = object_id == 1.0 ? sphere_one_color : sphere_two_color;
		base_color *= mix(0.7, 1.3, fbm(cylindrical_uv * 7.0));
		vec2 noise_uv = cylindrical_uv * 2.0 - 1.0;
		float dissolve_noise;
		float threshold;
		if (object_id == 1.0) {
			dissolve_noise = fbm(noise_uv * 5.0);
			threshold = 0.5 + 0.5 * sin(TIME);
		} else {
			noise_uv += vec2(fbm(noise_uv * 2.0 + vec2(TIME, 0.0)));
			dissolve_noise = smooth_noise(noise_uv * 25.0);
			threshold = 0.5 + 0.5 * sin(TIME);
			threshold *= threshold + 0.1;
		}
		if (dissolve_noise > threshold) {
			transparent = true;
			return vec4(0.0);
		}
		if (dissolve_noise > threshold - 0.1) {
			return vec4((object_id == 1.0 ? cyan_edge_color : yellow_edge_color) * edge_emission, 0.0);
		}
		return vec4(diffuse(base_color, normal), 0.4);
	}
	return vec4(specular(vec3(0.9), normal, ray), 1.0);
}

vec3 sky_color(vec3 ray) {
	float horizon = clamp(ray.y * 0.5 + 0.5, 0.0, 1.0);
	return mix(sky_horizon, sky_zenith, horizon);
}

vec3 raymarch(vec2 screen_uv) {
	vec2 uv = (screen_uv * 2.0 - 1.0) * vec2(viewport_aspect, 1.0);
	vec3 origin = vec3(0.0, 1.5, -6.0);
	vec3 ray = vec3(uv, REFERENCE_PHI);
	float pitch = -camera_orbit.y;
	ray.yz = vec2(
		ray.y * cos(pitch) - ray.z * sin(pitch),
		ray.y * sin(pitch) + ray.z * cos(pitch)
	);
	float yaw = -camera_orbit.x;
	ray.xz = vec2(
		ray.x * cos(yaw) - ray.z * sin(yaw),
		ray.x * sin(yaw) + ray.z * cos(yaw)
	);
	vec3 color = sky_color(ray);
	vec4 previous = vec4(0.0);
	bool terminate = false;
	bool hit_transparent = false;
	for (int bounce = 0; bounce < 5; bounce++) {
		if (terminate) {
			break;
		}
		float travel = 0.0;
		float bounce_falloff = 1.0 / float(bounce + 1);
		float transparent_object = -1.0;
		for (int step = 0; step < 512; step++) {
			vec3 point = origin + ray * (travel + 0.01);
			if (travel > 25.0) {
				if (bounce > 0) {
					color += sky_color(ray) * bounce_falloff * previous.a;
				}
				terminate = true;
				break;
			}
			vec2 mapped = scene_map(point);
			if (mapped.x < 0.0005 && mapped.y != transparent_object) {
				vec3 normal = scene_normal(point);
				bool transparent;
				vec4 data = material_data(mapped.y, point, normal, ray, transparent);
				if (transparent) {
					transparent_object = mapped.y;
					hit_transparent = true;
					continue;
				}
				if (ray.y <= 0.0 && max3(data.rgb) < 0.6 && !hit_transparent) {
					data.rgb = mix(data.rgb, data.rgb * soft_shadow(point, -LIGHT_DIRECTION, 0.01, 10.0, 2.0), 0.5 + 0.5 * sin(TIME));
				}
				vec3 shaded = bounce_falloff * data.rgb;
				if (bounce > 0) {
					color = mix(color, color + shaded, previous.a);
				} else {
					color = shaded;
				}
				previous = data;
				origin = point;
				ray = reflect(ray, normal);
				break;
			}
			travel += mapped.y != transparent_object ? mapped.x * 0.4 : 0.1;
		}
	}
	return color;
}

void fragment() {
	vec3 color = raymarch(SCREEN_UV);
	ALBEDO = clamp(color, 0.0, 1.0);
	EMISSION = max(color - vec3(0.5), vec3(0.0));
	ALPHA = 1.0;
}
