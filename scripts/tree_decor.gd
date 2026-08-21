@tool
class_name TreeDecor
extends Node3D

## Freely place this scene beneath LevelManager/TileVisuals. It is a visual
## decoration only: it does not reserve grid cells or affect cat movement.

const MODEL_SCENE_PATH := "res://water_yang/tree1.fbx"
const TREE_MATERIAL_PATH := "res://resources/tree_material.tres"

@export_group("Model")
@export_range(0.01, 20.0, 0.01) var model_scale := 1.0:
	set(value):
		model_scale = value
		_apply_model_scale()

@export var cast_shadow := true:
	set(value):
		cast_shadow = value
		_apply_material_style()

@export_group("Material")
@export var tint_color := Color.WHITE:
	set(value):
		tint_color = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var roughness := 0.9:
	set(value):
		roughness = value
		_apply_material_style()

@export_group("Toon Shader")
@export_range(2, 5, 1) var toon_steps := 3:
	set(value):
		toon_steps = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var shadow_darkness := 0.58:
	set(value):
		shadow_darkness = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var rim_strength := 0.24:
	set(value):
		rim_strength = value
		_apply_material_style()

@export_group("Outline")
@export var outline_color := Color(0.105, 0.16, 0.075, 1.0):
	set(value):
		outline_color = value
		_apply_material_style()

@export_range(0.001, 0.12, 0.001) var outline_width := 0.018:
	set(value):
		outline_width = value
		_apply_material_style()

var _model_root: Node3D
var _tree_material: ShaderMaterial
var _outline_material: ShaderMaterial


func _ready() -> void:
	add_to_group("persistent_tile_visuals")
	_ensure_model()
	_apply_model_scale()
	_apply_material_style()


func _ensure_model() -> void:
	if is_instance_valid(_model_root):
		return
	# Keep a material-bound FBX child in the scene as well as handling older
	# instances made before that child existed. The static binding makes the
	# texture visible immediately in the editor, before this @tool script runs.
	_model_root = get_node_or_null("TreeModel") as Node3D
	if _model_root != null:
		_build_materials()
		_apply_material_recursive(_model_root)
		return

	var packed_scene := load(MODEL_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("TreeDecor could not load %s" % MODEL_SCENE_PATH)
		return
	_model_root = packed_scene.instantiate() as Node3D
	if _model_root == null:
		push_error("TreeDecor model root must be Node3D")
		return
	_model_root.name = "TreeModel"
	add_child(_model_root)
	_build_materials()
	_apply_material_recursive(_model_root)


func _build_materials() -> void:
	var source := load(TREE_MATERIAL_PATH) as ShaderMaterial
	if source == null:
		push_error("TreeDecor could not load %s" % TREE_MATERIAL_PATH)
		return
	# Every tree owns its material instances, so Inspector edits affect only the
	# selected decoration rather than every tree placed on a map.
	_tree_material = source.duplicate(true) as ShaderMaterial
	_outline_material = _tree_material.next_pass as ShaderMaterial


func _apply_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and _tree_material != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface_index, _tree_material)
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in node.get_children():
		_apply_material_recursive(child)


func _apply_model_scale() -> void:
	if is_instance_valid(_model_root):
		_model_root.scale = Vector3.ONE * model_scale


func _apply_material_style() -> void:
	if _tree_material == null:
		return
	_tree_material.set_shader_parameter("tint_color", tint_color)
	_tree_material.set_shader_parameter("roughness", roughness)
	_tree_material.set_shader_parameter("shadow_steps", toon_steps)
	_tree_material.set_shader_parameter("shadow_darkness", shadow_darkness)
	_tree_material.set_shader_parameter("rim_strength", rim_strength)
	if _outline_material != null:
		_outline_material.set_shader_parameter("outline_color", outline_color)
		_outline_material.set_shader_parameter("outline_width", outline_width)
	if is_instance_valid(_model_root):
		_apply_material_recursive(_model_root)
