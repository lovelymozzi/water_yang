@tool
class_name ObstacleMarker
extends Node3D

@export var grid_pos: Vector2i = Vector2i.ZERO:
	set(value):
		grid_pos = value
		_request_editor_refresh()

var _marker_mesh: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_ensure_marker_mesh()
		refresh_editor_preview()


func refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return

	_ensure_marker_mesh()
	_marker_mesh.visible = true
	var manager := _find_level_manager()
	if manager == null:
		return

	position = manager.grid_to_world(grid_pos, 0.15)
	set_preview_color(manager.get_obstacle_color(grid_pos))


func set_preview_visible(value: bool) -> void:
	if not Engine.is_editor_hint():
		return

	_ensure_marker_mesh()
	_marker_mesh.visible = value


func set_preview_color(color: Color) -> void:
	_ensure_marker_mesh()
	var material := _marker_mesh.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(color.r, color.g, color.b, 0.65)


func _ensure_marker_mesh() -> void:
	if _marker_mesh != null:
		return

	_marker_mesh = MeshInstance3D.new()
	_marker_mesh.name = "MarkerMesh"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(1.2, 0.3, 1.2)
	_marker_mesh.mesh = mesh

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.84, 0.70, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mesh.material_override = material
	add_child(_marker_mesh)


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
