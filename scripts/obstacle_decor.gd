@tool
class_name ObstacleDecor
extends Node3D

## Visual wrapper for a single generated obstacle tile. Edit the exported
## properties in scenes/obstacle_tile_1x1.tscn to adjust every placed block.

const MODEL_SCENE_PATH := "res://water_yang/obstacle_tile_1x1.fbx"
const OBSTACLE_MATERIAL_PATH := "res://resources/obstacle_material.tres"
const DEFAULT_VISUAL_HEIGHT := 0.55

@export_group("Model")
@export_range(0.01, 20.0, 0.01) var model_scale := 1.0:
	set(value):
		model_scale = value
		_apply_model_scale()

@export_range(0.8, 1.4, 0.01) var footprint_scale := 1.0:
	set(value):
		footprint_scale = value
		_apply_model_scale()

@export_range(0.1, 1.2, 0.01) var visual_height := DEFAULT_VISUAL_HEIGHT:
	set(value):
		visual_height = maxf(value, 0.01)
		_apply_model_scale()

@export var cast_shadow := true:
	set(value):
		cast_shadow = value
		_apply_material_style()

@export_group("Textures")
@export var primary_texture: Texture2D = preload("res://water_yang/obstacle1_1.jpg"):
	set(value):
		primary_texture = value
		_apply_material_style()

@export var secondary_texture: Texture2D = preload("res://water_yang/obstacle1_2.jpg"):
	set(value):
		secondary_texture = value
		_apply_material_style()

@export var use_checker_texture_variation := true:
	set(value):
		use_checker_texture_variation = value
		_apply_material_style()

@export var preview_secondary_texture := false:
	set(value):
		preview_secondary_texture = value
		_apply_material_style()

@export var use_level_color_tint := false:
	set(value):
		use_level_color_tint = value
		_apply_material_style()

@export var line_art_texture: Texture2D:
	set(value):
		line_art_texture = value
		_apply_material_style()

@export var secondary_line_art_texture: Texture2D:
	set(value):
		secondary_line_art_texture = value
		_apply_material_style()

@export var tint_exclusion_mask: Texture2D:
	set(value):
		tint_exclusion_mask = value
		_apply_material_style()

@export var line_art_eye_mask: Texture2D:
	set(value):
		line_art_eye_mask = value
		_apply_material_style()

@export_group("Material")
@export_color_no_alpha var tint_color: Color = Color.WHITE:
	set(value):
		tint_color = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var tint_exclusion_enabled := 0.0:
	set(value):
		tint_exclusion_enabled = value
		_apply_material_style()

@export_group("Line Art")
@export_range(0.0, 1.0, 0.01) var line_art_enabled := 1.0:
	set(value):
		line_art_enabled = value
		_apply_material_style()

@export var line_art_color := Color(0.32, 0.24, 0.20, 1.0):
	set(value):
		line_art_color = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var line_art_strength := 0.82:
	set(value):
		line_art_strength = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var line_art_eyes_hidden := 0.0:
	set(value):
		line_art_eyes_hidden = value
		_apply_material_style()

@export_group("UV")
@export var uv_tiling := Vector2.ONE:
	set(value):
		uv_tiling = value
		_apply_material_style()

@export var uv_offset := Vector2.ZERO:
	set(value):
		uv_offset = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var tile_uv_min_u := 0.0:
	set(value):
		tile_uv_min_u = value
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

@export_range(0.5, 4.0, 0.05) var shadow_receive_strength: float = 1.0:
	set(value):
		shadow_receive_strength = value
		_apply_material_style()

@export_range(0.0, 1.0, 0.01) var rim_strength := 0.24:
	set(value):
		rim_strength = value
		_apply_material_style()

@export_group("Outline")
@export var outline_color := Color(0.18, 0.09, 0.06, 1.0):
	set(value):
		outline_color = value
		_apply_material_style()

@export_range(0.001, 0.08, 0.001) var outline_width := 0.006:
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

@export_group("Sink Clip")
@export_range(0.0, 1.0, 0.01) var sink_clip_enabled := 0.0:
	set(value):
		sink_clip_enabled = value
		_apply_material_style()

@export var sink_clip_plane_y := 0.0:
	set(value):
		sink_clip_plane_y = value
		_apply_material_style()

@export_range(0.01, 4.0, 0.01) var sink_clip_span := 1.0:
	set(value):
		sink_clip_span = value
		_apply_material_style()

var _model_root: Node3D
var _obstacle_material: ShaderMaterial
var _outline_material: ShaderMaterial
var _use_secondary_texture := false
var _level_tint_color := Color.WHITE


func _ready() -> void:
	_ensure_model()
	_apply_model_scale()
	_apply_material_style()


func apply_cell_style(
	cell: Vector2i,
	cell_color: Color = Color.WHITE,
	height: float = DEFAULT_VISUAL_HEIGHT
) -> void:
	_use_secondary_texture = use_checker_texture_variation and ((cell.x + cell.y) % 2 != 0)
	_level_tint_color = cell_color
	visual_height = maxf(height, 0.01)
	_apply_model_scale()
	_apply_material_style()


