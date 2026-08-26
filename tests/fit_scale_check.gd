extends Node

# 판 축소가 **정비율**인지, 그리고 축소된 판에서 타일·장애물·구멍·고양이가 여전히 칸 중심에
# 맞는지 확인한다. `LevelManager` 가 오토로드(`UiBridge`)를 참조하므로 `--script` 가 아니라
# **씬으로** 띄워야 컴파일된다.
#
#   /Applications/Godot.app/Contents/MacOS/Godot --headless res://tests/fit_scale_check.tscn

# 가로 9칸(기준 7칸 초과)인 스테이지. 축소가 실제로 걸리는 판이어야 배치를 볼 수 있다.
const WIDE_STAGE := "res://resources/levels/stage_057.json"

var _failures: Array[String] = []


func _ready() -> void:
	_check_ratio()
	await _check_board_layout()
	for line in _failures:
		printerr("[축소 검사] ", line)
	if _failures.is_empty():
		print("[축소 검사] 통과")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


# 배율 자체. 가로·세로 중 더 센 쪽 하나만 쓰고, 기준 이하는 손대지 않는다.
func _check_ratio() -> void:
	var lm := LevelManager.new()
	lm.tile_size = 2.0
	var cases := [
		[Vector2i(7, 9), 2.0],                  # 기준 이하 — 손대지 않는다
		[Vector2i(7, 10), 2.0],
		[Vector2i(8, 10), 2.0 * 7.0 / 8.0],     # 가로만 초과
		[Vector2i(9, 10), 2.0 * 7.0 / 9.0],
		[Vector2i(7, 11), 2.0 * 10.0 / 11.0],   # 세로만 초과
		[Vector2i(9, 11), 2.0 * 7.0 / 9.0],     # 둘 다 초과 — 더 센 쪽 하나만
	]
	for case in cases:
		lm.grid_size = case[0]
		var got: float = lm.fitted_tile_size()
		_expect(
			absf(got - float(case[1])) < 1e-6,
			"%s -> %f (기대 %f)" % [case[0], got, case[1]]
		)
	lm.free()


# 실제 판. 축소된 그리드에서 눈에 보이는 노드들이 칸 중심·칸 간격과 어긋나지 않아야 한다.
func _check_board_layout() -> void:
	var scene: Node = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	add_child(scene)
	# 물리·에셋 _ready 가 끝나고 보드가 다 세워질 때까지 기다린다.
	for _i in range(15):
		await get_tree().process_frame

	var manager: LevelManager = scene.get_node("LevelManager")
	LevelLayoutWriter.apply_to_manager(manager, LevelLayoutWriter.load_json(WIDE_STAGE))
	for _i in range(15):
		await get_tree().process_frame

	var tile: float = manager.fitted_tile_size()
	var ratio: float = manager.fit_scale()
	_expect(manager.grid_size.x > 7, "검사 스테이지가 기준(7칸)을 넘지 않는다: %s" % [manager.grid_size])
	_expect(ratio < 1.0, "축소가 걸리지 않았다: %f" % ratio)

	# 1) 칸 간격이 축소된 타일 한 변과 같다.
	var span: float = (
		manager.grid_to_world(Vector2i(1, 0)) - manager.grid_to_world(Vector2i.ZERO)
	).length()
	_expect(absf(span - tile) < 1e-5, "칸 간격 %f != 타일 %f" % [span, tile])

	# 2) 눈에 보이는 노드가 전부 같은 배율로, 축(x/y/z) 구분 없이 줄어야 한다.
	for root_name in ["TileVisuals", "ObstacleVisuals"]:
		var group: Node = manager.get_node_or_null(root_name)
		if group == null:
			continue
		for child in group.get_children():
			var node := child as Node3D
			# 꽃·나무 장식은 판 밖 연출이라 칸 크기와 무관하다. 칸에 놓이는 것만 본다.
			if node == null or not (
				node.name.begins_with("Tile_") or node.name.begins_with("Obstacle_")
			):
				continue
			var s: Vector3 = node.scale
			_expect(
				absf(s.x - s.y) < 1e-5 and absf(s.y - s.z) < 1e-5,
				"%s 가 비정비율로 스케일됐다: %s" % [node.name, s]
			)
			_expect(absf(s.x - ratio) < 1e-5, "%s 배율 %f != %f" % [node.name, s.x, ratio])

	# 3) 장애물·구멍·고양이가 자기 칸 중심(수평)에 있어야 한다.
	for cell in manager.get_obstacle_cells():
		_check_on_cell(manager, manager.get_node("ObstacleVisuals").get_node_or_null(
			"Obstacle_%d_%d" % [cell.x, cell.y]
		), cell, "장애물")
	for cell in manager.get_hole_cells():
		_check_on_cell(manager, manager.get_node("HoleVisuals").get_node_or_null(
			"CatHole_%d_%d" % [cell.x, cell.y]
		), cell, "구멍")
	for cat in manager.get_cats():
		_expect(
			manager.board_point_to_grid_cell(cat.position) == cat.get_lead_cell()
			or manager.board_point_to_grid_cell(cat.position) == cat.get_head_cell(),
			"고양이가 자기 칸 밖이다: %s vs %s" % [
				manager.board_point_to_grid_cell(cat.position), cat.get_head_cell()
			]
		)


func _check_on_cell(manager: LevelManager, node: Node, cell: Vector2i, label: String) -> void:
	var node3d := node as Node3D
	if node3d == null:
		_failures.append("%s 비주얼이 없다: %s" % [label, cell])
		return
	var want: Vector3 = manager.grid_to_world(cell)
	var got: Vector3 = node3d.position
	_expect(
		absf(got.x - want.x) < 1e-4 and absf(got.z - want.z) < 1e-4,
		"%s %s 가 칸 중심에서 벗어났다: %s != %s" % [label, cell, got, want]
	)
