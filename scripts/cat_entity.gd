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
const HEAD_BONE_NAME := "Bone002"
const TAIL_BONE_NAME := "Bone022"
const STRETCH_BONE_FIRST := 6
const STRETCH_BONE_LAST := 14
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


# 몸통이 점유한 칸. 머리(0)에서 꼬리(마지막)까지 인접한 경로다.
var body_cells: Array[Vector2i] = []
var facing_dir: Vector2i = Vector2i.UP
var level_manager: LevelManager

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
var _blink_time_remaining := -1.0
var _eyes_are_closed := false
var _blink_random := RandomNumberGenerator.new()
# 머리에서 꼬리까지의 실제 본 인덱스 순서와, 머리 본 기준 rest 누적 거리(모델 로컬 단위).
var _bone_chain: Array[int] = []
var _bone_chain_distances: Array[float] = []
var _rest_chain_length: float = 0.0


func _ready() -> void:
	_blink_random.seed = get_instance_id()
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
	return body_cells.has(cell)


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


func apply_rest_pose() -> void:
	# 이동 로직이 없는 정지 자세. 몸통을 grid_pos 에서 바라보는 방향의 반대쪽으로
	# 곧게 눕히고, initial_length 칸을 채우도록 중간 구간만 늘린다.
	if _cat_model == null or _skeleton == null or level_manager == null:
		return

	_skeleton.clear_bones_global_pose_override()
	_skeleton.reset_bone_poses()
	_enforce_locked_bone_scales()
	_apply_rest_length()

	# FBX 로컬 +Y 는 머리가 바라보는 방향이다. 몸통은 그 반대쪽으로 뻗는다.
	var forward := level_manager.grid_dir_to_world(facing_dir)
	if forward.length_squared() < 0.000001:
		forward = Vector3.FORWARD
	_cat_model.basis = _fbx_basis_for_direction(forward)
	# 상체 비율을 보존하기 위해 모델 루트는 반드시 균일 스케일만 사용한다.
	_cat_model.scale = Vector3.ONE * _grid_fitted_model_scale()
	# 노드 원점이 머리 칸이므로, 머리 본이 원점에 오도록 모델을 밀어 준다.
	_cat_model.position = _cat_model.basis * (-_head_bone_rest_global.origin)


func _apply_rest_length() -> void:
	# 늘어나는 구간(Bone006~014)의 rest 위치만 늘려 전체 길이를 맞춘다.
	# 부모 본을 스케일하면 자식에게 상속되어 길이가 체인을 따라 곱해진다.
	var stretch := _baseline_stretch_scale()
	for chain_index in range(1, _bone_chain.size()):
		if not _is_stretchable_chain_bone(chain_index):
			continue
		var bone_index: int = _bone_chain[chain_index]
		_skeleton.set_bone_pose_position(bone_index, _bone_rests[bone_index].origin * stretch)


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
	_apply_shader_parameters(_get_open_eyes_texture())


func _apply_shader_parameters(texture: Texture2D, use_tint_exclusion_mask := true) -> void:
	if _cat_material != null:
		_cat_material.set_shader_parameter("albedo_tex", texture)
		_cat_material.set_shader_parameter(
			"tint_exclusion_mask", _get_tint_exclusion_mask() if use_tint_exclusion_mask else null
		)
		_cat_material.set_shader_parameter("tint_exclusion_enabled", 1.0 if use_tint_exclusion_mask else 0.0)
		_cat_material.set_shader_parameter("tint_color", tint_color)
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
		var tile_scale := _baseline_stretch_scale()
		_material_id_2.set_shader_parameter("albedo_tex", texture)
		_material_id_2.set_shader_parameter(
			"tint_exclusion_mask", _get_tint_exclusion_mask() if use_tint_exclusion_mask else null
		)
		_material_id_2.set_shader_parameter("tint_exclusion_enabled", 1.0 if use_tint_exclusion_mask else 0.0)
		_material_id_2.set_shader_parameter("tint_color", tint_color)
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
