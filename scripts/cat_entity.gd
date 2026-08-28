@tool
class_name CatEntity
extends Node3D

const MODEL_SCENE_PATH := "res://water_yang/cat1.fbx"
const KEY_MODEL_SCENE_PATH := "res://water_yang/key1.fbx"
const KEY_TOON_MATERIAL := preload("res://resources/key_toon_material.tres")
const ORANGE_CAT_COLOR_ID := 0
const MODEL_TEXTURE_PATH := "res://water_yang/cat1.jpeg"
const TINT_EXCLUSION_MASK_PATH := "res://water_yang/cat1_mask.jpg"
# 중첩고양이 색 영역 마스크(3_기믹.md 2). 흰 영역(배)만 안쪽 색으로 칠해진다.
# 텍스처를 못 찾으면 셰이더가 임시 줄무늬로 폴백한다.
const COLOR_MASK1_PATH := "res://src/assets/color_mask1.jpg"
const COLOR_MASK2_PATH := "res://src/assets/color_mask2.jpg"
const NEST_REVEAL_TWEEN_SECONDS := 0.35
const CLOSED_EYES_TEXTURE_PATH := "res://water_yang/cat1_1.jpeg"
const OPEN_MOUTH_TEXTURE_PATH := "res://water_yang/cat1_2.jpeg"
const OPEN_MOUTH_TINT_EXCLUSION_MASK_PATH := "res://water_yang/cat2_mask.jpg"
const TOON_SHADER_PATH := "res://scripts/cat_toon.gdshader"
const OUTLINE_SHADER_PATH := "res://scripts/cat_outline.gdshader"
const ABSORB_SOUND := preload("res://src/sound/cat_Hole_sound.mp3")
const ITEM_MOVE_HOLE_POP_SOUND := preload("res://src/sound/bubble_pop.mp3")
const FLOATING_WATER_OUTLINE_COLOR := Color("f8ffff")
const FLOATING_WATER_OUTLINE_WIDTH := 0.020
const REFERENCE_TILE_SIZE := 2.0
const BLINK_INTERVAL_MIN := 2.4
const BLINK_INTERVAL_MAX := 5.2
const BLINK_CLOSED_DURATION := 0.11
const OPEN_MOUTH_CHANCE := 0.22
const OPEN_MOUTH_DURATION := 0.95
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
const INVALID_CELL := Vector2i(-9999, -9999)
# 오버행 고정점 반복 횟수. 3회면 0.001칸 아래로 수렴한다.
# 양끝 여백을 맞추는 완화 반복. 머리쪽 극점(앞다리 Bone027/028)은 체인이 줄면 2배로
# 밀려나오기 때문에, 감쇠 없는 단순 대입은 이득이 2가 되어 반드시 발산한다.
const OVERHANG_CALIBRATION_STEPS := 8
const OVERHANG_RELAXATION := 0.3
const OVERHANG_DEBUG := true
# 구멍 흡입에서 몸이 구멍 중심을 지나 더 내려가는 깊이(칸 단위). 이 깊이를 다 내려가면
# 바닥 아래로 완전히 사라진 것으로 보고 흡입을 끝낸다.
const ABSORB_SINK_CELLS := 0.9

@export_group("Layout")
@export var grid_pos: Vector2i = Vector2i.ZERO:
	set(value):
		grid_pos = value
		if _applying_initial_body:
			return
		_reset_initial_body()
		_request_editor_refresh()

@export_enum("up", "right", "down", "left") var facing_name: String = "up":
	set(value):
		facing_name = value
		facing_dir = _direction_from_name(facing_name)
		if _applying_initial_body:
			return
		_reset_initial_body()
		_request_editor_refresh()

# 꺾인 시작 몸. 리드 끝(index 0)에서 반대쪽 끝까지 4방향으로 인접한 칸 목록이며,
# 맵 생성기가 역설계로 만든 자세를 그대로 심기 위한 것이다(`MapGenerator`).
#
# 비어 있거나 유효하지 않으면 `grid_pos` + `facing_name` + `initial_length` 의 직선 몸으로
# 폴백한다. 손 배치와 기존 회귀 검사는 그 경로를 그대로 쓴다.
@export var initial_body_cells: Array[Vector2i] = []:
	set(value):
		initial_body_cells = value
		_reset_initial_body()
		_request_editor_refresh()

@export_group("Body")
@export_range(2, 16, 1) var initial_length: int = 4:
	set(value):
		initial_length = value
		if _applying_initial_body:
			return
		_reset_initial_body()
		_refresh_shader_material()
		if is_inside_tree() and not Engine.is_editor_hint() and level_manager != null:
			# Remote Inspector changes during Play do not use the editor preview
			# refresh path, so update the live skeleton here.
			# 길이가 바뀌면 중간복제 개수도 달라지므로 메시·본을 새로 만들어야 한다.
			_rebuild_body_visuals()
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
@export_range(1.0, 24.0, 0.5) var move_speed_cells: float = 10.5
@export_range(1, 12, 1) var path_queue_max: int = 5
# 우회 경로에만 허용하는 큐 상한. 손가락이 `path_queue_max` 안에 있는데도 벽이 두꺼워
# 길이 그보다 길어질 때 쓴다. 손가락이 멀리 튄 목표는 이 값과 무관하게 거절된다.
@export_range(1, 32, 1) var detour_queue_max: int = 12
# 구멍에 빨려 들어가는 속도. 이동보다 빠르면 낚아채이는 느낌이 난다.
@export_range(1.0, 32.0, 0.5) var absorb_speed_cells: float = 11.0

# 발자국 양끝에 남기는 여백(칸 단위). 몸 길이와 무관하게 항상 한 칸의 이 비율만큼이다.
# 0 이면 메시가 발자국을 꽉 채워 이동이 뻑뻑해 보인다.
@export_range(0.0, 0.4, 0.01) var footprint_margin_cells: float = 0.1:
	set(value):
		footprint_margin_cells = value
		_refresh_shader_material()
		if is_inside_tree() and not Engine.is_editor_hint() and level_manager != null:
			_update_visual_pose()
		_request_editor_refresh()

@export_group("Color Pair")
# LevelManager.pair_colors 의 인덱스. 같은 color_id 를 가진 구멍에만 빠진다.
# -1 은 아무 구멍이나 쓰는 와일드카드다.
@export_range(-1, 31, 1) var color_id: int = 0:
	set(value):
		color_id = value
		_refresh_shader_material()

# 켜면 틴트와 그라디언트를 팔레트의 짝 색에서 만든다. 색이 곧 짝 판정 기준이므로
# 표시색을 손으로 따로 맞추다 어긋나는 일을 막는다. 끄면 아래 값들이 그대로 쓰인다.
@export var tint_from_pair_color := false:
	set(value):
		tint_from_pair_color = value
		_refresh_shader_material()

@export_group("Nested Cat (3_기믹.md 2)")
# 겉에서 안쪽 순서의 안쪽 색 color_id. 1개면 2중첩, 2개면 3중첩. 비면 일반 고양이.
# 겉껍질이 구멍으로 빠지기 시작하면 첫 색의 고양이가 같은 자리에 남는다.
@export var nested_color_ids: Array[int] = []:
	set(value):
		nested_color_ids = value
		_refresh_shader_material()

# 아직 드러나지 않은 안쪽 고양이의 얇기(모델 단위, 법선 방향 수축).
@export_range(0.0, 0.08, 0.001) var nest_inner_shrink := 0.03

