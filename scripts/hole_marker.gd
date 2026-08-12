@tool
class_name HoleMarker
extends Node3D

# 1칸 크기의 탈출구. 배치는 장애물 마커와 완전히 같은 방식이다.
# LevelManager/LayoutHoles 아래에 두고 grid_pos 만 지정한다.
#
# 마커는 아무것도 그리지 않는다. 실제로 보이는 것은 LevelManager 가 이 칸에 만드는
# 캣홀 비주얼이며 에디터에서도 같은 것이 보인다. 마커가 따로 상자를 그리면 그 캣홀
# 위에 정체불명의 반투명 사각형이 겹쳐 보인다.

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


func _ready() -> void:
	if Engine.is_editor_hint():
		refresh_editor_preview()


# 노드 자체를 자기 칸으로 옮겨 둔다. 에디터에서 마커를 골랐을 때 기즈모가 엉뚱한 곳에
# 있지 않게 하려는 것이다.
func refresh_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return

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

	call_deferred("refresh_editor_preview")
	var manager := _find_level_manager()
	if manager != null:
		manager.request_preview_refresh()
