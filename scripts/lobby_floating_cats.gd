extends Node3D

const CAT_ENTITY_SCENE: PackedScene = preload("res://scenes/cat_entity.tscn")
const CAT_WAKE_SHADER: Shader = preload("res://scripts/cat_wake.gdshader")
const MAX_WATER_CATS := 2

@export_group("Floating Cats")
@export_range(1, 1, 1) var cat_count := 1
@export_range(0.1, 20.0, 0.1) var travel_speed := 2.3
@export_range(0.0, 2.0, 0.01) var bob_height := 0.20
@export_range(0.1, 8.0, 0.05) var bob_speed := 1.15
@export_range(0.1, 20.0, 0.1) var cat_scale := 9.0
@export_range(0.0, 3.0, 0.01) var water_surface_offset := 1.05

const CAT_TINTS := [
	Color("f2a35e"),
	Color("7dc9ef"),
	Color("a9db77"),
	Color("dca3dc"),
]

var _stage_tints: Array[Color] = []
var _water_bounds := AABB()
var _route_x_min := 0.0
var _route_x_max := 0.0
var _cats: Array[Node3D] = []
var _cat_wakes: Array[MeshInstance3D] = []
var _cat_lanes: Array[float] = []
var _cat_travel_distances: Array[float] = []
var _next_stage_tint_index := 0
var _elapsed := 0.0


func _ready() -> void:
	# The web bridge pauses the scene tree while the outgame UI owns the lobby.
	# Keep these ambient actors, including CatEntity's face-expression timer,
	# active during that state.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for tint in CAT_TINTS:
		_stage_tints.append(tint)
	var water := get_node_or_null("../LobbyGround/Water/water1") as MeshInstance3D
	if water == null:
		push_error("[LobbyFloatingCats] water1 mesh was not found.")
		return
	_water_bounds = water.global_transform * water.get_aabb()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		push_error("[LobbyFloatingCats] active camera was not found.")
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var water_height := _water_bounds.position.y + water_surface_offset
	var left_origin := camera.project_ray_origin(Vector2(0.0, viewport_size.y * 0.5))
	var left_direction := camera.project_ray_normal(Vector2(0.0, viewport_size.y * 0.5))
	var right_origin := camera.project_ray_origin(Vector2(viewport_size.x, viewport_size.y * 0.5))
	var right_direction := camera.project_ray_normal(Vector2(viewport_size.x, viewport_size.y * 0.5))
	var left_distance := (water_height - left_origin.y) / left_direction.y
	var right_distance := (water_height - right_origin.y) / right_direction.y
	var route_padding := cat_scale * 0.7
	_route_x_min = left_origin.x + left_direction.x * left_distance - route_padding
	_route_x_max = right_origin.x + right_direction.x * right_distance + route_padding
	_create_cats()
	UiBridge.host_initialize.connect(func(stage_data: Dictionary) -> void:
		if not visible:
			return
		var stage_paths: Array[String] = []
		var levels_dir := DirAccess.open("res://resources/levels")
		if levels_dir == null:
			push_error("[LobbyFloatingCats] stage levels directory was not found.")
			return
		for file_name in levels_dir.get_files():
			if file_name.begins_with("stage_") and file_name.ends_with(".json"):
				stage_paths.append("res://resources/levels/" + file_name)
		stage_paths.sort()
		if stage_paths.is_empty():
			push_error("[LobbyFloatingCats] no stage files were found.")
			return
		var stage_index := clampi(int(stage_data.get("stage", 1)) - 1, 0, stage_paths.size() - 1)
		var level := LevelLayoutWriter.load_json(stage_paths[stage_index])
		var color_ids: Array[int] = []
		for cat_data in level.get("cats", []):
			var color_id := int(cat_data.get("color_id", -1))
			if color_id >= 0:
				color_ids.append(color_id)
		var level_manager := get_node_or_null("../LevelManager") as LevelManager
		if level_manager == null:
			push_error("[LobbyFloatingCats] LevelManager was not found.")
			return
		_stage_tints.clear()
		for color_id in color_ids:
			if color_id < level_manager.pair_colors.size():
				_stage_tints.append(level_manager.pair_colors[color_id])
		if _stage_tints.is_empty():
			push_error("[LobbyFloatingCats] stage %d has no usable cat colors." % (stage_index + 1))
			return
		cat_count = mini(_stage_tints.size(), MAX_WATER_CATS)
		_create_cats()
		_next_stage_tint_index = cat_count
	)


