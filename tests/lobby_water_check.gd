extends SceneTree

# Godot 4.7.2 --headless --path . --fixed-fps 60 --script tests/lobby_water_check.gd
# Checks live geometry and animation data; visual comparison remains manual.
func _initialize() -> void:
	await process_frame
	var lobby := (load("res://scenes/lobby_scene.tscn") as PackedScene).instantiate()
	root.add_child(lobby)
	for frame in 8:
		await process_frame
	var actors := lobby.get_node("FloatingCats")
	var light := lobby.get_node("DirectionalLight3D") as DirectionalLight3D
	assert(light.shadow_enabled and is_equal_approx(light.shadow_opacity, 0.55), "Lobby tree shadows do not use the gameplay density")
	assert(light.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert(is_equal_approx(light.directional_shadow_max_distance, 110.0) and is_equal_approx(light.directional_shadow_fade_start, 0.95))
	assert(not lobby.get_node("LevelManager/TileVisuals/TreeShadowDecor").visible, "Painted tree shadow still overlaps the real tree shadows")
	assert(not bool((load("res://resources/lobby_grass_material.tres") as ShaderMaterial).get_shader_parameter("grass_shadow_enabled")), "Painted tree shadow still darkens the grass")
	var shadow_trees := 0
	for decoration in lobby.get_node("LevelManager/TileVisuals").get_children():
		if decoration.scene_file_path == "res://scenes/tree_decor.tscn":
			for mesh: MeshInstance3D in decoration.find_children("*", "MeshInstance3D", true, false):
				assert(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
				shadow_trees += 1
	assert(shadow_trees > 2, "Lobby trees no longer cast real shadows")
	var water := lobby.get_node("LobbyGround/Water/water1") as MeshInstance3D
	var water_bounds := water.global_transform * water.get_aabb()
	assert(absf(water_bounds.position.y - (-3.024224)) < 0.001, "Lobby water no longer uses the raised shoreline height")
	var bottom := lobby.get_node("UnderwaterIllustration") as MeshInstance3D
	assert(absf(bottom.global_position.y - (water_bounds.position.y - lobby.underwater_depth)) < 0.001, "Underwater painting did not follow the surface")
	assert(float(water.material_override.get_shader_parameter("undulation_strength")) > 0.0)
	assert(float(bottom.material_override.get_shader_parameter("refraction_strength")) > 0.0)
	var ground := lobby.get_node("LobbyGround/LobbyGround") as MeshInstance3D
	var cliff_material := ground.get_surface_override_material(1) as ShaderMaterial
	assert(is_equal_approx(float(cliff_material.get_shader_parameter("water_level")), water_bounds.position.y))
	assert(is_equal_approx(float(cliff_material.get_shader_parameter("cliff_water_fade_distance")), 0.5), "Submerged soil should lose its brown tint within half a meter of the actual surface")
	assert(ground.get_surface_override_material(1).next_pass == null, "Foam must lie on the water, not a cliff UV stripe")
	var shore_image: Image = water.material_override.get_shader_parameter("shore_distance_map").get_image()
	var shore_mask: Image = bottom.material_override.get_shader_parameter("shore_mask").get_image()
	var sparkles := lobby.get_node("WaterSparkles") as CPUParticles3D
	assert(sparkles.emitting and sparkles.emission_points.size() > 200, "Water sparkles have no usable emission area")
	var water_faces := water.mesh.get_faces()
	for point in sparkles.emission_points:
		var world_point: Vector3 = sparkles.global_transform * point
		assert(absf(world_point.y - water_bounds.get_center().y - 0.035) < 0.001, "A sparkle floats above the water")
		var uv := Vector2((world_point.x - water_bounds.position.x) / water_bounds.size.x, (world_point.z - water_bounds.position.z) / water_bounds.size.z)
		assert(shore_image.get_pixelv(Vector2i(uv * Vector2(shore_image.get_size()))).r * 2.0 >= 0.55, "A sparkle overlaps the cliff contact band")
		var on_water := false
		for triangle in range(0, water_faces.size(), 3):
			var polygon := PackedVector2Array()
			for corner in 3:
				var vertex: Vector3 = water.global_transform * water_faces[triangle + corner]
				polygon.append(Vector2(vertex.x, vertex.z))
			if Geometry2D.is_point_in_polygon(Vector2(world_point.x, world_point.z), polygon):
				on_water = true
				break
		assert(on_water, "A sparkle is emitted outside the actual water mesh")
	var shore_samples := 0
	# Validate the baked data against the current mesh, so a terrain edit cannot
	# silently leave the water foam at an old shoreline.
	for surface_index in ground.mesh.get_surface_count():
		var arrays := ground.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for triangle in range(0, indices.size(), 3):
			for edge in 3:
				var start := ground.global_transform * vertices[indices[triangle + edge]]
				var end := ground.global_transform * vertices[indices[triangle + (edge + 1) % 3]]
				if (start.y - water_bounds.position.y) * (end.y - water_bounds.position.y) >= 0.0:
					continue
				var point := start.lerp(end, (water_bounds.position.y - start.y) / (end.y - start.y))
				var uv := Vector2((point.x - water_bounds.position.x) / water_bounds.size.x, (point.z - water_bounds.position.z) / water_bounds.size.z)
				if uv.x < 0.0 or uv.x >= 1.0 or uv.y < 0.0 or uv.y >= 1.0:
					continue
				var pixel := Vector2i(uv * Vector2(shore_image.get_size()))
				assert(shore_image.get_pixelv(pixel).r * 2.0 < 0.025, "Shore foam distance map no longer matches the terrain")
				assert(shore_mask.get_pixelv(Vector2i(uv * Vector2(shore_mask.get_size()))).r < 0.08, "Underwater painting reaches the new cliff contact")
				shore_samples += 1
	assert(shore_samples > 100, "No usable terrain/water intersections checked")
	var normalized_widths: Array[float] = []
	for actor_scale in [6.0, 9.0, 12.0]:
		actors.cat_scale = actor_scale
		actors._create_cats()
		await process_frame
		await process_frame
		var material := actors._cat_wakes[0].material_override as ShaderMaterial
		var relative_velocity: Vector2 = material.get_shader_parameter("flow_velocity")
		assert(absf(relative_velocity.x + actors.travel_speed) < 0.04, "Water must flow backwards relative to the cat")
		assert(not (load("res://scripts/cat_wake.gdshader") as Shader).code.contains("sampler2D foam_shapes"), "A fixed foam image returned")
		var width: float = material.get_shader_parameter("body_width")
		assert(width / actor_scale > 0.20 and width / actor_scale < 0.30, "Foam width must use the measured cat silhouette")
		normalized_widths.append(width / actor_scale)
		assert(is_equal_approx(width, water.material_override.get_shader_parameter("foam_reference_width")), "Surface foam must share the first cat's measured scale")
		var cat = actors._cats[0]
		var contour: PackedVector2Array = material.get_shader_parameter("shadow_points")
		var contour_count: int = material.get_shader_parameter("shadow_point_count")
		assert(contour_count >= 3 and contour_count <= 128)
		contour.resize(contour_count)
		var contour_bounds := Rect2(contour[0], Vector2.ZERO)
		for point in contour:
			assert(point.is_finite())
			contour_bounds = contour_bounds.expand(point)
		var projected_triangles: Array[PackedVector2Array] = []
		var camera := root.get_camera_3d()
		for surface in cat._floating_mesh_surfaces:
			var vertices := PackedVector2Array()
			for point: Vector3 in surface.world:
				var ray := camera.project_ray_normal(camera.unproject_position(point))
				var on_water := point + ray * ((float(material.get_shader_parameter("water_y")) - point.y) / ray.y)
				vertices.append(Vector2(on_water.x, on_water.z))
			var indices: PackedInt32Array = surface.arrays[Mesh.ARRAY_INDEX]
			for triangle in range(0, indices.size(), 3):
				projected_triangles.append(PackedVector2Array([vertices[indices[triangle]], vertices[indices[triangle + 1]], vertices[indices[triangle + 2]]]))
		var points: PackedVector2Array = material.get_shader_parameter("body_points")
		var reference_radii: PackedFloat32Array = material.get_shader_parameter("body_radii")
		var detailed_gaps := 0
		for y in 20:
			for x in 60:
				var point := contour_bounds.position + contour_bounds.size * Vector2((x + 0.5) / 60.0, (y + 0.5) / 20.0)
				if Geometry2D.is_point_in_polygon(point, contour):
					continue
				var old_distance := INF
				for segment in points.size() - 1:
					var line := points[segment + 1] - points[segment]
					var t := clampf((point - points[segment]).dot(line) / maxf(line.length_squared(), 0.0001), 0.0, 1.0)
					old_distance = minf(old_distance, point.distance_to(points[segment].lerp(points[segment + 1], t)) - lerpf(reference_radii[segment], reference_radii[segment + 1], t) * actor_scale * 0.96)
				if old_distance > -width * 0.02:
					continue
				var boundary_distance := INF
				for segment in contour.size():
					boundary_distance = minf(boundary_distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, contour[segment], contour[(segment + 1) % contour.size()])))
				if boundary_distance < width * 0.07:
					continue
				var on_mesh := false
				for triangle in projected_triangles:
					if Geometry2D.is_point_in_polygon(point, triangle):
						on_mesh = true
						break
				if not on_mesh:
					detailed_gaps += 1
		assert(detailed_gaps > 0, "Rounded shadow still fills the real mesh gaps")
		print("LIVE SHADOW DETAIL scale=", actor_scale, "; contour points=", contour_count, "; actual mesh gaps cleared=", detailed_gaps)
		for outline in [cat._outline_material, cat._material_id_2_outline]:
			assert(outline.get_shader_parameter("flow_velocity") == material.get_shader_parameter("flow_velocity"), "Bow compression and material foam have different source velocities")
			assert(is_equal_approx(float(outline.get_shader_parameter("flow_distance")), float(material.get_shader_parameter("flow_distance"))), "Contact and outer foam have different crown-to-feet transport")
			assert((outline.get_shader_parameter("body_points") as PackedVector2Array) == (material.get_shader_parameter("body_points") as PackedVector2Array), "Crown branches do not share the same live body")
			assert(outline.get_shader_parameter("water_foam_enabled") == false, "Projected full-body foam must be disabled")
			assert(is_equal_approx(width, outline.get_shader_parameter("body_width")))
			assert(is_equal_approx(float(outline.get_shader_parameter("water_y")), float(material.get_shader_parameter("water_y")) + 0.01))
		var before: float = actors._elapsed
		var water_before: float = water.material_override.get_shader_parameter("water_motion_time")
		var distance_before: float = material.get_shader_parameter("flow_distance")
		paused = true
		for frame in 12:
			await process_frame
		assert(actors._elapsed > before + 0.15, "Lobby animation freezes while the web UI owns the tree")
		assert(float(water.material_override.get_shader_parameter("water_motion_time")) > water_before + 0.15, "Ambient surface motion freezes while UI owns the tree")
		assert(is_equal_approx(float(water.material_override.get_shader_parameter("water_motion_time")), float(bottom.material_override.get_shader_parameter("water_motion_time"))), "Surface reflection and bottom refraction have different clocks")
		assert(float(material.get_shader_parameter("flow_distance")) > distance_before, "Bow-to-stern advection freezes while the UI owns the tree")
		paused = false
		var previous_filaments := {}
		var visible_flanks := [false, false]
		for frame in 240:
			await process_frame
			assert(not actors._cats[0]._floating_water_sections.is_empty(), "Submerged live mesh has no water contact")
			assert(actors._cats[0]._floating_open_water_cuts == 0, "Live mesh contact has open seams")
			assert(actors._wake_fields[0].boundary_residual < 0.65 * 0.08, "Live mesh boundary solve did not converge")
			var field = actors._wake_fields[0]
			assert((material.get_shader_parameter("flow_origin") as Vector2).distance_to(field.center) < 0.0001)
			if frame % 30 == 0:
				var wake = actors._cat_wakes[0]
				var arrays: Array = wake.mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
				for vertex in vertices.size():
					assert(vertices[vertex].is_finite(), "Non-finite contact/ripple geometry")
					var color := colors[vertex]
					if color.r > 0.5 and color.b < 0.5 and color.a > 0.02:
						var p: Vector3 = wake.global_transform * vertices[vertex]
						visible_flanks[0 if p.z < field.center.y else 1] = true
				# Attached bow compression must not become a broad opaque paw rim.
				for face in range(0, vertices.size(), 6):
					if absf(vertices[face].y - 0.004) > 0.00001:
						continue
					assert(vertices[face + 1].distance_to(vertices[face]) <= field.body_width * 0.0601, "Attached foam overwhelms the contact silhouette")
					assert(vertices[face + 4].distance_to(vertices[face + 2]) <= field.body_width * 0.0601, "Attached foam has an oversized corner")
					assert(colors[face].a <= 0.4201 and colors[face + 2].a <= 0.4201, "Attached foam is brighter than its balanced contact setting")
			for particle in field.CAPACITY:
				if field.lifetimes[particle] <= 0.0:
					continue
				var identity: int = field.identities[particle]
				var normals: PackedVector2Array = field.strand_normals[particle]
				var widths: PackedFloat32Array = field.thicknesses[particle]
				for marker in field.SAMPLES:
					assert(normals[marker].is_finite() and absf(normals[marker].length() - 1.0) < 0.001, "Invalid ribbon material normal")
					assert(is_finite(widths[marker]) and widths[marker] >= 0.0 and widths[marker] <= field.body_width * 0.1001, "Ribbon compression creates an oversized spike")
					if previous_filaments.has(identity):
						var last: Dictionary = previous_filaments[identity]
						assert(normals[marker].dot(last.normals[marker]) > 0.85, "Ribbon flips its material side between frames")
						assert(absf(widths[marker] - last.widths[marker]) < field.body_width * 0.009, "Ribbon thickness jumps in one 60 Hz frame")
				previous_filaments[identity] = {"normals":normals.duplicate(), "widths":widths.duplicate()}
				if field.ages[particle] > 1.0 / 60.0:
					continue
				var birth: Vector2 = field.birth_points[particle]
				var nearest := INF
				for section in field.sections:
					for edge in section.size():
						nearest = minf(nearest, birth.distance_to(Geometry2D.get_closest_point_to_segment(birth, section[edge], section[(edge + 1) % section.size()])))
				assert(nearest < field.body_width * 0.016, "Foam birth does not touch the live cat mesh")
				assert(field.lifetimes[particle] <= 3.2)
			for wake in actors._cat_wakes:
				var bounds: AABB = wake.global_transform * wake.get_aabb()
				var positions: PackedVector2Array = wake.material_override.get_shader_parameter("body_points")
				var radii: PackedFloat32Array = wake.material_override.get_shader_parameter("body_radii")
				var body_width: float = wake.material_override.get_shader_parameter("body_width")
				assert(positions.size() == 21 and radii.size() == 21)
				var shadow_points: PackedVector2Array = wake.material_override.get_shader_parameter("shadow_points")
				var shadow_count: int = wake.material_override.get_shader_parameter("shadow_point_count")
				assert(shadow_count >= 3 and shadow_count <= 128)
				for vertex in shadow_count:
					var point := shadow_points[vertex]
					# Covers the existing 0.30-width offset and the feather in all directions.
					var reach := body_width * 0.38
					assert(point.x - reach >= bounds.position.x and point.x + reach <= bounds.end.x, "Mesh shadow clips along X")
					assert(point.y - reach >= bounds.position.z and point.y + reach <= bounds.end.z, "Mesh shadow clips along Z")
				for index in positions.size():
					assert(radii[index] > 0.0 and is_finite(radii[index]))
					# Includes the outer brush, the shadow offset and its soft edge.
					var reach: float = radii[index] * actor_scale + body_width * 0.72
					assert(positions[index].x - reach >= bounds.position.x and positions[index].x + reach <= bounds.end.x, "Foam or shadow clips along X")
					assert(positions[index].y - reach >= bounds.position.z and positions[index].y + reach <= bounds.end.z, "Foam or shadow clips along Z")
		assert(visible_flanks[0] and visible_flanks[1], "Tangential water shoulder is absent on one body flank")
	assert(normalized_widths.max() - normalized_widths.min() < 0.02, "Foam proportion changes with cat scale")
	var active_wake: ShaderMaterial = actors._cat_wakes[0].material_override
	var distance_before_speed_change: float = active_wake.get_shader_parameter("flow_distance")
	var position_before_speed_change: Vector3 = actors._cats[0].global_position
	actors.travel_speed *= 0.5
	await process_frame
	await process_frame
	var distance_after_speed_change: float = active_wake.get_shader_parameter("flow_distance")
	assert(distance_after_speed_change > distance_before_speed_change and distance_after_speed_change - distance_before_speed_change < 0.2, "Changing speed jumps the wave phase instead of integrating travel")
	assert(actors._cats[0].global_position.distance_to(position_before_speed_change) < 0.2, "Changing speed teleports the cat")
	actors.travel_speed = 0.0
	var water_before_stop: float = water.material_override.get_shader_parameter("water_motion_time")
	var emission_before_stop: int = actors._wake_fields[0]._emission
	var position_before_stop: Vector3 = actors._cats[0].global_position
	await process_frame
	await process_frame
	assert(is_equal_approx(float(active_wake.get_shader_parameter("flow_distance")), distance_after_speed_change), "A stopped cat keeps emitting a travelling wake")
	assert((active_wake.get_shader_parameter("flow_velocity") as Vector2).length() < 0.04)
	assert(actors._wake_fields[0]._emission == emission_before_stop, "A stopped cat emits new foam")
	var stopped_colors: PackedColorArray = actors._cat_wakes[0].mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for color in stopped_colors:
		assert(not (color.r > 0.5 and color.b < 0.5 and color.a > 0.001), "Stopped body retains the driven side ripple")
	assert(is_equal_approx(actors._cats[0].global_position.x, position_before_stop.x), "Stopping teleports the cat to the route origin")
	for frame in 42:
		await process_frame
	for lifetime in actors._wake_fields[0].lifetimes:
		assert(lifetime == 0.0, "Stopped wake leaves a persistent afterimage")
	assert(float(water.material_override.get_shader_parameter("water_motion_time")) > water_before_stop + 0.6, "Stopping a cat also stops the ambient water")
	# Move the real mesh clear of water. Contact and foam must both disappear.
	actors.water_surface_offset = 2.0
	await process_frame
	await process_frame
	assert(actors._cats[0]._floating_water_sections.is_empty(), "Dry mesh retains a projected contact outline")
	assert(actors._wake_fields[0].panel_starts.is_empty(), "Dry mesh forces the water")
	var shader := load("res://scripts/cat_wake.gdshader") as Shader
	assert(not shader.code.contains("fract(wave_time"), "Time-based opacity cycling returned")
	assert(shader.code.contains("shadow_alpha"))
	var gameplay_cat := (load("res://scenes/cat_entity.tscn") as PackedScene).instantiate()
	lobby.add_child(gameplay_cat)
	gameplay_cat.add_child(gameplay_cat.load_model_with_texture())
	assert(gameplay_cat._floating_body_radii.is_empty(), "Lobby profile leaked into a gameplay cat")
	assert(is_equal_approx(float(gameplay_cat._cat_material.get_shader_parameter("ambient_energy")), gameplay_cat.TOON_AMBIENT_ENERGY), "Lobby appearance leaked into the gameplay cat's current lighting preset")
	assert(gameplay_cat._outline_material.get_shader_parameter("water_foam_enabled") == false)
	var actual_emissions: Array[int] = []
	actors.water_surface_offset = 0.07
	actors.cat_scale = 9.0
	actors.cat_count = 1
	for speed in [0.0, 0.325, 0.65]:
		actors.travel_speed = speed
		actors._create_cats()
		for frame in 480:
			await process_frame
		actual_emissions.append(actors._wake_fields[0]._emission)
	assert(actual_emissions[0] == 0 and actual_emissions[2] > actual_emissions[1] * 2, "Actual skinned cat foam does not respond to travel speed")
	print("Actual skinned cat 8s emissions (stop/half/normal): ", actual_emissions)
	print("LOBBY WATER CHECK: PASS (shore samples=%d, live closed mesh/plane contact at three scales, bounded continuous ribbons, boundary solve, short stopped wake, dry mesh, bounds, pause, gameplay defaults)" % shore_samples)
	lobby.queue_free()
	await process_frame
	quit()
