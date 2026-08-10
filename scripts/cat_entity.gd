@tool
class_name CatEntity
extends Node3D

const MODEL_SCENE_PATH := "res://water_yang/cat1.fbx"
const MODEL_TEXTURE_PATH := "res://water_yang/cat1.jpeg"
const CLOSED_EYES_TEXTURE_PATH := "res://water_yang/cat1_1.jpeg"
const TOON_SHADER_PATH := "res://scripts/cat_toon.gdshader"
const OUTLINE_SHADER_PATH := "res://scripts/cat_outline.gdshader"
const REFERENCE_TILE_SIZE := 2.0
const BLINK_INTERVAL_MIN := 2.4
const BLINK_INTERVAL_MAX := 5.2
const BLINK_CLOSED_DURATION := 0.11
# 드래그 중 코너를 깎을 때 원호를 몇 조각으로 나눌지.
const CORNER_ARC_SEGMENTS := 5
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

@export_group("Motion")
# 렌더용 중심선이 그리드 목표를 따라잡는 시간. 0이면 예전처럼 칸 단위로 순간이동한다.
@export_range(0.0, 0.4, 0.005) var move_smooth_time: float = 0.075
# 손을 놓은 뒤 코너가 다시 각지게 굳는 시간.
@export_range(0.0, 0.6, 0.005) var settle_time: float = 0.14
# 드래그 중 코너를 깎는 정도. 1이면 타일 반폭만큼의 원호로 최단거리처럼 흐른다.
@export_range(0.0, 1.0, 0.05) var corner_round: float = 1.0

@export_group("Body")
@export_range(0.1, 16.0, 0.01) var fbx_scale_per_tile: float = 7.65:
	set(value):
		fbx_scale_per_tile = value
		_rebuild_body_visuals(false)

@export_group("Toon Shader")
@export var tint_color: Color = Color(1.0, 0.97, 0.97, 1.0):
	set(value):
		tint_color = value
		_refresh_shader_material()

@export_range(2, 5, 1) var toon_steps: int = 3:
	set(value):
		toon_steps = value
		_refresh_shader_material()

@export_range(0.0, 1.0, 0.01) var shadow_darkness: float = 0.58:
	set(value):
		shadow_darkness = value
		_refresh_shader_material()

@export_range(0.0, 1.0, 0.01) var rim_strength: float = 0.24:
	set(value):
		rim_strength = value
		_refresh_shader_material()

@export_group("Outline")
@export var outline_color: Color = Color(0.18, 0.09, 0.06, 1.0):
	set(value):
		outline_color = value
		_refresh_shader_material()

@export_range(0.001, 0.04, 0.001) var outline_width: float = 0.008:
	set(value):
		outline_width = value
		_refresh_shader_material()

# 몸통은 항상 머리(0)에서 꼬리(마지막)까지 인접한 셀 경로로 저장한다.
var body_cells: Array[Vector2i] = []
# 양 끝이 지나온 길. 최신 칸이 앞에 온다. 후진할 때 이 기록을 되짚어 간다.
# _front_trail은 body_cells[0] 바깥쪽, _back_trail은 body_cells[-1] 바깥쪽이다.
var _front_trail: Array[Vector2i] = []
var _back_trail: Array[Vector2i] = []
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
var _cat_material: ShaderMaterial
var _outline_material: ShaderMaterial
var _open_eyes_texture: Texture2D
var _closed_eyes_texture: Texture2D
var _blink_time_remaining := -1.0
var _eyes_are_closed := false
var _blink_random := RandomNumberGenerator.new()
# 머리에서 꼬리까지의 실제 본 인덱스 순서와, 머리 본 기준 rest 누적 거리(모델 로컬 단위).
var _bone_chain: Array[int] = []
var _bone_chain_distances: Array[float] = []
var _rest_chain_length: float = 0.0
# 렌더용 연속 중심선. body_cells 와 같은 길이이며, 각 점이 셀 중심을 향해 수렴한다.
var _spine: PackedVector3Array = PackedVector3Array()
var _round_weight: float = 0.0
var _is_dragging: bool = false
var _motion_active: bool = false


