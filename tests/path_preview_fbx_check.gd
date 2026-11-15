extends Node

var _failures: Array[String] = []


func _ready() -> void:
	UiBridge.standalone_autostart = false
	UiBridge.is_hosted = true
	var scene := load("res://scenes/main_scene.tscn") as PackedScene
	if scene == null:
		_failures.append("Failed to load main scene")
		_report()
		return

	var root_node := scene.instantiate()
	root_node.set_script(null)
	add_child(root_node)
	await get_tree().process_frame

	var manager := root_node.get_node_or_null("LevelManager") as LevelManager
	if manager == null:
		_failures.append("LevelManager missing")
		_report()
		return

	# Check the authored board and stages with different sizes/obstacle layouts.
	for stage in [0, 1, 33, 120, 237]:
		if stage != 0:
			LevelLayoutWriter.apply_to_manager(manager, LevelLayoutWriter.load_json("res://resources/levels/stage_%03d.json" % stage))
		await get_tree().process_frame
		var selected: CatEntity
		var move_target: Variant
		for candidate in manager.get_cats():
			candidate.set_process(false)
			if selected == null:
				move_target = _find_preview_target(candidate, manager)
				if move_target != null:
					selected = candidate
		if selected == null:
			_failures.append("Stage %d: no safe movement target" % stage)
			continue
		var static_geometry := {}
		for branch in ["BoardVisuals", "TileVisuals", "ObstacleVisuals", "OccupancyHighlights"]:
			for geometry: GeometryInstance3D in manager.get_node(branch).find_children("*", "GeometryInstance3D", true, false):
				static_geometry[geometry] = [geometry.global_transform, geometry.visible]
		selected.request_path_to(move_target)
		if selected.get_preview_path_cells().is_empty():
			_failures.append("Stage %d: movement queue did not populate" % stage)
		if manager.get_node("PathPreviewVisuals").get_child_count() != 0:
			_failures.append("Stage %d: legacy blocks appear before movement starts" % stage)
		for frame in 60:
			selected.advance(1.0 / 60.0)
			if manager.get_node("PathPreviewVisuals").get_child_count() != 0:
				_failures.append("Stage %d frame %d: legacy blocks cover terrain" % [stage, frame])
				break
			for geometry in static_geometry:
				if not is_instance_valid(geometry) or not geometry.is_inside_tree() or [geometry.global_transform, geometry.visible] != static_geometry[geometry]:
					_failures.append("Stage %d frame %d: static geometry changed during movement" % [stage, frame])
					break
		if selected.get_lead_cell() != move_target:
			_failures.append("Stage %d: cat did not reach requested cell" % stage)
		print("PATH PREVIEW stage=%d static_geometry=%d target=%s reached=%s" % [stage, static_geometry.size(), move_target, selected.get_lead_cell()])

	# Retain the optional FBX preview for boards using the original floor.
	manager.terrain_library = null
	manager.rebuild_now()

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

	var target: Variant = _find_preview_target(cat, manager)
	if target == null:
		_failures.append("Could not find a valid preview target")
		_report()
		return

	cat.request_path_to(target as Vector2i)

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

	if preview_root.get_child_count() != 0:
		_failures.append("Preview did not clear after starting drag from the non-draggable end")

	_report()


func _find_preview_target(cat: CatEntity, manager: LevelManager) -> Variant:
	for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		var cell: Vector2i = cat.get_lead_cell() + direction
		if not cat.can_enter(cell):
			continue
		var safe := manager.adjacent_hole(cell, cat.color_id) == null
		for body_cell in cat.body_cells:
			safe = safe and manager.adjacent_hole(body_cell, cat.color_id) == null
		if safe:
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
	get_tree().quit(0 if _failures.is_empty() else 1)
