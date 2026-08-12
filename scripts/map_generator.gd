class_name MapGenerator
extends RefCounted

# 역설계 맵 생성기. 자세한 설계 근거는 `2_맵생성기.md`.
#
# ## 왜 역설계인가
#
# 정방향으로 무작위 배치를 만들고 풀리는지 확인하는 방식은 대부분의 시도가 버려진다.
# 대신 **다 풀린 상태에서 시작해 고양이를 구멍 옆에 되돌려 놓고 거꾸로 걸어 나오게** 한다.
# 역주행 한 스텝은 정방향 한 스텝의 역이므로, 생성이 끝난 순간 풀이 수순이 이미 손에 있다.
# 풀이가 없는 맵이 나올 수 없다.
#
# ## 순서 (탈출 순서 = 고양이 인덱스)
#
# σ_0 이 먼저 탈출하고 σ_{n-1} 이 마지막이다. 정방향에서 σ_k 가 움직일 때 판 위에는
# σ_{k+1}..σ_{n-1} 이 **시작 자리 그대로** 있고 σ_0..σ_{k-1} 은 이미 사라졌다.
# 그래서 역설계는 `k = n-1` 부터 `0` 까지 내려가며 만든다. σ_k 를 되돌릴 때 이미 배치된
# σ_{k+1}.. 의 시작 몸이 곧 그 시점의 정적 장애물이 되어, 정방향 상황과 정확히 일치한다.
#
# ## 두 가지 함정
#
# 1. **조기 흡입.** 흡입은 플레이어가 피할 수 있는 선택이 아니라 강제다. 역주행 중간 상태의
#    끝이 짝 색 구멍에 인접하면 정방향에서 거기 닿는 순간 빨려 들어가 나머지 수순이 끊긴다.
#    그래서 매 역주행 스텝마다 두 끝이 짝 구멍에 인접하지 않는지 검사한다.
# 2. **기믹 역주입.** 역설계가 끝난 맵에 기믹을 사후에 꽂으면 기록된 풀이가 무효가 된다.
#    기믹이 생기면 반드시 이 역주행 루프 안에서 함께 되돌려야 한다. (`PuzzleState.gimmicks`)
#    장애물만 사후 주입이 안전한 이유는 아래 `_choose_obstacles()` 주석에 적었다.

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
# 시도마다 시드를 흩어 놓기 위한 소수. 연속한 시드는 비슷한 맵을 낸다.
const SEED_STRIDE := 7919


class Config:
	extends RefCounted

	var base_seed: int = 0
	var grid_size: Vector2i = Vector2i(7, 9)
	var cat_count: int = 4
	# 이 팔레트 크기를 넘는 색은 만들지 않는다. `LevelManager.pair_colors` 와 맞춘다.
	var color_count: int = 4
	# 길이는 맵 설계 요소다. 짧은 고양이는 잘 돌지만 긴 고양이는 2×2 에서 회전조차 못 하므로
	# 길이 자체가 난이도를 만든다. 그래서 한 판에 여러 길이를 섞는다(`_pick_body_lengths`).
	var body_length_min: int = 3
	var body_length_max: int = 12
	# 고양이 몸이 차지할 수 있는 빈 칸의 최대 비율. 넘으면 몸을 눌러 줄인다. 이걸 안 두면
	# 길이 합이 보드를 꽉 채워 아무도 움직일 수 없게 되고 생성이 통째로 실패한다.
	var total_length_ratio: float = 0.5
	# 고양이 한 마리가 시작 자리에서 구멍까지 걷는 수. 이게 곧 풀이 길이의 뼈대다.
	var reverse_steps_min: int = 5
	var reverse_steps_max: int = 12
	# A → B → C 를 요구하면 3 이다.
	var min_chain_depth: int = 3
	# 풀이가 밟지 않은 칸 중 이 비율만큼을 장애물로 채운다.
	var obstacle_fill_ratio: float = 0.55
	var max_attempts: int = 80
	var solver_node_budget: int = 40000
	# 역주행이 막혔을 때 처음부터 다시 굴려 보는 횟수.
	var walk_restarts: int = 24
	# 뒤 순번 고양이의 경로 위에 몸을 얹으려는 힘. 이게 의존 간선을 만든다.
	var dependency_bias: float = 4.0
	# 같은 끝으로 계속 뻗으려는 힘. 없으면 역주행이 제자리에서 펄럭인다.
	var straight_bias: float = 2.0
	var probe_tries: int = 4
	var probe_moves: int = 8


