extends SceneTree

func _init() -> void:
	var source := (load("res://resources/terrain/jam3d/wall.fbx") as PackedScene).instantiate()
	var material := load("res://resources/terrain/jam3d/wall_material.tres") as Material
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/terrain/jam3d/rules.json"))
	# The source catalog contains a concave cap here. Its raw-FBX alias points
	# at a full cliff instead; rotate the matching concave source cap instead.
	rules.mesh_names["middle_right_top_point"] = "middle_left_top_point"
	for rule: Dictionary in rules.rules:
		if rule.id == "middle_top_open":
			# Four concave corners are only appropriate when all diagonals are
			# empty. Here the bottom diagonals are filled, so keep that join flat.
			rule.output = {"tile_id": "middle_pioint_single7", "rotation": 180}
	# Only the two diagonals on the filled side affect a three-neighbor cap.
	# Source rules also test diagonals beyond its open edge, leaving valid
	# neighborhoods to a fallback with an extra notch in a connected corner.
	var cap_rules := []
	var offsets := [Vector2i(-1, 1), Vector2i(1, 1)]
	var names := {Vector2i(-1, -1): "topLeft", Vector2i(1, -1): "topRight",
		Vector2i(-1, 1): "bottomLeft", Vector2i(1, 1): "bottomRight"}
	for turn in 4:
		for diagonals in 4:
			var neighbors := {"self": "filled"}
			for index in offsets.size():
				var offset: Vector2i = offsets[index]
				for quarter in turn:
					offset = Vector2i(offset.y, -offset.x)
				neighbors[names[offset]] = "filled" if diagonals & (1 << index) else "empty"
			var tile_id: String = ["middle_pioint_single11", "middle_right_top_wall2",
				"middle_right_top_wall1", "straight_top_end"][diagonals]
			var angle: int = [90, 180, 180, 0][diagonals] + turn * 90
			cap_rules.append({"id": "connected_cap_%d_%d" % [turn, diagonals],
				"mask": [14, 7, 11, 13][turn], "neighbors": neighbors,
				"output": {"tile_id": tile_id, "rotation": posmod(angle, 360)}})
	for rule: Dictionary in rules.rules:
		if int(rule.mask) not in [14, 7, 11, 13]:
			cap_rules.append(rule)
	rules.rules = cap_rules
	var templates := {}
	for node: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		var transform_to_root := node.transform
		var parent := node.get_parent()
		while parent is Node3D and parent != source:
			transform_to_root = parent.transform * transform_to_root
			parent = parent.get_parent()
		transform_to_root = source.transform * transform_to_root
		transform_to_root.origin = Vector3.ZERO
		var bounds: AABB = transform_to_root * node.mesh.get_aabb()
		transform_to_root.basis = transform_to_root.basis.scaled(Vector3.ONE / maxf(bounds.size.x, bounds.size.z))
		var mesh := node.mesh.duplicate() as Mesh
		for surface in mesh.get_surface_count():
			mesh.surface_set_material(surface, material)
		templates[String(node.name)] = {"mesh": mesh, "transform": transform_to_root}
	# Source runtime aliases for model names absent from the FBX.
	templates["left_bottom_end"] = templates["left_middle"]
	templates["middle_pioint"] = templates["middle_pioint_single1"]
	# The catalog connector meshes are ramps across the join, rather than
	# level extensions of the path. Use the source's level straight piece.
	templates["corner_left_top_to_h"] = templates["straight"]
	templates["corner_left_top_to_v"] = templates["straight"]
	var single: Dictionary = templates["single"]
	var full_height: float = (single.transform * single.mesh.get_aabb()).size.y
	var outputs := []
	for mask: String in rules.fallback:
		var output: Dictionary = rules.fallback[mask].duplicate()
		output.seam_mask = int(mask)
		outputs.append(output)
	for rule in rules.rules:
		if rule.has("output"):
			var output: Dictionary = rule.output.duplicate()
			output.seam_mask = int(rule.mask)
			outputs.append(output)
	for connector in ["corner_left_top_to_h", "corner_left_top_to_v"]:
		for angle in [0, 180]:
			outputs.append({"tile_id": connector, "rotation": angle,
				"seam_mask": 10 if connector.ends_with("_h") else 5})
	var seam_masks := {}
	for output: Dictionary in outputs:
		var item_name := "%s_%d" % [output.tile_id, posmod(int(output.rotation), 360)]
		seam_masks[item_name] = int(seam_masks.get(item_name, 0)) | int(output.seam_mask)
	var library := MeshLibrary.new()
	library.resource_name = "Jam3D terrain pieces for Water Yang cell layouts"
	library.set_meta("neighbor_rules", rules)
	library.set_meta("source", "jam-3D/src/assets/wall.fbx + addons/wall_map/rules.json")
	library.set_meta("height_per_cell", full_height)
	var flower_surfaces := {}
	for output in outputs:
		var item_name := "%s_%d" % [output.tile_id, posmod(int(output.rotation), 360)]
		if library.find_item_by_name(item_name) >= 0:
			continue
		var mesh_name: String = rules.mesh_names.get(output.tile_id, output.tile_id)
		assert(templates.has(mesh_name), "Missing source terrain mesh: " + mesh_name)
		var template: Dictionary = templates[mesh_name]
		var model: Transform3D = template.transform
		var angle := float(output.rotation) - (90.0 if output.tile_id == "middle_right_top_point" else 0.0)
		if output.tile_id == "corner_left_top_to_v":
			angle += 90.0
		model = Transform3D(Basis(Vector3.UP, deg_to_rad(angle)), Vector3.ZERO) * model
		var bounds: AABB = model * template.mesh.get_aabb()
		# Preserve the source model's uniform XYZ scale. Align the thin middle
		# cap with full cliffs without flattening their original bevels/height.
		model.origin = Vector3(-bounds.get_center().x, full_height - bounds.end.y, -bounds.get_center().z)
		# Bake once, not at gameplay time. Raw FBX caps have slightly different
		# spans/heights; canonical seam coordinates prevent cracks and self-shadows.
		var corrected := ArrayMesh.new()
		var normal_basis := model.basis.inverse().transposed()
		var mirrored := model.basis.determinant() < 0.0
		for surface in template.mesh.get_surface_count():
			var arrays: Array = template.mesh.surface_get_arrays(surface).duplicate(true)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			for index in vertices.size():
				var point: Vector3 = model * vertices[index]
				var normal: Vector3 = (normal_basis * normals[index]).normalized()
				for axis in [0, 2]:
					if absf(absf(point[axis]) - 0.5) < 0.005:
						point[axis] = signf(point[axis]) * 0.5
						var side := (2 if point.x > 0.0 else 8) if axis == 0 else (4 if point.z > 0.0 else 1)
						var along := 2 if axis == 0 else 0
						if int(seam_masks[item_name]) & side and absf(point[along]) > 0.25 and point.y > full_height - 0.18 and normal.y > 0.04:
							# Shared edges use the straight source tile's five bevel
							# rings. Their original variants differ in radius, height
							# and normals, leaving hairline cracks and false shadows.
							var ring := 0 if normal.y > 0.99 else (1 if normal.y > 0.85 else (2 if normal.y > 0.45 else (3 if normal.y > 0.15 else 4)))
							if ring > 0 or absf(point[along]) < 0.45:
								point[along] = signf(point[along]) * float([0.35, 0.415625, 0.4625, 0.490625, 0.5][ring])
								point.y = full_height - float([0.0, 0.009375, 0.0375, 0.084375, 0.15][ring])
								var normal_y: float = [1.0, 0.94236, 0.707107, 0.33455, 0.07088][ring]
								normal = Vector3.UP * normal_y
								normal[along] = signf(point[along]) * sqrt(1.0 - normal_y * normal_y)
				if absf(point.y - full_height) < 0.005:
					point.y = full_height
					if normal.y > 0.99:
						normal = Vector3.UP
				vertices[index] = point
				normals[index] = normal
				if not tangents.is_empty():
					var tangent := (model.basis * Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])).normalized()
					tangents[index * 4] = tangent.x
					tangents[index * 4 + 1] = tangent.y
					tangents[index * 4 + 2] = tangent.z
					if mirrored:
						tangents[index * 4 + 3] = -tangents[index * 4 + 3]
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			if not tangents.is_empty():
				arrays[Mesh.ARRAY_TANGENT] = tangents
			if mirrored:
				# Baking a reflected source transform reverses triangle winding.
				# Restore front faces as well as tangent handedness before the
				# instance transform becomes identity; otherwise grass is culled.
				assert(template.mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for index in vertices.size():
						indices.append(index)
				for index in range(0, indices.size(), 3):
					var swap := indices[index + 1]
					indices[index + 1] = indices[index + 2]
					indices[index + 2] = swap
				arrays[Mesh.ARRAY_INDEX] = indices
			corrected.add_surface_from_arrays(template.mesh.surface_get_primitive_type(surface), arrays)
			corrected.surface_set_material(surface, material)
		model = Transform3D.IDENTITY
		var item_id := library.get_last_unused_item_id()
		library.create_item(item_id)
		library.set_item_name(item_id, item_name)
		library.set_item_mesh(item_id, corrected)
		library.set_item_mesh_transform(item_id, model)
		var normalized: AABB = corrected.get_aabb()
		assert(normalized.position.x >= -0.50001 and normalized.end.x <= 0.50001)
		assert(normalized.position.z >= -0.50001 and normalized.end.z <= 0.50001)
		# Godot expands a zero-thickness ArrayMesh AABB by 0.00001.
		assert(absf(normalized.end.y - full_height) < 0.00002, "%s cap=%s expected=%s" % [item_name, normalized.end.y, full_height])
		var triangles := []
		for surface_index in corrected.get_surface_count():
			var arrays: Array = corrected.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			# Preserve the source sampling order so fixing rendered winding does
			# not move deterministically placed flowers and grass.
			var indices: PackedInt32Array = template.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_INDEX]
			assert(normals.size() == vertices.size())
			if indices.is_empty():
				for vertex in vertices.size():
					indices.append(vertex)
			for index in range(0, indices.size(), 3):
				var normal: Vector3 = (normals[indices[index]] + normals[indices[index + 1]] + normals[indices[index + 2]]).normalized()
				if normal.y < 0.75:
					continue
				var a: Vector3 = vertices[indices[index]]
				var b: Vector3 = vertices[indices[index + 1]]
				var c: Vector3 = vertices[indices[index + 2]]
				var area := (b - a).cross(c - a).length() * 0.5
				if area > 0.00001:
					triangles.append({"a": a, "b": b, "c": c, "normal": normal, "area": area})
		flower_surfaces[item_id] = triangles
	library.set_meta("flower_surfaces", flower_surfaces)
	assert(ResourceSaver.save(library, "res://resources/terrain/jam3d/terrain_library.tres") == OK)
	print("TERRAIN LIBRARY: ", library.get_item_list().size(), " source variants; connected cap rules and bevel seams aligned; original height/width=", full_height, "; flower triangles baked")
	source.free()
	quit()