@export_group("Orange Cat Key (key1.fbx)")
# These fields drive only color_id 0, the orange cat. They remain editable in
# the Inspector so artists can tune the key without touching this script.
@export var show_key := false

@export var key_local_position := Vector3(0.1, -0.04, 0.1):
	set(value):
		key_local_position = value
		_refresh_key_visual()

@export var key_rotation_degrees := Vector3(0.0, 0.0, 90.0):
	set(value):
		key_rotation_degrees = value
		_refresh_key_visual()

@export var key_scale := Vector3.ONE:
	set(value):
		key_scale = value
		_refresh_key_visual()

# This resource uses the same toon-light and outline pipeline as the cat.
# Select it in the Inspector to edit its shader parameters directly.
@export var key_material_override: Material = KEY_TOON_MATERIAL:
	set(value):
		key_material_override = value
		_refresh_key_visual()

@export var key_outline_material: Material:
	set(value):
		key_outline_material = value
		_refresh_key_visual()

@export_group("Toon Shader")
@export var tint_color: Color = Color(1.0, 0.97, 0.97, 1.0):
	set(value):
		tint_color = value
		_refresh_shader_material()

@export_range(2, 5, 1) var toon_steps: int = 3:
	set(value):
		toon_steps = value
		_refresh_shader_material()

@export_range(0.0, 1.0, 0.01) var shadow_darkness: float = 0.22:
	set(value):
		shadow_darkness = value
		_refresh_shader_material()

@export_range(0.0, 0.5, 0.01) var toon_shadow_spread: float = 0.14:
	set(value):
		toon_shadow_spread = value
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

@export_range(0.2, 2.0, 0.01) var outline_brightness: float = 1.0:
	set(value):
		outline_brightness = value
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

@export_group("Cat Hole (cat_hole1.fbx) Outline")
# Keep the escape-hole silhouette independent from the movable cat's outline.
# The matching CatHole receives this through get_hole_visual_style().
@export_range(0.001, 0.04, 0.001) var cat_hole_outline_width: float = 0.008:
	set(value):
		cat_hole_outline_width = value
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
# `initial_body_cells` 에서 grid_pos / facing_name / initial_length 를 파생시키는 동안 참.
# 그 세터들이 다시 몸을 되돌리면 무한 재진입이 되므로 이 플래그로 끊는다.
var _applying_initial_body := false

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
# 남은 후진 스텝 수. 전진 큐와 동시에 차 있지 않다(방향이 바뀌면 반대쪽을 비운다).
var _pending_reverse := 0
var _is_reversing := false
var _slide_random := RandomNumberGenerator.new()

# 구멍 흡입. 시작하면 조작을 받지 않고 흡입만 진행한다.
var _is_absorbing := false
var _absorb_cell := INVALID_CELL
# 구멍으로 먼저 들어가는 끝이 리드쪽인지. 후진 중에는 후미가 먼저 닿을 수 있다.
var _absorb_from_lead := true
var _item_clear := false
# 몸이 자기 경로를 따라 구멍 쪽으로 밀려 들어간 길이(월드 단위).
var _swallowed_arc := 0.0
# 흡입이 끝나는 _swallowed_arc 값. 폴리라인 계산을 두 번 하지 않으려고
# _update_visual_pose() 가 매 프레임 채워 준다.
var _absorb_required_arc := 0.0

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
var _floating_water_outline := false
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
# 중간복제로 삽입한 본(머리→꼬리 순). 부모 걷기로는 체인에 들어오지 않으므로
# `_build_bone_chain()` 이 Bone008 뒤에 직접 이어 붙인다.
var _inserted_mid_bones: Array[int] = []
# 메시가 양끝 본보다 더 내미는 양(모델 단위). 머리는 코, 꼬리는 뒷다리가 만든다.
# 앞뒤가 4배 차이나므로 이걸 무시하면 꼬리쪽 셀이 0.4칸 비어 보인다.
var _head_mesh_overhang := 0.0
var _tail_mesh_overhang := 0.0
var _absorb_sound_player: AudioStreamPlayer
var _item_move_hole_pop_player: AudioStreamPlayer
# 중첩고양이. 겉껍질(this)이 빠지는 동안 자리에 남은 안쪽 고양이와 현재 수축량.
var _inner_cat: CatEntity
var _nest_shrink := 0.0
var _nest_mask1: Texture2D
var _nest_mask2: Texture2D


func _ready() -> void:
	_blink_random.seed = get_instance_id()
	_slide_random.seed = get_instance_id() + 104729
	_ear_random.seed = get_instance_id() + 7919
	facing_dir = _direction_from_name(facing_name)
	if body_cells.is_empty():
		_reset_initial_body()
	_ensure_visual_root()
	_absorb_sound_player = AudioStreamPlayer.new()
	_absorb_sound_player.stream = ABSORB_SOUND
	add_child(_absorb_sound_player)
	_item_move_hole_pop_player = AudioStreamPlayer.new()
	_item_move_hole_pop_player.stream = ITEM_MOVE_HOLE_POP_SOUND
	add_child(_item_move_hole_pop_player)

	if Engine.is_editor_hint():
		refresh_editor_preview()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_process_blink(delta)
	_process_ear_twitch(delta)
	advance(delta)


func set_floating_water_wave(time: float, phase: float, amplitude: float) -> void:
	if not _floating_water_outline:
		_floating_water_outline = true
		_apply_current_shader_parameters()
		_apply_material_recursive(_cat_model)
	for material in [_cat_material, _material_id_2, _outline_material, _material_id_2_outline]:
		if material == null:
			continue
		# Lobby motion is driven by the rig below.  Leaving vertex displacement
		# disabled keeps the opaque cat and its outline on the same depth surface.
		material.set_shader_parameter("water_wave_amplitude", 0.0)

	if _skeleton == null:
		return
	if _bone_rests.is_empty():
		_cache_bone_rests()
	for chain_index in _bone_chain.size():
		var bone_index: int = _bone_chain[chain_index]
		if bone_index < 0 or bone_index >= _bone_rests.size():
			continue
		var distance_ratio := float(chain_index) / maxf(float(_bone_chain.size() - 1), 1.0)
		var wave := sin(time * 2.1 + phase - distance_ratio * TAU * 0.7)
		var rest_rotation := _bone_rests[bone_index].basis.get_rotation_quaternion()
		_skeleton.set_bone_pose_rotation(
			bone_index,
			rest_rotation * Quaternion(Vector3.FORWARD, wave * amplitude * 1.45)
		)


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
			elif _is_inside_active_camera_view():
				UiBridge.post_progress({"sfx": "cat-mouth-open"})
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
	_reset_initial_body()
	_sync_to_grid_position()
	_ensure_visual_root()
	_rebuild_body_visuals()


func initialize_runtime(manager: LevelManager) -> void:
	level_manager = manager
	facing_dir = _direction_from_name(facing_name)
	_reset_initial_body()
	_sync_to_grid_position()
	_ensure_visual_root()
	_rebuild_body_visuals()


func get_head_cell() -> Vector2i:
	if body_cells.is_empty():
		return grid_pos
	return body_cells.back() if _lead_is_tail else body_cells.front()


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


func is_absorbing() -> bool:
	return _is_absorbing


func get_preview_path_cells() -> Array[Vector2i]:
	return path_queue.duplicate()