static func default_config() -> Config:
	return Config.new()


# 조건을 만족하는 레벨 하나. 실패하면 `ok = false` 와 시도별 실패 이유를 함께 돌려준다.
func generate(config: Config) -> Dictionary:
	var failures: Array[String] = []
	for attempt in config.max_attempts:
		var rng := RandomNumberGenerator.new()
		rng.seed = config.base_seed + attempt * SEED_STRIDE
		var built: Dictionary = _build_once(config, rng, attempt)
		if bool(built["ok"]):
			return built
		failures.append("시도 %d: %s" % [attempt, built["reason"]])
	return {
		"ok": false,
		"reason": "%d회 시도해도 조건을 만족하는 맵이 나오지 않았다" % config.max_attempts,
		"failures": failures,
	}


func _build_once(config: Config, rng: RandomNumberGenerator, attempt: int) -> Dictionary:
	var holes: Array = _place_holes(config, rng)
	if holes.size() < config.cat_count:
		return {"ok": false, "reason": "구멍을 %d개 놓을 자리가 없다" % config.cat_count}

	# 작업판. 여기 들어간 고양이는 "시작 자리에 있는 뒤 순번 고양이" 이며 정적 장애물로 쓰인다.
	var board := PuzzleState.create(config.grid_size)
	for hole in holes:
		board.add_hole(hole["cell"], int(hole["color"]))

	# plans[k] = {start_body, moves, path_cells}
	var plans: Array = []
	plans.resize(config.cat_count)
	# 뒤 순번 고양이들이 밟는 칸. 여기에 몸을 얹으면 의존 간선이 생긴다.
	var later_path_cells: Dictionary = {}
	var lengths: Array[int] = _pick_body_lengths(config, rng, holes.size())

	for k in range(config.cat_count - 1, -1, -1):
		var plan: Dictionary = _reverse_build_cat(
			config, rng, board, k, holes[k], later_path_cells, lengths[k]
		)
		if plan.is_empty():
			return {"ok": false, "reason": "고양이 %d 의 역주행이 막혔다" % k}
		plans[k] = plan
		var start_body: Array[Vector2i] = plan["start_body"]
		board.add_cat(k, int(holes[k]["color"]), start_body)
		for cell in plan["path_cells"]:
			later_path_cells[cell] = true

	# 정방향 풀이는 탈출 순서대로 이어 붙인 것이다. σ_0 이 전부 움직여 나가고 그다음 σ_1 이다.
	var solution: Array[Dictionary] = []
	for k in config.cat_count:
		solution.append_array(plans[k]["moves"])

	var touched: Dictionary = _collect_touched(board, solution)
	if touched.is_empty():
		return {"ok": false, "reason": "기록된 풀이가 재생되지 않았다"}

	for entry in _choose_obstacles(config, rng, touched, board):
		for cell in PuzzleState.cells_of_block(entry):
			board.add_obstacle(cell)

	var verdict: Dictionary = _verify(config, rng, board, solution)
	if not bool(verdict["ok"]):
		return verdict

	var level: Dictionary = {
		"ok": true,
		"reason": "",
		"seed": config.base_seed + attempt * SEED_STRIDE,
		"attempt": attempt,
		"grid_size": config.grid_size,
		"holes": [],
		"obstacles": _group_rectangles(board.obstacles),
		"cats": [],
		"solution": solution,
		"escape_order": _escape_order(config.cat_count),
		"dependency": {
			"edges": (verdict["graph"] as LevelDependencyGraph).edge_list(),
			"chain_depth": (verdict["graph"] as LevelDependencyGraph).longest_chain_depth(),
			"chain": (verdict["graph"] as LevelDependencyGraph).longest_chain(),
			"describe": (verdict["graph"] as LevelDependencyGraph).describe(),
		},
		"stats": {
			"solution_length": solution.size(),
			"solver_moves": (verdict["solver_moves"] as int),
			"solver_nodes": int(verdict["solver_nodes"]),
			"obstacle_cells": board.obstacles.size(),
		},
	}
	for hole in holes:
		level["holes"].append({"grid_pos": hole["cell"], "color_id": int(hole["color"])})
	for k in config.cat_count:
		level["cats"].append({
			"body_cells": plans[k]["start_body"],
			"color_id": int(holes[k]["color"]),
		})
	return level


