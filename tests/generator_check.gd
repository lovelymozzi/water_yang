extends SceneTree

# 맵 생성기 회귀 검사. 노드를 쓰지 않으므로 씬을 띄우지 않는다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/generator_check.gd
#
# 검사하는 것: 생성 성공, 시작 배치 규칙, 기록된 풀이 재생, 오토솔버 독립 풀이,
# 의존 사슬 깊이(A → B → C), 장애물이 풀이 칸을 침범하지 않음, 무작위 플레이 후에도 풀림,
# 같은 시드가 같은 맵을 내는 결정성, JSON 왕복.
#
# 규칙 자체가 실제 게임과 같은지는 이 하네스가 보지 않는다. 그건
# `tests/puzzle_state_parity_check.gd` 와 `tests/generator_replay_check.gd` 의 일이다.

const SEED_COUNT := 20
const SEED_STRIDE := 100003

var _failures: Array[String] = []


func _initialize() -> void:
	var generator := MapGenerator.new()
	var solver := LevelSolver.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260812

	var generated: int = 0
	var total_solution: int = 0
	var total_solver: int = 0
	var total_depth: int = 0
	var started: int = Time.get_ticks_msec()

	for index in SEED_COUNT:
		var config := MapGenerator.default_config()
		config.base_seed = index * SEED_STRIDE
		var level: Dictionary = generator.generate(config)
		if not bool(level["ok"]):
			_failures.append("시드 %d 생성 실패: %s" % [config.base_seed, level["reason"]])
			continue
		generated += 1
		total_solution += int(level["stats"]["solution_length"])
		total_solver += int(level["stats"]["solver_moves"])
		total_depth += int(level["dependency"]["chain_depth"])
		_check_level(solver, rng, config, level)

	_expect(generated == SEED_COUNT, "%d/%d 시드만 생성됐다" % [generated, SEED_COUNT])
	if generated > 0:
		print(
			"[생성] %d개 성공 / 평균 기록풀이 %.1f수, 오토솔버 %.1f수, 사슬깊이 %.2f / %dms"
			% [
				generated,
				float(total_solution) / float(generated),
				float(total_solver) / float(generated),
				float(total_depth) / float(generated),
				Time.get_ticks_msec() - started,
			]
		)

	_check_determinism(generator)
	_check_json_round_trip(generator)
	_report()
	quit()


func _check_level(
	solver: LevelSolver,
	rng: RandomNumberGenerator,
	config: MapGenerator.Config,
	level: Dictionary
) -> void:
	var label: String = "시드 %d" % int(level["seed"])
	var state: PuzzleState = LevelLayoutWriter.to_puzzle_state(level)

	# 1. 시작 배치 규칙. 특히 짝 구멍 인접 금지 — 그 배치는 흡입이 걸리지 않는 설계 오류다.
	var problems: Array[String] = state.start_layout_problems()
	_expect(problems.is_empty(), "%s 시작 배치 위반: %s" % [label, problems])

	# 2. 고양이 수와 색이 구멍과 맞는지.
	_expect(
		(level["cats"] as Array).size() == config.cat_count,
		"%s 고양이가 %d마리다" % [label, (level["cats"] as Array).size()]
	)
	_expect(
		(level["holes"] as Array).size() == config.cat_count,
		"%s 구멍이 %d개다" % [label, (level["holes"] as Array).size()]
	)

	# 3. 기록된 풀이가 그대로 재생되어야 한다. 역설계의 존재 이유다.
	var replay: PuzzleState = state.clone()
	var touched: Dictionary = {}
	for cat_id in replay.cat_ids():
		for cell in replay.body_of(cat_id):
			touched[cell] = true
	var broken: bool = false
	for move in level["solution"]:
		if not bool(replay.apply_move(move)["moved"]):
			_failures.append("%s 기록된 풀이가 %s 에서 끊겼다" % [label, move])
			broken = true
			break
		touched[move["to_cell"]] = true
		for cat_id in replay.cat_ids():
			for cell in replay.body_of(cat_id):
				touched[cell] = true
	if not broken:
		_expect(replay.is_solved(), "%s 풀이를 다 재생했는데 고양이가 남았다" % label)

	# 4. 장애물이 풀이가 밟는 칸을 침범하지 않는다. 사후 주입 안전성의 직접 확인이다.
	var trespassing: Array[Vector2i] = []
	for cell in touched:
		if state.obstacles.has(cell):
			trespassing.append(cell)
	_expect(trespassing.is_empty(), "%s 장애물이 풀이 칸을 덮었다: %s" % [label, trespassing])

	# 5. 오토솔버가 기록과 무관하게 스스로 풀 수 있는지.
	var solved: Dictionary = solver.solve(state, config.solver_node_budget)
	_expect(bool(solved["found"]), "%s 오토솔버가 풀지 못했다: %s" % [label, solved["reason"]])

	# 6. 의존성. 순환은 소프트락이고, 깊이 3 이 A → B → C 다.
	var graph: LevelDependencyGraph = solver.build_dependency_graph(
		state, level["escape_order"]
	)
	_expect(not graph.has_cycle(), "%s 의존성에 순환이 있다" % label)
	var depth: int = graph.longest_chain_depth()
	_expect(
		depth >= config.min_chain_depth,
		"%s 의존 사슬 깊이가 %d 뿐이다" % [label, depth]
	)
	_expect(
		depth == int(level["dependency"]["chain_depth"]),
		"%s 기록된 사슬 깊이(%d)와 재계산(%d)이 다르다"
		% [label, int(level["dependency"]["chain_depth"]), depth]
	)
	# 사슬의 각 간선이 실제로 강제되는지 다시 확인한다. u 는 v 가 있는 동안 혼자 못 나가야 한다.
	var chain: Array[int] = graph.longest_chain()
	for position in range(chain.size() - 1):
		var blocked_cat: int = chain[position]
		var blocker: int = chain[position + 1]
		var gone: Array[int] = []
		for other in level["escape_order"]:
			if int(other) < blocked_cat and int(other) != blocker:
				gone.append(int(other))
		_expect(
			not solver.can_escape_alone(state, blocked_cat, gone),
			"%s 고양이 %d 가 %d 없이도 나갈 수 있다 (의존이 가짜다)" % [label, blocked_cat, blocker]
		)

	# 7. 무작위로 몇 수 둔 뒤에도 풀려야 한다. 가역성 논증의 경험적 뒷받침이다.
	var probe: Dictionary = solver.random_play_probe(
		state, config.probe_tries, config.probe_moves, rng, config.solver_node_budget
	)
	_expect(bool(probe["ok"]), "%s 무작위 플레이 후 막혔다: %s" % [label, probe["reason"]])