func _ready() -> void:
	_blink_random.seed = get_instance_id()
	facing_dir = _direction_from_name(facing_name)
	if body_cells.is_empty():
		_reset_straight_body()
	_ensure_visual_root()
	_ensure_endpoint_handles()

	if Engine.is_editor_hint():
		refresh_editor_preview()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_process_blink(delta)
	_process_motion(delta)


func _process_blink(delta: float) -> void:
	if _cat_material == null:
		return
	if _closed_eyes_texture == null:
		_closed_eyes_texture = load(CLOSED_EYES_TEXTURE_PATH) as Texture2D
		if _closed_eyes_texture == null:
			return

	if _blink_time_remaining < 0.0:
		_schedule_next_blink()
		return

	_blink_time_remaining -= delta
	if _blink_time_remaining > 0.0:
		return

	_eyes_are_closed = not _eyes_are_closed
	_cat_material.set_shader_parameter(
		"albedo_tex",
		_closed_eyes_texture if _eyes_are_closed else _get_open_eyes_texture()
	)
	if _eyes_are_closed:
		_blink_time_remaining = BLINK_CLOSED_DURATION
	else:
		_schedule_next_blink()


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
	return body_cells.has(cell)


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
		# 모델을 다시 만들지 않고, 중심선이 새 목표를 향해 흐르도록 두기만 한다.
		if Engine.is_editor_hint():
			snap_pose_to_grid()
		else:
			_motion_active = true
		_update_endpoint_handles()
	return changed


func _move_head_to(target_cell: Vector2i) -> bool:
	return _move_endpoint(target_cell, false)


func _move_tail_to(target_cell: Vector2i) -> bool:
	return _move_endpoint(target_cell, true)


func _move_endpoint(target_cell: Vector2i, from_tail: bool) -> bool:
	# 게코아웃에서는 "잡아끄는 쪽"이 곧 머리다. 두 끝의 규칙이 완전히 대칭이므로
	# 꼬리를 잡은 경우에는 몸통을 뒤집어 같은 로직을 그대로 태운다.
	var path: Array[Vector2i] = body_cells.duplicate()
	var lead_trail: Array[Vector2i] = _front_trail
	var rear_trail: Array[Vector2i] = _back_trail
	if from_tail:
		path.reverse()
		lead_trail = _back_trail
		rear_trail = _front_trail

	var lead: Vector2i = path[0]
	if not _is_adjacent(lead, target_cell):
		return false

	var candidate: Array[Vector2i] = path.duplicate()
	var is_retreat: bool = target_cell == candidate[1]
	var rear_from_memory := false
	var vacated_rear := Vector2i.ZERO
	var rear_moved := false

	if is_retreat:
		# 후진: 잡은 끝을 몸통 안쪽으로 민다.
		if endpoint_drag_mode == "follow":
			var rear: Vector2i = candidate[-1]
			var rear_prev: Vector2i = candidate[-2]
			var remembered: Variant = _remembered_rear_cell(rear_trail, rear, rear_prev)
			var next_rear: Vector2i
			if remembered == null:
				# 기억이 없으면(= 반대쪽 끝이 지나온 적 없는 칸으로 나가면)
				# 미는 힘 그대로 직진하는 자연 후진이 된다.
				next_rear = rear + (rear - rear_prev)
			else:
				# 왔던 길이 남아 있으면 그 칸으로 되돌아간다.
				next_rear = remembered as Vector2i
				rear_from_memory = true
			candidate.pop_front()
			candidate.append(next_rear)
			rear_moved = true
		elif candidate.size() <= min_length:
			return false
		else:
			candidate.pop_front()
	else:
		# 전진: 새 칸으로 나아가고 반대쪽 끝이 한 칸 따라온다.
		candidate.push_front(target_cell)
		if endpoint_drag_mode == "follow":
			vacated_rear = candidate[-1]
			candidate.pop_back()
			rear_moved = true
		elif candidate.size() > max_length:
			return false

	var final_body: Array[Vector2i] = candidate.duplicate()
	if from_tail:
		final_body.reverse()
	if not level_manager.can_place_cat_body(self, final_body):
		return false

	# 이동이 확정된 뒤에만 통과한 길 기록을 갱신한다.
	body_cells = final_body
	if is_retreat:
		_remember(lead_trail, lead)
		if rear_moved:
			if rear_from_memory:
				rear_trail.pop_front()
			else:
				rear_trail.clear()
	else:
		# 잡은 쪽이 기억한 길을 되짚어 가면 그만큼 소비하고, 새 방향으로 틀면 기억을 버린다.
		if not lead_trail.is_empty() and lead_trail[0] == target_cell:
			lead_trail.pop_front()
		else:
			lead_trail.clear()
		if rear_moved:
			_remember(rear_trail, vacated_rear)
	return true