# 고양이별 몸 길이. **한 판에 길이가 섞여 있어야 한다** — 전부 같은 길이면 길이가 맵 설계에
# 아무 역할을 못 한다. 그래서 무작위로 뽑지 않고 [min, max] 구간에 고르게 펼친 뒤 지터를
# 주고 섞는다. 무작위 추출은 4마리쯤에서 값이 뭉치는 일이 흔하다.
#
# 길이 합은 빈 칸의 `total_length_ratio` 로 제한한다. 넘으면 긴 것부터 깎는다. 몸이 판을 꽉
# 채우면 아무도 움직일 수 없어 역주행이 첫 스텝에서 막힌다.
func _pick_body_lengths(
	config: Config, rng: RandomNumberGenerator, hole_count: int
) -> Array[int]:
	var low: int = mini(config.body_length_min, config.body_length_max)
	var high: int = maxi(config.body_length_min, config.body_length_max)
	var lengths: Array[int] = []
	for index in config.cat_count:
		var ratio: float = (
			float(index) / float(config.cat_count - 1) if config.cat_count > 1 else 0.5
		)
		var spread: int = int(round(lerp(float(low), float(high), ratio)))
		lengths.append(clampi(spread + rng.randi_range(-1, 1), low, high))

	var budget: int = int(
		floor(
			float(config.grid_size.x * config.grid_size.y - hole_count)
			* config.total_length_ratio
		)
	)
	# 긴 것부터 한 칸씩 깎아 예산에 맞춘다.
	while _sum(lengths) > budget:
		var longest: int = 0
		for index in lengths.size():
			if lengths[index] > lengths[longest]:
				longest = index
		if lengths[longest] <= low:
			break
		lengths[longest] -= 1

	_shuffle(lengths, rng)
	return lengths


static func _sum(values: Array[int]) -> int:
	var total: int = 0
	for value in values:
		total += value
	return total


func _escape_order(count: int) -> Array[int]:
	var order: Array[int] = []
	for index in count:
		order.append(index)
	return order


# ---------------------------------------------------------------- 구멍 배치

# 서로 체비셰프 거리 2 이상으로 떨어뜨린다. 붙여 놓으면 한 고양이가 지나가다 옆 구멍에
# 걸리기 쉬워 역주행 가드가 대부분의 칸을 거부한다.
#
# 색은 인덱스를 그대로 쓴다. `cat_count` 가 팔레트 크기를 넘으면 색이 겹치는데, 그러면
# 두 고양이가 서로의 구멍을 쓸 수 있어 순서 강제가 약해진다. 기본값은 겹치지 않는다.
func _place_holes(config: Config, rng: RandomNumberGenerator) -> Array:
	var candidates: Array[Vector2i] = []
	for y in config.grid_size.y:
		for x in config.grid_size.x:
			candidates.append(Vector2i(x, y))
	_shuffle(candidates, rng)

	var placed: Array = []
	for cell in candidates:
		if placed.size() >= config.cat_count:
			break
		var too_close: bool = false
		for existing in placed:
			var delta: Vector2i = (existing["cell"] as Vector2i) - cell
			if maxi(absi(delta.x), absi(delta.y)) < 2:
				too_close = true
				break
		if too_close:
			continue
		placed.append({"cell": cell, "color": placed.size() % maxi(config.color_count, 1)})
	return placed


