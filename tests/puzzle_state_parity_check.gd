extends SceneTree

# `PuzzleState` 가 실제 게임 규칙과 어긋나지 않는지 대조한다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/puzzle_state_parity_check.gd
#
# **계산한 값과 실제가 어긋나는 것이 이 프로젝트의 단골 실패 모드다.** 생성기와 솔버는
# 노드 없는 모델 위에서만 도는데, 그 모델이 `CatEntity` / `LevelManager` 와 조금이라도
# 다르면 "생성기는 풀린다는데 게임에서는 안 풀린다"가 된다. 그래서 두 구현의 판정을
# 보드 전 칸에 대해 직접 비교한다.

const CAT_SCRIPT_PATH := "res://scripts/cat_entity.gd"

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
	_check_blocking_parity(manager)
	_check_adjacent_hole_parity(manager)
	_check_move_set_parity(manager)
	_check_absorption_parity(manager)
	_check_bent_body_parity(manager)
	_report()
	return true


# `can_enter()` 와 `is_cell_blocked_for()` 를 보드 전 칸에서 비교한다.
func _check_blocking_parity(manager: LevelManager) -> void:
	var cat: CatEntity = _fresh_cat(manager, [Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7)])
	var state: PuzzleState = _mirror(manager)
	var mismatches: int = 0
	var checked: int = 0
	for y in range(-1, manager.grid_size.y + 1):
		for x in range(-1, manager.grid_size.x + 1):
			var cell := Vector2i(x, y)
			checked += 1
			if cat.can_enter(cell) != state.can_enter(cat_id_of(cat), cell):
				mismatches += 1
				if mismatches <= 5:
					_failures.append(
						"can_enter 불일치 %s: 실제 %s, 모델 %s"
						% [cell, cat.can_enter(cell), state.can_enter(cat_id_of(cat), cell)]
					)
			if manager.is_cell_blocked_for(cat, cell) != state.is_blocked_for(cat_id_of(cat), cell):
				mismatches += 1
				if mismatches <= 5:
					_failures.append("is_cell_blocked_for 불일치 %s" % [cell])
	_expect(mismatches == 0, "칸 판정이 %d곳 어긋났다" % mismatches)
	print("[대조] 칸 판정 %d칸 비교, 불일치 %d" % [checked, mismatches])


# 색 짝 인접 조회. 대각선이 걸리지 않는 것과 와일드카드까지 같은지 본다.
func _check_adjacent_hole_parity(manager: LevelManager) -> void:
	var state: PuzzleState = _mirror(manager)
	var mismatches: int = 0
	for y in manager.grid_size.y:
		for x in manager.grid_size.x:
			var cell := Vector2i(x, y)
			for color_id in [-1, 0, 1, 2, 3]:
				var actual: Variant = manager.adjacent_hole(cell, color_id)
				var mirrored: Variant = state.adjacent_paired_hole(cell, color_id)
				if actual != mirrored:
					mismatches += 1
					if mismatches <= 5:
						_failures.append(
							"adjacent_hole 불일치 %s 색 %d: 실제 %s, 모델 %s"
							% [cell, color_id, actual, mirrored]
						)
	_expect(mismatches == 0, "인접 구멍 조회가 %d곳 어긋났다" % mismatches)
	print("[대조] 인접 구멍 조회 불일치 %d" % mismatches)


# 원자 이동 집합이 같은지. 모델은 "두 끝 중 하나를 인접한 빈 칸으로"만 낸다.
func _check_move_set_parity(manager: LevelManager) -> void:
	var bodies: Array = [
		[Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7)],
		[Vector2i(2, 5), Vector2i(3, 5), Vector2i(3, 6)],
		[Vector2i(0, 5), Vector2i(0, 6), Vector2i(1, 6), Vector2i(1, 5)],
	]
	for body in bodies:
		var typed: Array[Vector2i] = []
		typed.assign(body)
		var cat: CatEntity = _fresh_cat(manager, typed)
		var state: PuzzleState = _mirror(manager)
		var cat_id: int = cat_id_of(cat)

		var expected: Dictionary = {}
		for end_cell in [cat.body_cells[0], cat.body_cells[cat.body_cells.size() - 1]]:
			for dir in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				if cat.can_enter(end_cell + dir):
					expected["%s>%s" % [end_cell, end_cell + dir]] = true

		var produced: Dictionary = {}
		for move in state.moves_for(cat_id):
			produced["%s>%s" % [move["from_end_cell"], move["to_cell"]]] = true

		_expect(
			expected.size() == produced.size(),
			"몸 %s 의 이동 개수가 다르다: 실제 %d, 모델 %d" % [typed, expected.size(), produced.size()]
		)
		for key in expected:
			_expect(produced.has(key), "몸 %s: 모델이 %s 를 빠뜨렸다" % [typed, key])
		for key in produced:
			_expect(expected.has(key), "몸 %s: 모델이 %s 를 더 냈다" % [typed, key])
	print("[대조] 이동 집합 %d개 배치 비교 완료" % bodies.size())