func _ensure_model() -> void:
	if is_instance_valid(_model_root):
		return

	_model_root = get_node_or_null("ObstacleModel") as Node3D
	if _model_root != null:
		_model_root.visible = false
		_build_materials()
		_apply_material_style()
		return

	var packed_scene := load(MODEL_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("ObstacleDecor could not load %s" % MODEL_SCENE_PATH)
		return

	_model_root = packed_scene.instantiate() as Node3D
	if _model_root == null:
		push_error("ObstacleDecor model root must be Node3D")
		return

	_model_root.name = "ObstacleModel"
	add_child(_model_root)
	_model_root.visible = false
	_build_materials()
	_apply_material_style()


func _build_materials() -> void:
	var source := load(OBSTACLE_MATERIAL_PATH) as ShaderMaterial
	if source == null:
		push_error("ObstacleDecor could not load %s" % OBSTACLE_MATERIAL_PATH)
		return
	_obstacle_material = source.duplicate(true) as ShaderMaterial
	_outline_material = _obstacle_material.next_pass as ShaderMaterial


func _apply_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and _obstacle_material != null:
			for surface_index in mesh_instance.mesh.get_surface_count():
				mesh_instance.set_surface_override_material(surface_index, _obstacle_material)
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in node.get_children():
		_apply_material_recursive(child)


func _apply_model_scale() -> void:
	if is_instance_valid(_model_root):
		var height_scale := visual_height / DEFAULT_VISUAL_HEIGHT
		_model_root.scale = Vector3(
			model_scale * footprint_scale,
			model_scale * height_scale,
			model_scale * footprint_scale
		)


func _apply_material_style() -> void:
	if _obstacle_material == null:
		call_deferred("_apply_material_style")
		return

	var active_texture := _get_active_texture()
	var active_line_art_texture := _get_active_line_art_texture()
	var final_tint := tint_color
	if use_level_color_tint:
		final_tint *= _level_tint_color

	_obstacle_material.set_shader_parameter("albedo_tex", active_texture)
	_obstacle_material.set_shader_parameter("line_art_tex", active_line_art_texture)
	_obstacle_material.set_shader_parameter("tint_exclusion_mask", tint_exclusion_mask)
	_obstacle_material.set_shader_parameter("line_art_eye_mask", line_art_eye_mask)
	_obstacle_material.set_shader_parameter("line_art_enabled", line_art_enabled)
	_obstacle_material.set_shader_parameter("line_art_color", line_art_color)
	_obstacle_material.set_shader_parameter("line_art_strength", line_art_strength)
	_obstacle_material.set_shader_parameter("line_art_eyes_hidden", line_art_eyes_hidden)
	_obstacle_material.set_shader_parameter(
		"tint_exclusion_enabled",
		tint_exclusion_enabled if tint_exclusion_mask != null else 0.0
	)
	_obstacle_material.set_shader_parameter("tint_color", final_tint)
	_obstacle_material.set_shader_parameter("shadow_steps", toon_steps)
	_obstacle_material.set_shader_parameter("shadow_darkness", shadow_darkness)
	_obstacle_material.set_shader_parameter("shadow_receive_strength", shadow_receive_strength)
	_obstacle_material.set_shader_parameter("rim_strength", rim_strength)
	_obstacle_material.set_shader_parameter("uv_tiling", uv_tiling)
	_obstacle_material.set_shader_parameter("uv_offset", uv_offset)
	_obstacle_material.set_shader_parameter("tile_uv_min_u", tile_uv_min_u)
	_obstacle_material.set_shader_parameter("sink_clip_enabled", sink_clip_enabled)
	_obstacle_material.set_shader_parameter("sink_clip_plane_y", sink_clip_plane_y)
	_obstacle_material.set_shader_parameter("sink_clip_span", sink_clip_span)
	if _outline_material != null:
		_outline_material.set_shader_parameter("line_art_enabled", line_art_enabled)
		_outline_material.set_shader_parameter("line_art_color", line_art_color)
		_outline_material.set_shader_parameter("line_art_strength", line_art_strength)
		_outline_material.set_shader_parameter("outline_color", outline_color)
		_outline_material.set_shader_parameter("outline_width", outline_width)
		_outline_material.set_shader_parameter("top_outline_scale", top_outline_scale)
		_outline_material.set_shader_parameter("bottom_outline_scale", bottom_outline_scale)
		_outline_material.set_shader_parameter("sink_clip_enabled", sink_clip_enabled)
		_outline_material.set_shader_parameter("sink_clip_plane_y", sink_clip_plane_y)
		_outline_material.set_shader_parameter("sink_clip_span", sink_clip_span)
	if is_instance_valid(_model_root):
		_apply_material_recursive(_model_root)
		_model_root.visible = true


func _get_active_texture() -> Texture2D:
	if _use_secondary_texture or preview_secondary_texture:
		if secondary_texture != null:
			return secondary_texture
	return primary_texture


func _get_active_line_art_texture() -> Texture2D:
	if _use_secondary_texture or preview_secondary_texture:
		if secondary_line_art_texture != null:
			return secondary_line_art_texture
	return line_art_texture