# ---------------------------------------------------------------- 역설계 (고양이 한 마리)

# 흡입 순간의 자세를 만들고 거기서 거꾸로 걸어 나온다.
# 반환: {"start_body": Array[Vector2i], "moves": Array[Dictionary], "path_cells": Dictionary}
func _reverse_build_cat(
	config: Config,
	rng: RandomNumberGenerator,
	board: PuzzleState,
	cat_id: int,
	hole: Dictionary,
	later_path_cells: Dictionary,
	length: int
) -> Dictionary:
	var target_steps: int = rng.randi_range(config.reverse_steps_min, config.reverse_steps_max)
	var best: Dictionary = {}
	var best_score: int = -1

	for restart in config.walk_restarts:
		var absorbed: Array[Vector2i] = _make_absorbed_body(rng, board, hole, length)
		if absorbed.is_empty():
			continue
		var walk: Dictionary = _random_reverse_walk(
			config, rng, board, cat_id, int(hole["color"]), absorbed, target_steps, later_path_cells
		)
		var steps: int = (walk["moves"] as Array).size()
		if steps < config.reverse_steps_min:
			continue
		# 뽑는 기준은 걸음 수가 아니라 **시작 몸이 뒤 순번 고양이의 경로를 몇 칸 막는가**다.
		# 의존 간선은 시작 몸이 남의 길을 막을 때만 생기므로, 긴 산책보다 이쪽이 중요하다.
		var blocked: int = 0
		for cell in (walk["start_body"] as Array[Vector2i]):
			if later_path_cells.has(cell):
				blocked += 1
		# 걸음 수는 동점을 가르는 데만 쓴다.
		var score: int = blocked * 1000 + steps
		if score > best_score:
			best_score = score
			best = walk
		if blocked > 0 and steps >= target_steps:
			break
	return best


# 흡입이 시작되는 순간의 몸. 한쪽 끝(`cells[0]`)이 구멍에 4방향 인접해 있다.
# 나머지 칸은 어디든 빈 칸이면 된다. 흡입은 종료 상태이므로 다른 끝이 어느 구멍에 붙어
# 있어도 문제가 되지 않는다.
func _make_absorbed_body(
	rng: RandomNumberGenerator, board: PuzzleState, hole: Dictionary, length: int
) -> Array[Vector2i]:
	var hole_cell: Vector2i = hole["cell"]
	var triggers: Array[Vector2i] = []
	for dir in DIRS:
		var cell: Vector2i = hole_cell + dir
		if board.is_free_cell(cell):
			triggers.append(cell)
	_shuffle(triggers, rng)

	for trigger in triggers:
		var body: Array[Vector2i] = _grow_self_avoiding(rng, board, trigger, length)
		if body.size() == length:
			return body
	return [] as Array[Vector2i]


