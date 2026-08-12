@tool
class_name ObstacleMarker
extends Node3D

# 장애물 한 덩어리. `scenes/obstacle_block.tscn` 을 LevelManager/LayoutObstacles 아래에
# 떨어뜨리고 grid_pos 와 block_size 만 지정하면 된다. 1x1 이면 한 칸짜리 장애물이다.
#
# 마커는 아무것도 그리지 않는다. 칸만 잠그고, 보이는 것은 `LevelManager` 가 그 칸에 만드는
# 장애물 덩어리이며 에디터에서도 같은 것이 보인다. 마커가 따로 상자를 그리면 그 덩어리 위에
# 정체불명의 반투명 사각형이 겹쳐 보인다(구멍 마커와 같은 이유다).

@export var grid_pos: Vector2i = Vector2i.ZERO:
	set(value):
		grid_pos = value
		_request_editor_refresh()

# 이 마커가 덮는 칸 수. grid_pos 를 좌상단으로 삼아 +x, +y 방향으로 뻗는다.
@export var block_size: Vector2i = Vector2i.ONE:
	set(value):
		block_size = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		_request_editor_refresh()


func _ready() -> void:
	if Engine.is_editor_hint():
		refresh_preview()


# 이 마커가 잠그는 칸 전부. LevelManager 와 에디터 프리뷰가 같은 목록을 쓴다.
func get_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(block_size.y):
		for x in range(block_size.x):
			cells.append(grid_pos + Vector2i(x, y))
	return cells


# 노드 자체를 자기 칸으로 옮겨 둔다. 에디터에서 마커를 골랐을 때 기즈모가 엉뚱한 곳에 있지
# 않게 하려는 것이다. 그리는 것은 없다.
func refresh_preview() -> void:
	var manager := _find_level_manager()
	if manager == null:
		return

	position = manager.grid_to_world(grid_pos, 0.0)


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

	call_deferred("refresh_preview")
	var manager := _find_level_manager()
	if manager != null:
		manager.request_preview_refresh()
