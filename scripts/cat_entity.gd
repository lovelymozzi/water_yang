@tool
class_name CatEntity
extends Node3D

const MODEL_SCENE_PATH := "res://water_yang/cat1.fbx"
const MODEL_TEXTURE_PATH := "res://water_yang/cat1.jpeg"
const TOON_SHADER_PATH := "res://scripts/cat_toon.gdshader"
const OUTLINE_SHADER_PATH := "res://scripts/cat_outline.gdshader"
const REFERENCE_TILE_SIZE := 2.0
const FOUR_CELL_CENTER_OFFSET := 0.35
# FBX bone IDs are not stored in physical head-to-tail order. This order comes from the skin weights.
const PATH_BONE_INDICES := [0, 2, 11, 12, 9, 10, 3, 4, 6, 5, 7, 8, 13, 14, 15, 16, 1]
const SCALE_LOCKED_BONE_NAMES := ["Bone001", "Bone002", "Bone017"]

@export_group("Layout")
@export var grid_pos: Vector2i = Vector2i.ZERO:
	set(value):
		grid_pos = value
		_reset_straight_body()
		_request_editor_refresh()

@export_enum("up", "right", "down", "left") var facing_name: String = "up":
	set(value):
		facing_name = value
		facing_dir = _direction_from_name(facing_name)
		_reset_straight_body()
		_request_editor_refresh()

@export_group("Body")
@export_range(2, 16, 1) var initial_length: int = 4:
	set(value):
		initial_length = value
		_reset_straight_body()
		_request_editor_refresh()

@export_range(2, 16, 1) var min_length: int = 2:
	set(value):
		min_length = value

@export_range(2, 32, 1) var max_length: int = 16:
	set(value):
		max_length = value

@export_enum("follow", "stretch") var endpoint_drag_mode: String = "follow"

@export_range(0.1, 16.0, 0.01) var fbx_scale_per_tile: float = 7.65:
	set(value):
		fbx_scale_per_tile = value
		_rebuild_body_visuals(false)

@export_group("Toon Shader")
@export var tint_color: Color = Color(1.0, 0.97, 0.97, 1.0):
	set(value):
		tint_color = value
		_rebuild_body_visuals(false)

@export_range(2, 5, 1) var toon_steps: int = 3
@export_range(0.0, 1.0, 0.01) var shadow_darkness: float = 0.58
@export_range(0.0, 1.0, 0.01) var rim_strength: float = 0.24

@export_group("Outline")
@export var outline_color: Color = Color(0.18, 0.09, 0.06, 1.0)
@export_range(0.001, 0.04, 0.001) var outline_width: float = 0.008

# 몸통은 항상 머리(0)에서 꼬리(마지막)까지 인접한 셀 경로로 저장한다.
var body_cells: Array[Vector2i] = []
var facing_dir: Vector2i = Vector2i.UP
var level_manager: LevelManager
var is_animating := false

var _visual_root: Node3D
var _handles_root: Node3D
var _head_handle: Area3D
var _tail_handle: Area3D
var _cat_model: Node3D
var _skeleton: Skeleton3D
var _bone_rests: Array[Transform3D] = []


func _ready() -> void:
	facing_dir = _direction_from_name(facing_name)
	if body_cells.is_empty():
		_reset_straight_body()
	_ensure_visual_root()
	_ensure_endpoint_handles()

	if Engine.is_editor_hint():
		refresh_editor_preview()


func refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return

	level_manager = _find_level_manager()
	if level_manager == null:
		return

	facing_dir = _direction_from_name(facing_name)
	# The editor preview must start from the same serialized layout as the game.
	_reset_straight_body()
	_sync_to_grid_position()
	_ensure_visual_root()
	_ensure_endpoint_handles()
	_rebuild_body_visuals(false)
	_update_endpoint_handles()