# `start` 에서 뻗는 길이 `length` 의 자기회피 경로. **되추적이 필요하다** — 길이 12쯤 되면
# 탐욕적으로 뻗다가 막다른 골목에 갇히는 일이 대부분이라, 다시 굴리는 것만으로는 긴 몸을
# 거의 만들지 못한다. 막히면 마지막 갈림길로 돌아가 다른 방향을 시도한다.
func _grow_self_avoiding(
	rng: RandomNumberGenerator, board: PuzzleState, start: Vector2i, length: int
) -> Array[Vector2i]:
	var body: Array[Vector2i] = [start]
	var used: Dictionary = {start: true}
	# 각 깊이에서 아직 시도하지 않은 방향. 되추적하면 여기서 다음 후보를 꺼낸다.
	var pending: Array = [_free_neighbours(rng, board, start, used)]

	while body.size() < length:
		var options: Array = pending[pending.size() - 1]
		if options.is_empty():
			# 이 자리에서 갈 곳이 없다. 한 칸 물러나 다른 방향을 시도한다.
			if body.size() <= 1:
				return [] as Array[Vector2i]
			used.erase(body[body.size() - 1])
			body.remove_at(body.size() - 1)
			pending.remove_at(pending.size() - 1)
			continue
		var next: Vector2i = options.pop_back()
		if used.has(next):
			continue
		body.append(next)
		used[next] = true
		pending.append(_free_neighbours(rng, board, next, used))
	return body


func _free_neighbours(
	rng: RandomNumberGenerator, board: PuzzleState, cell: Vector2i, used: Dictionary
) -> Array:
	var options: Array[Vector2i] = []
	for dir in DIRS:
		var next: Vector2i = cell + dir
		if board.is_free_cell(next) and not used.has(next):
			options.append(next)
	_shuffle(options, rng)
	return options


# 역주행. 현재 상태 `B'` 에서 한 스텝 앞선 상태 `earlier` 를 만들어 나간다.
#
# 정방향 한 스텝은 "끝 하나를 인접한 빈 칸으로 옮기고 반대쪽 끝을 뗀다"이므로, 그 역은
# **끝 하나를 밖으로 뻗고 반대쪽 끝을 뗀다**가 된다.
#   - 뒤끝을 뻗는 경우: earlier = B'[1..L-1] + [x],  정방향 수는 earlier[0](=B'[1]) → B'[0]
#   - 앞끝을 뻗는 경우: earlier = [x] + B'[0..L-2], 정방향 수는 earlier[L-1](=B'[L-2]) → B'[L-1]
# `x` 는 빈 칸이고 `B'` 안에 없어야 한다. 그 조건이 곧 정방향 `can_enter()` 를 만족시킨다
# (옮겨 들어갈 칸이 그때의 자기 몸에 없다는 것).
func _random_reverse_walk(
	config: Config,
	rng: RandomNumberGenerator,
	board: PuzzleState,
	cat_id: int,
	color_id: int,
	absorbed: Array[Vector2i],
	target_steps: int,
	later_path_cells: Dictionary
) -> Dictionary:
	var cells: Array[Vector2i] = absorbed.duplicate()
	var moves: Array[Dictionary] = []
	var path_cells: Dictionary = {}
	for cell in cells:
		path_cells[cell] = true
	# 직전에 뻗은 끝. 0 = 앞끝, 1 = 뒤끝, -1 = 아직 없음.
	var last_end: int = -1

	for step in target_steps:
		var candidates: Array = []
		var weights: Array[float] = []
		var total_weight: float = 0.0

		# 첫 역주행 스텝(= 정방향 마지막 수)은 뒤끝만 뻗는다. 흡입은 **방금 움직인 끝**에서만
		# 걸리므로, 마지막 수는 반드시 트리거 끝(cells[0])을 구멍 옆으로 옮기는 수여야 한다.
		# 앞끝을 뻗으면 마지막 수가 반대쪽 끝을 움직이게 되어 흡입이 걸리지 않는다.
		var allowed_sides: Array = [1] if moves.is_empty() else [0, 1]
		for end_side in allowed_sides:
			var tip: Vector2i = cells[0] if end_side == 0 else cells[cells.size() - 1]
			for dir in DIRS:
				var extension: Vector2i = tip + dir
				if not board.is_free_cell(extension):
					continue
				if cells.has(extension):
					continue

				var earlier: Array[Vector2i] = []
				var move: Dictionary = {}
				if end_side == 1:
					earlier.assign(cells.slice(1))
					earlier.append(extension)
					move = {
						"cat_id": cat_id,
						"from_end_cell": earlier[0],
						"to_cell": cells[0],
					}
				else:
					earlier.append(extension)
					earlier.append_array(cells.slice(0, cells.size() - 1))
					move = {
						"cat_id": cat_id,
						"from_end_cell": earlier[earlier.size() - 1],
						"to_cell": cells[cells.size() - 1],
					}

				# 조기 흡입 가드. 정방향에서 이 상태의 끝이 짝 구멍에 인접하면 그 순간
				# 강제로 빨려 들어가 나머지 수순이 통째로 무효가 된다. 판정 기준은 실제
				# 흡입과 같은 함수여야 하므로 `PuzzleState` 의 것을 그대로 쓴다.
				if board.body_touches_paired_hole(earlier, color_id):
					continue

				var weight: float = 1.0
				if later_path_cells.has(extension):
					weight += config.dependency_bias
				if end_side == last_end:
					weight += config.straight_bias
				candidates.append({"earlier": earlier, "move": move, "end_side": end_side})
				weights.append(weight)
				total_weight += weight

		if candidates.is_empty():
			break

		var roll: float = rng.randf() * total_weight
		var chosen: int = candidates.size() - 1
		for index in candidates.size():
			roll -= weights[index]
			if roll <= 0.0:
				chosen = index
				break

		var picked: Dictionary = candidates[chosen]
		cells = picked["earlier"]
		last_end = int(picked["end_side"])
		# 역주행이라 정방향 수는 앞에 붙는다.
		moves.push_front(picked["move"])
		for cell in cells:
			path_cells[cell] = true

	return {"start_body": cells, "moves": moves, "path_cells": path_cells}


