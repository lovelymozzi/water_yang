@tool
class_name CatEntity
extends Node3D

const MODEL_SCENE_PATH := "res://water_yang/cat1.fbx"
const MODEL_TEXTURE_PATH := "res://water_yang/cat1.jpeg"
const TINT_EXCLUSION_MASK_PATH := "res://water_yang/cat1_mask.jpg"
const CLOSED_EYES_TEXTURE_PATH := "res://water_yang/cat1_1.jpeg"
const OPEN_MOUTH_TEXTURE_PATH := "res://water_yang/cat1_2.jpeg"
const OPEN_MOUTH_TINT_EXCLUSION_MASK_PATH := "res://water_yang/cat2_mask.jpg"
const TOON_SHADER_PATH := "res://scripts/cat_toon.gdshader"
const OUTLINE_SHADER_PATH := "res://scripts/cat_outline.gdshader"
const REFERENCE_TILE_SIZE := 2.0
const BLINK_INTERVAL_MIN := 2.4
const BLINK_INTERVAL_MAX := 5.2
const BLINK_CLOSED_DURATION := 0.11
const OPEN_MOUTH_CHANCE := 0.22
const OPEN_MOUTH_DURATION := 0.70
const EAR_BONE_PAIRS := [["Bone031", "Bone032"], ["Bone033", "Bone034"]]
const EAR_TWITCH_INTERVAL_MIN := 3.8
const EAR_TWITCH_INTERVAL_MAX := 7.6
const EAR_TWITCH_DURATION := 0.30
const EAR_BASE_TWITCH_ANGLE := deg_to_rad(5.0)
const EAR_TIP_TWITCH_ANGLE := deg_to_rad(9.0)
const TILE_MATERIAL_NAMES := ["Material_cat_tile", "Material cat_tile"]
const TILE_MATERIAL_FALLBACK_SURFACE_INDEX := 1
const TILE_UV_REGION_MIN_U := 0.625
const HEAD_BONE_NAME := "Bone002"
const TAIL_BONE_NAME := "Bone022"
# Bone006 carries the front-paw/chest transition. Keep it rigid so its baked
# shading cannot be pulled down when the cat body gets longer.
const STRETCH_BONE_FIRST := 7
const STRETCH_BONE_LAST := 14
const SCALE_LOCKED_BONE_NAMES := ["Bone001", "Bone002", "Bone017"]
# 코너에 정확히 놓인 본이 어느 선분의 방향을 쓸지 확정하기 위한 미세 편향.
const SEGMENT_PICK_EPSILON := 0.0001

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
		_refresh_shader_material()
		if is_inside_tree() and not Engine.is_editor_hint() and level_manager != null:
			# Remote Inspector changes during Play do not use the editor preview
			# refresh path, so update the live skeleton here.
			_sync_to_grid_position()
			apply_rest_pose()
			level_manager.update_cat_occupancy(self)
		_request_editor_refresh()

@export_range(3, 16, 1) var min_length: int = 3:
	set(value):
		min_length = value

@export_range(2, 32, 1) var max_length: int = 16:
	set(value):
		max_length = value

@export_group("Body")
@export_range(0.1, 16.0, 0.01) var fbx_scale_per_tile: float = 7.65:
	set(value):
		fbx_scale_per_tile = value
		_rebuild_body_visuals()


@export_group("Movement")
# 1_움직임고찰.md 1절. 큐 상한은 항상 `속도 × 0.5초`로 맞춘다.
@export_range(1.0, 24.0, 0.5) var move_speed_cells: float = 8.0
@export_range(1, 12, 1) var path_queue_max: int = 4

@export_group("Toon Shader")
@export var tint_color: Color = Color(1.0, 0.97, 0.97, 1.0):
	set(value):
		tint_color = value
		_refresh_shader_material()

@export_group("Tint Gradient")
@export var tint_gradient_enabled := false:
	set(value):
		tint_gradient_enabled = value
		_refresh_shader_material()

@export var tint_gradient_top_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		tint_gradient_top_color = value
		_refresh_shader_material()

@export var tint_gradient_bottom_color: Color = Color(0.94, 0.90, 0.86, 1.0):
	set(value):
		tint_gradient_bottom_color = value
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

@export_range(0.4, 1.2, 0.01) var top_outline_scale: float = 0.78:
	set(value):
		top_outline_scale = value
		_refresh_shader_material()

@export_range(0.8, 1.6, 0.01) var bottom_outline_scale: float = 1.12:
	set(value):
		bottom_outline_scale = value
		_refresh_shader_material()

@export_group("Internal Line Art")
@export var line_art_texture: Texture2D:
	set(value):
		line_art_texture = value
		_refresh_shader_material()

@export var line_art_color: Color = Color(0.32, 0.24, 0.20, 1.0):
	set(value):
		line_art_color = value
		_refresh_shader_material()

@export_range(0.0, 1.0, 0.01) var line_art_strength: float = 0.82:
	set(value):
		line_art_strength = value
		_refresh_shader_material()


# 몸통이 점유한 칸. 리드(0)에서 반대쪽 끝(마지막)까지 인접한 경로다.
# 리드는 드래그로 끌고 있는 쪽이며, 모델의 얼굴 방향과는 무관하다.
var body_cells: Array[Vector2i] = []
var facing_dir: Vector2i = Vector2i.UP
var level_manager: LevelManager

# 앞으로 리드가 들어갈 셀. 손가락 입력이 여기에 쌓이고 이동은 여기서만 나온다.
var path_queue: Array[Vector2i] = []
# 전이 중 점유 칸. body_cells 앞에 목표 셀을 붙인 것이라 길이가 1칸 많다.
var _rail: Array[Vector2i] = []
var _transition_t := 0.0
var _is_moving := false
# 모델의 머리 본(Bone002)이 body_cells 의 뒤끝에 있는 상태. 리드를 반대쪽으로 잡으면 참이 된다.
var _lead_is_tail := false
var _pending_lead_flip := false
# 마지막 경로 요청이 브릿지를 찾지 못한 상태. 강제 릴리즈 판정에 쓴다.
var _is_blocked := false

