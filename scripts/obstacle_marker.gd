@tool
class_name ObstacleMarker
extends Node3D

# 장애물 한 덩어리. `scenes/obstacle_block.tscn` 을 LevelManager/LayoutObstacles 아래에
# 떨어뜨리고 grid_pos 와 block_size 만 지정하면 된다. 1x1 이면 한 칸짜리 장애물이다.
#
# 게임에는 아무것도 그리지 않는다. 칸만 잠그고, 보이는 것은 나중에 들어올 장애물
# 에셋이 맡는다. 에디터에서는 배치를 볼 수 있어야 하므로 반투명 덩어리를 그린다.

@export var grid_pos: Vector2i = Vector2i.ZERO:
	set(value):
		grid_pos = value
		_request_editor_refresh()

# 이 마커가 덮는 칸 수. grid_pos 를 좌상단으로 삼아 +x, +y 방향으로 뻗는다.
@export var block_size: Vector2i = Vector2i.ONE:
	set(value):
		block_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_request_editor_refresh()

var _marker_mesh: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_ensure_marker_mesh()
		refresh_editor_preview()


# 이 마커가 잠그는 칸 전부. LevelManager 와 에디터 프리뷰가 같은 목록을 쓴다.
func get_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(block_size.y):
		for x in range(block_size.x):
			cells.append(grid_pos + Vector2i(x, y))
	return cells


func refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return

	_ensure_marker_mesh()
	_marker_mesh.visible = true
	var manager := _find_level_manager()
	if manager == null:
		return

	# 노드는 좌상단 칸에 두고, 프리뷰 메시만 덩어리 중앙으로 밀어 맞춘다.
	position = manager.grid_to_world(grid_pos, 0.15)
	var span := Vector3(
		float(block_size.x - 1) * manager.tile_size,
		0.0,
		float(block_size.y - 1) * manager.tile_size
	)
	_marker_mesh.position = span * 0.5
	var mesh := _marker_mesh.mesh as BoxMesh
	if mesh != null:
		mesh.size = Vector3(
			span.x + manager.tile_size * 0.6,
			0.3,
			span.z + manager.tile_size * 0.6
		)
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