# ---------------------------------------------------------------- 장애물 사후 주입

# 기록된 풀이가 밟는 칸 전부. 시작 자세부터 매 수 뒤 상태까지 모두 모은다.
# 재생이 실패하면 빈 Dictionary 를 돌려준다 (역설계 자체가 깨졌다는 뜻이다).
func _collect_touched(start_state: PuzzleState, solution: Array[Dictionary]) -> Dictionary:
	var work: PuzzleState = start_state.clone()
	var touched: Dictionary = {}
	for hole_cell in work.holes:
		touched[hole_cell] = true
	for cat_id in work.cat_ids():
		for cell in work.body_of(cat_id):
			touched[cell] = true

	for move in solution:
		var result: Dictionary = work.apply_move(move)
		if not bool(result["moved"]):
			return {}
		touched[move["to_cell"]] = true
		for cat_id in work.cat_ids():
			for cell in work.body_of(cat_id):
				touched[cell] = true
	if not work.is_solved():
		return {}
	return touched


# 풀이가 한 번도 밟지 않은 칸에만 장애물을 놓는다.
#
# **이 사후 주입이 안전한 이유:** 장애물은 "칸을 뺏는" 순수 감산이다. 기록된 풀이는 고정된
# 칸 순서이므로, 그 칸을 하나도 건드리지 않으면 수순이 그대로 유효하다. 풀리는 맵이면
# `level_solver.gd` 머리의 가역성 논증에 의해 데드락도 없다.
# 상태를 바꾸는 기믹에는 이 논증이 성립하지 않으므로 기믹은 반드시 역설계 안에서 다뤄야 한다.
func _choose_obstacles(
	config: Config, rng: RandomNumberGenerator, touched: Dictionary, board: PuzzleState
) -> Array:
	var free_cells: Array[Vector2i] = []
	for y in config.grid_size.y:
		for x in config.grid_size.x:
			var cell := Vector2i(x, y)
			if touched.has(cell) or board.is_hole(cell):
				continue
			free_cells.append(cell)
	_shuffle(free_cells, rng)

	var wanted: int = int(floor(float(free_cells.size()) * config.obstacle_fill_ratio))
	var chosen: Dictionary = {}
	for index in mini(wanted, free_cells.size()):
		chosen[free_cells[index]] = true
	return _group_rectangles(chosen)


