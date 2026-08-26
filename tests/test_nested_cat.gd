extends Node

## 중첩고양이(3_기믹.md 2) 헤드리스 검증.
## 실행: Godot --headless res://tests/test_nested_cat.tscn
## (--script 모드는 UiBridge 오토로드가 등록되지 않아 씬 실행으로 돌린다)
##  1) 겉껍질 흡입 시작 순간 안쪽 고양이가 같은 칸에 얇게 실체화되는지
##  2) 겉껍질이 사라진 뒤에도 안쪽 고양이가 남아 클리어가 나지 않는지
##  3) 원복(굵기 0 수렴)이 실제로 일어나는지

var _frames := 0
var _manager: LevelManager
var _outer: CatEntity
var _inner: CatEntity
var _outer_cells: Array[Vector2i] = []
var _spawn_checked := false
var _cleared := false

func _ready() -> void:
	var scene := load("res://scenes/main_scene.tscn") as PackedScene
	add_child(scene.instantiate())


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 20:
		return
	if _frames == 20:
		_start()
		return
	if _frames > 900:
		push_error("FAIL: 900프레임 안에 끝나지 않음")
		get_tree().quit(1)
		return

	if not _spawn_checked:
		_check_spawn()
		return

	# 겉껍질이 사라질 때까지 기다렸다가 안쪽 고양이 상태를 본다.
	if is_instance_valid(_outer):
		return
	assert(not _cleared, "FAIL: 안쪽 고양이가 남았는데 레벨 클리어가 남")
	assert(is_instance_valid(_inner), "FAIL: 안쪽 고양이가 사라짐")
	assert(_manager.get_cats().has(_inner), "FAIL: 안쪽 고양이가 _cats 에 없음")
	# 원복 트윈이 끝날 시간을 준 뒤 굵기 확인.
	if _frames < 500:
		return
	assert(_inner._nest_shrink < 0.0005, "FAIL: 원복 안 됨 shrink=%f" % _inner._nest_shrink)
	assert(_inner.color_id == 1 and _inner.nested_color_ids == ([2] as Array[int]),
		"FAIL: 안쪽 색 전달 오류")
	print("PASS: nested cat spawn/occupancy/reveal")
	get_tree().quit(0)


func _start() -> void:
	_manager = _find_level_manager(self)
	assert(_manager != null, "FAIL: LevelManager 없음")
	_manager.level_cleared.connect(func() -> void: _cleared = true)
	var cats: Array = _manager.get_cats()
	assert(not cats.is_empty(), "FAIL: 고양이 없음")
	_outer = cats[0]
	# 3중첩으로 만든다: 겉(원래 색) + 안쪽 1, 2.
	_outer.nested_color_ids = [1, 2] as Array[int]
	_outer_cells = (_outer.body_cells as Array[Vector2i]).duplicate()
	# 겉껍질 색과 짝인 잠기지 않은 구멍을 찾아 강제로 빼낸다.
	var hole := _find_pair_hole(_outer.color_id)
	assert(hole != Vector2i(-9999, -9999), "FAIL: 짝 구멍 없음")
	assert(_outer.clear_with_item(hole), "FAIL: 흡입 시작 실패")


func _check_spawn() -> void:
	_spawn_checked = true
	# 흡입 시작 프레임에 안쪽 고양이가 이미 등록되어 있어야 한다.
	for cat in _manager.get_cats():
		if cat != _outer and cat.color_id == 1:
			_inner = cat
	assert(_inner != null, "FAIL: 안쪽 고양이가 스폰되지 않음")
	assert(_inner._nest_shrink > 0.0, "FAIL: 안쪽 고양이가 얇은 상태가 아님")
	assert(_inner.body_cells == _outer_cells, "FAIL: 안쪽 고양이 자리가 다름")
	for cell in _outer_cells:
		if not _manager.is_hole(cell):
			assert(_manager._get_cell_ref(cell) == _inner, "FAIL: 점유가 안쪽 고양이가 아님 %s" % cell)


func _find_pair_hole(color_id: int) -> Vector2i:
	for index in _manager._hole_cells.size():
		var cell: Vector2i = _manager._hole_cells[index]
		if _manager.is_hole_locked(cell):
			continue
		if _manager.color_ids_pair(color_id, _manager._hole_color_ids[index]):
			return cell
	return Vector2i(-9999, -9999)


func _find_level_manager(node: Node) -> LevelManager:
	if node is LevelManager:
		return node
	for child in node.get_children():
		var found := _find_level_manager(child)
		if found != null:
			return found
	return null
