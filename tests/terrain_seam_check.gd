extends Node

# Check every joined edge, including curved caps and narrow paths, on all
# authored maps. Fully filled 2x2 corners must also remain flat and covered.
# Rendering/shadow appearance is reviewed by the user, not this headless check.
func _ready() -> void:
	UiBridge.standalone_autostart = false
	UiBridge.is_hosted = true
	await get_tree().process_frame
	var library := load("res://resources/terrain/jam3d/terrain_library.tres") as MeshLibrary
	var height := float(library.get_meta("height_per_cell"))
	var profiles := {}
	var mesh_items := {}
	var surface_failures := []
	for item in library.get_item_list():
		var mesh := library.get_item_mesh(item)
		mesh_items[mesh] = item
		var model := library.get_item_mesh_transform(item)
		var faces := mesh.get_faces()
		# Boundary rays are two-sided and cannot detect backface-culled tops.
		# Require an upward-facing grass surface throughout every tile's core.
		for z in [-0.25, 0.0, 0.25]:
			for x in [-0.25, 0.0, 0.25]:
				var top := -INF
				for triangle in range(0, faces.size(), 3):
					var a := model * faces[triangle]
					var b := model * faces[triangle + 1]
					var c := model * faces[triangle + 2]
					# Godot front faces have clockwise winding.
					if (c - a).cross(b - a).y <= 0.0:
						continue
					var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 2.0, z), Vector3.DOWN, a, b, c)
					if hit is Vector3:
						top = maxf(top, hit.y)
				if not is_finite(top) or absf(top - height) > 0.0001:
					surface_failures.append(["missing front face", library.get_item_name(item), x, z, top])
		var sides := []
		for side: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var samples := []
			for sample in 25:
				var t := lerpf(-0.48, 0.48, float(sample) / 24.0)
				var x := side.x * 0.49999 if side.x != 0.0 else t
				var z := side.y * 0.49999 if side.y != 0.0 else t
				var top := -INF
				for triangle in range(0, faces.size(), 3):
					var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 2.0, z), Vector3.DOWN, model * faces[triangle], model * faces[triangle + 1], model * faces[triangle + 2])
					if hit is Vector3:
						top = maxf(top, hit.y)
				samples.append(top)
			sides.append(samples)
		profiles[item] = sides
		if library.get_item_name(item) == "middle_0":
			for point in faces:
				# get_faces() quantizes its triangle-cache coordinates to 0.0001.
				assert(absf((model * point).y - height) < 0.00006, "Interior grass is not flat")
		if library.get_item_name(item) == "middle_right_top_point_0":
			for top: float in sides[3]:
				assert(absf(top - height) < 0.0001, "Concave cap has a false cliff on its joined bottom edge")
	var scene := (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	scene.set_script(null)
	add_child(scene)
	var manager := scene.get_node("LevelManager") as LevelManager
	var pairs := {}
	var internal_gaps := []
	var stages := [0]
	for stage in range(1, 238):
		stages.append(stage)
	for stage in stages:
		if stage > 0:
			LevelLayoutWriter.apply_to_manager(manager, LevelLayoutWriter.load_json("res://resources/levels/stage_%03d.json" % stage))
		var terrain := manager.get_node("BoardVisuals/Terrain") as GridMap
		var cells := {}
		for cell in terrain.get_used_cells():
			cells[Vector2i(cell.x, cell.z)] = terrain.get_cell_item(cell)
		for visual: MeshInstance3D in manager.get_node("ObstacleVisuals").get_children():
			cells[manager.board_point_to_grid_cell(visual.position)] = mesh_items[visual.mesh]
		for cell: Vector2i in cells:
			for axis in 2:
				var neighbor: Vector2i = cell + (Vector2i.RIGHT if axis == 0 else Vector2i.DOWN)
				if cells.has(neighbor):
					pairs[Vector3i(axis, cells[cell], cells[neighbor])] = [stage, cell]
					var across := Vector2i.DOWN if axis == 0 else Vector2i.RIGHT
					for sign_value in [-1, 1]:
						if cells.has(cell + across * sign_value) and cells.has(neighbor + across * sign_value):
							for position in 2:
								var item: int = cells[cell] if position == 0 else cells[neighbor]
								var side := (1 if position == 0 else 0) if axis == 0 else (3 if position == 0 else 2)
								var sample: float = profiles[item][side][0 if sign_value < 0 else 24]
								if absf(sample - height) > 0.0001:
									internal_gaps.append([stage, str(cell), library.get_item_name(item), side, sign_value, sample])
		await get_tree().process_frame
	var maximum := 0.0
	var failures := []
	for pair: Vector3i in pairs:
		var first: Array = profiles[pair.y][1 if pair.x == 0 else 3]
		var second: Array = profiles[pair.z][0 if pair.x == 0 else 2]
		for sample in first.size():
			# Both sides may be air at the rounded outer edge of a narrow path.
			if not is_finite(first[sample]) or not is_finite(second[sample]):
				if first[sample] != second[sample]:
					failures.append(["coverage", library.get_item_name(pair.y), library.get_item_name(pair.z), pair.x, sample, pairs[pair]])
				continue
			var difference := absf(float(first[sample]) - float(second[sample]))
			maximum = maxf(maximum, difference)
			if difference > 0.0001:
				failures.append([library.get_item_name(pair.y), library.get_item_name(pair.z), pair.x, sample, difference, pairs[pair]])
	failures.append_array(internal_gaps)
	failures.append_array(surface_failures)
	print("TERRAIN SEAM CHECK: stages=", stages.size(), "; distinct joins=", pairs.size(), "; maximum height difference=", maximum, "; mismatched samples=", failures.size(), "; internal corner gaps=", internal_gaps.size(), "; missing front faces=", surface_failures.size())
	for index in mini(failures.size(), 12):
		print(failures[index])
	get_tree().quit(0 if failures.is_empty() else 1)