func _remembered_rear_cell(
	rear_trail: Array[Vector2i],
	rear: Vector2i,
	rear_prev: Vector2i
) -> Variant:
	if rear_trail.is_empty():
		return null
	var remembered: Vector2i = rear_trail[0]
	if not _is_adjacent(remembered, rear) or remembered == rear_prev:
		return null
	return remembered


func _remember(trail: Array[Vector2i], cell: Vector2i) -> void:
	trail.push_front(cell)
	# 기록은 보드를 한 번 가득 채울 만큼만 남긴다. 그 밖은 어차피 되돌아갈 수 없다.
	var limit: int = 64
	if level_manager != null:
		limit = maxi(level_manager.grid_size.x * level_manager.grid_size.y, 8)
	while trail.size() > limit:
		trail.pop_back()


func _reset_straight_body() -> void:
	facing_dir = _direction_from_name(facing_name)
	body_cells.clear()
	# 새로 배치하면 지나온 길 기록도 함께 비운다.
	_front_trail.clear()
	_back_trail.clear()
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


func _rebuild_body_visuals(_animate: bool) -> void:
	# FBX 인스턴스는 한 번만 만든다. 매 이동마다 다시 로드하면 스켈레톤 포즈가
	# 프레임마다 리셋되어 보간이 불가능해진다.
	if _visual_root == null or level_manager == null:
		return

	for child in _visual_root.get_children():
		child.free()

	_cat_model = load_model_with_texture()
	_cat_model.name = "SkinnedCat"
	_visual_root.add_child(_cat_model)
	_skeleton = _find_skeleton_in(_cat_model)
	_cache_bone_rests()
	snap_pose_to_grid()


func begin_drag() -> void:
	# 드래그 중에는 코너를 깎아 최단거리로 흐르게 한다.
	_is_dragging = true
	_motion_active = true


func end_drag() -> void:
	# 손을 놓으면 스파인이 셀 중심으로 수렴하고 코너가 다시 각지게 굳는다.
	_is_dragging = false
	_motion_active = true


func snap_pose_to_grid() -> void:
	# 보간 없이 그리드 정위치로 즉시 확정한다. 에디터 미리보기와 스폰 시점에 쓴다.
	_resize_spine()
	for index in _spine.size():
		_spine[index] = _spine_target(index)
	_round_weight = 0.0
	_motion_active = false
	_refresh_pose()


func _resize_spine() -> void:
	if _spine.size() == body_cells.size():
		return
	# 길이가 바뀌면 새로 생긴 점만 목표 위치에서 시작시킨다.
	var previous := _spine.duplicate()
	_spine.resize(body_cells.size())
	for index in _spine.size():
		_spine[index] = previous[index] if index < previous.size() else _spine_target(index)


func _spine_target(index: int) -> Vector3:
	return _cell_to_local(body_cells[index])


