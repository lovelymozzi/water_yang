extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var scene := load("res://scenes/main_scene.tscn") as PackedScene
	if scene == null:
		_failures.append("Failed to load main scene")
		_report()
		return

	var scene_root := scene.instantiate() as Node3D
	root.add_child(scene_root)
	await process_frame

	var manager := scene_root.get_node_or_null("LevelManager") as LevelManager
	if manager == null:
		_failures.append("LevelManager missing")
		_report()
		return
	manager.rebuild_now()
	await process_frame

	var board := manager.get_node_or_null("BoardVisuals/BoardBase") as CSGPolygon3D
	if board == null:
		_failures.append("BoardBase missing")
	else:
		# CSGPolygon3D is centered on its depth axis.  Its top must remain at
		# or below the path tiles' base plane so it cannot occlude their shadow
		# receiver surfaces.
		var board_top := board.position.y + board.depth * 0.5
		if board_top > 0.001:
			_failures.append("BoardBase top (%0.3f) overlaps path tile receivers" % board_top)

	var tile := _find_first_generated_tile(manager.get_node_or_null("TileVisuals"))
	if tile == null:
		_failures.append("Generated path tile missing")
	else:
		var tile_mesh := _find_mesh(tile)
		if tile_mesh == null:
			_failures.append("Generated path tile mesh missing")
		else:
			if tile_mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				_failures.append("Generated path tile is not configured to cast shadows")
			var cats: Array[CatEntity] = manager.get_cats()
			if cats.is_empty():
				_failures.append("Generated cat missing")
			else:
				var cat: CatEntity = cats[0]
				if cat.get_node_or_null("BodyVisuals/ContactShadow") != null:
					_failures.append("Cat still has an artificial contact-shadow mesh")
				var cat_mesh := _find_mesh(cat.get_node_or_null("BodyVisuals/SkinnedCat"))
				if cat_mesh == null:
					_failures.append("Cat FBX mesh missing")
				elif cat_mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED:
					_failures.append("Cat FBX mesh is not configured to cast real shadows")

	_report()


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _find_first_generated_tile(root_node: Node) -> Node3D:
	if root_node == null:
		return null
	for child in root_node.get_children():
		if child is Node3D and child.name.begins_with("Tile_"):
			return child as Node3D
	return null


func _report() -> void:
	if _failures.is_empty():
		print("BOARD/PATH SHADOW SEPARATION CHECK: PASS")
	else:
		print("BOARD/PATH SHADOW SEPARATION CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