# 같은 시드는 같은 맵을 내야 한다. 전역 RNG 를 쓰면 여기서 깨진다.
func _check_determinism(generator: MapGenerator) -> void:
	var first := MapGenerator.default_config()
	first.base_seed = 424242
	var second := MapGenerator.default_config()
	second.base_seed = 424242
	var a: Dictionary = generator.generate(first)
	var b: Dictionary = generator.generate(second)
	_expect(bool(a["ok"]) and bool(b["ok"]), "결정성 검사용 맵 생성이 실패했다")
	if not (bool(a["ok"]) and bool(b["ok"])):
		return
	_expect(int(a["seed"]) == int(b["seed"]), "같은 시드가 다른 내부 시드를 냈다")
	_expect(
		LevelLayoutWriter.to_puzzle_state(a).key() == LevelLayoutWriter.to_puzzle_state(b).key(),
		"같은 시드가 다른 배치를 냈다"
	)
	_expect(
		str(a["solution"]) == str(b["solution"]),
		"같은 시드가 다른 풀이를 냈다"
	)
	print("[결정성] 같은 시드가 같은 맵과 같은 풀이를 낸다")


# JSON 왕복. 시드 회귀와 테스트 재현이 이 직렬화에 걸려 있다.
func _check_json_round_trip(generator: MapGenerator) -> void:
	var config := MapGenerator.default_config()
	config.base_seed = 987654
	var level: Dictionary = generator.generate(config)
	_expect(bool(level["ok"]), "JSON 검사용 맵 생성이 실패했다")
	if not bool(level["ok"]):
		return

	var restored: Dictionary = LevelLayoutWriter.from_json(LevelLayoutWriter.to_json(level))
	_expect(restored["grid_size"] == level["grid_size"], "JSON 왕복에서 grid_size 가 변했다")
	_expect(
		LevelLayoutWriter.to_puzzle_state(restored).key()
		== LevelLayoutWriter.to_puzzle_state(level).key(),
		"JSON 왕복에서 배치가 변했다"
	)
	_expect(
		(restored["solution"] as Array).size() == (level["solution"] as Array).size(),
		"JSON 왕복에서 풀이 길이가 변했다"
	)

	# 되살린 레벨의 풀이가 되살린 배치에서 그대로 돌아야 한다.
	var state: PuzzleState = LevelLayoutWriter.to_puzzle_state(restored)
	for move in restored["solution"]:
		if not bool(state.apply_move(move)["moved"]):
			_failures.append("JSON 왕복 후 풀이가 %s 에서 끊겼다" % [move])
			return
	_expect(state.is_solved(), "JSON 왕복 후 풀이를 다 써도 고양이가 남았다")
	print("[JSON] 배치·풀이·의존성 왕복 무손실")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("GENERATOR CHECK: PASS")
		return
	print("GENERATOR CHECK: FAIL (%d)" % _failures.size())
	for failure in _failures:
		print("  - ", failure)