func initialize_runtime(manager: LevelManager) -> void:
	level_manager = manager
	facing_dir = _direction_from_name(facing_name)
	_reset_straight_body()
	_sync_to_grid_position()
	_ensure_visual_root()
	_ensure_endpoint_handles()
	_rebuild_body_visuals(false)
	_update_endpoint_handles()


func get_head_cell() -> Vector2i:
	return body_cells.front() if not body_cells.is_empty() else grid_pos


func get_tail_cell() -> Vector2i:
	return body_cells.back() if not body_cells.is_empty() else grid_pos


func occupies_cell(cell: Vector2i) -> bool:
	return get_occupied_cells().has(cell)


# 꺾이는 관절은 실제 메시 폭 때문에 경로 셀 밖의 대각 영역까지 닿는다.
# 두 대각 셀을 함께 예약해, 시각적으로 겹치지만 논리적으로는 비어 있던 상태를 막는다.
func get_turn_clearance_cells_for_body(cells: Array[Vector2i]) -> Array[Vector2i]:
	var clearance: Array[Vector2i] = []
	for index in range(1, cells.size() - 1):
		var turn := cells[index]
		var toward_head := cells[index - 1] - turn
		var toward_tail := cells[index + 1] - turn
		if toward_head == -toward_tail:
			continue
		# 몸통의 안쪽/바깥쪽 대각 모두를 보호한다. 어느 쪽으로 메시가 넓어져도
		# 다른 블록을 침범하지 않게 하기 위한 보수적인 여유 공간이다.
		clearance.append(turn + toward_head + toward_tail)
		clearance.append(turn - toward_head - toward_tail)
	return clearance


func get_occupied_cells() -> Array[Vector2i]:
	var occupied: Array[Vector2i] = body_cells.duplicate()
	for cell in get_turn_clearance_cells_for_body(body_cells):
		if not occupied.has(cell):
			occupied.append(cell)
	return occupied


func drag_endpoint_to(endpoint: StringName, target_cell: Vector2i) -> bool:
	if is_animating or level_manager == null or body_cells.size() < 2:
		return false

	var changed := false
	if endpoint == &"head":
		changed = _move_head_to(target_cell)
	elif endpoint == &"tail":
		changed = _move_tail_to(target_cell)

	if changed:
		level_manager.update_cat_occupancy(self)
		# grid_pos는 에디터에서 배치하는 최초 머리 위치다.
		# 이동 중 다시 대입하면 setter가 body_cells를 초기 직선 형태로 되돌린다.
		_rebuild_body_visuals(true)
		_update_endpoint_handles()
	return changed


func _move_head_to(target_cell: Vector2i) -> bool:
	var head := get_head_cell()
	if not _is_adjacent(head, target_cell):
		return false
	var candidate: Array[Vector2i] = body_cells.duplicate()

	# 머리를 바로 다음 몸통 칸으로 끌면 머리 쪽 한 칸이 줄어든다.
	if target_cell == candidate[1]:
		if endpoint_drag_mode == "follow":
			# 몸통 쪽으로 머리를 당기면 길이를 줄이지 않고, 반대쪽 다리까지 함께 전진시킨다.
			var tail_direction := candidate[-1] - candidate[-2]
			candidate.pop_front()
			candidate.append(candidate[-1] + tail_direction)
		elif candidate.size() <= min_length:
			return false
		else:
			candidate.pop_front()
	else:
		candidate.push_front(target_cell)
		if endpoint_drag_mode == "follow":
			# 머리가 전진한 만큼 꼬리도 한 칸 따라와 현재 몸통 길이를 유지한다.
			candidate.pop_back()
		elif candidate.size() > max_length:
			return false

	if not level_manager.can_place_cat_body(self, candidate):
		return false
	body_cells = candidate
	return true