func _process_motion(delta: float) -> void:
	# 눈 깜빡임은 계속 돌아야 하므로 _process 자체를 끄지 않고 플래그로만 쉰다.
	if not _motion_active or level_manager == null or _cat_model == null:
		return

	var moving := _advance_spine(delta)
	_refresh_pose()
	# 다 따라잡고 각지게 굳었으면 다음 입력까지 쉰다.
	if not moving and not _is_dragging:
		_motion_active = false


func _advance_spine(delta: float) -> bool:
	_resize_spine()

	# 프레임레이트와 무관한 지수 수렴. smooth_time 이 0이면 즉시 스냅이다.
	var chase := _smoothing_factor(delta, move_smooth_time)
	var settled := true
	var epsilon := level_manager.tile_size * 0.002

	for index in _spine.size():
		var target := _spine_target(index)
		var next: Vector3 = _spine[index].lerp(target, chase)
		if next.distance_to(target) > epsilon:
			settled = false
		_spine[index] = next

	# 드래그 중에는 라운딩을 올리고, 손을 놓으면 각진 그리드 형태로 되돌린다.
	var round_target := corner_round if _is_dragging else 0.0
	var round_chase := _smoothing_factor(delta, move_smooth_time if _is_dragging else settle_time)
	_round_weight = lerpf(_round_weight, round_target, round_chase)
	if absf(_round_weight - round_target) > 0.002:
		settled = false

	return not settled


func _smoothing_factor(delta: float, smooth_time: float) -> float:
	if smooth_time <= 0.0001:
		return 1.0
	return 1.0 - exp(-delta / smooth_time)


func _refresh_pose() -> void:
	if _cat_model == null or _bone_rests.is_empty() or _spine.size() < 2:
		return
	var polyline := _build_pose_polyline()
	if polyline.size() < 2:
		return
	_place_model_on(polyline)
	_apply_body_pose_along(polyline)


func _build_pose_polyline() -> PackedVector3Array:
	# 렌더용 중심선. 코 끝(머리 돌출) -> 스파인 -> 꼬리 끝(꼬리 돌출) 순서다.
	# _round_weight 가 0이면 셀 중심을 잇는 각진 경로 그대로이고,
	# 1에 가까울수록 코너가 원호로 깎여 대각선 최단거리처럼 흐른다.
	var radius := level_manager.tile_size * 0.5 * clampf(_round_weight, 0.0, 1.0)
	var overhang := _body_overhang()
	var points := PackedVector3Array()

	var head_direction := (_spine[0] - _spine[1]).normalized()
	points.append(_spine[0] + head_direction * overhang)
	points.append(_spine[0])

	for index in range(1, _spine.size() - 1):
		var previous: Vector3 = _spine[index - 1]
		var current: Vector3 = _spine[index]
		var following: Vector3 = _spine[index + 1]
		var incoming := (current - previous)
		var outgoing := (following - current)
		if radius <= 0.0001 or incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001:
			points.append(current)
			continue
		if incoming.normalized().is_equal_approx(outgoing.normalized()):
			points.append(current)
			continue

		# 코너를 2차 베지어 원호로 대체한다. 반지름은 인접 구간의 절반을 넘지 않게 막아
		# 곡선이 이웃 셀로 삐져나가지 않도록 한다.
		var arc_radius := minf(radius, minf(incoming.length(), outgoing.length()) * 0.5)
		var entry := current - incoming.normalized() * arc_radius
		var exit_point := current + outgoing.normalized() * arc_radius
		for step in range(CORNER_ARC_SEGMENTS + 1):
			var t := float(step) / float(CORNER_ARC_SEGMENTS)
			points.append(entry.lerp(current, t).lerp(current.lerp(exit_point, t), t))

	points.append(_spine[-1])
	var tail_direction := (_spine[-1] - _spine[-2]).normalized()
	points.append(_spine[-1] + tail_direction * overhang)
	return points


func _polyline_lengths(points: PackedVector3Array) -> PackedFloat32Array:
	var lengths := PackedFloat32Array()
	var total := 0.0
	lengths.append(0.0)
	for index in range(1, points.size()):
		total += points[index].distance_to(points[index - 1])
		lengths.append(total)
	return lengths


