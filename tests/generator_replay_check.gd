extends SceneTree

# 생성한 레벨을 **실제 게임 코드로** 재생한다. 오토솔버 검증의 최종 근거다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/generator_replay_check.gd
#
# 생성기와 솔버는 노드 없는 `PuzzleState` 위에서만 돈다. 그 모델이 맞다는 것을 증명하는
# 유일한 방법은 기록된 풀이를 `CatEntity.begin_drag()` / `request_path_to()` / `advance()` 로
# 실제로 눌러 보고 전원이 흡입되는지 보는 것이다.
#
# 재생 규약: 움직일 끝이 뒤끝이면 `begin_drag(뒤끝)` 으로 리드를 넘긴 뒤 인접한 목표 칸을
# 가리킨다. **자기 몸을 가리키지 않으므로 후진 벽 슬라이드의 무작위성을 타지 않는다.**
# 그래서 재생이 결정적이다.

const REPLAY_SEEDS := [11, 2200066, 4400132]
const STEP_DELTA := 1.0 / 120.0
const STEP_GUARD := 600

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
	var generator := MapGenerator.new()
	for seed_value in REPLAY_SEEDS:
		_replay_one(manager, generator, seed_value)
	_report()
	return true


func _replay_one(manager: LevelManager, generator: MapGenerator, seed_value: int) -> void:
	var config := MapGenerator.default_config()
	config.base_seed = seed_value
	config.grid_size = manager.grid_size
	config.color_count = manager.pair_colors.size()
	var level: Dictionary = generator.generate(config)
	if not bool(level["ok"]):
		_failures.append("시드 %d 생성 실패: %s" % [seed_value, level["reason"]])
		return

	LevelLayoutWriter.apply_to_manager(manager, level)

	var label: String = "시드 %d" % int(level["seed"])
	var cats_root: Node = manager.get_node("LayoutCats")
	var expected_cats: int = (level["cats"] as Array).size()
	_expect(
		manager.get_cats().size() == expected_cats,
		"%s 씬에 고양이가 %d마리 올라갔다 (기대 %d)" % [label, manager.get_cats().size(), expected_cats]
	)

	# 심은 배치가 생성 결과와 같은지 먼저 본다. 여기서 어긋나면 재생은 볼 필요가 없다.
	for index in expected_cats:
		var cat: CatEntity = cats_root.get_node_or_null("Cat_%d" % index) as CatEntity
		if cat == null:
			_failures.append("%s Cat_%d 가 씬에 없다" % [label, index])
			return
		var expected_body: Array = level["cats"][index]["body_cells"]
		_expect(
			cat.body_cells == expected_body,
			"%s Cat_%d 의 몸이 다르다: 씬 %s, 생성 %s" % [label, index, cat.body_cells, expected_body]
		)
		_expect(
			cat.color_id == int(level["cats"][index]["color_id"]),
			"%s Cat_%d 의 색이 다르다" % [label, index]
		)
	# 시작부터 흡입되는 배치는 설계 오류다. 생성기가 막고 있지만 실제 코드로도 확인한다.
	for cat in manager.get_cats():
		_expect(not cat.is_absorbing(), "%s 시작부터 흡입된 고양이가 있다" % label)

	var cleared := [false]
	var connection: Callable = func(): cleared[0] = true
	manager.level_cleared.connect(connection)

	# 모델을 나란히 돌려 매 수마다 몸을 대조한다. 모델과 게임이 갈라지는 순간을 바로 잡는다.
	var model: PuzzleState = LevelLayoutWriter.to_puzzle_state(level)
	var move_index: int = 0
	for move in level["solution"]:
		move_index += 1
		var cat_id: int = int(move["cat_id"])
		var from_end_cell: Vector2i = move["from_end_cell"]
		var to_cell: Vector2i = move["to_cell"]
		var cat: CatEntity = cats_root.get_node_or_null("Cat_%d" % cat_id) as CatEntity
		if cat == null or not is_instance_valid(cat):
			_failures.append("%s %d번째 수: Cat_%d 가 이미 사라졌다" % [label, move_index, cat_id])
			break

		if not _push_one_step(cat, from_end_cell, to_cell):
			_failures.append(
				"%s %d번째 수 실패: Cat_%d 의 %s → %s (몸 %s, 막힘 %s)"
				% [label, move_index, cat_id, from_end_cell, to_cell, cat.body_cells, cat.is_blocked()]
			)
			break

		model.apply_move(move)

		# 흡입이 시작됐으면 완전히 사라질 때까지 진행시킨다. 그 뒤에야 다음 고양이 차례다.
		if is_instance_valid(cat) and cat.is_absorbing():
			_drain(cat)
		if not model.cats.has(cat_id):
			_expect(
				not is_instance_valid(cat) or not manager.get_cats().has(cat),
				"%s %d번째 수: 모델은 Cat_%d 를 내보냈는데 게임에는 남았다" % [label, move_index, cat_id]
			)
			continue

		_expect(
			is_instance_valid(cat), "%s %d번째 수: 모델에는 남았는데 게임에서 사라졌다" % [label, move_index]
		)
		if is_instance_valid(cat):
			# 리드를 반대쪽으로 잡으면 게임은 body_cells 를 뒤집는다. 같은 배치이므로 정규화해 본다.
			_expect(
				_same_body(cat.body_cells, model.body_of(cat_id)),
				"%s %d번째 수 후 몸이 갈라졌다: 게임 %s, 모델 %s"
				% [label, move_index, cat.body_cells, model.body_of(cat_id)]
			)

	_expect(model.is_solved(), "%s 모델 쪽 재생이 끝나지 않았다" % label)
	_expect(manager.get_cats().is_empty(), "%s 게임에 고양이 %d마리가 남았다" % [label, manager.get_cats().size()])
	_expect(cleared[0], "%s 전원이 나갔는데 level_cleared 가 없다" % label)
	manager.level_cleared.disconnect(connection)
	print(
		"[재생] %s: %d수를 실제 게임 코드로 재생해 %d마리 전원 탈출, 사슬깊이 %d"
		% [
			label,
			(level["solution"] as Array).size(),
			expected_cats,
			int(level["dependency"]["chain_depth"]),
		]
	)