var _visual_root: Node3D
var _cat_model: Node3D
var _skeleton: Skeleton3D
var _bone_rests: Array[Transform3D] = []
var _head_bone_index := -1
var _head_bone_rest_global := Transform3D.IDENTITY
var _cat_material: ShaderMaterial
var _material_id_2: ShaderMaterial
var _outline_material: ShaderMaterial
var _material_id_2_outline: ShaderMaterial
var _open_eyes_texture: Texture2D
var _tint_exclusion_mask: Texture2D
var _closed_eyes_texture: Texture2D
var _open_mouth_texture: Texture2D
var _open_mouth_tint_exclusion_mask: Texture2D
var _blink_time_remaining := -1.0
var _eyes_are_closed := false
var _mouth_is_open := false
var _blink_random := RandomNumberGenerator.new()
var _ear_twitch_time_remaining := -1.0
var _ear_twitch_elapsed := 0.0
var _ear_random := RandomNumberGenerator.new()
var _active_ear := 0
var _next_ear := 0
# 머리에서 꼬리까지의 실제 본 인덱스 순서와, 머리 본 기준 rest 누적 거리(모델 로컬 단위).
var _bone_chain: Array[int] = []
var _bone_chain_distances: Array[float] = []
var _rest_chain_length: float = 0.0
# 부모가 항상 자식보다 앞에 오는 본 순서. 로컬 포즈 환산은 이 순서로만 해야 한다.
var _bone_tree_order: Array[int] = []


func _ready() -> void:
	_blink_random.seed = get_instance_id()
	_ear_random.seed = get_instance_id() + 7919
	facing_dir = _direction_from_name(facing_name)
	if body_cells.is_empty():
		_reset_straight_body()
	_ensure_visual_root()

	if Engine.is_editor_hint():
		refresh_editor_preview()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_process_blink(delta)
	_process_ear_twitch(delta)
	advance(delta)


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

	if not _eyes_are_closed:
		_mouth_is_open = _blink_random.randf() < OPEN_MOUTH_CHANCE
		if _mouth_is_open:
			_open_mouth_texture = _get_open_mouth_texture()
			_open_mouth_tint_exclusion_mask = _get_open_mouth_tint_exclusion_mask()
			if _open_mouth_texture == null or _open_mouth_tint_exclusion_mask == null:
				_mouth_is_open = false
	_eyes_are_closed = not _eyes_are_closed
	if not _eyes_are_closed:
		_mouth_is_open = false
	# Rebind every shader input on an eye-texture swap.  Updating only the
	# albedo left the live material dependent on its previous mask binding.
	_apply_shader_parameters(
		_get_active_face_texture(),
		not _eyes_are_closed or _mouth_is_open,
		_eyes_are_closed and not _mouth_is_open,
		_get_active_tint_exclusion_mask()
	)
	if _eyes_are_closed:
		_blink_time_remaining = OPEN_MOUTH_DURATION if _mouth_is_open else BLINK_CLOSED_DURATION
	else:
		_schedule_next_blink()


func _process_ear_twitch(delta: float) -> void:
	if _skeleton == null:
		return

	if _ear_twitch_elapsed > 0.0:
		_ear_twitch_elapsed += delta
		var progress := minf(_ear_twitch_elapsed / EAR_TWITCH_DURATION, 1.0)
		var twitch := sin(progress * TAU * 1.5) * sin(progress * PI)
		_apply_ear_twitch_pose(twitch, _active_ear)
		if progress >= 1.0:
			_apply_ear_twitch_pose(0.0, _active_ear)
			_schedule_next_ear_twitch()
		return

	if _ear_twitch_time_remaining < 0.0:
		_schedule_next_ear_twitch()
		return

	_ear_twitch_time_remaining -= delta
	if _ear_twitch_time_remaining > 0.0:
		return

	_active_ear = _next_ear
	_next_ear = 1 - _next_ear
	_ear_twitch_elapsed = 0.000001


func _apply_ear_twitch_pose(twitch: float, ear_number: int) -> void:
	if _skeleton == null or ear_number < 0 or ear_number >= EAR_BONE_PAIRS.size():
		return
	var direction := 1.0 if ear_number == 0 else -1.0
	var bone_pair: Array = EAR_BONE_PAIRS[ear_number]
	for bone_part in range(bone_pair.size()):
		var bone_index := _skeleton.find_bone(bone_pair[bone_part])
		if bone_index < 0 or bone_index >= _bone_rests.size():
			continue
		var angle := EAR_BASE_TWITCH_ANGLE if bone_part == 0 else EAR_TIP_TWITCH_ANGLE
		var rest_rotation := _bone_rests[bone_index].basis.get_rotation_quaternion()
		_skeleton.set_bone_pose_rotation(
			bone_index,
			rest_rotation * Quaternion(Vector3.FORWARD, twitch * angle * direction)
		)


func refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	level_manager = _find_level_manager()
	if level_manager == null:
		return
	facing_dir = _direction_from_name(facing_name)
	_reset_straight_body()
	_sync_to_grid_position()
	_ensure_visual_root()
	_rebuild_body_visuals()


func initialize_runtime(manager: LevelManager) -> void:
	level_manager = manager
	facing_dir = _direction_from_name(facing_name)
	_reset_straight_body()
	_sync_to_grid_position()
	_ensure_visual_root()
	_rebuild_body_visuals()


func get_head_cell() -> Vector2i:
	return body_cells.front() if not body_cells.is_empty() else grid_pos


func get_tail_cell() -> Vector2i:
	return body_cells.back() if not body_cells.is_empty() else grid_pos


func occupies_cell(cell: Vector2i) -> bool:
	return get_occupied_cells().has(cell)