# 흡입이 같은 순간에 걸리는지. 모델이 흡입을 강제로 처리하는 것이 역설계 가드의 근거다.
func _check_absorption_parity(manager: LevelManager) -> void:
	var hole: Vector2i = manager.get_hole_cells()[0]
	var hole_color: int = manager.get_hole_color_id(hole)
	# 구멍에서 두 칸 떨어진 자리에 세우고 한 칸 다가간다.
	var body: Array[Vector2i] = [
		hole + Vector2i(0, 2), hole + Vector2i(0, 3), hole + Vector2i(0, 4)
	]
	var cat: CatEntity = _fresh_cat(manager, body, hole_color)
	var state: PuzzleState = _mirror(manager)
	var cat_id: int = cat_id_of(cat)

	_expect(not cat.is_absorbing(), "실제: 시작부터 흡입됐다")
	_expect(
		state.cats_touching_paired_hole().is_empty(),
		"모델: 시작부터 짝 구멍에 인접으로 잡혔다"
	)

	# 아직 두 칸 남았으므로 흡입되지 않아야 한다.
	var far_move := {
		"cat_id": cat_id,
		"from_end_cell": body[body.size() - 1],
		"to_cell": body[body.size() - 1] + Vector2i(0, 1),
	}
	var far_result: Dictionary = state.clone().apply_move(far_move)
	_expect(not bool(far_result["absorbed"]), "모델: 멀어지는 이동에서 흡입이 걸렸다")

	# 구멍 옆칸으로 들어가면 양쪽 모두 흡입이다.
	cat.request_path_to(hole + Vector2i(0, 1))
	cat.advance(1.2 / cat.move_speed_cells)
	var near_result: Dictionary = state.apply_move({
		"cat_id": cat_id,
		"from_end_cell": body[0],
		"to_cell": hole + Vector2i(0, 1),
	})
	_expect(cat.is_absorbing(), "실제: 구멍 옆칸에 들어섰는데 흡입이 없다")
	_expect(bool(near_result["absorbed"]), "모델: 구멍 옆칸에 들어섰는데 흡입이 없다")
	_expect(state.is_solved(), "모델: 흡입된 고양이가 판에 남았다")
	_drain(cat)
	print("[대조] 흡입 시점 일치 (구멍 %s 색 %d)" % [hole, hole_color])


# 꺾인 시작 몸이 그대로 심어지는지. 생성기가 내는 자세가 이 형태다.
func _check_bent_body_parity(manager: LevelManager) -> void:
	var bent: Array[Vector2i] = [
		Vector2i(2, 6), Vector2i(3, 6), Vector2i(3, 7), Vector2i(4, 7)
	]
	var cat: CatEntity = _fresh_cat(manager, bent)
	_expect(cat.body_cells == bent, "꺾인 몸이 그대로 심어지지 않았다: %s" % [cat.body_cells])
	_expect(cat.grid_pos == bent[0], "grid_pos 가 리드 끝이 아니다: %s" % [cat.grid_pos])
	_expect(cat.initial_length == bent.size(), "initial_length 가 %d 다" % cat.initial_length)
	_expect(cat.facing_dir == bent[0] - bent[1], "facing_dir 이 %s 다" % [cat.facing_dir])
	var state: PuzzleState = _mirror(manager)
	_expect(
		state.body_of(cat_id_of(cat)) == bent,
		"모델이 읽은 몸이 다르다: %s" % [state.body_of(cat_id_of(cat))]
	)

	# 직선 폴백도 살아 있어야 한다. 기존 하네스와 손 배치가 이 경로를 쓴다.
	var straight: CatEntity = _fresh_cat(manager, [] as Array[Vector2i])
	straight.facing_name = "up"
	straight.initial_length = 3
	straight.grid_pos = Vector2i(3, 4)
	_expect(
		straight.body_cells == [Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6)],
		"직선 폴백이 깨졌다: %s" % [straight.body_cells]
	)
	print("[대조] 꺾인 몸 심기와 직선 폴백 모두 정상")


# ---------------------------------------------------------------- 하네스 도구

# 실제 보드 상태를 그대로 읽어 모델로 옮긴다. 이 변환이 대조의 기준선이다.
func _mirror(manager: LevelManager) -> PuzzleState:
	var state := PuzzleState.create(manager.grid_size)
	for cell in manager.get_hole_cells():
		state.add_hole(cell, manager.get_hole_color_id(cell))
	for child in manager.get_node("LayoutObstacles").get_children():
		if not child.has_method("get_cells"):
			continue
		for cell in child.call("get_cells"):
			if manager.is_inside_grid(cell):
				state.add_obstacle(cell)
	for cat in manager.get_cats():
		state.add_cat(cat_id_of(cat), cat.color_id, cat.body_cells)
	return state


func cat_id_of(cat: CatEntity) -> int:
	return cat.get_instance_id() % 100000


# 검사용 고양이를 새로 만든다. 기존 고양이는 정리한다.
func _fresh_cat(
	manager: LevelManager, body: Array[Vector2i], color_id: int = 0
) -> CatEntity:
	for existing in manager.get_cats().duplicate():
		manager.release_cat_cell(existing)
		manager._cats.erase(existing)
		existing.get_parent().remove_child(existing)
		existing.queue_free()

	var cat := CatEntity.new()
	cat.set_script(load(CAT_SCRIPT_PATH))
	cat.color_id = color_id
	if body.is_empty():
		cat.grid_pos = Vector2i(3, 4)
		cat.initial_length = 3
	else:
		cat.initial_body_cells = body
	manager.get_node("LayoutCats").add_child(cat)
	cat.initialize_runtime(manager)
	manager.update_cat_occupancy(cat)
	manager._cats.append(cat)
	cat.advance(0.0)
	return cat


func _drain(cat: CatEntity) -> void:
	var elapsed := 0.0
	while is_instance_valid(cat) and cat.is_absorbing() and elapsed < 3.0:
		cat.advance(1.0 / 120.0)
		elapsed += 1.0 / 120.0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("PARITY CHECK: PASS")
		return
	print("PARITY CHECK: FAIL (%d)" % _failures.size())
	for failure in _failures:
		print("  - ", failure)
