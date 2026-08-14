extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var scene := load("res://scenes/obstacle_tile_1x1.tscn") as PackedScene
	if scene == null:
		_failures.append("Failed to load obstacle scene")
		_report()
		return

	var obstacle := scene.instantiate() as Node3D
	root.add_child(obstacle)
	await process_frame

	if obstacle == null:
		_failures.append("Failed to instantiate obstacle scene")
		_report()
		return

	if not obstacle.has_method("apply_cell_style"):
		_failures.append("Obstacle scene missing apply_cell_style")
		_report()
		return

	obstacle.call("apply_cell_style", Vector2i.ZERO, Color.WHITE, 0.83)
	await process_frame

	var visual_height := float(obstacle.get("visual_height"))
	if absf(visual_height - 0.83) > 0.001:
		_failures.append("Obstacle visual_height did not receive apply_cell_style height")

	var model_root := obstacle.get_node_or_null("ObstacleModel") as Node3D
	if model_root == null:
		_failures.append("ObstacleModel missing under obstacle scene")
		_report()
		return

	var expected_y := 0.83 / 0.55
	if absf(model_root.scale.x - 1.0) > 0.001:
		_failures.append("Obstacle X scale changed unexpectedly")
	if absf(model_root.scale.y - expected_y) > 0.001:
		_failures.append("Obstacle Y scale did not follow obstacle_fbx_height")
	if absf(model_root.scale.z - 1.0) > 0.001:
		_failures.append("Obstacle Z scale changed unexpectedly")

	_report()


func _report() -> void:
	if _failures.is_empty():
		print("OBSTACLE HEIGHT SLIDER CHECK: PASS")
	else:
		print("OBSTACLE HEIGHT SLIDER CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