func _move_tail_to(target_cell: Vector2i) -> bool:
	var tail := get_tail_cell()
	if not _is_adjacent(tail, target_cell):
		return false
	var candidate: Array[Vector2i] = body_cells.duplicate()

	# 꼬리를 바로 앞 몸통 칸으로 끌면 꼬리 쪽 한 칸이 줄어든다.
	if target_cell == candidate[-2]:
		if endpoint_drag_mode == "follow":
			# 꼬리를 몸통 쪽으로 당기면 머리도 반대 방향으로 한 칸 함께 전진시킨다.
			var head_direction := candidate[0] - candidate[1]
			candidate.pop_back()
			candidate.push_front(candidate[0] + head_direction)
		elif candidate.size() <= min_length:
			return false
		else:
			candidate.pop_back()
	else:
		candidate.append(target_cell)
		if endpoint_drag_mode == "follow":
			# 꼬리가 전진한 만큼 머리도 한 칸 따라와 현재 몸통 길이를 유지한다.
			candidate.pop_front()
		elif candidate.size() > max_length:
			return false

	if not level_manager.can_place_cat_body(self, candidate):
		return false
	body_cells = candidate
	return true


func _reset_straight_body() -> void:
	facing_dir = _direction_from_name(facing_name)
	body_cells.clear()
	var length := clampi(initial_length, min_length, max_length)
	# 머리는 grid_pos에 두고 몸통은 바라보는 방향의 반대쪽으로 놓는다.
	for index in range(length):
		body_cells.append(grid_pos - facing_dir * index)


func _sync_to_grid_position() -> void:
	if level_manager == null:
		return
	# Keep the editable CatEntity pivot on the head cell, not at the board origin.
	# Both the editor preview and the running game call this same function.
	position = level_manager.grid_to_world(get_head_cell(), level_manager.cat_world_y)
	rotation = Vector3.ZERO
	scale = Vector3.ONE


func _ensure_visual_root() -> void:
	# Remove the visual root generated by the previous single-FBX implementation.
	# Leaving it alive in the editor caused the editor and game to render different cats.
	var legacy_visual := get_node_or_null("VisualRoot")
	if legacy_visual != null:
		if legacy_visual == _visual_root:
			_visual_root = null
		legacy_visual.queue_free()

	if _visual_root != null:
		return

	var existing_visual := get_node_or_null("BodyVisuals")
	if existing_visual is Node3D:
		_visual_root = existing_visual as Node3D
		return

	_visual_root = Node3D.new()
	_visual_root.name = "BodyVisuals"
	add_child(_visual_root)


func _ensure_endpoint_handles() -> void:
	if _handles_root == null:
		_handles_root = Node3D.new()
		_handles_root.name = "EndpointHandles"
		add_child(_handles_root)

	if _head_handle == null:
		_head_handle = _create_endpoint_handle("HeadHandle", &"head")
		_handles_root.add_child(_head_handle)
	if _tail_handle == null:
		_tail_handle = _create_endpoint_handle("TailHandle", &"tail")
		_handles_root.add_child(_tail_handle)


func _create_endpoint_handle(handle_name: String, endpoint: StringName) -> Area3D:
	var handle := Area3D.new()
	handle.name = handle_name
	handle.set_meta("cat_endpoint", endpoint)
	handle.collision_layer = 1
	handle.collision_mask = 0
	handle.input_ray_pickable = true

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = level_manager.tile_size * 0.42 if level_manager != null else 0.8
	collision.shape = shape
	handle.add_child(collision)
	return handle


func _update_endpoint_handles() -> void:
	if level_manager == null or _head_handle == null or _tail_handle == null:
		return
	_head_handle.position = _cell_to_local(get_head_cell())
	_tail_handle.position = _cell_to_local(get_tail_cell())


func _rebuild_body_visuals(animate: bool) -> void:
	if _visual_root == null or level_manager == null:
		return

	for child in _visual_root.get_children():
		child.free()

	# 스키닝된 cat1.fbx 인스턴스 하나만 사용한다. 길이와 꺾임은 아래의 본 포즈가 담당한다.
	_cat_model = load_model_with_texture()
	_cat_model.name = "SkinnedCat"
	_visual_root.add_child(_cat_model)
	_skeleton = _find_skeleton_in(_cat_model)
	_cache_bone_rests()
	_place_model_at_head()
	_apply_body_pose()


