class_name DragController
extends Node

signal input_received

# 1_움직임고찰.md 2절. 두 끝의 로직은 완전히 동일하고, 잡은 쪽이 리드가 된다.

# 끝 셀 중심에서 이 거리 안이면 잡힌다. 드래그 실패를 줄이려고 넉넉하게 둔다.
@export_range(0.5, 3.0, 0.1) var grab_radius_cells: float = 1.2
# 막힌 상태에서 손가락이 리드 셀에서 이만큼 멀어지면 조용히 터치를 끝낸다.
@export_range(1, 6, 1) var release_distance_cells: int = 5

const MOUSE_POINTER := -1

var level_manager: LevelManager

var _cat: CatEntity = null
var _pointer_index := 0
var _has_pointer := false
# 잡는 순간 포인터가 끝 셀 중심에서 빗겨 있던 양. 이후 좌표에서 계속 빼 준다.
var _grab_offset := Vector3.ZERO
var _pointer_cell := Vector2i.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	# release 이벤트에만 의존하면 입력이 영구 고착된다. 포커스 상실도 릴리즈로 본다.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position)
		else:
			_release_pointer(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_move(drag.index, drag.position)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_press(MOUSE_POINTER, button.position)
		else:
			_release_pointer(MOUSE_POINTER)
	elif event is InputEventMouseMotion:
		_move(MOUSE_POINTER, (event as InputEventMouseMotion).position)


func _process(_delta: float) -> void:
	if not _has_pointer or _cat == null:
		return
	# 구멍에 빨려 들어간 고양이는 곧 사라진다. 참조를 붙들고 있으면 해제된 객체를 만진다.
	if not is_instance_valid(_cat) or _cat.is_absorbing():
		_release()
		return
	if not _cat.is_blocked():
		return
	# 막힌 방향으로 계속 끌어 손가락이 5칸 이상 벌어지면 별도 알림 없이 종료한다.
	var lead: Vector2i = _cat.get_lead_cell()
	var gap: int = maxi(absi(_pointer_cell.x - lead.x), absi(_pointer_cell.y - lead.y))
	if gap >= release_distance_cells:
		_release()


func _press(pointer_index: int, screen_position: Vector2) -> void:
	# 이미 잡고 있으면 새 포인터를 받지 않는다. 터치가 끝나야 새 입력을 받는다.
	if _has_pointer or level_manager == null:
		return
	var point: Variant = level_manager.screen_to_board_point(screen_position)
	if point == null:
		return
	var board_point: Vector3 = point

	var best_cat: CatEntity = null
	var best_cell := Vector2i.ZERO
	var best_distance := grab_radius_cells * level_manager.fitted_tile_size()
	for cat in level_manager.get_cats():
		if cat.is_absorbing():
			continue
		for end_cell in cat.get_end_cells():
			var center: Vector3 = level_manager.grid_to_world(end_cell, level_manager.cat_world_y)
			var distance: float = Vector2(center.x - board_point.x, center.z - board_point.z).length()
			if distance <= best_distance:
				best_distance = distance
				best_cat = cat
				best_cell = end_cell
	if best_cat == null:
		return

	input_received.emit()
	_cat = best_cat
	_pointer_index = pointer_index
	_has_pointer = true
	_pointer_cell = best_cell
	var grabbed_center: Vector3 = level_manager.grid_to_world(best_cell, level_manager.cat_world_y)
	_grab_offset = board_point - grabbed_center
	_grab_offset.y = 0.0
	_cat.begin_drag(best_cell)


func _move(pointer_index: int, screen_position: Vector2) -> void:
	if not _has_pointer or pointer_index != _pointer_index or _cat == null:
		return
	if not is_instance_valid(_cat) or _cat.is_absorbing():
		_release()
		return
	var point: Variant = level_manager.screen_to_board_point(screen_position)
	if point == null:
		return
	var corrected: Vector3 = (point as Vector3) - _grab_offset
	var cell: Variant = level_manager.board_point_to_grid_cell(corrected)
	if cell == null:
		return
	_pointer_cell = cell
	_cat.request_path_to(_pointer_cell)


func _release_pointer(pointer_index: int) -> void:
	if _has_pointer and pointer_index == _pointer_index:
		_release()


# 손을 떼도 큐는 남는다. 잔여 경로를 완주한 뒤 멈춘다.
func _release() -> void:
	_cat = null
	_has_pointer = false