# 새 터치. 잔여 큐를 버리고, 잡은 쪽이 뒤끝이면 리드를 그쪽으로 넘긴다.
# 전이 중에는 레일을 뒤집지 않고 전이가 끝난 시점으로 미룬다.
func begin_drag(end_cell: Vector2i) -> void:
	if _is_absorbing:
		return
	path_queue.clear()
	_pending_reverse = 0
	_is_blocked = false
	if body_cells.size() < 2 or end_cell != body_cells.back():
		_notify_path_preview_changed()
		return
	if _is_moving:
		_pending_lead_flip = true
	else:
		_flip_lead()
		# 뒤끝을 잡아 리드가 된 순간 그 끝이 짝 구멍 옆이면 곧바로 빨려 들어간다.
		# 흡입은 리드에서만 걸리므로, 반대쪽 끝으로 넣는 방법이 이 플립뿐이다.
		# 전이 중이었다면 _finish_step 이 플립을 적용한 뒤 같은 판정을 한다.
		_try_begin_absorb()
	_notify_path_preview_changed()


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
	if _pending_lead_flip or _is_absorbing or level_manager == null:
		return
	if not level_manager.is_inside_grid(target):
		# 보드 밖을 가리키는 것도 닿을 수 없는 상태다. 강제 릴리즈 판정에 들어가야 한다.
		_is_blocked = true
		_notify_path_preview_changed()
		return
	# 손가락이 자기 몸을 가리키면 후진이다. 몇 번째 칸인지가 곧 밀어 넣을 스텝 수다.
	var settled: Array[Vector2i] = _settled_body()
	var back_index: int = settled.find(target)
	if back_index == 0:
		path_queue.clear()
		_notify_path_preview_changed()
		return
	if back_index > 0:
		path_queue.clear()
		_pending_reverse = mini(back_index, path_queue_max)
		_is_blocked = false
		_notify_path_preview_changed()
		return

	_pending_reverse = 0
	var future: Array[Vector2i] = _future_body()
	if future.is_empty() or target == future[0]:
		_notify_path_preview_changed()
		return
	var bridge: Array[Vector2i] = _plan_bridge(future, target)
	if bridge.is_empty():
		_is_blocked = true
		_notify_path_preview_changed()
		return
	_is_blocked = false
	path_queue.append_array(bridge)
	_notify_path_preview_changed()


# 큐를 모두 소비한 뒤의 몸 상태. 브릿지 탐색의 출발점이다.
# 진행 중인 전이가 끝난 뒤의 몸.
func _settled_body() -> Array[Vector2i]:
	if not _is_moving:
		return body_cells
	return _rail.slice(1) if _is_reversing else _rail.slice(0, _rail.size() - 1)


func _future_body() -> Array[Vector2i]:
	var future: Array[Vector2i] = _settled_body().duplicate()
	for cell in path_queue:
		future.push_front(cell)
		future.resize(future.size() - 1)
	return future


# (셀, 스텝) BFS. 스텝 k 에서는 몸의 뒤쪽 k 칸이 이미 비켜난 것으로 본다.
func _plan_bridge(future: Array[Vector2i], target: Vector2i) -> Array[Vector2i]:
	var start: Vector2i = future[0]
	# 손가락이 앵커에서 얼마나 떨어져 있는지가 입력을 받아들이는 기준이다. 빠른 플릭으로
	# 멀리 튄 목표를 자동 주행으로 만들지 않으려는 가드이며, 벽과는 무관하다.
	var reach: int = path_queue_max - path_queue.size()
	if reach <= 0:
		return []
	if absi(target.x - start.x) + absi(target.y - start.y) > reach:
		return []

	# 손가락이 가까운데 길이 막혔으면 경로 자체는 더 길어도 좋다. 벽 두께와 상관없이
	# 착지점까지 열린 길이 있으면 찾아 준다.
	var budget: int = maxi(reach, detour_queue_max - path_queue.size())
	if budget <= 0:
		return []

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
	if _is_absorbing:
		_advance_absorb(delta)
		return
	var pose_changed := _is_moving
	var remaining: float = delta * move_speed_cells
	while remaining > 0.0:
		if not _is_moving and not _begin_step():
			break
		pose_changed = true
		var step: float = minf(remaining, 1.0 - _transition_t)
		_transition_t += step
		remaining -= step
		if _transition_t >= 1.0 - 0.000001:
			_finish_step()
	if pose_changed:
		_update_visual_pose()


func _begin_step() -> bool:
	if _pending_lead_flip:
		_pending_lead_flip = false
		_flip_lead()
	# 판정은 셀 중앙에서 커밋하는 이 순간뿐이다. 시작한 전이는 반드시 끝까지 간다.
	if _pending_reverse > 0:
		var behind: Vector2i = _reverse_target()
		if behind == INVALID_CELL:
			_pending_reverse = 0
			_is_blocked = true
			return false
		_pending_reverse -= 1
		_is_reversing = true
		_rail = body_cells.duplicate()
		_rail.push_back(behind)
	else:
		if path_queue.is_empty():
			return false
		var next: Vector2i = path_queue[0]
		if not can_enter(next):
			path_queue.clear()
			_is_blocked = true
			return false
		path_queue.remove_at(0)
		_is_reversing = false
		_rail = body_cells.duplicate()
		_rail.push_front(next)
	_transition_t = 0.0
	_is_moving = true
	level_manager.update_cat_occupancy(self)
	return true


# 후진에서 새로 점유하는 칸은 후미 앞 한 칸뿐이다. 리드가 자기 몸 칸으로 들어가는 것은
# 강체 슬라이드라 충돌이 아니므로 can_enter() 를 쓰지 않는다.
# 기본은 후미 방향으로 직진이고, 막히면 벽을 타고 옆으로 흐른다.
func _reverse_target() -> Vector2i:
	if body_cells.size() < 2:
		return INVALID_CELL
	var rear: Vector2i = body_cells[body_cells.size() - 1]
	var direction: Vector2i = rear - body_cells[body_cells.size() - 2]
	if _can_slide_into(rear + direction):
		return rear + direction

	# 한 번 옆으로 꺾이면 그쪽이 새 후미 방향이 되므로, 다음 스텝부터는 직진이 곧
	# 벽을 타고 흐르는 것이 된다. 그래서 좌우 선택은 슬라이드가 시작될 때만 고른다.
	var left := Vector2i(direction.y, -direction.x)
	var right := Vector2i(-direction.y, direction.x)
	var left_open := _can_slide_into(rear + left)
	var right_open := _can_slide_into(rear + right)
	if left_open and right_open:
		return rear + (left if _slide_random.randi() % 2 == 0 else right)
	if left_open:
		return rear + left
	if right_open:
		return rear + right
	return INVALID_CELL


func _can_slide_into(cell: Vector2i) -> bool:
	if level_manager == null or not level_manager.is_inside_grid(cell):
		return false
	if level_manager.is_cell_blocked_for(self, cell):
		return false
	return not body_cells.has(cell)


func _finish_step() -> void:
	body_cells = _rail.slice(1) if _is_reversing else _rail.slice(0, _rail.size() - 1)
	_rail = body_cells.duplicate()
	_transition_t = 0.0
	_is_moving = false
	_is_reversing = false
	_update_facing()
	level_manager.update_cat_occupancy(self)
	if UiBridge.is_hosted:
		UiBridge.post_progress({"sfx": "cat-move"})
	if _pending_lead_flip:
		_pending_lead_flip = false
		_flip_lead()
	# grid_pos 세터는 몸을 직선으로 되돌리는 레이아웃용이다. 이동 중에는 건드리지 않고
	# 실제 위치는 언제나 body_cells 로만 읽는다.
	# 흡입 판정은 셀 중앙에서 커밋한 이 순간에만 한다. 전이 중에 시작하면 레일과
	# 점유가 어긋난다.
	_try_begin_absorb()