func _place_model_at_head() -> void:
	if _cat_model == null or _bone_rests.is_empty() or body_cells.size() < 2:
		return

	var head_position := _cell_to_local(get_head_cell())
	var head_to_tail := _cell_to_local(body_cells[1]) - head_position
	# FBX의 실제 본 체인은 local -Y 방향으로 머리에서 꼬리로 진행한다.
	# 따라서 모델의 local +Y는 첫 구간의 반대(꼬리 -> 머리)로 배치한다.
	var tail_to_head := -head_to_tail.normalized()
	var base_scale := _grid_fitted_model_scale()
	# 이동 전후에 모델 루트 스케일은 항상 같은 값으로 고정한다.
	_cat_model.basis = _fbx_basis_for_direction(tail_to_head)
	# 상체 비율을 보존하기 위해 모델 루트도 반드시 균일 스케일만 사용한다.
	_cat_model.scale = Vector3.ONE * base_scale
	# Bone001의 rest 위치가 머리 중심과 일치하도록 모델 루트를 보정한다.
	# FBX 메시 중심이 Bone001보다 꼬리 쪽으로 치우쳐 있어, 4칸 묶음의 중앙으로 올려 보정한다.
	var center_offset := tail_to_head * level_manager.tile_size * FOUR_CELL_CENTER_OFFSET
	_cat_model.position = head_position + center_offset - _cat_model.basis * _bone_rests[0].origin


func _apply_body_pose() -> void:
	if _skeleton == null:
		return
	_skeleton.clear_bones_global_pose_override()
	_apply_body_pose_rotation_only()


func _apply_body_pose_grid_override() -> void:
	if _skeleton == null or _bone_rests.size() < 2 or body_cells.size() < 2:
		return

	# 모델 스케일은 고정하고, 각 본의 위치와 회전만 4칸 체인 경로에 맞춘다.
	_skeleton.reset_bone_poses()
	var target_points := _sample_body_path_for_bones(_bone_rests.size())
	var root_anchor := _bone_rests[0].origin

	for index in _bone_rests.size():
		var next_index := mini(index + 1, target_points.size() - 1)
		var direction := target_points[next_index] - target_points[index]
		if direction.length_squared() < 0.000001:
			direction = target_points[index] - target_points[maxi(index - 1, 0)]
		if direction.length_squared() < 0.000001:
			direction = Vector3.RIGHT
		else:
			direction = direction.normalized()

		# 이 FBX의 얼굴 메시 법선은 본의 local -Z 쪽에 있으므로, 얼굴 면을 위로 반전한다.
		var face_axis := Vector3.BACK
		var side_axis := face_axis.cross(direction).normalized()
		var target_transform := Transform3D(Basis(direction, side_axis, face_axis), root_anchor + target_points[index])
		_skeleton.set_bone_global_pose_override(index, target_transform, 1.0, true)

	_enforce_locked_bone_scales()


func _apply_body_pose_rotation_only() -> void:
	if _skeleton == null or _bone_rests.size() < 2 or body_cells.size() < 2:
		return

	_skeleton.reset_bone_poses()
	_enforce_locked_bone_scales()
	if not _body_path_has_turn():
		return

	# 뱀형 체인은 각 관절을 local Z축으로만 회전한다.
	# 이 축은 얼굴의 위아래 방향과 같아서, 몸통이 뒤집히거나 비틀리지 않는다.
	var target_points := _sample_body_path_for_bones(_bone_rests.size())
	var previous_direction := target_points[1] - target_points[0]
	if previous_direction.length_squared() < 0.000001:
		return
	previous_direction = previous_direction.normalized()

	for bone_index in range(2, 16):
		var next_index := mini(bone_index + 1, target_points.size() - 1)
		var current_direction := target_points[next_index] - target_points[bone_index]
		if current_direction.length_squared() < 0.000001:
			continue
		current_direction = current_direction.normalized()

		if not current_direction.is_equal_approx(previous_direction):
			# FBX의 local Z 회전 방향은 보드 좌표계와 반대이므로 부호를 반전한다.
			var turn_angle := -atan2(previous_direction.cross(current_direction).z, previous_direction.dot(current_direction))
			_skeleton.set_bone_pose_rotation(bone_index, Quaternion(Vector3.FORWARD, turn_angle))
		previous_direction = current_direction


