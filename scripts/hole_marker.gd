@tool
class_name HoleMarker
extends Node3D

# 1칸 크기의 구멍. 배치는 장애물 마커와 완전히 같은 방식이다.
# LevelManager/LayoutHoles 아래에 두고 grid_pos 만 지정한다.

@export var grid_pos: Vector2i = Vector2i.ZERO:
	set(value):
		grid_pos = value
		_request_editor_refresh()

# LevelManager.pair_colors 의 인덱스. 같은 color_id 를 가진 고양이만 이 구멍으로 빠진다.
# -1 은 아무 색이나 받는 와일드카드다.
@export_range(-1, 15, 1) var color_id: int = 0:
	set(value):
		color_id = value
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
	set_preview_color(manager.get_hole_rim_color(color_id))


func set_preview_visible(value: bool) -> void:
	if not Engine.is_editor_hint():
		return

	_ensure_marker_mesh()
	_marker_mesh.visible = value


func set_preview_color(color: Color) -> void:
	_ensure_marker_mesh()
	var material := _marker_mesh.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(color.r, color.g, color.b, 0.75)


func _ensure_marker_mesh() -> void:
	if _marker_mesh != null:
		return

	_marker_mesh = MeshInstance3D.new()
	_marker_mesh.name = "MarkerMesh"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(1.2, 0.3, 1.2)
	_marker_mesh.mesh = mesh

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.06, 0.07, 0.05, 0.75)
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