# ---------------------------------------------------------------- 구멍 흡입

# **리드(잡은 끝)만** 짝 구멍과 4방향 인접일 때 빨려 들어간다. 머리 이동 중 꼬리가
# 스친 것은 흡입이 아니다 — 반대쪽 끝으로 넣으려면 그 끝을 잡아 리드로 만들어야 한다.
# 드래그 중에도 걸린다. 리드가 옆칸에 커밋되는 순간 손에서 낚아채 간다.
func _try_begin_absorb() -> bool:
	if _is_absorbing or level_manager == null or body_cells.size() < 1:
		return false
	# 색이 짝인 구멍만 걸린다. 짝이 아니면 옆칸에 서 있어도 아무 일도 없다.
	var hole: Variant = level_manager.adjacent_hole(body_cells[0], color_id)
	if hole != null:
		_begin_absorb(hole as Vector2i, true)
		return true
	return false


func _begin_absorb(hole_cell: Vector2i, from_lead: bool, item_clear := false) -> void:
	_is_absorbing = true
	_absorb_cell = hole_cell
	_absorb_from_lead = from_lead
	_item_clear = item_clear
	_swallowed_arc = 0.0
	_absorb_required_arc = 0.0
	path_queue.clear()
	_pending_reverse = 0
	_pending_lead_flip = false
	_is_moving = false
	_is_reversing = false
	_transition_t = 0.0
	_is_blocked = false
	_rail = body_cells.duplicate()
	if UiBridge.is_hosted:
		UiBridge.post_progress({"sfx": "cat-hole-absorb"})
	else:
		_absorb_sound_player.play()
	# 빨려 들어가기 시작한 순간부터 점유를 놓는다. 다른 고양이가 곧바로 지나갈 수 있다.
	level_manager.release_cat_cell(self)
	# 중첩고양이면 겉껍질이 빠지는 이 순간 안쪽 고양이를 같은 자리에 남긴다.
	if not nested_color_ids.is_empty():
		_spawn_inner_cat()
	_notify_path_preview_changed()
	_apply_current_shader_parameters()


# 안쪽 고양이를 얇은 상태로 현재 몸 자리에 실체화한다(3_기믹.md 2).
# 점유를 곧바로 넘겨받으므로 다른 고양이가 이 자리를 지나가지 못한다.
func _spawn_inner_cat() -> void:
	var inner := CatEntity.new()
	inner.name = String(name) + "Inner"
	inner.color_id = nested_color_ids[0]
	inner.nested_color_ids.assign(nested_color_ids.slice(1))
	inner.tint_from_pair_color = true
	# body_cells 는 리드가 앞이라, 꼬리를 잡아 뺀 상태(_lead_is_tail)면 모델 머리가
	# 배열 뒤끝에 있다. 새 고양이는 항상 배열 앞을 머리로 삼으므로 그대로 넘기면
	# 남는 고양이가 반대 방향을 본다. 모델 머리가 앞에 오도록 되돌려 넘긴다.
	var inherited_cells: Array[Vector2i] = body_cells.duplicate()
	if _lead_is_tail:
		inherited_cells.reverse()
	inner.initial_body_cells = inherited_cells
	inner.move_speed_cells = move_speed_cells
	inner.absorb_speed_cells = absorb_speed_cells
	inner.nest_inner_shrink = nest_inner_shrink
	inner._nest_shrink = nest_inner_shrink
	get_parent().add_child(inner)
	inner.initialize_runtime(level_manager)
	level_manager.register_runtime_cat(inner)
	_inner_cat = inner


# 겉껍질이 거의 다 빠진 순간(마지막 1칸) 원래 굵기로 되돌아오는 연출.
func reveal_full_thickness() -> void:
	if _nest_shrink <= 0.0:
		return
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_method(_set_nest_shrink, _nest_shrink, 0.0, NEST_REVEAL_TWEEN_SECONDS)


func _set_nest_shrink(value: float) -> void:
	_nest_shrink = value
	for material in [_cat_material, _material_id_2, _outline_material, _material_id_2_outline]:
		if material != null:
			material.set_shader_parameter("body_shrink", value)


func _advance_absorb(delta: float) -> void:
	_swallowed_arc += delta * absorb_speed_cells * level_manager.fitted_tile_size()
	_update_visual_pose()
	# 겉껍질의 남은 진행이 마지막 1칸(+ 구멍 낙하 구간)으로 줄면 안쪽 고양이를 원복한다.
	if _inner_cat != null and _absorb_required_arc > 0.0:
		var remaining: float = _absorb_required_arc - _swallowed_arc
		if remaining <= level_manager.fitted_tile_size() * (1.0 + ABSORB_SINK_CELLS):
			_inner_cat.reveal_full_thickness()
			_inner_cat = null
	if _absorb_required_arc > 0.0 and _swallowed_arc >= _absorb_required_arc:
		_finish_absorb()


func _finish_absorb() -> void:
	# 프레임 순서가 어긋나 원복 트리거를 건너뛴 경우의 안전망.
	if _inner_cat != null:
		_inner_cat.reveal_full_thickness()
		_inner_cat = null
	_is_absorbing = false
	visible = false
	var manager: LevelManager = level_manager
	# 이후 프레임에서 이동/포즈 계산이 다시 돌지 않게 끊는다.
	level_manager = null
	manager.release_cat_cell(self)
	manager.on_cat_escaped(self, _absorb_cell)
	print(
		"[sound:item-move-hole-pop] emit hosted=%s hole=%s cat=%s" %
		[str(UiBridge.is_hosted), str(_absorb_cell), name]
	)
	if UiBridge.is_hosted:
		UiBridge.post_progress({"sfx": "item-move-hole-pop"})
	else:
		remove_child(_item_move_hole_pop_player)
		manager.add_child(_item_move_hole_pop_player)
		_item_move_hole_pop_player.finished.connect(_item_move_hole_pop_player.queue_free)
		_item_move_hole_pop_player.play()
		_item_move_hole_pop_player = null
	queue_free()


func clear_with_item(hole_cell: Vector2i) -> bool:
	if _is_absorbing or level_manager == null:
		return false
	if not level_manager.is_hole(hole_cell) or level_manager.is_hole_locked(hole_cell):
		return false
	if not level_manager.color_ids_pair(color_id, level_manager.get_hole_color_id(hole_cell)):
		return false
	_begin_absorb(hole_cell, not _lead_is_tail, true)
	return true


