@tool
class_name CatEntity
extends Area3D

const MODEL_SCENE_PATH := "res://water_yang/ca1.fbx"
const MODEL_TEXTURE_PATH := "res://water_yang/cat1.jpeg"
const TOON_SHADER_PATH := "res://scripts/cat_toon.gdshader"
const MODEL_SCALE := Vector3(0.45, 0.45, 0.45)
const BUMP_DISTANCE := 0.35
const BUMP_TIME := 0.12
const ESCAPE_MIN_TIME := 0.28
const ESCAPE_MAX_TIME := 0.8

@export_group("Layout")
@export var grid_pos: Vector2i = Vector2i.ZERO:
	set(value):
		grid_pos = value
		_request_editor_refresh()

@export_enum("up", "right", "down", "left") var facing_name: String = "up":
	set(value):
		facing_name = value
		facing_dir = _direction_from_name(facing_name)
		_request_editor_refresh()

@export_group("Toon Shader")
@export var tint_color: Color = Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		tint_color = value
		_update_material()

@export_range(2, 5, 1) var toon_steps: int = 3:
	set(value):
		toon_steps = value
		_update_material()

@export_range(0.0, 1.0, 0.01) var shadow_darkness: float = 0.58:
	set(value):
		shadow_darkness = value
		_update_material()

@export_range(0.0, 1.0, 0.01) var rim_strength: float = 0.24:
	set(value):
		rim_strength = value
		_update_material()

var facing_dir: Vector2i = Vector2i.UP
var level_manager: LevelManager
var is_animating: bool = false

var _visual_root: Node3D


func _ready() -> void:
	input_ray_pickable = true
	collision_layer = 1
	collision_mask = 1
	facing_dir = _direction_from_name(facing_name)
	_ensure_collision_shape()
	_ensure_visual_root()

	if Engine.is_editor_hint():
		refresh_editor_preview()


func setup(
	p_grid_pos: Vector2i,
	p_facing_dir: Vector2i,
	p_level_manager: LevelManager,
	p_tint_color: Color = Color(1.0, 1.0, 1.0, 1.0)
) -> void:
	grid_pos = p_grid_pos
	facing_dir = p_facing_dir
	facing_name = _name_from_direction(facing_dir)
	level_manager = p_level_manager
	tint_color = p_tint_color

	_ensure_collision_shape()
	_ensure_visual_root()
	_sync_to_grid_position()


func refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return

	level_manager = _find_level_manager()
	if level_manager == null:
		return

	facing_dir = _direction_from_name(facing_name)
	_ensure_collision_shape()
	_ensure_visual_root()
	_update_material()
	_sync_to_grid_position()


func try_escape() -> void:
	# 이미 액션 중인 고양이는 다시 선택되지 않게 막는다.
	if is_animating or level_manager == null:
		return

	var escape_result: Dictionary = level_manager.get_escape_result(self)
	if bool(escape_result.get("is_path_clear", false)):
		var exit_world_position: Vector3 = escape_result.get("exit_world_position", position)
		_play_escape(exit_world_position)
	else:
		_play_bump()


func _ensure_collision_shape() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return

	var collision_shape: CollisionShape3D = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"

	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(1.1, 1.5, 1.1)
	collision_shape.shape = box_shape
	add_child(collision_shape)


func _ensure_visual_root() -> void:
	if _visual_root != null:
		return

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot"
	add_child(_visual_root)

	var model_instance: Node3D = _load_model_with_texture()
	model_instance.scale = MODEL_SCALE
	_visual_root.add_child(model_instance)


func _load_model_with_texture() -> Node3D:
	# FBX를 인스턴스화하고 툰 셰이더 재질을 모든 메시에게 입힌다.
	var packed_scene: PackedScene = load(MODEL_SCENE_PATH) as PackedScene
	var model_root: Node3D

	if packed_scene != null:
		var instantiated: Node = packed_scene.instantiate()
		if instantiated is Node3D:
			model_root = instantiated as Node3D
		else:
			model_root = Node3D.new()
			model_root.add_child(instantiated)
	else:
		model_root = _create_fallback_mesh()

	var material: Material = _build_cat_material()
	_apply_material_recursive(model_root, material)
	return model_root