# 한 수를 실제 입력 경로로 눌러 넣는다. 커밋될 때까지 `advance()` 를 돌린다.
func _push_one_step(cat: CatEntity, from_end_cell: Vector2i, to_cell: Vector2i) -> bool:
	# 움직일 끝이 뒤끝이면 리드를 그쪽으로 넘긴다. 앞끝이면 잔여 큐만 비운다.
	cat.begin_drag(from_end_cell)
	if cat.body_cells[0] != from_end_cell:
		return false
	cat.request_path_to(to_cell)
	if cat.is_blocked():
		return false

	for guard in STEP_GUARD:
		if not is_instance_valid(cat):
			return true
		if cat.body_cells[0] == to_cell:
			return true
		if cat.is_blocked():
			return false
		cat.advance(STEP_DELTA)
	return false


func _drain(cat: CatEntity) -> void:
	var elapsed := 0.0
	while is_instance_valid(cat) and cat.is_absorbing() and elapsed < 3.0:
		cat.advance(STEP_DELTA)
		elapsed += STEP_DELTA


# 뒤집힌 몸은 같은 배치다.
func _same_body(actual: Array[Vector2i], expected: Array[Vector2i]) -> bool:
	if actual == expected:
		return true
	var flipped: Array[Vector2i] = expected.duplicate()
	flipped.reverse()
	return actual == flipped


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("REPLAY CHECK: PASS")
		return
	print("REPLAY CHECK: FAIL (%d)" % _failures.size())
	for failure in _failures:
		print("  - ", failure)