func _apply_body_pose_rotation_only_absolute() -> void:
	if _skeleton == null or _bone_rests.size() < 2 or body_cells.size() < 2:
		return

	# 본의 길이와 위치는 FBX rest pose를 유지한다. 타일 경로의 방향 변화만 관절 회전으로 전달한다.
	_skeleton.reset_bone_poses()
	_enforce_locked_bone_scales()
	# 직선 상태에서는 FBX의 개별 rest 회전을 그대로 유지해야 몸통 앞면이 뒤집히지 않는다.
	if not _body_path_has_turn():
		return
	var target_points := _sample_body_path_for_bones(_bone_rests.size())
	var final_global_bases: Array[Basis] = []

	for index in _bone_rests.size():
		if index < 2 or index >= 16:
			var rest_global_basis := _skeleton.get_bone_global_rest(index).basis
			final_global_bases.append(rest_global_basis)
			continue

		var next_index := mini(index + 1, target_points.size() - 1)
		var direction := target_points[next_index] - target_points[index]
		if direction.length_squared() < 0.000001:
			direction = target_points[index] - target_points[maxi(index - 1, 0)]
		if direction.length_squared() < 0.000001:
			direction = Vector3.RIGHT
		else:
			direction = direction.normalized()

		# 모델의 얼굴 면은 local +Z이며, 모델 루트가 이를 월드 위쪽으로 향하게 한다.
		var face_axis := Vector3.FORWARD
		var side_axis := face_axis.cross(direction).normalized()
		var desired_global_basis := Basis(direction, side_axis, face_axis)
		var parent_index := _skeleton.get_bone_parent(index)
		var parent_basis := final_global_bases[parent_index] if parent_index >= 0 else Basis.IDENTITY
		var desired_local_basis := parent_basis.inverse() * desired_global_basis
		var pose_basis := _bone_rests[index].basis.inverse() * desired_local_basis
		_skeleton.set_bone_pose_rotation(index, pose_basis.get_rotation_quaternion())
		final_global_bases.append(desired_global_basis)


func _body_path_has_turn() -> bool:
	if body_cells.size() < 3:
		return false
	var previous_direction := body_cells[1] - body_cells[0]
	for index in range(1, body_cells.size() - 1):
		var current_direction := body_cells[index + 1] - body_cells[index]
		if current_direction != previous_direction:
			return true
		previous_direction = current_direction
	return false


func _apply_body_pose_deformed() -> void:
	if _skeleton == null or _bone_rests.size() < 2 or body_cells.size() < 2:
		return

	# 본을 부모 로컬 좌표에서 누적 계산하지 않고, Skeleton3D 기준 전역 포즈로 직접 배치한다.
	# 따라서 각 관절은 언제나 body_cells가 만든 타일 경로 위에 놓인다.
	var target_points := _sample_body_path_for_bones(PATH_BONE_INDICES.size())
	var root_anchor := _bone_rests[0].origin
	for path_index in PATH_BONE_INDICES.size():
		var bone_index: int = PATH_BONE_INDICES[path_index]
		var next_index := mini(path_index + 1, target_points.size() - 1)
		var direction := target_points[next_index] - target_points[path_index]
		if direction.length_squared() < 0.000001:
			direction = target_points[path_index] - target_points[maxi(path_index - 1, 0)]
		if direction.length_squared() < 0.000001:
			direction = Vector3.RIGHT
		else:
			direction = direction.normalized()

		# FBX 스킨의 얼굴 면은 Skeleton local -Z를 향하므로, 월드 위쪽으로 반전한다.
		var face_axis := Vector3.BACK
		var side_axis := face_axis.cross(direction).normalized()
		var target_transform := Transform3D(Basis(direction, side_axis, face_axis), root_anchor + target_points[path_index])
		_skeleton.set_bone_global_pose_override(bone_index, target_transform, 1.0, true)


