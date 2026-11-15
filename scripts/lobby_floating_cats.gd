extends Node3D

const CAT_ENTITY_SCENE: PackedScene = preload("res://scenes/cat_entity.tscn")
const CAT_WAKE_SHADER: Shader = preload("res://scripts/cat_wake.gdshader")
const WAKE_FIELD = preload("res://scripts/lobby_wake_field.gd")
const WATER_MATERIAL: ShaderMaterial = preload("res://resources/lobby_water_material.tres")
const GRASS_MATERIAL: ShaderMaterial = preload("res://resources/lobby_grass_material.tres")
const MAX_WATER_CATS := 2

@export_group("Floating Cats")
@export_range(1, 1, 1) var cat_count := 1
@export_range(0.1, 20.0, 0.1) var travel_speed := 0.65
@export_range(0.0, 2.0, 0.01) var bob_height := 0.06
@export_range(0.1, 8.0, 0.05) var bob_speed := 0.7
@export_range(0.1, 20.0, 0.1) var cat_scale := 9.0
@export_range(0.0, 3.0, 0.01) var water_surface_offset := 0.07

const CAT_TINTS := [
	Color("ffcd7a"),
	Color("91def1"),
	Color("cbed86"),
	Color("e8bee1"),
]

var _stage_tints: Array[Color] = []
var _water_bounds := AABB()
var _route_x_min := 0.0
var _route_x_max := 0.0
var _cats: Array[Node3D] = []
var _cat_wakes: Array[MeshInstance3D] = []
var _wake_fields: Array = []
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
				_stage_tints.append(level_manager.get_pair_color(color_id))
		if _stage_tints.is_empty():
			push_error("[LobbyFloatingCats] stage %d has no usable cat colors." % (stage_index + 1))
			return
		cat_count = mini(_stage_tints.size(), MAX_WATER_CATS)
		_create_cats()
		_next_stage_tint_index = cat_count
	)


