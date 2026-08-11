@tool
class_name CatEntity
extends Node3D

const MODEL_SCENE_PATH := "res://water_yang/cat1.fbx"
const MODEL_TEXTURE_PATH := "res://water_yang/cat1.jpeg"
const TINT_EXCLUSION_MASK_PATH := "res://water_yang/cat1_mask.jpg"
const CLOSED_EYES_TEXTURE_PATH := "res://water_yang/cat1_1.jpeg"
const TOON_SHADER_PATH := "res://scripts/cat_toon.gdshader"
const OUTLINE_SHADER_PATH := "res://scripts/cat_outline.gdshader"
const REFERENCE_TILE_SIZE := 2.0
const BLINK_INTERVAL_MIN := 2.4
const BLINK_INTERVAL_MAX := 5.2
const BLINK_CLOSED_DURATION := 0.11
const TILE_MATERIAL_NAMES := ["Material_cat_tile", "Material cat_tile"]
const TILE_MATERIAL_FALLBACK_SURFACE_INDEX := 1
const TILE_UV_REGION_MIN_U := 0.625
# The source FBX is authored at four cells.  Length 3 is the game minimum,
# so it must shrink the middle section relative to this reference.
const BODY_TEXTURE_REFERENCE_LENGTH := 4
const HEAD_BONE_NAME := "Bone002"
const TAIL_BONE_NAME := "Bone022"
# Bone006 carries the front-paw/chest transition. Keep it rigid so its baked
# shading cannot be pulled down when the cat body gets longer.
const STRETCH_BONE_FIRST := 7
const STRETCH_BONE_LAST := 14
# 드래그 중 코너를 깎을 때 원호를 몇 조각으로 나눌지.
const CORNER_ARC_SEGMENTS := 6
# 입력 이벤트 하나가 확정할 수 있는 최대 셀 이동 수. 빠른 스와이프용 안전장치다.
const MAX_COMMITS_PER_UPDATE := 8
# 90° 필렛이 경로를 줄이는 길이 / 반지름. 2 - PI/2 다.
const CORNER_ARC_SHORTENING := 0.4292
# 이미 미끄러지고 있는 축에 주는 가산점(타일 단위).
const SLIDE_AXIS_HYSTERESIS := 0.2
# 다른 축으로 바꾸려면 마우스가 그 방향 셀 경계를 실제로 넘어야 한다. 타일 반폭이다.
const SLIDE_AXIS_SWITCH := 0.5
# 이 값보다 많이 미끄러져 있으면 축을 바꾸지 않는다. 코너는 셀 중심에서만 돈다.
const SLIDE_SWITCH_EPSILON := 0.02
# 이 거리(타일 비율) 안에서는 축을 고르지 않는다. 0에 가까운 입력에서 축이 무작위로
# 잡히는 것만 막는 용도이므로 아주 작게 둔다. 크게 잡으면 드래그 시작에 팝이 생긴다.
const SLIDE_DEAD_ZONE := 0.02
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
		_refresh_shader_material()
		if is_inside_tree() and not Engine.is_editor_hint() and level_manager != null:
			# Remote Inspector changes during Play do not use the editor preview
			# refresh path, so update the live skeleton and endpoint handles here.
			_sync_to_grid_position()
			snap_pose_to_grid()
			_update_endpoint_handles()
			level_manager.update_cat_occupancy(self)
		_request_editor_refresh()

@export_range(3, 16, 1) var min_length: int = 3:
	set(value):
		min_length = value

@export_range(2, 32, 1) var max_length: int = 16:
	set(value):
		max_length = value

@export_enum("follow", "stretch") var endpoint_drag_mode: String = "follow"

@export_group("Motion")
# 드래그를 시작할 때 코너 라운딩이 켜지는 시간.
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

