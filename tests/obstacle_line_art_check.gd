extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var scene := load("res://scenes/obstacle_tile_1x1.tscn") as PackedScene
	if scene == null:
		_failures.append("Failed to load obstacle scene")
		_report()
		return

	var node := scene.instantiate()
	root.add_child(node)
	if node == null:
		_failures.append("Failed to instantiate obstacle scene")
		_report()
		return

	if not node.has_method("apply_cell_style"):
		_failures.append("Obstacle scene missing apply_cell_style")
		_report()
		return

	node.set("line_art_enabled", 0.37)
	node.set("line_art_color", Color(0.52, 0.18, 0.12, 1.0))
	node.set("line_art_strength", 0.64)
	node.call("apply_cell_style", Vector2i(0, 0), Color.WHITE)
	await process_frame

	var model := node.get_node_or_null("ObstacleModel")
	if model == null:
		_failures.append("ObstacleModel missing")
		_report()
		return

	var mesh_instance := _find_mesh(model)
	if mesh_instance == null:
		_failures.append("MeshInstance3D missing under ObstacleModel")
		_report()
		return

	var mat := mesh_instance.get_surface_override_material(0) as ShaderMaterial
	if mat == null:
		_failures.append("Obstacle shader material missing")
		_report()
		return
	var outline_mat := mat.next_pass as ShaderMaterial
	if outline_mat == null:
		_failures.append("Obstacle outline shader material missing")
		_report()
		return

	var line_enabled = float(mat.get_shader_parameter("line_art_enabled"))
	var line_strength = float(mat.get_shader_parameter("line_art_strength"))
	var line_color = mat.get_shader_parameter("line_art_color")
	var outline_line_enabled = float(outline_mat.get_shader_parameter("line_art_enabled"))
	var outline_line_strength = float(outline_mat.get_shader_parameter("line_art_strength"))
	var outline_line_color = outline_mat.get_shader_parameter("line_art_color")
	if absf(line_enabled - 0.37) > 0.001:
		_failures.append("line_art_enabled shader parameter mismatch")
	if absf(line_strength - 0.64) > 0.001:
		_failures.append("line_art_strength shader parameter mismatch")
	if line_color != Color(0.52, 0.18, 0.12, 1.0):
		_failures.append("line_art_color shader parameter mismatch")
	if absf(outline_line_enabled - 0.37) > 0.001:
		_failures.append("outline line_art_enabled shader parameter mismatch")
	if absf(outline_line_strength - 0.64) > 0.001:
		_failures.append("outline line_art_strength shader parameter mismatch")
	if outline_line_color != Color(0.52, 0.18, 0.12, 1.0):
		_failures.append("outline line_art_color shader parameter mismatch")

	_report()


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
		print("OBSTACLE LINE ART CHECK: PASS")
	else:
		print("OBSTACLE LINE ART CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