func _apply_body_pose_local() -> void:
	if _skeleton == null or _bone_rests.size() < 2 or body_cells.size() < 2:
		return

	# 부모 본의 스케일은 체인을 따라 누적되므로, 관절의 로컬 위치와 회전만 사용한다.
	_skeleton.reset_bone_poses()
	var target_points := _sample_body_path_for_bones(_bone_rests.size())
	var final_global_bases: Array[Basis] = []

	for index in _bone_rests.size():
		var next_index := mini(index + 1, target_points.size() - 1)
		var direction := target_points[next_index] - target_points[index]
		if direction.length_squared() < 0.000001:
			direction = Vector3.RIGHT
		else:
			direction = direction.normalized()

		# FBX 본 체인은 local X 방향으로 진행하며, local Z는 얼굴이 향하는 위쪽으로 유지한다.
		var face_axis := Vector3.FORWARD
		var side_axis := face_axis.cross(direction).normalized()
		var desired_global_basis := Basis(direction, side_axis, face_axis)
		var parent_index := _skeleton.get_bone_parent(index)
		var parent_basis := final_global_bases[parent_index] if parent_index >= 0 else Basis.IDENTITY
		var desired_local_basis := parent_basis.inverse() * desired_global_basis
		var pose_basis := _bone_rests[index].basis.inverse() * desired_local_basis
		_skeleton.set_bone_pose_rotation(index, pose_basis.get_rotation_quaternion())

		if index > 0:
			# Pose position은 FBX에서 가져온 rest transform을 기준으로 한 추가 이동값이다.
			var desired_local_origin := parent_basis.inverse() * (target_points[index] - target_points[index - 1])
			var pose_position := _bone_rests[index].basis.inverse() * (desired_local_origin - _bone_rests[index].origin)
			_skeleton.set_bone_pose_position(index, pose_position)

		final_global_bases.append(desired_global_basis)


func _sample_body_path_for_bones(sample_count: int) -> Array[Vector3]:
	var path_points: Array[Vector3] = []
	var path_lengths: Array[float] = []
	var total_length := 0.0
	var head_position := _cell_to_local(get_head_cell())
	for cell in body_cells:
		path_points.append(_cat_model.basis.inverse() * (_cell_to_local(cell) - head_position))
	for index in range(path_points.size() - 1):
		total_length += path_points[index].distance_to(path_points[index + 1])
		path_lengths.append(total_length)

	var samples: Array[Vector3] = []
	for sample_index in sample_count:
		var ratio := float(sample_index) / float(maxi(sample_count - 1, 1))
		samples.append(_point_on_path(path_points, path_lengths, total_length * ratio))
	return samples


func _rest_distance_to_bone(bone_index: int) -> float:
	var distance := 0.0
	for index in range(1, bone_index + 1):
		distance += _bone_rests[index].origin.length()
	return distance


func _point_on_path(path_points: Array[Vector3], path_lengths: Array[float], distance: float) -> Vector3:
	if distance <= 0.0 or path_points.size() == 1:
		return path_points[0]
	for index in path_lengths.size():
		if distance <= path_lengths[index]:
			var start_distance := path_lengths[index - 1] if index > 0 else 0.0
			var segment_length := path_lengths[index] - start_distance
			var weight := (distance - start_distance) / segment_length
			return path_points[index].lerp(path_points[index + 1], weight)
	return path_points.back()