@export_range(-1.0, 1.0, 0.01) var visual_forward_offset_tiles: float = 0.0:
	set(value):
		visual_forward_offset_tiles = value
		if is_inside_tree() and level_manager != null:
			snap_pose_to_grid()

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
var _head_bone_index := -1
var _head_bone_rest_global := Transform3D.IDENTITY
var _cat_material: ShaderMaterial
var _material_id_2: ShaderMaterial
var _outline_material: ShaderMaterial
var _material_id_2_outline: ShaderMaterial
var _open_eyes_texture: Texture2D
var _tint_exclusion_mask: Texture2D
var _closed_eyes_texture: Texture2D
var _blink_time_remaining := -1.0
var _eyes_are_closed := false
var _blink_random := RandomNumberGenerator.new()
# 머리에서 꼬리까지의 실제 본 인덱스 순서와, 머리 본 기준 rest 누적 거리(모델 로컬 단위).
var _bone_chain: Array[int] = []
var _bone_chain_distances: Array[float] = []
var _rest_chain_length: float = 0.0
# 머리가 셀 사이 어디쯤 있는지. _slide_cell 로 향해 _slide_t(0..1) 만큼 나아간 상태다.
var _slide_cell: Vector2i = Vector2i.ZERO
var _slide_t: float = 0.0
var _slide_valid: bool = false
var _slide_axis: Vector2i = Vector2i.ZERO
# 축이 바뀐 순간의 진행량. 여기서부터 0으로 다시 세어야 전환 지점에서 머리가 튀지 않는다.
var _axis_entry: float = 0.0
var _drag_endpoint: StringName = &"head"
# 잡은 순간 손가락이 셀 중심에서 얼마나 빗겨 있었는지. 이후 좌표에서 계속 빼 준다.
# 이 보정이 없으면 빗겨 잡은 만큼이 영구 편향으로 남아 옆칸으로 튀어나간다.
var _grab_offset: Vector3 = Vector3.ZERO
# 이동 중 1, 정지 시 0. 방향 샘플링을 연속(현) / 예각(접선) 중 무엇으로 할지 결정한다.
var _smooth_weight: float = 0.0
# 머리가 향한 방향(로컬). 레일은 슬라이드가 시작되는 순간 머리 셀에서 꺾이므로,
# 그대로 쓰면 코가 한 프레임에 한 칸 가까이 순간이동한다. 시간축으로 따라가게 한다.
var _forward: Vector3 = Vector3.ZERO
var _track_head_index: int = 0
# 머리가 지금 어느 쪽 이웃 칸을 향해 미끄러지는지. -1 = 레일 앞쪽, +1 = 뒤쪽, 0 = 정지.
var _head_step_offset: int = 0
var _round_weight: float = 0.0
var _is_dragging: bool = false
var _motion_active: bool = false
var _saturation_reports: int = 0


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
	# Rebind every shader input on an eye-texture swap.  Updating only the
	# albedo left the live material dependent on its previous mask binding.
	_apply_shader_parameters(
		_closed_eyes_texture if _eyes_are_closed else _get_open_eyes_texture(),
		not _eyes_are_closed
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


func can_move_endpoint(endpoint: StringName, target_cell: Vector2i) -> bool:
	# 실제로 옮기지 않고 가능한지만 본다. 머리가 그 칸으로 미끄러져도 되는지 판단할 때 쓴다.
	if level_manager == null or body_cells.size() < 2:
		return false
	return _plan_endpoint_move(target_cell, endpoint == &"tail") != null


func _move_endpoint(target_cell: Vector2i, from_tail: bool) -> bool:
	var plan: Variant = _plan_endpoint_move(target_cell, from_tail)
	if plan == null:
		return false
	_commit_endpoint_move(plan as Dictionary, from_tail)
	return true


func _plan_endpoint_move(target_cell: Vector2i, from_tail: bool) -> Variant:
	# 게코아웃에서는 "잡아끄는 쪽"이 곧 머리다. 두 끝의 규칙이 완전히 대칭이므로
	# 꼬리를 잡은 경우에는 몸통을 뒤집어 같은 로직을 그대로 태운다.
	var path: Array[Vector2i] = body_cells.duplicate()
	var rear_trail: Array[Vector2i] = _front_trail if from_tail else _back_trail
	if from_tail:
		path.reverse()

	var lead: Vector2i = path[0]
	if not _is_adjacent(lead, target_cell):
		return null

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
			return null
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
			return null

	var final_body: Array[Vector2i] = candidate.duplicate()
	if from_tail:
		final_body.reverse()
	if not level_manager.can_place_cat_body(self, final_body):
		return null

	return {
		"final_body": final_body,
		"lead": lead,
		"target": target_cell,
		"is_retreat": is_retreat,
		"rear_moved": rear_moved,
		"rear_from_memory": rear_from_memory,
		"vacated_rear": vacated_rear,
	}


func _commit_endpoint_move(plan: Dictionary, from_tail: bool) -> void:
	var lead_trail: Array[Vector2i] = _back_trail if from_tail else _front_trail
	var rear_trail: Array[Vector2i] = _front_trail if from_tail else _back_trail
	var final_body: Array[Vector2i] = plan["final_body"]
	body_cells = final_body

	# 이동이 확정된 뒤에만 통과한 길 기록을 갱신한다.
	if plan["is_retreat"]:
		_remember(lead_trail, plan["lead"])
		if plan["rear_moved"]:
			if plan["rear_from_memory"]:
				rear_trail.pop_front()
			else:
				rear_trail.clear()
	else:
		# 잡은 쪽이 기억한 길을 되짚어 가면 그만큼 소비하고, 새 방향으로 틀면 기억을 버린다.
		if not lead_trail.is_empty() and lead_trail[0] == plan["target"]:
			lead_trail.pop_front()
		else:
			lead_trail.clear()
		if plan["rear_moved"]:
			_remember(rear_trail, plan["vacated_rear"])


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
	# The tile material's repeat count depends on cached rest lengths.
	_apply_current_shader_parameters()
	snap_pose_to_grid()


func begin_drag(endpoint: StringName, world_point: Variant = null) -> void:
	_is_dragging = true
	_drag_endpoint = endpoint
	_motion_active = true

	# 시작 축은 몸통이 지금 향한 선이다. 축이 비어 있으면 첫 프레임의 진행 성분이 0이라
	# 조준용 미세한 좌우 움직임이 축을 가로채고, 마우스가 같은 열 안에 있는데도 머리가 꺾인다.
	_axis_entry = 0.0
	_slide_axis = Vector2i.ZERO
	if body_cells.size() >= 2:
		_slide_axis = (
			body_cells[0] - body_cells[1] if endpoint == &"head"
			else body_cells[-1] - body_cells[-2]
		)

	_grab_offset = Vector3.ZERO
	if world_point == null or level_manager == null or body_cells.is_empty():
		return
	# 손가락의 "이동량"이 머리를 끌게 한다. 잡은 지점 자체는 기준점이 될 뿐이다.
	var lead_cell: Vector2i = get_head_cell() if endpoint == &"head" else get_tail_cell()
	var offset: Vector3 = (world_point as Vector3) - position - _cell_to_local(lead_cell)
	offset.y = 0.0
	_grab_offset = offset


func update_drag(endpoint: StringName, world_point: Vector3) -> void:
	# 손가락 위치를 그대로 받아 머리를 셀 사이 어디에나 놓는다.
	# 논리 확정(body_cells)은 머리가 이웃 셀 중심에 닿는 순간에만 일어난다.
	if level_manager == null or body_cells.size() < 2:
		return
	_is_dragging = true
	_drag_endpoint = endpoint
	_motion_active = true

	var local_point := world_point - position - _grab_offset
	for _commit in range(MAX_COMMITS_PER_UPDATE):
		var lead_cell: Vector2i = get_head_cell() if endpoint == &"head" else get_tail_cell()
		var lead_position := _cell_to_local(lead_cell)
		var to_pointer := local_point - lead_position
		to_pointer.y = 0.0

		var step_cell: Variant = _best_step_cell(endpoint, lead_cell, to_pointer)
		if step_cell == null:
			_slide_valid = false
			_slide_t = 0.0
			return

		var axis := _cell_to_local(step_cell as Vector2i) - lead_position
		axis.y = 0.0
		var span := axis.length()
		if span < 0.0001:
			_slide_valid = false
			return

		var raw := to_pointer.dot(axis / span) / span
		_slide_cell = step_cell as Vector2i
		_slide_valid = true

		var direction: Vector2i = _slide_cell - lead_cell
		if direction != _slide_axis:
			# 축을 막 바꿨다. 그 시점의 진행량을 기준점으로 삼아 0에서 다시 센다.
			# 이 보정이 없으면 전환 지점에서 머리가 그만큼 순간이동한다. 축이 잠긴 동안
			# 반대축 오프셋은 한 칸 이상 쌓일 수 있으므로 상한을 두지 않는다.
			_axis_entry = maxf(raw, 0.0)
		_slide_axis = direction

		# 기준점부터 1:1 로 센다. (1 - entry) 로 나누면 남은 거리를 몰아서 달리게 되어
		# 대각 드래그처럼 오프셋이 크게 쌓인 경우 한 칸을 한 프레임에 순간이동한다.
		var travel := clampf(raw - _axis_entry, 0.0, 1.0)
		if travel < 1.0:
			# 셀 중심에 아직 못 미쳤다. 중간 지점에 그대로 머문다.
			_slide_t = clampf(travel, 0.0, 1.0)
			return

		# 이웃 셀 중심을 넘어섰으니 한 칸 확정하고, 남은 거리로 다시 판단한다.
		if not drag_endpoint_to(endpoint, _slide_cell):
			_slide_t = 1.0
			return
		_slide_t = 0.0
		# 기준점도 한 칸만큼 당겨 둔다. 0으로 되돌리면 손가락이 이미 지나온 만큼이
		# 곧바로 travel 로 잡혀서 확정 시점에 머리가 그만큼 앞으로 순간이동한다.
		_axis_entry = maxf(raw - 1.0, 0.0)

	# 여기까지 왔다면 한 이벤트에서 확정 상한까지 소진했다는 뜻이다. 정상 입력에서는
	# 일어나지 않으므로, 반복되면 프리즈 원인 추적의 단서가 된다.
	if _saturation_reports < 20:
		_saturation_reports += 1
		push_warning("[drag] 한 이벤트에서 %d칸을 확정했다. %s" % [
			MAX_COMMITS_PER_UPDATE, describe_state()])
	_slide_valid = false
	_slide_t = 0.0


func end_drag() -> void:
	# 손을 놓으면 가장 가까운 그리드 정위치로 붙는다. 절반을 넘었으면 그 칸으로 확정하고,
	# 아니면 원래 칸으로 되돌아간다. 어느 쪽이든 남은 거리는 애니메이션으로 흡수한다.
	_is_dragging = false
	if _slide_valid and _slide_t >= 0.5:
		var target := _slide_cell
		var travelled := _slide_t
		if drag_endpoint_to(_drag_endpoint, target):
			# 같은 화면 위치를 유지하려면 새 머리 기준의 반대 방향 슬라이드로 바꿔 놓는다.
			_slide_cell = body_cells[1] if _drag_endpoint == &"head" else body_cells[-2]
			_slide_t = 1.0 - travelled
	_motion_active = true


func describe_state() -> String:
	# 프리즈 진단용 스냅샷.
	return "%s len=%d body=%s slide=%s/%.2f axis=%s entry=%.2f trail=%d/%d motion=%s" % [
		name, body_cells.size(), str(body_cells), str(_slide_cell), _slide_t,
		str(_slide_axis), _axis_entry, _front_trail.size(), _back_trail.size(),
		str(_motion_active)]


func _unit_sign(value: float) -> int:
	if value > 0.0:
		return 1
	if value < 0.0:
		return -1
	return 0


func _best_step_cell(endpoint: StringName, lead_cell: Vector2i, to_pointer: Vector3) -> Variant:
	# 방향(각도)이 아니라 그리드 좌표로 판단한다. 각도로 고르면 칸을 확정한 직후
	# 진행축 성분이 0이 되는 순간마다 측면 성분이 이겨서, 마우스가 같은 열 안에 있어도
	# 머리가 옆 열로 꺾인다.
	var tile := level_manager.tile_size
	var along_x := to_pointer.x / tile
	var along_z := to_pointer.z / tile
	if maxf(absf(along_x), absf(along_z)) < SLIDE_DEAD_ZONE:
		return null

	var score_x := absf(along_x)
	var score_z := absf(along_z)
	if _slide_axis != Vector2i.ZERO:
		# 셀 사이에 걸쳐 있는 동안에는 축을 바꾸지 않는다. 몸통은 레일 위에만 있을 수 있어서
		# 축을 바꾸려면 머리가 셀 중심으로 되돌아와야 하는데, 그 되돌림이 곧 "뒤로 튐"이다.
		# 대신 그대로 진행해 셀 중심에 도착한 뒤(확정 직후 slide_t=0) 그 자리에서 돈다.
		var mid_cell := _slide_t > SLIDE_SWITCH_EPSILON
		if _slide_axis.x != 0:
			score_x += SLIDE_AXIS_HYSTERESIS
			# 측면 축은 마우스가 그 셀로 실제로 넘어갔을 때만 후보가 된다.
			if mid_cell or score_z <= SLIDE_AXIS_SWITCH:
				score_z = -1.0
		else:
			score_z += SLIDE_AXIS_HYSTERESIS
			if mid_cell or score_x <= SLIDE_AXIS_SWITCH:
				score_x = -1.0

	# signi() 는 int 를 받는다. 소수 성분을 그대로 넘기면 잘려서 0이 되므로 직접 부호를 낸다.
	var step_x := Vector2i(_unit_sign(along_x), 0)
	var step_z := Vector2i(0, _unit_sign(along_z))
	var order: Array[Vector2i] = []
	if score_x >= score_z:
		order.append(step_x)
		if score_z > -1.0:
			order.append(step_z)
	else:
		order.append(step_z)
		if score_x > -1.0:
			order.append(step_x)

	# 우선 축이 막혀 있으면 남은 축으로 우회한다.
	for direction in order:
		if direction == Vector2i.ZERO:
			continue
		if can_move_endpoint(endpoint, lead_cell + direction):
			return lead_cell + direction
	return null


func snap_pose_to_grid() -> void:
	# 보간 없이 그리드 정위치로 즉시 확정한다. 에디터 미리보기와 스폰 시점에 쓴다.
	_slide_valid = false
	_slide_t = 0.0
	_slide_axis = Vector2i.ZERO
	_axis_entry = 0.0
	_round_weight = 0.0
	_smooth_weight = 0.0
	_forward = Vector3.ZERO
	_motion_active = false
	_refresh_pose()


func _process_motion(delta: float) -> void:
	# 눈 깜빡임은 계속 돌아야 하므로 _process 자체를 끄지 않고 플래그로만 쉰다.
	if not _motion_active or level_manager == null or _cat_model == null:
		return

	var settled := true
	if not _is_dragging:
		# 손을 놓은 뒤: 남은 거리와 코너 라운딩을 함께 0으로 되돌린다.
		var settle := _smoothing_factor(delta, settle_time)
		_slide_t = lerpf(_slide_t, 0.0, settle)
		if _slide_t > 0.002:
			settled = false
		else:
			_slide_t = 0.0
			_slide_valid = false

	var chase := _smoothing_factor(delta, move_smooth_time if _is_dragging else settle_time)
	var round_target := corner_round if _is_dragging else 0.0
	_round_weight = lerpf(_round_weight, round_target, chase)
	if absf(_round_weight - round_target) > 0.002:
		settled = false

	var smooth_target := 1.0 if _is_dragging else 0.0
	_smooth_weight = lerpf(_smooth_weight, smooth_target, chase)
	if absf(_smooth_weight - smooth_target) > 0.002:
		settled = false

	if not _advance_forward(delta):
		settled = false

	_refresh_pose()
	if settled and not _is_dragging:
		_motion_active = false


func _smoothing_factor(delta: float, smooth_time: float) -> float:
	if smooth_time <= 0.0001:
		return 1.0
	return 1.0 - exp(-delta / smooth_time)


func _refresh_pose() -> void:
	if _cat_model == null or _bone_rests.is_empty() or body_cells.size() < 2:
		return
	var track := _build_track()
	if track.is_empty():
		return
	_place_model_on(track)
	_apply_body_pose_along(track)


func _track_cells() -> Array[Vector2i]:
	# 레일은 현재 몸통이 점유한 칸과, 지금 미끄러져 들어가는 중인 한 칸까지만 쓴다.
	# 기억한 길 전체를 넣으면 꼬리 끝이 점유하지 않은 칸으로 삐져나간다.
	var cells: Array[Vector2i] = body_cells.duplicate()
	_track_head_index = 0
	_head_step_offset = 0
	if not _slide_valid or _slide_t <= 0.0:
		return cells

	if _drag_endpoint == &"head":
		if _slide_cell == body_cells[1]:
			# 머리 후진 중. 반대쪽 끝은 확정될 때와 같은 규칙으로 다음 칸을 향한다.
			cells.append(_next_rear_cell(_back_trail, body_cells[-1], body_cells[-2]))
			_head_step_offset = 1
		else:
			# 머리 전진 중. 아직 레일에 없는 새 칸을 앞에 이어 붙인다.
			cells.push_front(_slide_cell)
			_track_head_index = 1
			_head_step_offset = -1
	else:
		if _slide_cell == body_cells[-2]:
			# 꼬리 후진 중. 머리 쪽이 다음 칸으로 밀려 나간다.
			cells.push_front(_next_rear_cell(_front_trail, body_cells[0], body_cells[1]))
			_track_head_index = 1
			_head_step_offset = -1
		else:
			cells.append(_slide_cell)
			_head_step_offset = 1
	return cells


func _next_rear_cell(
	trail: Array[Vector2i],
	rear: Vector2i,
	rear_prev: Vector2i
) -> Vector2i:
	# 확정 이동과 완전히 같은 규칙이다. 그래서 미끄러지는 방향과 확정 결과가 어긋나지 않는다.
	var remembered: Variant = _remembered_rear_cell(trail, rear, rear_prev)
	if remembered == null:
		return rear + (rear - rear_prev)
	return remembered as Vector2i


func _build_track() -> Dictionary:
	var cells := _track_cells()
	if cells.size() < 2:
		return {}

	var base := PackedVector3Array()
	for cell in cells:
		base.append(_cell_to_local(cell))

	# 양 끝을 직선으로 연장해 본 체인이 레일 밖으로 빠져나가지 않게 한다.
	var reach := _stretched_chain_length() * _grid_fitted_model_scale() + level_manager.tile_size * 2.0
	base.insert(0, base[0] + (base[0] - base[1]).normalized() * reach)
	base.append(base[-1] + (base[-1] - base[-2]).normalized() * reach)
	var head_vertex := _track_head_index + 1

	# 코너 라운딩. _round_weight 가 0이면 셀 중심을 잇는 각진 레일 그대로다.
	var radius := level_manager.tile_size * 0.5 * clampf(_round_weight, 0.0, 1.0)
	radius = minf(radius, _max_corner_radius(base))
	var points := PackedVector3Array()
	var vertex_index := PackedInt32Array()
	points.append(base[0])
	vertex_index.append(0)

	for index in range(1, base.size() - 1):
		var incoming := base[index] - base[index - 1]
		var outgoing := base[index + 1] - base[index]
		var straight := (
			radius <= 0.0001
			or incoming.length_squared() < 0.000001
			or outgoing.length_squared() < 0.000001
			or incoming.normalized().is_equal_approx(outgoing.normalized())
		)
		if straight:
			points.append(base[index])
			vertex_index.append(points.size() - 1)
			continue

		# 코너를 2차 베지어 원호로 대체한다. 반지름은 인접 구간의 절반을 넘지 않게 막아
		# 곡선이 이웃 셀로 삐져나가지 않도록 한다.
		var arc_radius := minf(radius, minf(incoming.length(), outgoing.length()) * 0.5)
		var entry := base[index] - incoming.normalized() * arc_radius
		var exit_point := base[index] + outgoing.normalized() * arc_radius
		var middle := points.size() + CORNER_ARC_SEGMENTS / 2
		for step in range(CORNER_ARC_SEGMENTS + 1):
			var t := float(step) / float(CORNER_ARC_SEGMENTS)
			points.append(entry.lerp(base[index], t).lerp(base[index].lerp(exit_point, t), t))
		# 라운딩된 코너에서는 원호 한가운데를 그 셀의 대표 지점으로 삼는다.
		vertex_index.append(middle)

	points.append(base[-1])
	vertex_index.append(points.size() - 1)

	var lengths := _polyline_lengths(points)

	# 머리 위치는 레일의 호/점으로 잡지 않는다. 머리 셀에 코너가 생기는 순간 그 셀의
	# 대표 지점이 셀 중심에서 필렛 중간점으로 바뀌면서 머리가 뒤로 튀기 때문이다.
	# 셀 중심 사이를 slide_t 로 직접 보간하면 손가락과도 정확히 맞고 확정 시점에도 이어진다.
	var step_vertex: int = clampi(head_vertex + _head_step_offset, 0, vertex_index.size() - 1)
	var head_position: Vector3 = base[head_vertex].lerp(base[step_vertex], _slide_t)
	# 본 방향을 뽑을 기준 호는 정점 호 사이를 같은 비율로 보간한다.
	var head_arc: float = lerpf(
		lengths[vertex_index[head_vertex]], lengths[vertex_index[step_vertex]], _slide_t
	)

	# Initial Length is anchored at the head cell; any added length extends
	# tailward instead of being split across the head and tail.
	return {
		"points": points,
		"lengths": lengths,
		"nose_arc": head_arc,
		"overhang": 0.0,
		"head_position": head_position,
	}


func _max_corner_radius(base: PackedVector3Array) -> float:
	# 필렛은 경로를 짧게 만들지만 본 체인 길이는 고정이다. 그 차이만큼 몸통이
	# 양 끝으로 더 밀려 나가므로, 돌출분이 타일 반폭을 넘지 않는 선에서 반지름을 제한한다.
	var corners := 0
	for index in range(1, base.size() - 1):
		var incoming := base[index] - base[index - 1]
		var outgoing := base[index + 1] - base[index]
		if incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001:
			continue
		if not incoming.normalized().is_equal_approx(outgoing.normalized()):
			corners += 1
	if corners == 0:
		return level_manager.tile_size * 0.5

	var allowance := maxf(level_manager.tile_size * 0.5 - _body_overhang(), 0.0)
	return maxf(allowance * 2.0 * 0.9 / (CORNER_ARC_SHORTENING * float(corners)), 0.0)


func _polyline_lengths(points: PackedVector3Array) -> PackedFloat32Array:
	var lengths := PackedFloat32Array()
	var total := 0.0
	lengths.append(0.0)
	for index in range(1, points.size()):
		total += points[index].distance_to(points[index - 1])
		lengths.append(total)
	return lengths


func _polyline_segment_at(lengths: PackedFloat32Array, distance: float) -> int:
	for index in range(1, lengths.size()):
		if distance <= lengths[index]:
			return index
	return lengths.size() - 1


func _polyline_point_at(
	points: PackedVector3Array,
	lengths: PackedFloat32Array,
	distance: float
) -> Vector3:
	var index := _polyline_segment_at(lengths, distance)
	var span := lengths[index] - lengths[index - 1]
	if span < 0.000001:
		return points[index]
	var weight := clampf((distance - lengths[index - 1]) / span, 0.0, 1.0)
	return points[index - 1].lerp(points[index], weight)


func _polyline_tangent_at(
	points: PackedVector3Array,
	lengths: PackedFloat32Array,
	distance: float
) -> Vector3:
	# 이웃 본을 잇는 현(chord)이 아니라 그 지점의 접선을 쓴다. 각진 레일에서는
	# 코너 하나가 관절 하나에 그대로 실리고, 곡선에서는 접선이 매끄럽게 변한다.
	var index := _polyline_segment_at(lengths, distance)
	var segment := points[index] - points[index - 1]
	if segment.length_squared() < 0.000001:
		return Vector3.RIGHT
	return segment.normalized()


func _bone_arc(chain_index: int, nose_arc: float, model_scale: float) -> float:
	return nose_arc + _stretched_chain_distance(chain_index) * model_scale


func _bone_span_direction(track: Dictionary, chain_index: int, model_scale: float) -> Vector3:
	var points: PackedVector3Array = track["points"]
	var lengths: PackedFloat32Array = track["lengths"]
	var nose_arc: float = track["nose_arc"]
	var start := _bone_arc(chain_index, nose_arc, model_scale)
	var next_index: int = mini(chain_index + 1, _bone_chain_distances.size() - 1)
	var end := _bone_arc(next_index, nose_arc, model_scale)

	# 정지 상태: 관절이 담당하는 구간의 중간에서 접선을 읽는다. 이렇게 해야 코너가
	# "코너 다음 관절"이 아니라 "코너에 가장 가까운 관절" 하나에 그대로 실린다.
	var sample: float = start if is_equal_approx(start, end) else (start + end) * 0.5
	var sharp := _polyline_tangent_at(points, lengths, sample)
	if _smooth_weight <= 0.001 or is_equal_approx(start, end):
		return sharp

	# 이동 중: 구간 양 끝을 잇는 현을 쓴다. 접선은 세그먼트 단위로 계단식이라
	# 몸이 미끄러질 때 관절 방향이 5도씩 툭툭 튀며 떨린다. 현은 호 길이에 대해 연속이다.
	var chord := (
		_polyline_point_at(points, lengths, end) - _polyline_point_at(points, lengths, start)
	)
	if chord.length_squared() < 0.000001:
		return sharp
	return sharp.lerp(chord.normalized(), clampf(_smooth_weight, 0.0, 1.0)).normalized()


func _target_forward(track: Dictionary) -> Vector3:
	# 레일은 머리 -> 꼬리 방향으로 진행한다. 머리가 향한 방향은 그 반대다.
	return -_bone_span_direction(track, 0, _grid_fitted_model_scale())


func _advance_forward(delta: float) -> bool:
	var track := _build_track()
	if track.is_empty():
		return true
	var target := _target_forward(track)
	if _forward.length_squared() < 0.000001:
		_forward = target
		return true
	var chased := _forward.slerp(target, _smoothing_factor(delta, move_smooth_time))
	if chased.length_squared() < 0.000001:
		chased = target
	_forward = chased.normalized()
	return _forward.dot(target) > 0.99995


func _place_model_on(track: Dictionary) -> void:
	# 머리 셀 지점은 레일 위에 정확히 둔다. 손가락을 그대로 따라가야 하기 때문이다.
	# 코 끝만 그 지점에서 _forward 방향으로 돌출분만큼 내민다. _forward 는 시간축으로
	# 따라오므로 슬라이드가 시작될 때 코가 순간이동하지 않고 부드럽게 돌아간다.
	var overhang: float = track["overhang"]
	var head: Vector3 = track["head_position"]
	if _forward.length_squared() < 0.000001:
		_forward = _target_forward(track)
	_cat_model.basis = _fbx_basis_for_direction(_forward)
	# 상체 비율을 보존하기 위해 모델 루트는 반드시 균일 스케일만 사용한다.
	_cat_model.scale = Vector3.ONE * _grid_fitted_model_scale()
	var visual_offset := level_manager.tile_size * visual_forward_offset_tiles
	_cat_model.position = head + _forward * (overhang + visual_offset) - _cat_model.basis * _head_bone_rest_global.origin


func _grid_path_length() -> float:
	return float(maxi(body_cells.size() - 1, 0)) * level_manager.tile_size


func _body_overhang() -> float:
	return maxf((_stretched_chain_length() * _grid_fitted_model_scale() - _grid_path_length()) * 0.5, 0.0)


func _apply_body_pose_along(track: Dictionary) -> void:
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

	var to_local := _cat_model.basis.inverse()
	# 첫 관절의 기준은 스무딩된 머리 방향이다. 그래서 코가 도는 동작이 목 관절에 실린다.
	var previous_direction := (to_local * -_forward).normalized()

	for chain_index in range(1, _bone_chain.size()):
		# 각 관절은 레일 위 자기 호 길이 지점의 접선을 따른다.
		# 그래서 몸통과 다리가 머리가 지나간 궤적을 그대로 훑고 지나간다.
		var direction := (
			to_local * _bone_span_direction(track, chain_index, model_scale)
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
	_apply_stretchable_bone_offsets()


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
	if head_to_root.is_empty() or tail_to_root.is_empty() or head_to_root.back() != tail_to_root.back():
		return

	_bone_chain = head_to_root
	tail_to_root.reverse()
	for index in range(1, tail_to_root.size()):
		_bone_chain.append(tail_to_root[index])

	var distance := 0.0
	_bone_chain_distances.append(0.0)

	for chain_index in range(1, _bone_chain.size()):
		var previous_bone: int = _bone_chain[chain_index - 1]
		var next_bone: int = _bone_chain[chain_index]
		# 뱀형 리그는 단일 체인이다. 갈래가 생기면 가장 긴 뼈를 몸통 진행 방향으로 본다.
		if _skeleton.get_bone_parent(previous_bone) == next_bone:
			distance += _bone_rests[previous_bone].origin.length()
		else:
			distance += _bone_rests[next_bone].origin.length()
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


func _body_length_scale() -> float:
	# Use intervals rather than cells so mesh scaling and texture tiling stay
	# in sync with the four-cell authored FBX.
	return float(maxi(initial_length - 1, 1)) / float(BODY_TEXTURE_REFERENCE_LENGTH - 1)


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


func _stretchable_bone_scale() -> float:
	# Only the middle Bone006..Bone014 section absorbs added Initial Length.
	var stretchable_length := _stretchable_rest_length()
	if stretchable_length <= 0.000001:
		return 1.0
	var added_length := _rest_chain_length * (_body_length_scale() - 1.0)
	# Keep a small positive lower bound for the inspector's minimum length of 2.
	return maxf(0.05, 1.0 + added_length / stretchable_length)


func _stretched_chain_distance(chain_index: int) -> float:
	var distance := 0.0
	for index in range(1, mini(chain_index + 1, _bone_chain_distances.size())):
		var segment := _bone_chain_distances[index] - _bone_chain_distances[index - 1]
		if _is_stretchable_chain_bone(index):
			segment *= _stretchable_bone_scale()
		distance += segment
	return distance


func _stretched_chain_length() -> float:
	return _stretched_chain_distance(_bone_chain_distances.size() - 1)


func _apply_stretchable_bone_offsets() -> void:
	if _skeleton == null:
		return
	var stretch_scale := _stretchable_bone_scale()
	# Scaling a parent bone is inherited by every child, causing the length to
	# multiply down the chain.  Instead, extend only the rest-position of each
	# segment entering Bone006..Bone014. The positions are on local X in this FBX.
	for chain_index in range(1, _bone_chain.size()):
		if _is_stretchable_chain_bone(chain_index):
			var bone_index := _bone_chain[chain_index]
			_skeleton.set_bone_pose_position(
				bone_index, _bone_rests[bone_index].origin * stretch_scale
			)


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
	_apply_shader_parameters(_get_open_eyes_texture())


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


func _apply_shader_parameters(texture: Texture2D, use_tint_exclusion_mask := true) -> void:
	var gradient_axis := _get_tint_gradient_axis()
	if _cat_material != null:
		_cat_material.set_shader_parameter("albedo_tex", texture)
		_cat_material.set_shader_parameter(
			"tint_exclusion_mask", _get_tint_exclusion_mask() if use_tint_exclusion_mask else null
		)
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
		_cat_material.set_shader_parameter("line_art_enabled", 1.0 if line_art_texture != null else 0.0)
		_cat_material.set_shader_parameter("line_art_color", line_art_color)
		_cat_material.set_shader_parameter("line_art_strength", line_art_strength)
	if _material_id_2 != null:
		# Material cat_tile covers the Bone006..Bone014 section. Only this section
		# is moved to change the cat's length, so its UV repeats must follow the
		# actual pose extension rather than the total grid-length ratio.
		var tile_scale := _stretchable_bone_scale()
		_material_id_2.set_shader_parameter("albedo_tex", texture)
		_material_id_2.set_shader_parameter(
			"tint_exclusion_mask", _get_tint_exclusion_mask() if use_tint_exclusion_mask else null
		)
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
		_material_id_2.set_shader_parameter("line_art_enabled", 1.0 if line_art_texture != null else 0.0)
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


func _get_tint_exclusion_mask() -> Texture2D:
	if _tint_exclusion_mask == null:
		_tint_exclusion_mask = load(TINT_EXCLUSION_MASK_PATH) as Texture2D
	return _tint_exclusion_mask


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
