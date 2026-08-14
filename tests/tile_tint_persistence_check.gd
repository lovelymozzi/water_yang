extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	await _check_scene(
		"res://scenes/path_tile_1x1.tscn",
		Color(0.31, 0.58, 0.44, 1.0),
		2.2
	)
	await _check_scene(
		"res://scenes/obstacle_tile_1x1.tscn",
		Color(0.74, 0.66, 0.43, 1.0),
		1.0
	)
	_report()


func _check_scene(scene_path: String, custom_tint: Color, expected_shadow_receive_strength: float) -> void:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		_failures.append("Failed to load %s" % scene_path)
		return

	var tile := scene.instantiate() as Node3D
	root.add_child(tile)
	await process_frame

	if tile == null:
		_failures.append("Failed to instantiate %s" % scene_path)
		return
	if not tile.has_method("apply_cell_style"):
		_failures.append("%s missing apply_cell_style" % scene_path)
		tile.queue_free()
		await process_frame
		return

	var material := _get_material(tile)
	if material == null:
		_failures.append("%s missing shader material" % scene_path)
		tile.queue_free()
		await process_frame
		return

	var scene_tint := tile.get("tint_color") as Color
	if not (material.get_shader_parameter("tint_color") as Color).is_equal_approx(scene_tint):
		_failures.append("%s did not initialize shader tint from the scene tint_color" % scene_path)

	var shadow_receive_strength := float(tile.get("shadow_receive_strength"))
	if absf(shadow_receive_strength - expected_shadow_receive_strength) > 0.001:
		_failures.append(
			"%s shadow_receive_strength was %s instead of %s"
			% [scene_path, shadow_receive_strength, expected_shadow_receive_strength]
		)

	tile.set("tint_color", custom_tint)
	await process_frame
	if not (tile.get("tint_color") as Color).is_equal_approx(custom_tint):
		_failures.append("%s root tint_color reset after editing" % scene_path)
	if not (material.get_shader_parameter("tint_color") as Color).is_equal_approx(custom_tint):
		_failures.append("%s shader tint_color did not follow the edited tint_color" % scene_path)

	var level_tint := Color(0.12, 0.73, 0.33, 1.0)
	tile.call("apply_cell_style", Vector2i(1, 0), level_tint, 0.34)
	await process_frame
	if not (tile.get("tint_color") as Color).is_equal_approx(custom_tint):
		_failures.append("%s root tint_color changed during apply_cell_style" % scene_path)
	if not (material.get_shader_parameter("tint_color") as Color).is_equal_approx(custom_tint):
		_failures.append("%s shader tint changed even though use_level_color_tint is off" % scene_path)

	tile.set("use_level_color_tint", true)
	tile.call("apply_cell_style", Vector2i(1, 0), level_tint, 0.34)
	await process_frame
	var expected_level_tint := custom_tint * level_tint
	if not (material.get_shader_parameter("tint_color") as Color).is_equal_approx(expected_level_tint):
		_failures.append("%s shader tint did not combine tint_color with the level tint" % scene_path)

	tile.queue_free()
	await process_frame


func _get_material(tile: Node3D) -> ShaderMaterial:
	var model := tile.get_node_or_null("ObstacleModel")
	if model == null:
		return null
	var mesh := _find_mesh(model)
	if mesh == null:
		return null
	return mesh.get_surface_override_material(0) as ShaderMaterial


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _report() -> void:
	if _failures.is_empty():
		print("TILE TINT PERSISTENCE CHECK: PASS")
	else:
		print("TILE TINT PERSISTENCE CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