# 흡입 중 이 호 위치의 본이 놓일 자리와 머리 축 방향. 몸은 자기 경로를 따라 구멍 쪽으로
# 밀리고, 끝점을 지난 부분은 구멍 중심까지 직선으로 간 뒤 곧장 아래로 내려간다.
# 포즈 경로를 새로 만들지 않고 샘플 위치만 바꾸는 것이 핵심이다.
func _absorb_pose_at(
	polyline: PackedVector3Array,
	cumulative: PackedFloat32Array,
	total_length: float,
	arc_from_lead: float
) -> Array:
	var entry_arc: float = 0.0 if _absorb_from_lead else total_length
	var from_entry: float = absf(arc_from_lead - entry_arc) - _swallowed_arc
	if from_entry >= 0.0:
		var shifted: float = from_entry if _absorb_from_lead else total_length - from_entry
		return [
			_sample_polyline(polyline, cumulative, shifted),
			_model_head_direction(polyline, cumulative, shifted),
		]

	var entry_point: Vector3 = _sample_polyline(polyline, cumulative, entry_arc)
	var hole_point: Vector3 = level_manager.grid_to_world(_absorb_cell, level_manager.cat_world_y)
	var to_hole: Vector3 = hole_point - entry_point
	var span: float = to_hole.length()
	var overshoot: float = -from_entry
	var direction: Vector3 = _model_head_direction(polyline, cumulative, entry_arc)
	if span > 0.000001:
		# 모델 머리가 들어가는 쪽 끝에 있으면 머리 축이 구멍을 향한다.
		var head_on_entry: bool = _absorb_from_lead != _lead_is_tail
		direction = to_hole.normalized() * (1.0 if head_on_entry else -1.0)
	if span > 0.000001 and overshoot <= span:
		var position := entry_point.lerp(hole_point, overshoot / span)
		return [position, direction]
	return [hole_point + Vector3.DOWN * (overshoot - span), direction]


# 마지막 본까지 바닥 아래로 사라지는 데 필요한 총 흡입 길이.
func _absorb_arc_to_finish(
	polyline: PackedVector3Array, cumulative: PackedFloat32Array, total_length: float
) -> float:
	var entry_arc: float = 0.0 if _absorb_from_lead else total_length
	var entry_point: Vector3 = _sample_polyline(polyline, cumulative, entry_arc)
	var hole_point: Vector3 = level_manager.grid_to_world(_absorb_cell, level_manager.cat_world_y)
	return (
		total_length
		+ entry_point.distance_to(hole_point)
		+ level_manager.fitted_tile_size() * ABSORB_SINK_CELLS
	)


func can_enter(cell: Vector2i) -> bool:
	if level_manager == null or not level_manager.is_inside_grid(cell):
		return false
	if level_manager.is_cell_blocked_for(self, cell):
		return false
	# 뒤끝 칸도 막힌다. 전이 중 뒤끝은 아직 0.5칸을 점유한다.
	return not body_cells.has(cell)


# 시작 자세로 되돌린다. `initial_body_cells` 가 유효하면 그 경로를 그대로 쓰고,
# 아니면 `grid_pos` + `facing_name` + `initial_length` 의 직선 몸으로 폴백한다.
func _reset_initial_body() -> void:
	facing_dir = _direction_from_name(facing_name)
	path_queue.clear()
	_pending_reverse = 0
	_is_reversing = false
	_transition_t = 0.0
	_is_moving = false
	_lead_is_tail = false
	_pending_lead_flip = false
	_is_blocked = false
	body_cells.clear()
	_notify_path_preview_changed()

	if _is_valid_body_path(initial_body_cells):
		body_cells.assign(initial_body_cells)
		# grid_pos / facing_name / initial_length 는 여기서 파생시킨다. 세터를 다시 타면
		# 무한 재진입이 되므로 가드 플래그를 걸고 대입한다.
		_applying_initial_body = true
		grid_pos = body_cells[0]
		initial_length = body_cells.size()
		facing_dir = body_cells[0] - body_cells[1]
		facing_name = _name_from_direction(facing_dir)
		_applying_initial_body = false
		_rail = body_cells.duplicate()
		return

	var length := clampi(initial_length, min_length, max_length)
	# 머리는 grid_pos에 두고 몸통은 바라보는 방향의 반대쪽으로 놓는다.
	for index in range(length):
		body_cells.append(grid_pos - facing_dir * index)
	_rail = body_cells.duplicate()


# 4방향으로 인접하고 자기와 교차하지 않는 2칸 이상의 경로인지. 보드 안인지는 여기서 보지
# 않는다(`level_manager` 가 아직 없는 시점에도 세터가 돌기 때문이다).
func _is_valid_body_path(cells: Array[Vector2i]) -> bool:
	if cells.size() < 2:
		return false
	for index in cells.size():
		if cells.find(cells[index]) != index:
			return false
		if index > 0:
			var step: Vector2i = cells[index] - cells[index - 1]
			if absi(step.x) + absi(step.y) != 1:
				return false
	return true


func _name_from_direction(direction: Vector2i) -> String:
	match direction:
		Vector2i.UP:
			return "up"
		Vector2i.RIGHT:
			return "right"
		Vector2i.DOWN:
			return "down"
		Vector2i.LEFT:
			return "left"
	return facing_name


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
	_inserted_mid_bones.clear()
	# 1차 캐시: 원본 rest 길이와 오버행을 잰다. 몇 칸 분량을 복제해야 하는지가 여기서 나온다.
	_cache_bone_rests()
	_extend_middle_section()
	# 타일 머티리얼의 반복 횟수는 캐시된 rest 길이에 의존한다.
	_apply_current_shader_parameters()
	apply_rest_pose()

	# color_id 0 is the orange pair.  Keep the key under Bone004 so it
	# stays just below the neck while the cat follows corners and animates.
	if color_id == ORANGE_CAT_COLOR_ID and show_key:
		var neck_key_attachment := BoneAttachment3D.new()
		neck_key_attachment.name = "NeckKeyAttachment"
		neck_key_attachment.bone_name = "Bone004"
		_skeleton.add_child(neck_key_attachment)
		var key_model := (load(KEY_MODEL_SCENE_PATH) as PackedScene).instantiate() as Node3D
		key_model.name = "Key"
		neck_key_attachment.add_child(key_model)
		_apply_key_visual_settings(key_model)


func _refresh_key_visual() -> void:
	if _skeleton != null:
		var key := _skeleton.get_node_or_null("NeckKeyAttachment/Key") as Node3D
		if key != null:
			_apply_key_visual_settings(key)
	_request_editor_refresh()


func _apply_key_visual_settings(key: Node3D) -> void:
	# The imported mesh sits off its FBX root. The Inspector default recenters
	# it on Bone004 and lifts it onto the cat's visible surface.
	key.position = key_local_position
	key.rotation_degrees = key_rotation_degrees
	key.scale = key_scale
	for mesh in _skinned_meshes(key):
		mesh.material_override = key_material_override
	if key_material_override != null and key_outline_material != null:
		key_material_override.next_pass = key_outline_material


