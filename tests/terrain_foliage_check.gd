extends Node

func _ready() -> void:
	UiBridge.standalone_autostart = false
	UiBridge.is_hosted = true
	await get_tree().process_frame
	var scene := (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	scene.set_script(null)
	var authored_grass := {}
	for decoration in scene.get_node("LevelManager/TileVisuals").get_children():
		if decoration.scene_file_path == "res://scenes/grass_decor.tscn":
			authored_grass[decoration.name] = decoration.basis
	add_child(scene)
	var manager := scene.get_node("LevelManager") as LevelManager
	assert(scene.get_node("DirectionalLight3D").shadow_enabled)
	assert(is_equal_approx(scene.get_node("DirectionalLight3D").shadow_opacity, 0.55))
	assert(not manager.get_node("TileVisuals/TreeShadowDecor").visible, "Only the real tree shadows should shade gameplay")
	var source := (load("res://water_yang/grass1.fbx") as PackedScene).instantiate()
	var source_mesh := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var model := source_mesh.transform
	var model_parent := source_mesh.get_parent()
	while model_parent is Node3D:
		model = model_parent.transform * model
		model_parent = model_parent.get_parent()
	var model_bounds := model * source_mesh.mesh.get_aabb()
	var local_root := model.affine_inverse() * Vector3(model_bounds.get_center().x, model_bounds.position.y, model_bounds.get_center().z)
	source.free()
	# Counts before thinning and seam repairs. Correcting cap geometry changes
	# the accepted flower area slightly; coverage must stay within five percent.
	var before := {0: Vector2i(222, 372), 1: Vector2i(142, 231), 33: Vector2i(236, 401), 52: Vector2i(209, 341), 57: Vector2i(235, 390)}
	for stage: int in before:
		if stage > 0:
			LevelLayoutWriter.apply_to_manager(manager, LevelLayoutWriter.load_json("res://resources/levels/stage_%03d.json" % stage))
		var terrain := manager.get_node("BoardVisuals/Terrain") as GridMap
		var flowers := terrain.get_node("Flowers") as MultiMeshInstance3D
		var grass := terrain.get_node("Grass") as MultiMeshInstance3D
		print("FOLIAGE COVERAGE stage=", stage, " flowers=", flowers.multimesh.instance_count, " grass=", grass.multimesh.instance_count, " exterior cells=", terrain.get_used_cells().size())
		assert(absi(flowers.multimesh.instance_count - before[stage].x) <= ceili(before[stage].x * 0.05), "Terrain seam repairs unexpectedly changed flower coverage")
		assert(grass.multimesh.instance_count > 0 and grass.multimesh.instance_count < before[stage].y * 0.45, "Grass was not substantially reduced")
		var roots: Array[Vector2] = []
		var placements: Array[Transform3D] = []
		for instance in grass.multimesh.instance_count:
			var placement: Transform3D = grass.multimesh.get_meta("terrain_instance_transforms")[instance]
			placements.append(placement)
			var position := placement * local_root
			var root_position := Vector2(position.x, position.z)
			for previous_root in roots:
				var offset := root_position - previous_root
				assert(offset.length() >= 0.648, "Grass roots too close: %s vs %s, distance=%f, local root=%s" % [root_position, previous_root, offset.length(), local_root])
				assert(absf(offset.x) >= 0.218 or absf(offset.y) >= 1.798, "Nearby grass clumps form vertical columns")
			roots.append(root_position)
		assert(flowers.material_override == load("res://resources/terrain/jam3d/flower_material.tres"))
		assert(grass.material_override == load("res://resources/gameplay_grass_material.tres"))
		for batch in [flowers, grass]:
			assert(batch.multimesh.custom_aabb.size.length() > 1.0, "Missing instancing bounds")
		var counts := Vector2i(flowers.multimesh.instance_count, grass.multimesh.instance_count)
		var bounds := grass.multimesh.custom_aabb
		print("FOLIAGE BOUNDS stage=", stage, " bounds=", var_to_str(bounds))
		manager.rebuild_now()
		assert((manager.get_node("BoardVisuals/Terrain/Flowers") as MultiMeshInstance3D).multimesh.instance_count == counts.x)
		var repeated := manager.get_node("BoardVisuals/Terrain/Grass") as MultiMeshInstance3D
		assert(repeated.multimesh.instance_count == counts.y)
		assert(repeated.multimesh.custom_aabb.is_equal_approx(bounds), "Foliage is not deterministic")
		for instance in placements.size():
			assert((repeated.multimesh.get_meta("terrain_instance_transforms")[instance] as Transform3D).is_equal_approx(placements[instance]), "Grass placements change on rebuild")
		for grass_name in authored_grass:
			var decoration := manager.get_node("TileVisuals/" + String(grass_name)) as Node3D
			var original: Basis = authored_grass[grass_name].transposed()
			var actual := decoration.basis.transposed()
			assert(actual.x.is_equal_approx(original.x) and actual.z.is_equal_approx(original.z), "Grass width or footprint changed")
			assert(actual.y.is_equal_approx(original.y * 1.65), "Grass height is incorrect or compounds on rebuild")
		print("FOLIAGE stage=", stage, " flowers=", counts.x, "; grass=", counts.y, " (before ", before[stage].y, "); spacing and stagger checked")
		await get_tree().process_frame
	var material := load("res://resources/gameplay_grass_material.tres") as ShaderMaterial
	var lobby := load("res://resources/lobby_grass_material.tres") as ShaderMaterial
	var terrain_material := load("res://resources/terrain/jam3d/wall_material.tres") as StandardMaterial3D
	assert(material.get_shader_parameter("albedo_texture") == terrain_material.albedo_texture, "Grass must retain the terrain texture")
	assert(material.get_shader_parameter("albedo_tint") == terrain_material.albedo_color)
	assert(material.get_shader_parameter("grass_use_texture_color"), "Grass texture detail must remain enabled")
	for grass_pass: ShaderMaterial in [material, material.next_pass]:
		assert(is_equal_approx(grass_pass.get_shader_parameter("grass_wind_strength"), lobby.get_shader_parameter("grass_wind_strength")))
		assert(grass_pass.get_shader_parameter("grass_wind_use_engine_time"))
	for grass_pass: ShaderMaterial in [lobby, lobby.next_pass]:
		assert(not grass_pass.get_shader_parameter("grass_wind_use_engine_time"), "Lobby must retain its existing clock")
	print("TERRAIN FOLIAGE CHECK: PASS sparse staggered grass, stable flower coverage, authored grass poses, stable rebuilds, shadows, palette and wind")
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit()
