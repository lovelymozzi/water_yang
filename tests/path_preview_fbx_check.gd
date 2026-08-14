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

	var cats := manager.get_cats()
	if cats.is_empty():
		_failures.append("No runtime cats found")
		_report()
		return

	var cat := cats[0] as CatEntity
	if cat == null:
		_failures.append("First cat is invalid")
		_report()
		return

	cat.begin_drag(cat.get_tail_cell())
	await process_frame

	var target: Variant = _find_preview_target(cat, manager)
	if target == null:
		_failures.append("Could not find a valid preview target")
		_report()
		return

	cat.request_path_to(target as Vector2i)
	await process_frame

	var preview_cells := cat.get_preview_path_cells()
	if preview_cells.is_empty():
		_failures.append("Path queue did not populate after request_path_to")
		_report()
		return

	var preview_root := manager.get_node_or_null("PathPreviewVisuals") as Node3D
	if preview_root == null:
		_failures.append("PathPreviewVisuals missing")
		_report()
		return

	if preview_root.get_child_count() != preview_cells.size():
		_failures.append("Preview child count does not match queued path cells")

	var preview := preview_root.get_child(0) as Node3D if preview_root.get_child_count() > 0 else null
	if preview == null:
		_failures.append("No preview Node3D instances were created")
		_report()
		return

	if preview.scene_file_path != "res://scenes/path_tile_1x1.tscn":
		_failures.append("Preview scene is not res://scenes/path_tile_1x1.tscn")

	var visual_height := float(preview.get("visual_height"))
	if absf(visual_height - manager.path_preview_height) > 0.001:
		_failures.append("Preview visual_height did not follow LevelManager.path_preview_height")

	var model_root := preview.get_node_or_null("ObstacleModel") as Node3D
	if model_root == null:
		_failures.append("Preview ObstacleModel missing")
		_report()
		return

	if model_root.scene_file_path != "res://water_yang/path_tile_1x1.fbx":
		_failures.append("Preview model is not instanced from res://water_yang/path_tile_1x1.fbx")

	if _find_mesh(model_root) == null:
		_failures.append("Preview FBX mesh missing under ObstacleModel")

	cat.begin_drag(cat.get_head_cell())
	await process_frame

	if preview_root.get_child_count() != 0:
		_failures.append("Preview did not clear after starting drag from the non-draggable end")

	_report()


func _find_preview_target(cat: CatEntity, manager: LevelManager) -> Variant:
	for y in range(manager.grid_size.y):
		for x in range(manager.grid_size.x):
			var cell := Vector2i(x, y)
			cat.request_path_to(cell)
			if not cat.get_preview_path_cells().is_empty():
				return cell
	return null


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
		print("PATH PREVIEW FBX CHECK: PASS")
	else:
		print("PATH PREVIEW FBX CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