func _create_fallback_mesh() -> Node3D:
	# 모델 임포트가 아직 안 끝났더라도 플레이 흐름을 확인할 수 있게 대체 메시를 둔다.
	var fallback_root: Node3D = Node3D.new()
	var body_mesh: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.mid_height = 0.8
	capsule.radius = 0.35
	body_mesh.mesh = capsule
	body_mesh.position.y = 0.5
	fallback_root.add_child(body_mesh)
	return fallback_root


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material

	for child in node.get_children():
		_apply_material_recursive(child, material)


func _update_material() -> void:
	if _visual_root == null:
		return

	var material: Material = _build_cat_material()
	_apply_material_recursive(_visual_root, material)


func _build_cat_material() -> Material:
	var shader: Shader = load(TOON_SHADER_PATH) as Shader
	var texture: Texture2D = load(MODEL_TEXTURE_PATH) as Texture2D

	if shader == null:
		var fallback_material: StandardMaterial3D = StandardMaterial3D.new()
		fallback_material.albedo_texture = texture
		fallback_material.albedo_color = tint_color
		fallback_material.roughness = 0.75
		fallback_material.metallic = 0.0
		return fallback_material

	var toon_material: ShaderMaterial = ShaderMaterial.new()
	toon_material.shader = shader
	toon_material.set_shader_parameter("albedo_tex", texture)
	toon_material.set_shader_parameter("tint_color", tint_color)
	toon_material.set_shader_parameter("shadow_steps", toon_steps)
	toon_material.set_shader_parameter("shadow_darkness", shadow_darkness)
	toon_material.set_shader_parameter("rim_strength", rim_strength)
	return toon_material


func _sync_to_grid_position() -> void:
	if level_manager == null:
		return

	position = level_manager.grid_to_world(grid_pos, level_manager.cat_world_y)
	rotation.y = _direction_to_yaw(facing_dir)


func _play_bump() -> void:
	is_animating = true

	var home_position: Vector3 = level_manager.grid_to_world(grid_pos, level_manager.cat_world_y)
	var bump_target: Vector3 = home_position + level_manager.grid_dir_to_world(facing_dir) * BUMP_DISTANCE

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", bump_target, BUMP_TIME)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", home_position, BUMP_TIME)
	tween.finished.connect(_on_bump_finished)


func _play_escape(exit_world_position: Vector3) -> void:
	is_animating = true
	input_ray_pickable = false

	# 탈출이 확정되면 즉시 점유를 해제해 다음 클릭 계산에 반영한다.
	level_manager.release_cat_cell(self)

	var distance: float = position.distance_to(exit_world_position)
	var duration: float = clampf(distance / (level_manager.tile_size * 5.5), ESCAPE_MIN_TIME, ESCAPE_MAX_TIME)

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "position", exit_world_position, duration)
	tween.finished.connect(_on_escape_finished)


func _on_bump_finished() -> void:
	is_animating = false


func _on_escape_finished() -> void:
	level_manager.on_cat_escaped(self)
	queue_free()


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


func _direction_to_yaw(dir: Vector2i) -> float:
	match dir:
		Vector2i.UP:
			return 0.0
		Vector2i.RIGHT:
			return deg_to_rad(-90.0)
		Vector2i.DOWN:
			return PI
		Vector2i.LEFT:
			return deg_to_rad(90.0)
		_:
			return 0.0


func _direction_from_name(dir_name: String) -> Vector2i:
	match dir_name.to_lower():
		"up":
			return Vector2i.UP
		"right":
			return Vector2i.RIGHT
		"down":
			return Vector2i.DOWN
		"left":
			return Vector2i.LEFT
		_:
			return Vector2i.UP


func _name_from_direction(dir: Vector2i) -> String:
	match dir:
		Vector2i.UP:
			return "up"
		Vector2i.RIGHT:
			return "right"
		Vector2i.DOWN:
			return "down"
		Vector2i.LEFT:
			return "left"
		_:
			return "up"
