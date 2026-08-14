extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	var scene := load("res://scenes/path_tile_1x1.tscn") as PackedScene
	if scene == null:
		_failures.append("Failed to load path tile scene")
		_report()
		return

	var default_tile := scene.instantiate() as Node3D
	var even_tile := scene.instantiate() as Node3D
	var odd_tile := scene.instantiate() as Node3D
	root.add_child(default_tile)
	root.add_child(even_tile)
	root.add_child(odd_tile)
	await process_frame

	if default_tile == null or even_tile == null or odd_tile == null:
		_failures.append("Failed to instantiate path tile scene")
		_report()
		return

	var default_material := _get_material(default_tile)
	if default_material == null:
		_failures.append("Default path tile shader material missing")
		_report()
		return

	var expected_tint := default_tile.get("tint_color") as Color
	var default_texture := load("res://water_yang/bg_road1_1.jpg") as Texture2D
	if default_material.get_shader_parameter("albedo_tex") != default_texture:
		_failures.append("Default path tile did not initialize bg_road1_1 before styling")
	if default_material.get_shader_parameter("tint_color") != expected_tint:
		_failures.append("Default path tile tint_color did not initialize from the scene setting")

	var preview_tint := Color(0.64, 0.79, 0.40, 1.0)
	even_tile.call("apply_cell_style", Vector2i.ZERO, preview_tint, 0.12)
	odd_tile.call("apply_cell_style", Vector2i(1, 0), preview_tint, 0.12)
	await process_frame

	var even_material := _get_material(even_tile)
	var odd_material := _get_material(odd_tile)
	if even_material == null or odd_material == null:
		_failures.append("Path tile shader material missing")
		_report()
		return

	var primary := load("res://water_yang/bg_road1_1.jpg") as Texture2D
	var secondary := load("res://water_yang/bg_road1_2.jpg") as Texture2D
	if even_material.get_shader_parameter("albedo_tex") != primary:
		_failures.append("Even path tile did not use bg_road1_1")
	if odd_material.get_shader_parameter("albedo_tex") != secondary:
		_failures.append("Odd path tile did not use bg_road1_2")
	if even_material.get_shader_parameter("tint_color") != expected_tint:
		_failures.append("Even path tile tint_color changed unexpectedly")
	if odd_material.get_shader_parameter("tint_color") != expected_tint:
		_failures.append("Odd path tile tint_color changed unexpectedly")

	_report()


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
		print("PATH TILE TEXTURE CHECK: PASS")
	else:
		print("PATH TILE TEXTURE CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
