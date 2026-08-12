extends SceneTree

# 장애물 템플릿 회귀 검사. 렌더가 없으므로 셀 상태로만 본다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/obstacle_check.gd

const OBSTACLE_BLOCK_SCENE := "res://scenes/obstacle_block.tscn"

var _scene: Node
var _frames := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false

	var manager: LevelManager = _scene.get_node("LevelManager")
	_check_map_has_no_obstacles(manager)
	_check_single_cell_block(manager)
	_check_rect_block(manager)
	_check_block_is_visible(manager)
	_check_out_of_grid_is_ignored(manager)
	_report()
	return true


# 맵 자체에는 장애물이 없어야 한다. 템플릿만 있고 배치는 비어 있는 상태다.
func _check_map_has_no_obstacles(manager: LevelManager) -> void:
	_expect(
		manager.get_node("LayoutObstacles").get_child_count() == 0,
		"맵에 장애물 배치가 남아 있다: %d개" % manager.get_node("LayoutObstacles").get_child_count()
	)
	_expect(_obstacle_cells(manager).is_empty(), "맵에 잠긴 장애물 칸이 있다: %s" % [_obstacle_cells(manager)])
	print("[맵] 장애물 배치 0개, 잠긴 칸 0개")


func _check_single_cell_block(manager: LevelManager) -> void:
	_place_block(manager, Vector2i(3, 7), Vector2i.ONE)
	var cells: Array[Vector2i] = _obstacle_cells(manager)
	_expect(cells.size() == 1, "1x1 템플릿이 한 칸이 아니다: %d칸 %s" % [cells.size(), cells])
	_expect(cells.has(Vector2i(3, 7)), "1x1 템플릿이 지정한 칸을 잠그지 않았다: %s" % [cells])
	print("[템플릿] 1x1 이 %s 한 칸만 잠갔다" % [cells])


func _check_rect_block(manager: LevelManager) -> void:
	_place_block(manager, Vector2i(2, 4), Vector2i(3, 3))
	var cells: Array[Vector2i] = _obstacle_cells(manager)
	_expect(cells.size() == 9, "3x3 템플릿이 9칸이 아니다: %d칸 %s" % [cells.size(), cells])
	for y in range(4, 7):
		for x in range(2, 5):
			_expect(cells.has(Vector2i(x, y)), "3x3 안쪽 칸이 빠졌다: %s" % [Vector2i(x, y)])
	# 덩어리 바로 밖은 열려 있어야 한다. 안 그러면 우회 경로가 사라진다.
	for cell in [Vector2i(1, 5), Vector2i(5, 5), Vector2i(3, 3), Vector2i(3, 7)]:
		_expect(not cells.has(cell), "덩어리 밖 칸이 잠겼다: %s" % [cell])
	print("[템플릿] 3x3 이 (2,4) 부터 9칸을 잠갔다")


# 잠긴 칸은 반드시 보여야 한다. 안 보이면 플레이어가 못 움직이는 이유가 벽인지 버그인지
# 구분할 수 없다. 덩어리 하나가 여러 칸을 잠그더라도 비주얼은 칸마다 하나씩 만든다.
func _check_block_is_visible(manager: LevelManager) -> void:
	var cells: Array = _place_block(manager, Vector2i(2, 4), Vector2i(3, 3))
	var visuals: Node = manager.get_node("ObstacleVisuals")
	_expect(
		visuals.get_child_count() == cells.size(),
		"잠긴 칸 %d개인데 그려진 노드가 %d개다" % [cells.size(), visuals.get_child_count()]
	)
	for cell in cells:
		_expect(
			visuals.get_node_or_null("Obstacle_%d_%d" % [cell.x, cell.y]) != null,
			"잠긴 칸 %s 에 장애물 비주얼이 없다" % [cell]
		)
	print("[템플릿] 잠긴 칸 %d개가 모두 그려졌다" % cells.size())


func _check_out_of_grid_is_ignored(manager: LevelManager) -> void:
	# 보드 밖으로 걸친 덩어리는 안쪽 칸만 잠그고 조용히 잘린다.
	_place_block(manager, Vector2i(5, 7), Vector2i(4, 4))
	var cells: Array[Vector2i] = _obstacle_cells(manager)
	for cell in cells:
		_expect(manager.is_inside_grid(cell), "보드 밖 칸이 잠겼다: %s" % [cell])
	_expect(cells.size() == 4, "걸친 덩어리의 안쪽 칸 수가 다르다: %d %s" % [cells.size(), cells])
	print("[템플릿] 보드 밖으로 걸친 덩어리가 안쪽 %d칸만 잠갔다" % cells.size())


# 잠긴 칸 목록을 돌려준다. 배치 직후의 상태를 다시 조회할 일이 많다.
func _place_block(
	manager: LevelManager, cell: Vector2i, size: Vector2i
) -> Array[Vector2i]:
	var layout: Node = manager.get_node("LayoutObstacles")
	for existing in layout.get_children():
		layout.remove_child(existing)
		existing.queue_free()

	var block: Node3D = (load(OBSTACLE_BLOCK_SCENE) as PackedScene).instantiate() as Node3D
	block.set("grid_pos", cell)
	block.set("block_size", size)
	layout.add_child(block)
	# 배치를 바꿨으면 보드를 다시 만들어야 셀 상태가 반영된다.
	manager._rebuild_from_scene_layout()
	return _obstacle_cells(manager)


func _obstacle_cells(manager: LevelManager) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(manager.grid_size.y):
		for x in range(manager.grid_size.x):
			var cell := Vector2i(x, y)
			if manager._get_cell_state(cell) == LevelManager.CellState.OBSTACLE:
				cells.append(cell)
	return cells


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("OBSTACLE CHECK: PASS")
	else:
		print("OBSTACLE CHECK: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - %s" % failure)
	quit()