# 길이 증가분을 본+링 복제로 흡수한다(중간복제, `CatMiddleDuplicator`). 복제 후 남는 끝수만
# 기존 신축 배율이 흡수하므로 배율이 항상 1±6% 에 머물고, 길이가 길어져도 링 밀도와 꺾임
# 모양이 길이 3과 같다. 몸 길이는 고정이므로 스폰 시 한 번만 하면 된다.
func _extend_middle_section() -> void:
	if _skeleton == null or _rest_chain_length <= 0.000001:
		return
	var model_scale := _grid_fitted_model_scale()
	if model_scale <= 0.000001:
		return
	var extra_model: float = _target_chain_world_length() / model_scale - _rest_chain_length
	if extra_model <= 0.0:
		return

	var tile_mesh: MeshInstance3D = null
	for mesh_instance in _skinned_meshes(_cat_model):
		if mesh_instance.mesh.get_surface_count() > CatMiddleDuplicator.TILE_SURFACE_INDEX:
			tile_mesh = mesh_instance
			break
	_inserted_mid_bones = CatMiddleDuplicator.extend(_skeleton, tile_mesh, extra_model)
	if _inserted_mid_bones.is_empty():
		return

	# 2차 캐시: 삽입 본을 체인과 거리에 반영한다. 오버행은 1차 값을 유지한다 —
	# 오버행은 머리·꼬리 청크의 속성이라 중간 복제와 무관한데, 측정이 바인드 공간 AABB
	# 근사여서 복제 후에 다시 재면 꼬리쪽이 0으로 잘못 잡힌다.
	var saved_head_overhang := _head_mesh_overhang
	var saved_tail_overhang := _tail_mesh_overhang
	_cache_bone_rests()
	_head_mesh_overhang = saved_head_overhang
	_tail_mesh_overhang = saved_tail_overhang


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
	if _is_absorbing:
		_absorb_required_arc = _absorb_arc_to_finish(polyline, cumulative, total_length)
	var head_pose: Array = _pose_at(polyline, cumulative, total_length, head_arc)
	var head_dir: Vector3 = head_pose[1]
	var item_lift := 0.0
	if _is_absorbing and _item_clear:
		var entry_arc: float = 0.0 if _absorb_from_lead else total_length
		var entry_point: Vector3 = _sample_polyline(polyline, cumulative, entry_arc)
		var hole_point: Vector3 = level_manager.grid_to_world(_absorb_cell, level_manager.cat_world_y)
		var span: float = entry_point.distance_to(hole_point)
		if span > 0.000001:
			item_lift = sin(PI * minf(_swallowed_arc / span, 1.0)) * level_manager.fitted_tile_size() * 0.25
	var item_lift_offset := Vector3.UP * item_lift

	position = head_pose[0] + item_lift_offset
	rotation = Vector3.ZERO
	scale = Vector3.ONE
	# FBX 로컬 +Y 는 머리가 바라보는 방향이다. 상체 비율 보존을 위해 균일 스케일만 쓴다.
	_cat_model.basis = _fbx_basis_for_direction(head_dir)
	_cat_model.scale = Vector3.ONE * model_scale
	# 노드 원점이 머리 본 위치이므로, 머리 본이 원점에 오도록 모델을 밀어 준다.
	_cat_model.position = _cat_model.basis * (-_head_bone_rest_global.origin)

	if not is_inside_tree() or not is_instance_valid(_skeleton) or not _skeleton.is_inside_tree():
		return
	var cat_to_skeleton: Transform3D = global_transform.affine_inverse() * _skeleton.global_transform
	var skeleton_rotation: Basis = cat_to_skeleton.basis.orthonormalized()
	var skeleton_rotation_inverse: Basis = skeleton_rotation.inverse()
	var reference_inverse: Basis = _fbx_basis_for_direction(head_dir).inverse()
	var to_skeleton: Transform3D = cat_to_skeleton.affine_inverse()
	var desired := {}
	for chain_index in _bone_chain.size():
		var arc: float = chain_distances[chain_index] * model_scale
		var arc_from_lead: float = (total_length - arc) if _lead_is_tail else arc
		var pose: Array = _pose_at(polyline, cumulative, total_length, arc_from_lead)
		var point: Vector3 = pose[0] + item_lift_offset
		var direction: Vector3 = pose[1]
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


# 호 위치 하나를 (자리, 머리 축 방향) 으로 바꾸는 단일 창구. 평소에는 폴리라인을 그대로
# 샘플링하고, 흡입 중에만 구멍 쪽으로 밀린 좌표계를 쓴다.
func _pose_at(
	polyline: PackedVector3Array,
	cumulative: PackedFloat32Array,
	total_length: float,
	arc_from_lead: float
) -> Array:
	if _is_absorbing:
		return _absorb_pose_at(polyline, cumulative, total_length, arc_from_lead)
	return [
		_sample_polyline(polyline, cumulative, arc_from_lead),
		_model_head_direction(polyline, cumulative, arc_from_lead),
	]


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
	return _extend_ends(_cell_center_polyline())


# 셀 중심을 잇는 순수 경로. 코너는 언제나 셀 중앙을 관통한다.
func _cell_center_polyline() -> PackedVector3Array:
	var points := PackedVector3Array()
	var height := level_manager.cat_world_y
	if not _is_moving or _rail.size() < 3:
		for cell in body_cells:
			points.append(level_manager.grid_to_world(cell, height))
		return points

	# 전이 중 양끝만 셀 사이에 놓인다. 후진에서는 들어가는 끝과 빠지는 끝이 뒤바뀐다.
	var last := _rail.size() - 1
	var lead_from: int = 0 if _is_reversing else 1
	var lead_to: int = 1 if _is_reversing else 0
	var far_from: int = last - 1 if _is_reversing else last
	var far_to: int = last if _is_reversing else last - 1
	points.append(
		level_manager.grid_to_world(_rail[lead_from], height).lerp(
			level_manager.grid_to_world(_rail[lead_to], height), _transition_t
		)
	)
	for index in range(1, last):
		points.append(level_manager.grid_to_world(_rail[index], height))
	points.append(
		level_manager.grid_to_world(_rail[far_from], height).lerp(
			level_manager.grid_to_world(_rail[far_to], height), _transition_t
		)
	)
	return points


# 양끝을 메시 오버행만큼 밖으로 내민다. 이래야 스킨된 메시가 발자국을 정확히 채운다.
# 내미는 방향은 끝 선분의 연장선이므로 셀 중심 경로의 모양은 변하지 않는다.
func _extend_ends(points: PackedVector3Array) -> PackedVector3Array:
	if points.size() < 2:
		return points
	var lead_overhang: float = _tail_mesh_overhang if _lead_is_tail else _head_mesh_overhang
	var far_overhang: float = _head_mesh_overhang if _lead_is_tail else _tail_mesh_overhang
	var extended := PackedVector3Array()
	extended.append(points[0] + _outward_direction(points, true) * _end_extension(lead_overhang))
	extended.append_array(points)
	extended.append(
		points[points.size() - 1] + _outward_direction(points, false) * _end_extension(far_overhang)
	)
	return extended


# 끝에서 바깥을 향하는 단위 방향. 길이가 0인 선분(전이 시작 순간)은 건너뛴다.
func _outward_direction(points: PackedVector3Array, from_start: bool) -> Vector3:
	var count := points.size() - 1
	for offset in count:
		var index: int = offset if from_start else count - 1 - offset
		var delta: Vector3 = points[index] - points[index + 1]
		if delta.length_squared() > 0.000001:
			return (delta if from_start else -delta).normalized()
	var fallback := level_manager.grid_dir_to_world(facing_dir)
	return fallback if fallback.length_squared() > 0.000001 else Vector3.FORWARD


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
	_cache_mesh_overhang()