# 인접한 장애물 칸을 사각형으로 묶는다. `ObstacleMarker` 는 `block_size` 로 여러 칸을 한
# 노드가 잠그므로, 칸마다 노드를 만들지 않는다는 기존 배치 규칙에 맞춘다.
func _group_rectangles(cells: Dictionary) -> Array:
	var remaining: Dictionary = cells.duplicate()
	var sorted_cells: Array = cells.keys()
	sorted_cells.sort_custom(
		func(a, b): return a.y < b.y if a.y != b.y else a.x < b.x
	)

	var blocks: Array = []
	for cell in sorted_cells:
		if not remaining.has(cell):
			continue
		var width: int = 1
		while remaining.has(cell + Vector2i(width, 0)):
			width += 1
		var height: int = 1
		while true:
			var row_complete: bool = true
			for offset in width:
				if not remaining.has(cell + Vector2i(offset, height)):
					row_complete = false
					break
			if not row_complete:
				break
			height += 1
		for row in height:
			for column in width:
				remaining.erase(cell + Vector2i(column, row))
		blocks.append({"grid_pos": cell, "block_size": Vector2i(width, height)})
	return blocks


# ---------------------------------------------------------------- 검증

func _verify(
	config: Config,
	rng: RandomNumberGenerator,
	state: PuzzleState,
	solution: Array[Dictionary]
) -> Dictionary:
	var problems: Array[String] = state.start_layout_problems()
	if not problems.is_empty():
		return {"ok": false, "reason": "시작 배치 위반: %s" % [problems]}

	# 기록된 풀이가 장애물을 넣은 뒤에도 그대로 재생되는지. 사후 주입의 안전성 확인이다.
	var replay: PuzzleState = state.clone()
	for move in solution:
		if not bool(replay.apply_move(move)["moved"]):
			return {"ok": false, "reason": "장애물 주입 후 풀이 재생이 %s 에서 끊겼다" % [move]}
	if not replay.is_solved():
		return {"ok": false, "reason": "풀이를 다 재생했는데 고양이가 남았다"}

	# 오토솔버가 기록과 무관하게 스스로 풀 수 있는지. 모델이 자기 모순이 아닌지 보는 것이다.
	var solver := LevelSolver.new()
	var solved: Dictionary = solver.solve(state, config.solver_node_budget)
	if not bool(solved["found"]):
		return {"ok": false, "reason": "오토솔버가 풀지 못했다: %s" % solved["reason"]}

	var order: Array[int] = _escape_order(state.cat_ids().size())
	var graph: LevelDependencyGraph = solver.build_dependency_graph(state, order)
	if graph.has_cycle():
		return {"ok": false, "reason": "의존성에 순환이 있다 = 아무도 먼저 나갈 수 없다"}
	var depth: int = graph.longest_chain_depth()
	if depth < config.min_chain_depth:
		return {"ok": false, "reason": "의존 사슬 깊이가 %d 뿐이다 (%d 이상 필요)" % [depth, config.min_chain_depth]}

	var probe: Dictionary = solver.random_play_probe(
		state, config.probe_tries, config.probe_moves, rng, config.solver_node_budget
	)
	if not bool(probe["ok"]):
		return {"ok": false, "reason": "무작위 플레이 후 풀리지 않았다: %s" % probe["reason"]}

	return {
		"ok": true,
		"graph": graph,
		"solver_moves": (solved["moves"] as Array).size(),
		"solver_nodes": int(solved["nodes"]),
	}


# ---------------------------------------------------------------- 유틸

# 시드가 같으면 결과가 같아야 하므로 `Array.shuffle()`(전역 RNG)을 쓰지 않는다.
func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var swap_with: int = rng.randi_range(0, index)
		var carried = items[index]
		items[index] = items[swap_with]
		items[swap_with] = carried