func _polyline_tangent_at(
	points: PackedVector3Array,
	lengths: PackedFloat32Array,
	distance: float
) -> Vector3:
	# 이웃 본을 잇는 현(chord)이 아니라 그 지점의 접선을 쓴다. 각진 경로에서는
	# 코너 하나가 관절 하나에 그대로 실리고, 곡선에서는 접선이 매끄럽게 변한다.
	for index in range(1, points.size()):
		if distance <= lengths[index] or index == points.size() - 1:
			var segment := points[index] - points[index - 1]
			if segment.length_squared() < 0.000001:
				continue
			return segment.normalized()
	return Vector3.RIGHT


func _bone_span_direction(
	polyline: PackedVector3Array,
	lengths: PackedFloat32Array,
	chain_index: int,
	model_scale: float
) -> Vector3:
	# 관절 위치가 아니라 그 관절이 담당하는 구간의 중간에서 접선을 읽는다.
	# 이렇게 해야 코너가 "코너 다음 관절"이 아니라 "코너에 가장 가까운 관절"에 실린다.
	var start: float = _bone_chain_distances[chain_index] * model_scale
	var next_index: int = mini(chain_index + 1, _bone_chain_distances.size() - 1)
	var end: float = _bone_chain_distances[next_index] * model_scale
	var sample: float = start if is_equal_approx(start, end) else (start + end) * 0.5
	return _polyline_tangent_at(polyline, lengths, sample)


func _place_model_on(polyline: PackedVector3Array) -> void:
	# polyline[0] 이 코 끝이고 진행 방향은 머리 -> 꼬리다. 모델의 local +Y 는 그 반대다.
	var lengths := _polyline_lengths(polyline)
	var forward := -_bone_span_direction(polyline, lengths, 0, _grid_fitted_model_scale())
	_cat_model.basis = _fbx_basis_for_direction(forward)
	# 상체 비율을 보존하기 위해 모델 루트는 반드시 균일 스케일만 사용한다.
	_cat_model.scale = Vector3.ONE * _grid_fitted_model_scale()
	_cat_model.position = polyline[0] - _cat_model.basis * _bone_rests[0].origin


func _grid_path_length() -> float:
	return float(maxi(body_cells.size() - 1, 0)) * level_manager.tile_size


func _body_overhang() -> float:
	return maxf((_rest_chain_length * _grid_fitted_model_scale() - _grid_path_length()) * 0.5, 0.0)


func _apply_body_pose_along(polyline: PackedVector3Array) -> void:
	if _skeleton == null:
		return

	# 본의 rest 길이를 그대로 두고 관절 회전만 준다. 이렇게 해야 몸 비율이 변하지 않는다.
	_skeleton.clear_bones_global_pose_override()
	_skeleton.reset_bone_poses()
	_enforce_locked_bone_scales()
	if _bone_chain.size() < 2 or _cat_model == null:
		return

	var model_scale := _grid_fitted_model_scale()
	if model_scale <= 0.0:
		return

	var lengths := _polyline_lengths(polyline)
	var to_local := _cat_model.basis.inverse()
	var previous_direction := (
		to_local * _bone_span_direction(polyline, lengths, 0, model_scale)
	).normalized()

	for chain_index in range(1, _bone_chain.size()):
		# 몸통이 모델보다 길면 뒤쪽 경로에는 본이 닿지 않는다. 남는 본은 마지막 접선을 따른다.
		var direction := (
			to_local * _bone_span_direction(polyline, lengths, chain_index, model_scale)
		).normalized()
		if direction.is_equal_approx(previous_direction):
			continue

		# FBX의 local Z 회전 방향은 보드 좌표계와 반대이므로 부호를 반전한다.
		var turn := -atan2(previous_direction.cross(direction).z, previous_direction.dot(direction))
		var bone_index: int = _bone_chain[chain_index]
		# rest 회전 위에 꺾임을 얹는다. rest 회전을 덮어쓰면 몸통 앞면이 뒤집힌다.
		var rest_rotation := _bone_rests[bone_index].basis.get_rotation_quaternion()
		_skeleton.set_bone_pose_rotation(
			bone_index,
			rest_rotation * Quaternion(Vector3.FORWARD, turn)
		)
		previous_direction = direction

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
	_bone_chain.clear()
	_bone_chain_distances.clear()
	_rest_chain_length = 0.0
	if _skeleton == null:
		return
	for index in _skeleton.get_bone_count():
		_bone_rests.append(_skeleton.get_bone_rest(index))
	_build_bone_chain()


