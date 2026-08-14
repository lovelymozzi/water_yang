extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var scene := load("res://scenes/path_tile_1x1.tscn") as PackedScene
	if scene == null:
		_failures.append("Failed to load path tile scene")
		_report()
		return

	var tile := scene.instantiate() as Node3D
	root.add_child(tile)
	await process_frame

	var tile_mesh := _find_mesh(tile.get_node_or_null("ObstacleModel"))
	if tile_mesh == null:
		_failures.append("Path tile mesh missing")
	else:
		if tile_mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			_failures.append("Path tile default cast_shadow is not ON")

	var preview_tile := scene.instantiate() as Node3D
	root.add_child(preview_tile)
	await process_frame
	preview_tile.set("cast_shadow", false)
	await process_frame
	var preview_mesh := _find_mesh(preview_tile.get_node_or_null("ObstacleModel"))
	if preview_mesh == null:
		_failures.append("Preview path tile mesh missing")
	elif preview_mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_failures.append("Preview path tile cast_shadow is not OFF after override")

	_report()


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	if node == null:
		return null
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _report() -> void:
	if _failures.is_empty():
		print("PATH TILE SHADOW CHECK: PASS")
	else:
		print("PATH TILE SHADOW CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
