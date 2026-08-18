@tool
class_name GrassDecor
extends Node3D

## A freely movable visual decoration. Place instances below
## LevelManager/TileVisuals; it never reserves board cells or affects movement.
## The same toon/outline setup is shared by grass and flower decor scenes.

const GRASS_MATERIAL_PATH := "res://resources/grass_material.tres"

@export_group("Model")
@export_range(0.01, 20.0, 0.01) var model_scale := 1.0:
	set(value):
		model_scale = value
		_apply_model_scale()

@export var cast_shadow := true:
	set(value):
		cast_shadow = value
		_apply_material_style()

@export_group("Cat Toon Shader")
@export var tint_color := Color.WHITE:
	set(value):
		tint_color = value
		_apply_material_style()

@export_range(2, 5, 1) var toon_steps := 3:
	set(value):
		toon_steps = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var shadow_darkness := 0.3:
	set(value):
		shadow_darkness = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var rim_strength := 0.56:
	set(value):
		rim_strength = value
		_apply_material_style()

@export_group("Ambient")
@export var ambient_color := Color.WHITE:
	set(value):
		ambient_color = value
		_apply_material_style()

@export_range(0.0, 2.0, 0.01) var ambient_energy := 0.0:
	set(value):
		ambient_energy = value
		_apply_material_style()

@export_group("Outline")
@export var outline_color := Color(0.18, 0.09, 0.06, 1.0):
	set(value):
		outline_color = value
		_apply_material_style()

@export_range(0.0, 0.04, 0.001) var outline_width := 0.006:
	set(value):
		outline_width = value
		_apply_material_style()

@export_range(0.4, 1.2, 0.01) var top_outline_scale := 0.78:
	set(value):
		top_outline_scale = value
		_apply_material_style()

@export_range(0.8, 1.6, 0.01) var bottom_outline_scale := 1.12:
	set(value):
		bottom_outline_scale = value
		_apply_material_style()

var _model_root: Node3D
var _grass_material: ShaderMaterial
var _outline_material: ShaderMaterial


func _ready() -> void:
	add_to_group("persistent_tile_visuals")
	_model_root = get_child(0) as Node3D if get_child_count() > 0 else null
	if _model_root == null:
		push_error("GrassDecor requires a Node3D model child")
		return
	_build_materials()
	_apply_model_scale()
	_apply_material_style()


func _build_materials() -> void:
	var source := load(GRASS_MATERIAL_PATH) as ShaderMaterial
	if source == null:
		push_error("GrassDecor could not load %s" % GRASS_MATERIAL_PATH)
		return
	# Each decoration owns its copy, so Inspector edits affect only this grass.
	_grass_material = source.duplicate(true) as ShaderMaterial
	_outline_material = _grass_material.next_pass as ShaderMaterial


func _apply_model_scale() -> void:
	if is_instance_valid(_model_root):
		_model_root.scale = Vector3.ONE * model_scale


func _apply_material_style() -> void:
	if _grass_material == null:
		call_deferred("_apply_material_style")
		return
	_grass_material.set_shader_parameter("tint_color", tint_color)
	_grass_material.set_shader_parameter("shadow_steps", toon_steps)
	_grass_material.set_shader_parameter("shadow_darkness", shadow_darkness)
	_grass_material.set_shader_parameter("rim_strength", rim_strength)
	_grass_material.set_shader_parameter("ambient_color", ambient_color)
	_grass_material.set_shader_parameter("ambient_energy", ambient_energy)
	if _outline_material != null:
		_outline_material.set_shader_parameter("outline_color", outline_color)
		_outline_material.set_shader_parameter("outline_width", outline_width)
		_outline_material.set_shader_parameter("top_outline_scale", top_outline_scale)
		_outline_material.set_shader_parameter("bottom_outline_scale", bottom_outline_scale)
	if is_instance_valid(_model_root):
		_apply_material_recursive(_model_root)


func _apply_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface_index, _grass_material)
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in node.get_children():
		_apply_material_recursive(child)