# 오버행은 신축 배율에 따라 조금씩 달라진다. 머리 끝 정점 일부가 신축 구간 본에 물려
# 있어서, rest AABB 로 잰 상수를 쓰면 양끝 여백이 0.08/0.12 처럼 어긋난다.
# 포즈 -> 실측 -> 재계산을 몇 번 돌려 고정점으로 수렴시킨다. 1300 정점이라 비용은 무시할 만하다.
# 스킨된 메시가 양끝 본보다 얼마나 더 나가는지 rest 자세의 AABB 로 잰다.
# 머리는 귀·코, 꼬리는 뒷다리가 만들며 앞뒤가 4배 차이난다.
func _cache_mesh_overhang() -> void:
	_head_mesh_overhang = 0.0
	_tail_mesh_overhang = 0.0
	if _skeleton == null or _cat_model == null or _bone_chain.size() < 2:
		return
	var head_origin: Vector3 = _skeleton.get_bone_global_rest(_bone_chain[0]).origin
	var tail_origin: Vector3 = _skeleton.get_bone_global_rest(_bone_chain[_bone_chain.size() - 1]).origin
	var axis: Vector3 = head_origin - tail_origin
	if axis.length_squared() < 0.000001:
		return
	var chain_length: float = axis.length()
	axis = axis.normalized()

	var lowest := INF
	var highest := -INF
	for mesh_instance in _skinned_meshes(_cat_model):
		# 메시 정점은 본 rest 공간이 아니라 Skin 의 바인드 공간에 있고, 이 리그의 공통
		# 바인드 행렬에는 회전이 들어 있다. rest 역행렬을 역바인드로 쓰면 값이 엉뚱해진다.
		var bind: Transform3D = _rest_bind_transform(mesh_instance)
		var bounds: AABB = mesh_instance.mesh.get_aabb()
		for corner in 8:
			var along: float = ((bind * bounds.get_endpoint(corner)) - tail_origin).dot(axis)
			lowest = minf(lowest, along)
			highest = maxf(highest, along)
	if lowest == INF:
		return
	_head_mesh_overhang = maxf(highest - chain_length, 0.0)
	_tail_mesh_overhang = maxf(-lowest, 0.0)


func _rest_bind_transform(mesh_instance: MeshInstance3D) -> Transform3D:
	var skin: Skin = mesh_instance.skin
	if skin == null or skin.get_bind_count() == 0:
		return Transform3D.IDENTITY
	var bone_name: String = skin.get_bind_name(0)
	var bone: int = _skeleton.find_bone(bone_name) if bone_name != "" else skin.get_bind_bone(0)
	if bone < 0:
		return Transform3D.IDENTITY
	return _skeleton.get_bone_global_rest(bone) * skin.get_bind_pose(0)


func _skinned_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_skinned_meshes(child))
	return found


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

	# 중간복제 본은 Bone008 의 자식 사슬이지 Bone009 의 조상이 아니라서(부모 인덱스 순서
	# 제약 때문에 리페어런트하지 않는다) 부모 걷기에 안 잡힌다. 여기서 직접 이어 붙인다.
	# Bone009 의 rest 는 삽입 길이만큼 늘어나 있으므로 아래 거리 계산이 그대로 맞는다.
	if not _inserted_mid_bones.is_empty():
		var cut_index: int = _bone_chain.find(
			_skeleton.find_bone(CatMiddleDuplicator.CUT_BONE_NAME)
		)
		if cut_index >= 0:
			for offset in _inserted_mid_bones.size():
				_bone_chain.insert(cut_index + 1 + offset, _inserted_mid_bones[offset])

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
	return fbx_scale_per_tile * level_manager.fitted_tile_size() / REFERENCE_TILE_SIZE


func _is_stretchable_chain_bone(chain_index: int) -> bool:
	if _skeleton == null or chain_index < 0 or chain_index >= _bone_chain.size():
		return false
	var bone_name := _skeleton.get_bone_name(_bone_chain[chain_index])
	var suffix := bone_name.trim_prefix("Bone")
	# 접미사가 순수 숫자인 원본 본만 신축한다. 중간복제 본("BoneMid001")은 to_int() 가
	# 숫자를 뽑아내 7~14 로 오인할 수 있으므로 반드시 여기서 걸러야 한다.
	if not suffix.is_valid_int():
		return false
	var bone_number := suffix.to_int()
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
	# 스킨된 메시가 발자국을 정확히 채우는 배율.
	# 텍스처 반복은 이 고정값으로 계산해 이동 중 패턴이 기어가지 않게 한다.
	if level_manager == null:
		return 1.0
	return _fitted_stretch_scale(_target_chain_world_length())


# 본 체인이 가져야 할 길이. 셀 중심 경로에 양끝 내밀기를 더한 값이다.
func _target_chain_world_length() -> float:
	if level_manager == null:
		return 1.0
	var path := float(maxi(body_cells.size() - 1, 1)) * level_manager.fitted_tile_size()
	return path + _end_extension(_head_mesh_overhang) + _end_extension(_tail_mesh_overhang)


# 폴리라인 양끝을 끝 셀 중심에서 밖으로 내미는 양. 메시가 그만큼 더 나가므로
# 오버행이 큰 머리쪽은 거의 내밀지 않는다. 음수면 경로가 접히므로 0으로 묶는다.
func _end_extension(overhang_model: float) -> float:
	var to_edge := level_manager.fitted_tile_size() * (0.5 - footprint_margin_cells)
	return maxf(to_edge - overhang_model * _grid_fitted_model_scale(), 0.0)

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
	# 길이별 본 확장은 Skin 바인드를 바꾸므로, FBX 원본을 다른 고양이와 공유하면 안 된다.
	for mesh_instance in _skinned_meshes(model_root):
		if mesh_instance.skin != null:
			mesh_instance.skin = mesh_instance.skin.duplicate(true)
	_build_cat_material()
	_apply_material_recursive(model_root)
	# Lobby actors mount the model directly rather than through board setup.
	# The floating-water method caches the live rig on its first update.
	# Board setup clears its inserted-bone cache immediately after this call,
	# so it must remain responsible for its own rest-pose cache.
	_cat_model = model_root
	_skeleton = _find_skeleton_in(model_root)
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
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if _floating_water_outline
			else GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		)
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
	# Inspector and Remote Inspector changes both need to refresh the matching
	# CatHole immediately. Do not wait for a board rebuild to copy this style.
	if level_manager != null:
		level_manager.sync_hole_visual_style_for_color(color_id)