func _process(delta: float) -> void:
	_elapsed += delta
	# Ambient water keeps moving when the cats stop or UI pauses the tree.
	# Both layers use this clock, including fixed-step render captures.
	var water_time := float(WATER_MATERIAL.get_shader_parameter("water_motion_time")) + delta
	WATER_MATERIAL.set_shader_parameter("water_motion_time", water_time)
	(get_node("../UnderwaterIllustration").material_override as ShaderMaterial).set_shader_parameter("water_motion_time", water_time)
	(get_node("../Camera3D/Sunlight").material_override as ShaderMaterial).set_shader_parameter("sunlight_time", water_time)
	(get_node("../Camera3D/SunDust").mesh.material as ShaderMaterial).set_shader_parameter("sunlight_time", water_time)
	GRASS_MATERIAL.set_shader_parameter("grass_wind_time", water_time)
	(GRASS_MATERIAL.next_pass as ShaderMaterial).set_shader_parameter("grass_wind_time", water_time)
	for index in _cats.size():
		if index >= _cat_wakes.size():
			continue
		var cat := _cats[index]
		var wake := _cat_wakes[index]
		if not is_instance_valid(cat) or not cat.is_inside_tree() or not is_instance_valid(wake) or not wake.is_inside_tree():
			continue
		var phase := float(index) / float(_cats.size())
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
		var travel_distance := fposmod(_cat_travel_distances[index] + travel_speed * delta, route_width)
		if travel_distance < _cat_travel_distances[index] and _stage_tints.size() > cat_count:
			(cat as CatEntity).tint_color = _stage_tints[_next_stage_tint_index % _stage_tints.size()]
			_next_stage_tint_index += 1
		_cat_travel_distances[index] = travel_distance
		var flow_wave := sin(travel_distance / route_width * TAU * 1.35 + phase * PI) * 0.70
		var wake_material := wake.material_override as ShaderMaterial
		var velocity := Vector2(travel_speed, cos(travel_distance / route_width * TAU * 1.35 + phase * PI) * 0.70 * TAU * 1.35 * travel_speed / route_width)
		var distance := float(wake_material.get_shader_parameter("flow_distance")) + velocity.length() * delta
		# The rig that displaces water must slow and stop with its movement.
		# Use accumulated distance; changing speed never jumps its pose.
		var motion_time := distance / 0.65
		var wave := motion_time * bob_speed + phase * TAU
		cat.global_position.x = _route_x_min + travel_distance
		cat.global_position.y = _water_bounds.position.y + water_surface_offset + sin(wave) * bob_height
		cat.global_position.z = _cat_lanes[index] + flow_wave
		wake.global_position.y = _water_bounds.position.y + 0.06
		wake_material.set_shader_parameter("flow_velocity", -velocity)
		# Integrate travel instead of multiplying the current speed by all past
		# time: changing speed must not jump the wave phase.
		wake_material.set_shader_parameter("flow_distance", distance)
		# Do not assign Euler components around X=90°. That angle has an Euler
		# singularity and can re-express the same pose with a 180° head flip.
		var floating_rotation := Quaternion.from_euler(Vector3(deg_to_rad(90.0), deg_to_rad(90.0), 0.0))
		floating_rotation *= Quaternion(Vector3.RIGHT, sin(wave) * 0.025)
		floating_rotation *= Quaternion(Vector3.FORWARD, cos(wave) * 0.020)
		cat.quaternion = floating_rotation
		(cat as CatEntity).set_floating_water_wave(_elapsed, phase * TAU + (motion_time - _elapsed) * 2.1, 0.012, wake_material)
		var body_points: PackedVector2Array = wake_material.get_shader_parameter("body_points")
		var body_radii: PackedFloat32Array = wake_material.get_shader_parameter("body_radii")
		var body_width: float = wake_material.get_shader_parameter("body_width")
		var field = _wake_fields[index]
		field.step(delta, (cat as CatEntity)._floating_water_sections, body_width, velocity, (cat as CatEntity)._floating_section_velocities, (cat as CatEntity)._floating_section_incidence)
		wake_material.set_shader_parameter("flow_origin", field.center)
		for material in [wake_material, (cat as CatEntity)._outline_material, (cat as CatEntity)._material_id_2_outline]:
			material.set_shader_parameter("flow_distance", wake_material.get_shader_parameter("flow_distance"))
			material.set_shader_parameter("flow_velocity", -field.source_velocity)
		var footprint := Rect2(body_points[0], Vector2.ZERO)
		for point_index in body_points.size():
			var padding := Vector2.ONE * (body_radii[point_index] * cat_scale + body_width * 0.85)
			footprint = footprint.expand(body_points[point_index] - padding)
			footprint = footprint.expand(body_points[point_index] + padding)
		for section in field.sections:
			for point in section:
				footprint = footprint.expand(point - Vector2.ONE * body_width * 0.12)
				footprint = footprint.expand(point + Vector2.ONE * body_width * 0.12)
		for strand in WAKE_FIELD.CAPACITY:
			if field.lifetimes[strand] <= 0.0:
				continue
			for point in field.strands[strand]:
				footprint = footprint.expand(point - Vector2.ONE * body_width * 0.28)
				footprint = footprint.expand(point + Vector2.ONE * body_width * 0.28)
		wake.global_position.x = footprint.get_center().x
		wake.global_position.z = footprint.get_center().y
		var mesh := wake.mesh as ImmediateMesh
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var shadow_corners := [Vector2.ZERO, Vector2(1.0, 0.0), Vector2.ONE, Vector2(0.0, 1.0)]
		for corner in [0, 1, 2, 0, 2, 3]:
			var position: Vector2 = shadow_corners[corner] * footprint.size - footprint.size * 0.5
			mesh.surface_set_color(Color.WHITE)
			mesh.surface_set_uv(shadow_corners[corner])
			mesh.surface_set_uv2(Vector2.ZERO)
			mesh.surface_add_vertex(Vector3(position.x, 0.0, position.y))
		# Meniscus/bow compression lies on the actual mesh/plane intersection.
		# This replaces the old camera-projected full-body foam shell.
		var panel_slips := PackedFloat32Array()
		panel_slips.resize(field.panel_starts.size())
		var heading := velocity.normalized()
		if velocity.length_squared() > 0.000001:
			# Sample on the solved panels and interpolate along contact arcs.
			# Re-evaluating the full flow at every tiny triangle cut is costly.
			for panel in field.panel_starts.size():
				var point: Vector2 = (field.panel_starts[panel] + field.panel_ends[panel]) * 0.5
				var tangent: Vector2 = (field.panel_ends[panel] - field.panel_starts[panel]).normalized()
				var local_flow: Vector2 = field.sample_velocity(point + field.panel_normals[panel] * body_width * 0.018)
				panel_slips[panel] = absf((local_flow - field.panel_velocities[panel]).dot(tangent)) / velocity.length()
		for section_index in field.sections.size():
			var section: PackedVector2Array = field.sections[section_index]
			var panel_start: int = field.section_panel_offsets[section_index]
			var panel_count: int = field.section_panel_offsets[section_index + 1] - panel_start
			var perimeter := 0.0
			var twice_area := 0.0
			for endpoint in section.size():
				perimeter += section[endpoint].distance_to(section[(endpoint + 1) % section.size()])
				twice_area += (section[endpoint] - section[0]).cross(section[(endpoint + 1) % section.size()] - section[0])
			var section_width := minf(body_width, absf(twice_area) * 2.0 / perimeter)
			var section_normals := PackedVector2Array()
			var contact_scales := PackedFloat32Array()
			var side_strengths := PackedFloat32Array()
			var contact_arc := 0.0
			# Smooth over an actual arc length, so tiny triangle cuts cannot
			# launch a long spike at a paw/body contact corner.
			for endpoint in section.size():
				var neighbors := PackedVector2Array()
				for direction in [-1, 1]:
					var remaining := minf(body_width * 0.035, perimeter * 0.1)
					var cursor := endpoint
					for edge in section.size():
						var next := posmod(cursor + direction, section.size())
						var length := section[cursor].distance_to(section[next])
						if remaining <= length:
							neighbors.append(section[cursor].lerp(section[next], remaining / maxf(length, 0.000001)))
							break
						remaining -= length
						cursor = next
				var tangent := (neighbors[1] - neighbors[0]).normalized()
				var normal := Vector2(tangent.y, -tangent.x)
				section_normals.append(normal)
				# The contact ribbon needs the same local sizing as shed foam.
				# A circumcircle through arc neighbors measures the bend diameter;
				# straight flanks retain their section width, tight paw bends shrink.
				var before := neighbors[0] - section[endpoint]
				var after := neighbors[1] - section[endpoint]
				var bend_diameter := before.length() * after.length() * neighbors[0].distance_to(neighbors[1]) / maxf(absf(before.cross(after)), body_width * body_width * 0.000001)
				contact_scales.append(minf(section_width, bend_diameter))
				var panel_coordinate := contact_arc / perimeter * panel_count - 0.5
				var left := floori(panel_coordinate)
				var slip := lerpf(panel_slips[panel_start + posmod(left, panel_count)], panel_slips[panel_start + posmod(left + 1, panel_count)], fposmod(panel_coordinate, 1.0))
				var flank := 1.0 - pow(absf(normal.dot(heading)), 2.0)
				side_strengths.append(smoothstep(0.1, 1.2, slip) * flank)
				contact_arc += section[endpoint].distance_to(section[(endpoint + 1) % section.size()])
			for segment in section.size():
				var corners: Array[Vector2] = []
				for endpoint in [segment, (segment + 1) % section.size()]:
					var normal := section_normals[endpoint]
					var wall_velocity: Vector2 = field.section_velocities[section_index][endpoint]
					var alignment: float = field.section_incidence[section_index][endpoint]
					var incident := clampf(wall_velocity.dot(normal) * alignment / maxf(velocity.length(), 0.001), 0.0, 1.0)
					var thickness := contact_scales[endpoint] * (0.004 + incident * incident * 0.055) * smoothstep(0.03, 0.65, velocity.length())
					corners.append(section[endpoint] + normal * contact_scales[endpoint] * 0.001)
					corners.append(section[endpoint] + normal * thickness)
				for corner in [0, 1, 2, 1, 3, 2]:
					var position := corners[corner] - footprint.get_center()
					mesh.surface_set_color(Color(0.0, 0.0, 0.0, smoothstep(0.02, 0.5, velocity.length()) * 0.42))
					mesh.surface_set_uv(Vector2(0.5, float(corner % 2)))
					mesh.surface_add_vertex(Vector3(position.x, 0.004, position.y))
				# A translucent water shoulder connects bow compression to the
				# flanks on the live mesh contact, driven by tangential fluid slip.
				corners.clear()
				for endpoint in [segment, (segment + 1) % section.size()]:
					var normal := section_normals[endpoint]
					var width := contact_scales[endpoint] * (0.055 + side_strengths[endpoint] * 0.10)
					corners.append(section[endpoint] + normal * contact_scales[endpoint] * 0.004)
					corners.append(section[endpoint] + normal * width)
				for corner in [0, 1, 2, 1, 3, 2]:
					var endpoint: int = segment if corner < 2 else (segment + 1) % section.size()
					var position := corners[corner] - footprint.get_center()
					var strength := side_strengths[endpoint] * smoothstep(0.03, 0.65, velocity.length())
					mesh.surface_set_color(Color(1.0, 0.0, 0.0, strength * 0.48))
					mesh.surface_set_uv(Vector2(0.5, float(corner % 2)))
					mesh.surface_add_vertex(Vector3(position.x, 0.005, position.y))
		for strand in WAKE_FIELD.CAPACITY:
			if field.lifetimes[strand] <= 0.0:
				continue
			var curve: PackedVector2Array = field.strands[strand]
			var age: float = field.ages[strand]
			var life: float = field.lifetimes[strand]
			var alpha: float = smoothstep(0.0, 0.08, age) * field.opacities[strand] * (1.0 - smoothstep(life - 0.35, life, age))
			var widths: PackedFloat32Array = field.thicknesses[strand]
			var normals: PackedVector2Array = field.strand_normals[strand]
			# Round the rendered sheet without changing the advected material
			# markers, their births, or their velocities. Bound spline overshoot.
			var render_curve := PackedVector2Array()
			var render_offsets := PackedVector2Array()
			for sample_index in (WAKE_FIELD.SAMPLES - 1) * 4 + 1:
				var coordinate := float(sample_index) / 4.0
				var segment := mini(floori(coordinate), WAKE_FIELD.SAMPLES - 2)
				var t := coordinate - float(segment)
				var previous := maxi(segment - 1, 0)
				var next := mini(segment + 2, WAKE_FIELD.SAMPLES - 1)
				var linear := curve[segment].lerp(curve[segment + 1], t)
				var rounded := curve[segment].cubic_interpolate(curve[segment + 1], curve[previous], curve[next], t)
				render_curve.append(linear + (rounded - linear).limit_length(body_width * 0.025))
				var width := clampf(cubic_interpolate(widths[segment], widths[segment + 1], widths[previous], widths[next], t), 0.0, maxf(widths[segment], widths[segment + 1]))
				# Interpolate the offset vector, not its angle: almost opposite
				# material normals must pinch smoothly instead of flipping arcs.
				var offset := (normals[segment] * widths[segment] * 2.0).cubic_interpolate(normals[segment + 1] * widths[segment + 1] * 2.0, normals[previous] * widths[previous] * 2.0, normals[next] * widths[next] * 2.0, t)
				render_offsets.append(offset.limit_length(width * 2.0))
			for segment in render_curve.size() - 1:
				var corners: Array[Vector2] = []
				for endpoint in [segment, segment + 1]:
					# The material sheet occupies the waterward side of its
					# crest, rather than losing half its width inside the body.
					corners.append(render_curve[endpoint])
					corners.append(render_curve[endpoint] + render_offsets[endpoint])
				for corner in [0, 1, 2, 1, 3, 2]:
					var position := corners[corner] - footprint.get_center()
					mesh.surface_set_color(Color(0.0, 0.0, 0.0, alpha))
					var endpoint: int = segment if corner < 2 else segment + 1
					mesh.surface_set_uv(Vector2(float(endpoint) / float(render_curve.size() - 1), float(corner % 2)))
					mesh.surface_add_vertex(Vector3(position.x, 0.006, position.y))
		mesh.surface_end()
		if index == 0:
			var water := get_node("../LobbyGround/Water/water1") as MeshInstance3D
			(water.material_override as ShaderMaterial).set_shader_parameter("foam_reference_width", body_width)