func _reset_bone_pose() -> void:
	if _skeleton == null:
		return
	# 스킨은 FBX의 rest pose를 그대로 사용한다. 본 체인의 실제 로컬 축과
	# 가중치를 확정하기 전의 임의 회전/스케일은 메시를 찌그러뜨릴 수 있다.
	_skeleton.reset_bone_poses()
	_enforce_locked_bone_scales()


func _enforce_locked_bone_scales() -> void:
	if _skeleton == null:
		return
	# 머리와 지정한 다리 본은 어떤 이동 포즈에서도 스케일을 변경하지 않는다.
	for bone_name in SCALE_LOCKED_BONE_NAMES:
		var bone_index: int = _skeleton.find_bone(bone_name)
		if bone_index >= 0:
			_skeleton.set_bone_pose_scale(bone_index, Vector3.ONE)


func _cache_bone_rests() -> void:
	_bone_rests.clear()
	if _skeleton == null:
		return
	for index in _skeleton.get_bone_count():
		_bone_rests.append(_skeleton.get_bone_rest(index))


func _grid_fitted_model_scale() -> float:
	if level_manager == null:
		return fbx_scale_per_tile
	# 자동 체인 길이 보정(약 6.0)은 기준 모델(7.65)보다 작아 상체가 축소되어 보였다.
	# 에디터 기준과 동일한 FBX 균일 스케일을 고정 사용한다.
	return fbx_scale_per_tile * level_manager.tile_size / REFERENCE_TILE_SIZE


func _fbx_basis_for_direction(direction: Vector3) -> Basis:
	# FBX local Y is the body length and local +Z is the face side.
	# Keep the face side toward world up while only the body length follows the grid path.
	var body_axis := direction.normalized()
	var face_axis := Vector3.UP
	var side_axis := body_axis.cross(face_axis).normalized()
	return Basis(side_axis, body_axis, face_axis)


func _cell_to_local(cell: Vector2i) -> Vector3:
	return level_manager.grid_to_world(cell, level_manager.cat_world_y) - position


# FBX와 텍스처 로더는 향후 리깅된 머리/꼬리 모델로 교체할 때 그대로 사용한다.
func load_model_with_texture() -> Node3D:
	var packed_scene := load(MODEL_SCENE_PATH) as PackedScene
	var model_root := packed_scene.instantiate() as Node3D if packed_scene != null else Node3D.new()
	var material := _build_cat_material()
	_apply_material_recursive(model_root, material)
	return model_root


func _find_skeleton_in(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var skeleton := _find_skeleton_in(child)
		if skeleton != null:
			return skeleton
	return null


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	for child in node.get_children():
		_apply_material_recursive(child, material)


func _build_cat_material() -> Material:
	var shader := load(TOON_SHADER_PATH) as Shader
	var texture := load(MODEL_TEXTURE_PATH) as Texture2D
	if shader == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_texture = texture
		fallback.albedo_color = tint_color
		return fallback
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_tex", texture)
	material.set_shader_parameter("tint_color", tint_color)
	material.set_shader_parameter("shadow_steps", toon_steps)
	material.set_shader_parameter("shadow_darkness", shadow_darkness)
	material.set_shader_parameter("rim_strength", rim_strength)
	return material


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1


func _find_level_manager() -> LevelManager:
	var current: Node = get_parent()
	while current != null:
		if current is LevelManager:
			return current as LevelManager
		current = current.get_parent()
	return null


func _request_editor_refresh() -> void:
	if not Engine.is_editor_hint():
		return
	call_deferred("refresh_editor_preview")
	var manager := _find_level_manager()
	if manager != null:
		manager.request_preview_refresh()


func _direction_from_name(dir_name: String) -> Vector2i:
	match dir_name.to_lower():
		"up": return Vector2i.UP
		"right": return Vector2i.RIGHT
		"down": return Vector2i.DOWN
		"left": return Vector2i.LEFT
		_: return Vector2i.UP