func _apply_shader_parameters(
	texture: Texture2D,
	use_tint_exclusion_mask := true,
	hide_line_art_eyes := false,
	custom_tint_exclusion_mask: Texture2D = null
) -> void:
	var tint_exclusion_mask: Texture2D = custom_tint_exclusion_mask if custom_tint_exclusion_mask != null else _get_tint_exclusion_mask()
	var active_tint: Color = _effective_tint_color()
	if _cat_material != null:
		_cat_material.set_shader_parameter("albedo_tex", texture)
		_cat_material.set_shader_parameter("tint_exclusion_mask", tint_exclusion_mask)
		_cat_material.set_shader_parameter("tint_exclusion_enabled", 1.0 if use_tint_exclusion_mask else 0.0)
		_cat_material.set_shader_parameter("tint_color", active_tint)
		_cat_material.set_shader_parameter("shadow_steps", toon_steps)
		_cat_material.set_shader_parameter("shadow_darkness", shadow_darkness)
		_cat_material.set_shader_parameter("toon_shadow_spread", toon_shadow_spread)
		_cat_material.set_shader_parameter("rim_strength", 0.0 if _floating_water_outline else rim_strength)
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
		_material_id_2.set_shader_parameter("tint_color", active_tint)
		_material_id_2.set_shader_parameter("shadow_steps", toon_steps)
		_material_id_2.set_shader_parameter("shadow_darkness", shadow_darkness)
		_material_id_2.set_shader_parameter("toon_shadow_spread", toon_shadow_spread)
		_material_id_2.set_shader_parameter("rim_strength", 0.0 if _floating_water_outline else rim_strength)
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
		_outline_material.set_shader_parameter("outline_color", _effective_outline_color())
		_outline_material.set_shader_parameter(
			"outline_width",
			FLOATING_WATER_OUTLINE_WIDTH if _floating_water_outline else outline_width
		)
		_outline_material.set_shader_parameter("top_outline_scale", top_outline_scale)
		_outline_material.set_shader_parameter("bottom_outline_scale", bottom_outline_scale)
	if _material_id_2_outline != null:
		_material_id_2_outline.set_shader_parameter("outline_color", _effective_outline_color())
		_material_id_2_outline.set_shader_parameter(
			"outline_width",
			FLOATING_WATER_OUTLINE_WIDTH if _floating_water_outline else outline_width
		)
		_material_id_2_outline.set_shader_parameter("top_outline_scale", top_outline_scale)
		_material_id_2_outline.set_shader_parameter("bottom_outline_scale", bottom_outline_scale)

	# 중첩고양이 색 영역. 마스크 텍스처가 아직 없으면 셰이더의 임시 줄무늬로 폴백한다.
	var mask1 := _get_nest_mask1()
	for body_material in [_cat_material, _material_id_2]:
		if body_material == null:
			continue
		body_material.set_shader_parameter("nest1_enabled", 1.0 if nested_color_ids.size() >= 1 else 0.0)
		body_material.set_shader_parameter("nest2_enabled", 1.0 if nested_color_ids.size() >= 2 else 0.0)
		body_material.set_shader_parameter("nest_color1", _nest_color(0))
		body_material.set_shader_parameter("nest_color2", _nest_color(1))
		body_material.set_shader_parameter("nest_mask1", mask1)
		body_material.set_shader_parameter("nest_mask2", _get_nest_mask2())
		body_material.set_shader_parameter("nest_procedural", 0.0 if mask1 != null else 1.0)

	# 흡입 중에만 바닥 면 아래로 내려간 부분을 지운다. 본체와 아웃라인이 같은 기준을
	# 써야 껍데기만 남는 일이 없다.
	var tile: float = level_manager.fitted_tile_size() if level_manager != null else 2.0
	for sink_material in [_cat_material, _material_id_2, _outline_material, _material_id_2_outline]:
		if sink_material == null:
			continue
		sink_material.set_shader_parameter("sink_clip_enabled", 1.0 if _is_absorbing else 0.0)
		sink_material.set_shader_parameter("sink_clip_plane_y", LevelManager.TILE_HEIGHT)
		sink_material.set_shader_parameter("sink_clip_span", tile * ABSORB_SINK_CELLS)
		sink_material.set_shader_parameter("body_shrink", _nest_shrink)


# 안쪽 i번째 색. 팔레트에서 뽑아 겉껍질 위 마스크 영역에 그대로 보여 준다.
func _nest_color(index: int) -> Color:
	if index >= nested_color_ids.size() or level_manager == null:
		return Color.WHITE
	return level_manager.get_pair_color(nested_color_ids[index])


func _get_nest_mask1() -> Texture2D:
	if _nest_mask1 == null and ResourceLoader.exists(COLOR_MASK1_PATH):
		_nest_mask1 = load(COLOR_MASK1_PATH) as Texture2D
	return _nest_mask1


func _get_nest_mask2() -> Texture2D:
	if _nest_mask2 == null and ResourceLoader.exists(COLOR_MASK2_PATH):
		_nest_mask2 = load(COLOR_MASK2_PATH) as Texture2D
	return _nest_mask2


func _get_open_eyes_texture() -> Texture2D:
	if _open_eyes_texture == null:
		_open_eyes_texture = load(MODEL_TEXTURE_PATH) as Texture2D
	return _open_eyes_texture


func _get_open_mouth_texture() -> Texture2D:
	if _open_mouth_texture == null:
		_open_mouth_texture = load(OPEN_MOUTH_TEXTURE_PATH) as Texture2D
	return _open_mouth_texture


# 팔레트 짝 색. 팔레트를 쓰지 않는 설정이거나 아직 매니저가 없으면 null 이고,
# 그때는 Inspector 에 적어 둔 틴트 값이 그대로 쓰인다.
func _pair_color() -> Variant:
	if not tint_from_pair_color or color_id < 0 or level_manager == null:
		return null
	return level_manager.get_pair_color(color_id)


func _effective_tint_color() -> Color:
	var pair: Variant = _pair_color()
	return tint_color if pair == null else pair as Color


# CatHole uses this snapshot when it represents this cat's color_id. Keep the
# names aligned with cat_toon.gdshader and cat_outline.gdshader. The CatHole
# keeps its own outline-width control because cat_hole1.fbx needs a different
# visual weight from the movable cat.
func get_hole_visual_style(pair_color: Color) -> Dictionary:
	return {
		"tint_color": pair_color if tint_from_pair_color else tint_color,
		"toon_steps": toon_steps,
		"shadow_darkness": shadow_darkness,
		"toon_shadow_spread": toon_shadow_spread,
		"rim_strength": rim_strength,
		"line_art_tex": line_art_texture,
		"line_art_eye_mask": _get_tint_exclusion_mask(),
		"line_art_enabled": 1.0 if line_art_texture != null else 0.0,
		"line_art_color": line_art_color,
		"line_art_strength": line_art_strength,
		"tint_exclusion_mask": _get_tint_exclusion_mask(),
		"tint_exclusion_enabled": 1.0,
		# 외곽선 색은 파생값을 쓴다. 원시 Inspector 값을 넘기면 짝 색을 쓰는 고양이의 구멍이
		# 템플릿에 박힌 손튜닝 색(크림 고양이 기준)을 복제받는다. 폭은 위의 전용 값으로 관리한다.
		"outline_color": _effective_outline_color(),
		"outline_width": cat_hole_outline_width,
		"top_outline_scale": top_outline_scale,
		"bottom_outline_scale": bottom_outline_scale,
	}


# 외곽선 기본색도 짝 색에서 만든다. 안 그러면 템플릿에 박힌 손튜닝 값(크림색 고양이 기준)이
# 모든 생성 고양이에 복제되어, 파란 고양이가 웜톤(핑크빛) 외곽선을 받는다. 밝기와 알파는
# CatEntity Inspector 에서 개별 조정할 수 있게 별도 배율/알파를 얹는다.
func _effective_outline_color() -> Color:
	if _floating_water_outline:
		return FLOATING_WATER_OUTLINE_COLOR
	var pair: Variant = _pair_color()
	var base_color: Color = outline_color if pair == null else (pair as Color).darkened(0.27)
	var effective := Color(
		clampf(base_color.r * outline_brightness, 0.0, 1.0),
		clampf(base_color.g * outline_brightness, 0.0, 1.0),
		clampf(base_color.b * outline_brightness, 0.0, 1.0),
		outline_color.a
	)
	return effective


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


func _is_inside_active_camera_view() -> bool:
	if not is_visible_in_tree():
		return false
	var camera := get_viewport().get_camera_3d()
	var mouth_position := global_position
	if is_instance_valid(_skeleton) and _skeleton.is_inside_tree() and _head_bone_index >= 0:
		mouth_position = _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone_index).origin
	if camera == null or camera.is_position_behind(mouth_position):
		return false
	var screen_position := camera.unproject_position(mouth_position)
	return get_viewport().get_visible_rect().has_point(screen_position)


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


func _notify_path_preview_changed() -> void:
	if level_manager != null:
		level_manager.refresh_path_preview()


func _direction_from_name(dir_name: String) -> Vector2i:
	match dir_name.to_lower():
		"up": return Vector2i.UP
		"right": return Vector2i.RIGHT
		"down": return Vector2i.DOWN
		"left": return Vector2i.LEFT
		_: return Vector2i.UP
