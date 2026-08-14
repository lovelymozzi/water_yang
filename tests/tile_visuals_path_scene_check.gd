extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var scene := load("res://scenes/main_scene.tscn") as PackedScene
	if scene == null:
		_failures.append("Failed to load main scene")
		_report()
		return

	var root_node := scene.instantiate()
	root.add_child(root_node)
	await process_frame

	var manager := root_node.get_node_or_null("LevelManager") as LevelManager
	if manager == null:
		_failures.append("LevelManager missing")
		_report()
		return

	if manager.has_method("rebuild_now"):
		manager.call("rebuild_now")
	await process_frame

	var tiles_root := manager.get_node_or_null("TileVisuals") as Node3D
	if tiles_root == null:
		_failures.append("TileVisuals missing")
		_report()
		return

	var tile := _find_first_generated_tile(tiles_root)
	if tile == null:
		_failures.append("No generated Tile_* nodes found under TileVisuals")
		_report()
		return

	if tile.scene_file_path != "res://scenes/path_tile_1x1.tscn":
		_failures.append("TileVisuals is not instancing res://scenes/path_tile_1x1.tscn")

	var model_root := tile.get_node_or_null("ObstacleModel") as Node3D
	if model_root == null:
		_failures.append("%s missing ObstacleModel" % tile.name)
		_report()
		return

	if model_root.scene_file_path != "res://water_yang/path_tile_1x1.fbx":
		_failures.append("%s is not using res://water_yang/path_tile_1x1.fbx" % tile.name)

	var material := _get_material(tile)
	if material == null:
		_failures.append("%s shader material missing" % tile.name)
		_report()
		return

	var primary := load("res://water_yang/bg_road1_1.jpg") as Texture2D
	var secondary := load("res://water_yang/bg_road1_2.jpg") as Texture2D
	var expected_texture := primary
	var cell: Variant = _cell_from_tile_name(tile.name)
	if cell != null and ((cell.x + cell.y) % 2 != 0):
		expected_texture = secondary
	if material.get_shader_parameter("albedo_tex") != expected_texture:
		_failures.append("%s is not using the expected checker texture" % tile.name)

	_report()


func _find_first_generated_tile(tiles_root: Node3D) -> Node3D:
	for child in tiles_root.get_children():
		if child is Node3D and child.name.begins_with("Tile_"):
			return child as Node3D
	return null


func _cell_from_tile_name(tile_name: String) -> Variant:
	var parts := tile_name.split("_")
	if parts.size() != 3:
		return null
	return Vector2i(parts[1].to_int(), parts[2].to_int())


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
		print("TILE VISUALS PATH SCENE CHECK: PASS")
	else:
		print("TILE VISUALS PATH SCENE CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