func _process(delta: float) -> void:
	_elapsed += delta
	for index in _cats.size():
		if index >= _cat_wakes.size():
			continue
		var cat := _cats[index]
		var wake := _cat_wakes[index]
		if not is_instance_valid(cat) or not cat.is_inside_tree() or not is_instance_valid(wake) or not wake.is_inside_tree():
			continue
		var phase := float(index) / float(_cats.size())
		var wave := _elapsed * bob_speed + phase * TAU
		var leg_wave := sin(_elapsed * 2.1 + phase * TAU)
		var route_width := _route_x_max - _route_x_min
		if is_zero_approx(route_width):
			var camera := get_viewport().get_camera_3d()
			var viewport_size := get_viewport().get_visible_rect().size
			if camera == null or viewport_size.x <= 0.0:
				return
			var water_height := _water_bounds.position.y + water_surface_offset
			var left_origin := camera.project_ray_origin(Vector2(0.0, viewport_size.y * 0.5))
			var left_direction := camera.project_ray_normal(Vector2(0.0, viewport_size.y * 0.5))
			var right_origin := camera.project_ray_origin(Vector2(viewport_size.x, viewport_size.y * 0.5))
			var right_direction := camera.project_ray_normal(Vector2(viewport_size.x, viewport_size.y * 0.5))
			var left_distance := (water_height - left_origin.y) / left_direction.y
			var right_distance := (water_height - right_origin.y) / right_direction.y
			var route_padding := cat_scale * 0.7
			_route_x_min = left_origin.x + left_direction.x * left_distance - route_padding
			_route_x_max = right_origin.x + right_direction.x * right_distance + route_padding
			route_width = _route_x_max - _route_x_min
			if is_zero_approx(route_width):
				return
		var travel_distance := fposmod(_elapsed * travel_speed + phase * route_width, route_width)
		if travel_distance < _cat_travel_distances[index] and _stage_tints.size() > cat_count:
			(cat as CatEntity).tint_color = _stage_tints[_next_stage_tint_index % _stage_tints.size()]
			_next_stage_tint_index += 1
		_cat_travel_distances[index] = travel_distance
		var flow_wave := sin(travel_distance / route_width * TAU * 1.35 + phase * PI) * 0.70
		cat.global_position.x = _route_x_min + travel_distance
		cat.global_position.y = _water_bounds.position.y + water_surface_offset + sin(wave) * bob_height
		cat.global_position.z = _cat_lanes[index] + flow_wave
		wake.global_position = Vector3(
			cat.global_position.x - 1.4,
			_water_bounds.position.y + 0.06,
			cat.global_position.z + leg_wave * 0.16
		)
		var wake_material := wake.material_override as ShaderMaterial
		wake_material.set_shader_parameter("leg_wave", leg_wave)
		# Do not assign Euler components around X=90°. That angle has an Euler
		# singularity and can re-express the same pose with a 180° head flip.
		var floating_rotation := Quaternion.from_euler(Vector3(deg_to_rad(90.0), deg_to_rad(90.0), 0.0))
		floating_rotation *= Quaternion(Vector3.RIGHT, sin(wave) * 0.07)
		floating_rotation *= Quaternion(Vector3.FORWARD, cos(wave) * 0.055)
		cat.quaternion = floating_rotation
		(cat as CatEntity).set_floating_water_wave(_elapsed, phase * TAU, 0.028)


func _create_cats() -> void:
	for cat in _cats:
		cat.queue_free()
	for wake in _cat_wakes:
		wake.queue_free()
	_cats.clear()
	_cat_wakes.clear()
	_cat_lanes.clear()
	_cat_travel_distances.clear()
	for index in cat_count:
		# Reuse the gameplay cat's face-texture swapping and toon/outline pipeline.
		# CatEntity's board-body setup is unnecessary here; only its skinned model
		# and idle expression processor are mounted on the floating actor.
		var cat := CAT_ENTITY_SCENE.instantiate() as CatEntity
		cat.name = "FloatingCat%d" % (index + 1)
		cat.tint_from_pair_color = false
		cat.tint_color = _stage_tints[index % _stage_tints.size()]
		cat.scale = Vector3.ONE * cat_scale
		# 원본의 긴 축은 이미 물길과 평행하다. X축으로 눕혀 물 위에 옆으로 뜨게 한다.
		cat.quaternion = Quaternion.from_euler(Vector3(deg_to_rad(90.0), deg_to_rad(90.0), 0.0))
		add_child(cat)
		var skinned_model := cat.load_model_with_texture()
		cat.add_child(skinned_model)
		var lane_z := lerpf(
			_water_bounds.position.z + _water_bounds.size.z * 0.43,
			_water_bounds.position.z + _water_bounds.size.z * 0.57,
			float(index) / maxf(float(cat_count - 1), 1.0)
		)
		cat.global_position = Vector3(
			_route_x_min,
			_water_bounds.position.y + water_surface_offset,
			lane_z
		)
		_cat_lanes.append(lane_z)
		_cat_travel_distances.append(0.0)
		_cats.append(cat)
		var wake := MeshInstance3D.new()
		wake.name = "FloatingCatWake%d" % (index + 1)
		var wake_mesh := PlaneMesh.new()
		wake_mesh.size = Vector2(9.0, 3.2)
		wake.mesh = wake_mesh
		var wake_material := ShaderMaterial.new()
		wake_material.shader = CAT_WAKE_SHADER
		wake_material.render_priority = 2
		wake_material.set_shader_parameter("wake_color", Color("8edce4"))
		wake.material_override = wake_material
		wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wake)
		_cat_wakes.append(wake)
