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

	var manager := root_node.get_node_or_null("LevelManager")
	if manager == null:
		_failures.append("LevelManager missing")
		_report()
		return

	if manager.has_method("rebuild_now"):
		manager.call("rebuild_now")
	await process_frame

	var board_visuals := manager.get_node_or_null("BoardVisuals")
	if board_visuals == null:
		_failures.append("BoardVisuals missing")
		_report()
		return

	var board_base := board_visuals.get_node_or_null("BoardBase")
	if board_base == null:
		_failures.append("BoardBase missing")
		_report()
		return

	var material := board_base.get("material") as StandardMaterial3D
	if material == null:
		_failures.append("BoardBase material missing")
		_report()
		return

	var expected_texture := load("res://water_yang/bg_tile1_1.jpg") as Texture2D
	if material.albedo_texture != expected_texture:
		_failures.append("BoardBase albedo texture mismatch")
	if not material.texture_repeat:
		_failures.append("BoardBase texture repeat not enabled")
	if material.uv1_scale.x <= 1.0:
		_failures.append("BoardBase uv1_scale.x did not tile")
	if material.uv1_scale.y <= 1.0:
		_failures.append("BoardBase uv1_scale.y did not tile")

	_report()


func _report() -> void:
	if _failures.is_empty():
		print("BOARD VISUAL TEXTURE CHECK: PASS")
	else:
		print("BOARD VISUAL TEXTURE CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