# ---------------------------------------------------------------- 이동 (1_움직임고찰.md)

# 걸침을 포함한 점유 칸. 전이 중에는 몸 길이보다 1칸 많다.
# 표시용과 판정용이 같은 집합이어야 하므로 양쪽 모두 이 함수만 쓴다.
func get_occupied_cells() -> Array[Vector2i]:
	return _rail if _is_moving else body_cells


func get_lead_cell() -> Vector2i:
	if _is_moving and not _rail.is_empty():
		return _rail[0]
	return body_cells.front() if not body_cells.is_empty() else grid_pos


func get_end_cells() -> Array[Vector2i]:
	if body_cells.size() < 2:
		return [get_lead_cell()]
	return [body_cells.front(), body_cells.back()]


func is_blocked() -> bool:
	return _is_blocked


# 새 터치. 잔여 큐를 버리고, 잡은 쪽이 뒤끝이면 리드를 그쪽으로 넘긴다.
# 전이 중에는 레일을 뒤집지 않고 전이가 끝난 시점으로 미룬다.
func begin_drag(end_cell: Vector2i) -> void:
	path_queue.clear()
	_is_blocked = false
	if body_cells.size() < 2 or end_cell != body_cells.back():
		return
	if _is_moving:
		_pending_lead_flip = true
	else:
		_flip_lead()


func _flip_lead() -> void:
	body_cells.reverse()
	_rail = body_cells.duplicate()
	_lead_is_tail = not _lead_is_tail
	_update_facing()


func _update_facing() -> void:
	if body_cells.size() >= 2:
		facing_dir = body_cells[0] - body_cells[1]


# 손가락이 가리키는 셀까지 큐를 잇는다. 인접하면 한 칸, 끊겼으면 브릿지로 잇는다.
func request_path_to(target: Vector2i) -> void:
	if _pending_lead_flip or level_manager == null:
		return
	if not level_manager.is_inside_grid(target):
		# 보드 밖을 가리키는 것도 닿을 수 없는 상태다. 강제 릴리즈 판정에 들어가야 한다.
		_is_blocked = true
		return
	var future: Array[Vector2i] = _future_body()
	if future.is_empty() or target == future[0]:
		return
	if future.has(target):
		return
	var bridge: Array[Vector2i] = _plan_bridge(future, target)
	if bridge.is_empty():
		_is_blocked = true
		return
	_is_blocked = false
	path_queue.append_array(bridge)


# 큐를 모두 소비한 뒤의 몸 상태. 브릿지 탐색의 출발점이다.
func _future_body() -> Array[Vector2i]:
	var future: Array[Vector2i] = (_rail.slice(0, _rail.size() - 1) if _is_moving else body_cells).duplicate()
	for cell in path_queue:
		future.push_front(cell)
		future.resize(future.size() - 1)
	return future


# (셀, 스텝) BFS. 스텝 k 에서는 몸의 뒤쪽 k 칸이 이미 비켜난 것으로 본다.
func _plan_bridge(future: Array[Vector2i], target: Vector2i) -> Array[Vector2i]:
	var budget: int = path_queue_max - path_queue.size()
	if budget <= 0:
		return []

	var start: Vector2i = future[0]
	var start_dir: Vector2i = (start - future[1]) if future.size() >= 2 else facing_dir
	var came := {}
	var frontier: Array = [[start, 0, start_dir]]
	came[Vector3i(start.x, start.y, 0)] = null

	while not frontier.is_empty():
		var node: Array = frontier.pop_front()
		var cell: Vector2i = node[0]
		var step: int = node[1]
		if step >= budget:
			continue
		for dir in _neighbor_order(node[2]):
			var next: Vector2i = cell + dir
			var next_step: int = step + 1
			var key := Vector3i(next.x, next.y, next_step)
			if came.has(key):
				continue
			if not _is_cell_free_at_step(future, next, next_step):
				continue
			if _path_contains(came, Vector3i(cell.x, cell.y, step), next):
				continue
			came[key] = Vector3i(cell.x, cell.y, step)
			if next == target:
				return _rebuild_path(came, key)
			frontier.append([next, next_step, dir])
	return []


# 직전 진행 방향을 먼저 펼쳐 동일 코스트 경로에서 결정성을 확보한다.
func _neighbor_order(previous_dir: Vector2i) -> Array[Vector2i]:
	var base: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	if not base.has(previous_dir):
		return base
	var ordered: Array[Vector2i] = [previous_dir]
	for dir in base:
		if dir != previous_dir and dir != -previous_dir:
			ordered.append(dir)
	ordered.append(-previous_dir)
	return ordered


func _is_cell_free_at_step(future: Array[Vector2i], cell: Vector2i, step: int) -> bool:
	if level_manager == null or not level_manager.is_inside_grid(cell):
		return false
	if level_manager.is_cell_blocked_for(self, cell):
		return false
	var index: int = future.find(cell)
	# 뒤에서 step 칸은 그때쯤 이미 비켜났다.
	return index < 0 or index + step > future.size() - 1


func _path_contains(came: Dictionary, key: Vector3i, cell: Vector2i) -> bool:
	var current: Variant = key
	while current != null:
		var node: Vector3i = current
		if node.x == cell.x and node.y == cell.y:
			return true
		current = came.get(node)
	return false