func _build_bone_chain() -> void:
	# 본 순서를 상수로 적어두지 않고 부모-자식 링크를 따라 머리에서 꼬리까지 실제로 걷는다.
	# 리그가 바뀌어도 경로 순서와 관절 간격이 자동으로 따라온다.
	var root_index := -1
	for index in _skeleton.get_bone_count():
		if _skeleton.get_bone_parent(index) == -1:
			root_index = index
			break
	if root_index < 0:
		return

	var current := root_index
	var distance := 0.0
	_bone_chain.append(current)
	_bone_chain_distances.append(0.0)

	while true:
		var children: PackedInt32Array = _skeleton.get_bone_children(current)
		if children.is_empty():
			break
		# 뱀형 리그는 단일 체인이다. 갈래가 생기면 가장 긴 뼈를 몸통 진행 방향으로 본다.
		var next_bone: int = children[0]
		for child in children:
			if _bone_rests[child].origin.length() > _bone_rests[next_bone].origin.length():
				next_bone = child
		distance += _bone_rests[next_bone].origin.length()
		_bone_chain.append(next_bone)
		_bone_chain_distances.append(distance)
		current = next_bone

	_rest_chain_length = distance


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
	var outline_shader := load(OUTLINE_SHADER_PATH) as Shader
	var texture := _get_open_eyes_texture()
	if shader == null:
		_cat_material = null
		_outline_material = null
		var fallback := StandardMaterial3D.new()
		fallback.albedo_texture = texture
		fallback.albedo_color = tint_color
		return fallback
	_cat_material = ShaderMaterial.new()
	_outline_material = null
	_cat_material.shader = shader

	# Render the expanded, front-face-culled outline as a next pass. This keeps
	# it on the same skinned mesh, so the outline always follows the cat pose.
	if outline_shader != null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = outline_shader
		_cat_material.next_pass = _outline_material

	_apply_shader_parameters(texture)
	return _cat_material


func _refresh_shader_material() -> void:
	# Export setters also run while the node is deserializing, before its visual
	# model exists. Defer once so inspector edits update a live material safely.
	call_deferred("_apply_current_shader_parameters")


func _apply_current_shader_parameters() -> void:
	if _cat_material == null:
		if Engine.is_editor_hint():
			_request_editor_refresh()
		return
	_apply_shader_parameters(_get_open_eyes_texture())


func _apply_shader_parameters(texture: Texture2D) -> void:
	if _cat_material != null:
		_cat_material.set_shader_parameter("albedo_tex", texture)
		_cat_material.set_shader_parameter("tint_color", tint_color)
		_cat_material.set_shader_parameter("shadow_steps", toon_steps)
		_cat_material.set_shader_parameter("shadow_darkness", shadow_darkness)
		_cat_material.set_shader_parameter("rim_strength", rim_strength)
	if _outline_material != null:
		_outline_material.set_shader_parameter("outline_color", outline_color)
		_outline_material.set_shader_parameter("outline_width", outline_width)


func _get_open_eyes_texture() -> Texture2D:
	if _open_eyes_texture == null:
		_open_eyes_texture = load(MODEL_TEXTURE_PATH) as Texture2D
	return _open_eyes_texture


func _schedule_next_blink() -> void:
	_eyes_are_closed = false
	_blink_time_remaining = _blink_random.randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)


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