func _create_cats() -> void:
	for cat in _cats:
		cat.queue_free()
	for wake in _cat_wakes:
		wake.queue_free()
	_cats.clear()
	_cat_wakes.clear()
	_wake_fields.clear()
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
		for outline in [cat._outline_material, cat._material_id_2_outline]:
			outline.set_shader_parameter("water_foam_color", Color("9af6d4"))
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
		_cat_travel_distances.append(float(index) / float(cat_count) * (_route_x_max - _route_x_min))
		_cats.append(cat)
		var wake := MeshInstance3D.new()
		wake.name = "FloatingCatWake%d" % (index + 1)
		var wake_mesh := ImmediateMesh.new()
		# Live contact ribbons, advected filaments and the soft shadow.
		wake.mesh = wake_mesh
		var wake_material := ShaderMaterial.new()
		wake_material.shader = CAT_WAKE_SHADER
		wake_material.set_shader_parameter("flow_distance", 0.0)
		wake_material.set_shader_parameter("side_ripple_strength", 1.0)
		wake_material.set_shader_parameter("water_origin", Vector2(_water_bounds.position.x, _water_bounds.position.z))
		wake_material.set_shader_parameter("water_size", Vector2(_water_bounds.size.x, _water_bounds.size.z))
		wake_material.set_shader_parameter("shore_distance_map", WATER_MATERIAL.get_shader_parameter("shore_distance_map"))
		wake_material.render_priority = 2
		wake_material.set_shader_parameter("wake_color", Color("9af6d4"))
		wake_material.set_shader_parameter("water_y", _water_bounds.position.y + 0.06)
		wake.material_override = wake_material
		wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wake)
		_cat_wakes.append(wake)
		var field = WAKE_FIELD.new()
		field._random.seed += index * 104729
		_wake_fields.append(field)