func _rebuild_path(came: Dictionary, key: Vector3i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current: Variant = key
	while current != null:
		var node: Vector3i = current
		var parent: Variant = came.get(node)
		if parent == null:
			break
		path.push_front(Vector2i(node.x, node.y))
		current = parent
	return path


func advance(delta: float) -> void:
	if level_manager == null or body_cells.is_empty():
		return
	var remaining: float = delta * move_speed_cells
	while remaining > 0.0:
		if not _is_moving and not _begin_step():
			break
		var step: float = minf(remaining, 1.0 - _transition_t)
		_transition_t += step
		remaining -= step
		if _transition_t >= 1.0 - 0.000001:
			_finish_step()
	_update_visual_pose()


func _begin_step() -> bool:
	if _pending_lead_flip:
		_pending_lead_flip = false
		_flip_lead()
	if path_queue.is_empty():
		return false
	var next: Vector2i = path_queue[0]
	# 판정은 셀 중앙에서 커밋하는 이 순간뿐이다. 시작한 전이는 반드시 끝까지 간다.
	if not can_enter(next):
		path_queue.clear()
		_is_blocked = true
		return false
	path_queue.remove_at(0)
	_rail = body_cells.duplicate()
	_rail.push_front(next)
	_transition_t = 0.0
	_is_moving = true
	level_manager.update_cat_occupancy(self)
	return true


func _finish_step() -> void:
	body_cells = _rail.slice(0, _rail.size() - 1)
	_rail = body_cells.duplicate()
	_transition_t = 0.0
	_is_moving = false
	_update_facing()
	level_manager.update_cat_occupancy(self)
	if _pending_lead_flip:
		_pending_lead_flip = false
		_flip_lead()
	# grid_pos 세터는 몸을 직선으로 되돌리는 레이아웃용이다. 이동 중에는 건드리지 않고
	# 실제 위치는 언제나 body_cells 로만 읽는다.


func can_enter(cell: Vector2i) -> bool:
	if level_manager == null or not level_manager.is_inside_grid(cell):
		return false
	if level_manager.is_cell_blocked_for(self, cell):
		return false
	# 뒤끝 칸도 막힌다. 전이 중 뒤끝은 아직 0.5칸을 점유한다.
	return not body_cells.has(cell)


func _reset_straight_body() -> void:
	facing_dir = _direction_from_name(facing_name)
	path_queue.clear()
	_transition_t = 0.0
	_is_moving = false
	_lead_is_tail = false
	_pending_lead_flip = false
	_is_blocked = false
	body_cells.clear()
	var length := clampi(initial_length, min_length, max_length)
	# 머리는 grid_pos에 두고 몸통은 바라보는 방향의 반대쪽으로 놓는다.
	for index in range(length):
		body_cells.append(grid_pos - facing_dir * index)
	_rail = body_cells.duplicate()


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


func _rebuild_body_visuals() -> void:
	# FBX 인스턴스는 한 번만 만든다.
	if _visual_root == null or level_manager == null:
		return

	for child in _visual_root.get_children():
		child.free()

	_cat_model = load_model_with_texture()
	_cat_model.name = "SkinnedCat"
	_visual_root.add_child(_cat_model)
	_skeleton = _find_skeleton_in(_cat_model)
	_cache_bone_rests()
	# 타일 머티리얼의 반복 횟수는 캐시된 rest 길이에 의존한다.
	_apply_current_shader_parameters()
	apply_rest_pose()


# 정지 자세는 폴리라인이 직선인 이동 자세일 뿐이다. 두 경로를 따로 두지 않는다.
func apply_rest_pose() -> void:
	_update_visual_pose()


# 몸을 셀 중심 폴리라인 위에 올린다. 본 위치는 호 길이로 직접 구하며
# 회전을 누적해 포즈를 재구성하지 않는다. 그것이 이 프로젝트의 단골 실패 모드다.
func _update_visual_pose() -> void:
	if _cat_model == null or _skeleton == null or level_manager == null:
		return
	if _bone_chain.is_empty() or body_cells.is_empty():
		return

	var polyline: PackedVector3Array = _body_polyline()
	if polyline.size() < 2:
		return
	var cumulative: PackedFloat32Array = _cumulative_lengths(polyline)
	var total_length: float = cumulative[cumulative.size() - 1]
	if total_length <= 0.000001:
		return

	var model_scale := _grid_fitted_model_scale()
	var chain_distances: PackedFloat32Array = _stretched_chain_distances()
	# 리드를 반대쪽 끝으로 잡으면 모델의 머리 본은 폴리라인 반대편 끝에 놓인다.
	var head_arc: float = total_length if _lead_is_tail else 0.0
	var head_dir: Vector3 = _model_head_direction(polyline, cumulative, head_arc)

	position = _sample_polyline(polyline, cumulative, head_arc)
	rotation = Vector3.ZERO
	scale = Vector3.ONE
	# FBX 로컬 +Y 는 머리가 바라보는 방향이다. 상체 비율 보존을 위해 균일 스케일만 쓴다.
	_cat_model.basis = _fbx_basis_for_direction(head_dir)
	_cat_model.scale = Vector3.ONE * model_scale
	# 노드 원점이 머리 본 위치이므로, 머리 본이 원점에 오도록 모델을 밀어 준다.
	_cat_model.position = _cat_model.basis * (-_head_bone_rest_global.origin)

	var cat_to_skeleton: Transform3D = global_transform.affine_inverse() * _skeleton.global_transform
	var skeleton_rotation: Basis = cat_to_skeleton.basis.orthonormalized()
	var skeleton_rotation_inverse: Basis = skeleton_rotation.inverse()
	var reference_inverse: Basis = _fbx_basis_for_direction(head_dir).inverse()
	var to_skeleton: Transform3D = cat_to_skeleton.affine_inverse()

	var desired := {}
	for chain_index in _bone_chain.size():
		var arc: float = chain_distances[chain_index] * model_scale
		var arc_from_lead: float = (total_length - arc) if _lead_is_tail else arc
		var point: Vector3 = _sample_polyline(polyline, cumulative, arc_from_lead)
		var direction: Vector3 = _model_head_direction(polyline, cumulative, arc_from_lead)
		var bone_index: int = _bone_chain[chain_index]
		var rest_basis: Basis = _skeleton.get_bone_global_rest(bone_index).basis
		# 기준 자세(머리 방향)에서 이 본의 접선 방향으로 돌리는 회전만 얹는다.
		var posed_basis: Basis = (
			skeleton_rotation_inverse
			* _fbx_basis_for_direction(direction)
			* reference_inverse
			* skeleton_rotation
			* rest_basis
		)
		desired[bone_index] = Transform3D(posed_basis.orthonormalized(), to_skeleton * (point - position))

	_apply_bone_globals(desired)


# 계산한 글로벌 포즈를 부모부터 순서대로 로컬 포즈로 환산해 넣는다.
# 글로벌 오버라이드를 쓰지 않으므로 "계산한 자리 vs 실제 본 위치"가 어긋날 여지가 없다.
func _apply_bone_globals(desired: Dictionary) -> void:
	var computed := {}
	for bone_index in _bones_in_tree_order():
		var parent_index: int = _skeleton.get_bone_parent(bone_index)
		var parent_global: Transform3D = computed.get(parent_index, Transform3D.IDENTITY)
		var local: Transform3D
		if desired.has(bone_index):
			local = parent_global.affine_inverse() * (desired[bone_index] as Transform3D)
			# 비균일 스케일은 회전과 교환되지 않아 자식 간격을 표류시킨다. 항상 균일하게 둔다.
			local.basis = local.basis.orthonormalized()
			_skeleton.set_bone_pose_position(bone_index, local.origin)
			_skeleton.set_bone_pose_rotation(bone_index, local.basis.get_rotation_quaternion())
			_skeleton.set_bone_pose_scale(bone_index, local.basis.get_scale())
		else:
			# 체인 밖 본은 손대지 않는다. 여기서 rest 로 덮으면 귀 모션 같은 다른
			# 포즈가 매 프레임 지워진다. 현재 포즈를 그대로 읽어 부모 누적에만 쓴다.
			local = _skeleton.get_bone_pose(bone_index)
		computed[bone_index] = parent_global * local
	_enforce_locked_bone_scales()


func _bones_in_tree_order() -> Array[int]:
	if not _bone_tree_order.is_empty():
		return _bone_tree_order
	var placed := {}
	while _bone_tree_order.size() < _skeleton.get_bone_count():
		var added := false
		for bone_index in _skeleton.get_bone_count():
			if placed.has(bone_index):
				continue
			var parent_index: int = _skeleton.get_bone_parent(bone_index)
			if parent_index >= 0 and not placed.has(parent_index):
				continue
			placed[bone_index] = true
			_bone_tree_order.append(bone_index)
			added = true
		if not added:
			break
	return _bone_tree_order


# 리드 → 반대쪽 끝 순서의 셀 중심 폴리라인. 전이 중에는 양 끝만 셀 사이에 놓인다.
func _body_polyline() -> PackedVector3Array:
	var points := PackedVector3Array()
	var height := level_manager.cat_world_y
	if not _is_moving or _rail.size() < 3:
		for cell in body_cells:
			points.append(level_manager.grid_to_world(cell, height))
		return points

	var last := _rail.size() - 1
	points.append(
		level_manager.grid_to_world(_rail[1], height).lerp(
			level_manager.grid_to_world(_rail[0], height), _transition_t
		)
	)
	for index in range(1, last):
		points.append(level_manager.grid_to_world(_rail[index], height))
	points.append(
		level_manager.grid_to_world(_rail[last], height).lerp(
			level_manager.grid_to_world(_rail[last - 1], height), _transition_t
		)
	)
	return points


func _cumulative_lengths(polyline: PackedVector3Array) -> PackedFloat32Array:
	var lengths := PackedFloat32Array()
	lengths.append(0.0)
	var total := 0.0
	for index in range(1, polyline.size()):
		total += polyline[index - 1].distance_to(polyline[index])
		lengths.append(total)
	return lengths


func _sample_polyline(
	polyline: PackedVector3Array, cumulative: PackedFloat32Array, arc: float
) -> Vector3:
	var target := clampf(arc, 0.0, cumulative[cumulative.size() - 1])
	var segment := _segment_index_at(cumulative, target)
	var span: float = cumulative[segment + 1] - cumulative[segment]
	if span <= 0.000001:
		return polyline[segment]
	return polyline[segment].lerp(polyline[segment + 1], (target - cumulative[segment]) / span)


# 이 위치에서 모델의 머리가 향하는 방향. 폴리라인 선분 방향을 그대로 쓰므로
# 코너 회전이 여러 관절에 나눠지지 않고 코너를 낀 두 본 사이에서만 일어난다.
func _model_head_direction(
	polyline: PackedVector3Array, cumulative: PackedFloat32Array, arc: float
) -> Vector3:
	var total: float = cumulative[cumulative.size() - 1]
	# 경계에서는 머리 쪽 선분을 택한다. 그래야 코너 본의 방향이 한쪽으로 확정된다.
	var bias := SEGMENT_PICK_EPSILON if _lead_is_tail else -SEGMENT_PICK_EPSILON
	var segment := _segment_index_at(cumulative, clampf(arc + bias, 0.0, total))
	var direction := _segment_direction(polyline, segment)
	if direction.length_squared() < 0.000001:
		direction = level_manager.grid_dir_to_world(facing_dir)
		return direction if direction.length_squared() > 0.000001 else Vector3.FORWARD
	return direction if _lead_is_tail else -direction


# 길이가 0인 선분(전이 시작 순간의 끝 조각)은 건너뛰고 가장 가까운 유효 선분을 쓴다.
func _segment_direction(polyline: PackedVector3Array, segment: int) -> Vector3:
	var count := polyline.size() - 1
	for offset in count:
		for candidate in [segment - offset, segment + offset]:
			if candidate < 0 or candidate >= count:
				continue
			var delta: Vector3 = polyline[candidate + 1] - polyline[candidate]
			if delta.length_squared() > 0.000001:
				return delta.normalized()
	return Vector3.ZERO


func _segment_index_at(cumulative: PackedFloat32Array, arc: float) -> int:
	var last := cumulative.size() - 2
	for index in range(last, -1, -1):
		if arc >= cumulative[index]:
			return index
	return 0


# 늘어나는 구간(Bone007~014)에만 배율을 준 누적 거리. 총합은 셀 중심 경로 길이와 같아진다.
func _stretched_chain_distances() -> PackedFloat32Array:
	var distances := PackedFloat32Array()
	distances.append(0.0)
	var stretch := _baseline_stretch_scale()
	var total := 0.0
	for chain_index in range(1, _bone_chain.size()):
		var segment: float = _bone_chain_distances[chain_index] - _bone_chain_distances[chain_index - 1]
		if _is_stretchable_chain_bone(chain_index):
			segment *= stretch
		total += segment
		distances.append(total)
	return distances


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
	_bone_tree_order.clear()
	_rest_chain_length = 0.0
	_head_bone_index = -1
	_head_bone_rest_global = Transform3D.IDENTITY
	if _skeleton == null:
		return
	for index in _skeleton.get_bone_count():
		_bone_rests.append(_skeleton.get_bone_rest(index))
	_head_bone_index = _skeleton.find_bone(HEAD_BONE_NAME)
	if _head_bone_index >= 0:
		_head_bone_rest_global = _skeleton.get_bone_global_rest(_head_bone_index)
	_build_bone_chain()


func _build_bone_chain() -> void:
	# 본 순서를 상수로 적어두지 않고 부모-자식 링크를 따라 머리에서 꼬리까지 실제로 걷는다.
	# 리그가 바뀌어도 경로 순서와 관절 간격이 자동으로 따라온다.
	var head_index := _skeleton.find_bone(HEAD_BONE_NAME)
	var tail_index := _skeleton.find_bone(TAIL_BONE_NAME)
	if head_index < 0 or tail_index < 0:
		return
	var head_to_root: Array[int] = _bone_path_to_root(head_index)
	var tail_to_root: Array[int] = _bone_path_to_root(tail_index)
	if head_to_root.is_empty() or tail_to_root.is_empty():
		return

	tail_to_root.reverse()
	if head_to_root.back() == tail_to_root.front():
		# 공통 조상이 있는 일반적인 경우. 머리에서 조상까지 올라갔다가 꼬리로 내려간다.
		_bone_chain = head_to_root
		for index in range(1, tail_to_root.size()):
			_bone_chain.append(tail_to_root[index])
	else:
		# cat1.fbx 의 Bone002 는 스키닝 체인과 부모 링크가 없는 별도 루트 본이다.
		# 부모를 따라가면 몸통 체인에 닿지 못하므로 머리 끝 본으로 앞에 붙인다.
		_bone_chain = [head_index]
		_bone_chain.append_array(tail_to_root)

	# 관절 간격은 부모 링크의 로컬 오프셋이 아니라 rest 글로벌 위치의 실제 거리로 잰다.
	# 분기 리그와 링크가 끊긴 루트 본을 함께 다루려면 이 방식이어야 한다.
	var distance := 0.0
	_bone_chain_distances.append(0.0)
	for chain_index in range(1, _bone_chain.size()):
		var previous_origin: Vector3 = _skeleton.get_bone_global_rest(_bone_chain[chain_index - 1]).origin
		var current_origin: Vector3 = _skeleton.get_bone_global_rest(_bone_chain[chain_index]).origin
		distance += previous_origin.distance_to(current_origin)
		_bone_chain_distances.append(distance)

	_rest_chain_length = distance


func _bone_path_to_root(bone_index: int) -> Array[int]:
	var path: Array[int] = []
	var current := bone_index
	while current >= 0:
		path.append(current)
		current = _skeleton.get_bone_parent(current)
	return path


func _grid_fitted_model_scale() -> float:
	if level_manager == null:
		return fbx_scale_per_tile
	# 자동 체인 길이 보정(약 6.0)은 기준 모델(7.65)보다 작아 상체가 축소되어 보였다.
	# 에디터 기준과 동일한 FBX 균일 스케일을 고정 사용한다.
	return fbx_scale_per_tile * level_manager.tile_size / REFERENCE_TILE_SIZE


func _is_stretchable_chain_bone(chain_index: int) -> bool:
	if _skeleton == null or chain_index < 0 or chain_index >= _bone_chain.size():
		return false
	var bone_name := _skeleton.get_bone_name(_bone_chain[chain_index])
	var bone_number := bone_name.trim_prefix("Bone").to_int()
	return bone_number >= STRETCH_BONE_FIRST and bone_number <= STRETCH_BONE_LAST


func _stretchable_rest_length() -> float:
	var total := 0.0
	for chain_index in range(1, _bone_chain_distances.size()):
		if _is_stretchable_chain_bone(chain_index):
			total += _bone_chain_distances[chain_index] - _bone_chain_distances[chain_index - 1]
	return total


func _fitted_stretch_scale(target_world_length: float) -> float:
	# 체인 전체 길이가 target_world_length 와 정확히 같아지는 중간 구간 배율을 구한다.
	# 머리/꼬리(Bone006 밖)는 늘어나지 않으므로 그만큼을 뺀 나머지를 중간이 흡수한다.
	var stretchable_length := _stretchable_rest_length()
	var model_scale := _grid_fitted_model_scale()
	if stretchable_length <= 0.000001 or model_scale <= 0.000001:
		return 1.0
	var target_model_length := target_world_length / model_scale
	var fixed_length := _rest_chain_length - stretchable_length
	# Keep a small positive lower bound for the inspector's minimum length of 2.
	return maxf(0.05, (target_model_length - fixed_length) / stretchable_length)


func _baseline_stretch_scale() -> float:
	# 정지 직선 상태에서 머리 셀 중심 ~ 꼬리 셀 중심 거리에 맞춘 배율.
	# 텍스처 반복은 이 고정값으로 계산해 이동 중 패턴이 기어가지 않게 한다.
	if level_manager == null:
		return 1.0
	var cells := maxi(body_cells.size() - 1, 1)
	return _fitted_stretch_scale(float(cells) * level_manager.tile_size)

func _fbx_basis_for_direction(direction: Vector3) -> Basis:
	# FBX local Y is the body length and local +Z is the face side.
	# Keep the face side toward world up while only the body length follows the grid path.
	var body_axis := direction.normalized()
	var face_axis := Vector3.UP
	var side_axis := body_axis.cross(face_axis).normalized()
	return Basis(side_axis, body_axis, face_axis)


# FBX와 텍스처 로더는 향후 리깅된 머리/꼬리 모델로 교체할 때 그대로 사용한다.
func load_model_with_texture() -> Node3D:
	var packed_scene := load(MODEL_SCENE_PATH) as PackedScene
	var model_root := packed_scene.instantiate() as Node3D if packed_scene != null else Node3D.new()
	_build_cat_material()
	_apply_material_recursive(model_root)
	return model_root


func _find_skeleton_in(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var skeleton := _find_skeleton_in(child)
		if skeleton != null:
			return skeleton
	return null


func _apply_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		# Keep the FBX material split. A material override would flatten both
		# surfaces into one, preventing body-only UV tiling correction.
		mesh_instance.material_override = null
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				var material: Material = _cat_material
				if _is_tile_material_surface(mesh_instance, surface_index) and _material_id_2 != null:
					material = _material_id_2
				mesh_instance.set_surface_override_material(surface_index, material)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	for child in node.get_children():
		_apply_material_recursive(child)


func _is_tile_material_surface(mesh_instance: MeshInstance3D, surface_index: int) -> bool:
	var source_material := mesh_instance.mesh.surface_get_material(surface_index) if mesh_instance.mesh != null else null
	# Godot can import FBX materials as unnamed subresources, so resource_name is
	# not reliable by itself. This FBX orders Material_cat first and
	# Material cat_tile second; retain that verified slot as a fallback.
	return (
		source_material != null and source_material.resource_name in TILE_MATERIAL_NAMES
	) or surface_index == TILE_MATERIAL_FALLBACK_SURFACE_INDEX


func _build_cat_material() -> void:
	var shader := load(TOON_SHADER_PATH) as Shader
	var outline_shader := load(OUTLINE_SHADER_PATH) as Shader
	var texture := _get_open_eyes_texture()
	if shader == null:
		_cat_material = null
		_material_id_2 = null
		_outline_material = null
		_material_id_2_outline = null
		return
	_cat_material = ShaderMaterial.new()
	_material_id_2 = ShaderMaterial.new()
	_outline_material = null
	_material_id_2_outline = null
	_cat_material.shader = shader
	_material_id_2.shader = shader

	# Render the expanded, front-face-culled outline as a next pass. This keeps
	# it on the same skinned mesh, so the outline always follows the cat pose.
	if outline_shader != null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = outline_shader
		_material_id_2_outline = ShaderMaterial.new()
		_material_id_2_outline.shader = outline_shader
		_cat_material.next_pass = _outline_material
		_material_id_2.next_pass = _material_id_2_outline

	_apply_shader_parameters(texture)


func _refresh_shader_material() -> void:
	# Export setters also run while the node is deserializing, before its visual
	# model exists. Defer once so inspector edits update a live material safely.
	call_deferred("_apply_current_shader_parameters")


func _apply_current_shader_parameters() -> void:
	if _cat_material == null:
		if Engine.is_editor_hint():
			_request_editor_refresh()
		return
	_apply_shader_parameters(
		_get_active_face_texture(),
		not _eyes_are_closed or _mouth_is_open,
		_eyes_are_closed and not _mouth_is_open,
		_get_active_tint_exclusion_mask()
	)


func _get_tint_gradient_axis() -> Vector2:
	# The FBX's local Y axis runs from head to tail. Bone rest positions provide
	# a stable range shared by every material slot, unlike disconnected UV islands.
	if _skeleton == null or _bone_chain.is_empty():
		return Vector2(1.0, -1.0)
	var head_y := _skeleton.get_bone_global_rest(_bone_chain[0]).origin.y
	var tail_y := _skeleton.get_bone_global_rest(_bone_chain[-1]).origin.y
	if is_equal_approx(head_y, tail_y):
		return Vector2(head_y + 0.5, head_y - 0.5)
	return Vector2(head_y, tail_y)


func _apply_shader_parameters(
	texture: Texture2D,
	use_tint_exclusion_mask := true,
	hide_line_art_eyes := false,
	custom_tint_exclusion_mask: Texture2D = null
) -> void:
	var tint_exclusion_mask: Texture2D = custom_tint_exclusion_mask if custom_tint_exclusion_mask != null else _get_tint_exclusion_mask()
	var gradient_axis := _get_tint_gradient_axis()
	if _cat_material != null:
		_cat_material.set_shader_parameter("albedo_tex", texture)
		_cat_material.set_shader_parameter("tint_exclusion_mask", tint_exclusion_mask)
		_cat_material.set_shader_parameter("tint_exclusion_enabled", 1.0 if use_tint_exclusion_mask else 0.0)
		_cat_material.set_shader_parameter("tint_color", tint_color)
		_cat_material.set_shader_parameter("tint_gradient_enabled", 1.0 if tint_gradient_enabled else 0.0)
		_cat_material.set_shader_parameter("tint_gradient_top_color", tint_gradient_top_color)
		_cat_material.set_shader_parameter("tint_gradient_bottom_color", tint_gradient_bottom_color)
		_cat_material.set_shader_parameter("tint_gradient_head_y", gradient_axis.x)
		_cat_material.set_shader_parameter("tint_gradient_tail_y", gradient_axis.y)
		_cat_material.set_shader_parameter("shadow_steps", toon_steps)
		_cat_material.set_shader_parameter("shadow_darkness", shadow_darkness)
		_cat_material.set_shader_parameter("rim_strength", rim_strength)
		_cat_material.set_shader_parameter("line_art_tex", line_art_texture)
		_cat_material.set_shader_parameter("line_art_eye_mask", _get_tint_exclusion_mask())
		_cat_material.set_shader_parameter("line_art_enabled", 1.0 if line_art_texture != null else 0.0)
		_cat_material.set_shader_parameter("line_art_eyes_hidden", 1.0 if hide_line_art_eyes else 0.0)
		_cat_material.set_shader_parameter("line_art_color", line_art_color)
		_cat_material.set_shader_parameter("line_art_strength", line_art_strength)
	if _material_id_2 != null:
		# Material cat_tile covers the Bone006..Bone014 section. Only this section
		# is moved to change the cat's length, so its UV repeats must follow the
		# actual pose extension rather than the total grid-length ratio.
		var tile_scale := _baseline_stretch_scale()
		_material_id_2.set_shader_parameter("albedo_tex", texture)
		_material_id_2.set_shader_parameter("tint_exclusion_mask", tint_exclusion_mask)
		_material_id_2.set_shader_parameter("tint_exclusion_enabled", 1.0 if use_tint_exclusion_mask else 0.0)
		_material_id_2.set_shader_parameter("tint_color", tint_color)
		_material_id_2.set_shader_parameter("tint_gradient_enabled", 1.0 if tint_gradient_enabled else 0.0)
		_material_id_2.set_shader_parameter("tint_gradient_top_color", tint_gradient_top_color)
		_material_id_2.set_shader_parameter("tint_gradient_bottom_color", tint_gradient_bottom_color)
		_material_id_2.set_shader_parameter("tint_gradient_head_y", gradient_axis.x)
		_material_id_2.set_shader_parameter("tint_gradient_tail_y", gradient_axis.y)
		_material_id_2.set_shader_parameter("shadow_steps", toon_steps)
		_material_id_2.set_shader_parameter("shadow_darkness", shadow_darkness)
		_material_id_2.set_shader_parameter("rim_strength", rim_strength)
		_material_id_2.set_shader_parameter("line_art_tex", line_art_texture)
		_material_id_2.set_shader_parameter("line_art_eye_mask", _get_tint_exclusion_mask())
		_material_id_2.set_shader_parameter("line_art_enabled", 1.0 if line_art_texture != null else 0.0)
		_material_id_2.set_shader_parameter("line_art_eyes_hidden", 1.0 if hide_line_art_eyes else 0.0)
		_material_id_2.set_shader_parameter("line_art_color", line_art_color)
		_material_id_2.set_shader_parameter("line_art_strength", line_art_strength)
		_material_id_2.set_shader_parameter("tile_uv_min_u", TILE_UV_REGION_MIN_U)
		# Material cat_tile already uses the right-side tile region in its UV map.
		# Keep U unchanged; repeat only along its vertical V direction.
		_material_id_2.set_shader_parameter("uv_tiling", Vector2(1.0, tile_scale))
		_material_id_2.set_shader_parameter("uv_offset", Vector2(0.0, (1.0 - tile_scale) * 0.5))
	if _outline_material != null:
		_outline_material.set_shader_parameter("outline_color", outline_color)
		_outline_material.set_shader_parameter("outline_width", outline_width)
		_outline_material.set_shader_parameter("top_outline_scale", top_outline_scale)
		_outline_material.set_shader_parameter("bottom_outline_scale", bottom_outline_scale)
	if _material_id_2_outline != null:
		_material_id_2_outline.set_shader_parameter("outline_color", outline_color)
		_material_id_2_outline.set_shader_parameter("outline_width", outline_width)
		_material_id_2_outline.set_shader_parameter("top_outline_scale", top_outline_scale)
		_material_id_2_outline.set_shader_parameter("bottom_outline_scale", bottom_outline_scale)


func _get_open_eyes_texture() -> Texture2D:
	if _open_eyes_texture == null:
		_open_eyes_texture = load(MODEL_TEXTURE_PATH) as Texture2D
	return _open_eyes_texture


func _get_open_mouth_texture() -> Texture2D:
	if _open_mouth_texture == null:
		_open_mouth_texture = load(OPEN_MOUTH_TEXTURE_PATH) as Texture2D
	return _open_mouth_texture


func _get_tint_exclusion_mask() -> Texture2D:
	if _tint_exclusion_mask == null:
		_tint_exclusion_mask = load(TINT_EXCLUSION_MASK_PATH) as Texture2D
	return _tint_exclusion_mask


func _get_open_mouth_tint_exclusion_mask() -> Texture2D:
	if _open_mouth_tint_exclusion_mask == null:
		_open_mouth_tint_exclusion_mask = load(OPEN_MOUTH_TINT_EXCLUSION_MASK_PATH) as Texture2D
	return _open_mouth_tint_exclusion_mask


func _get_active_face_texture() -> Texture2D:
	if _mouth_is_open:
		return _get_open_mouth_texture()
	if _eyes_are_closed:
		return _closed_eyes_texture
	return _get_open_eyes_texture()


func _get_active_tint_exclusion_mask() -> Texture2D:
	if _mouth_is_open:
		return _get_open_mouth_tint_exclusion_mask()
	if _eyes_are_closed:
		return null
	return _get_tint_exclusion_mask()


func _schedule_next_blink() -> void:
	_eyes_are_closed = false
	_blink_time_remaining = _blink_random.randf_range(BLINK_INTERVAL_MIN, BLINK_INTERVAL_MAX)


func _schedule_next_ear_twitch() -> void:
	_ear_twitch_elapsed = 0.0
	_ear_twitch_time_remaining = _ear_random.randf_range(
		EAR_TWITCH_INTERVAL_MIN, EAR_TWITCH_INTERVAL_MAX
	)


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
