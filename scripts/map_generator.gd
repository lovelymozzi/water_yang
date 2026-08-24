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
#
# ## 왜 역설계만으로는 "빈 공간이 없는" 맵이 안 나오는가
#
# 각 고양이의 역주행은 **뒤 순번 고양이만 놓인 판**에서 만들어진다. 그 판은 헐렁하므로
# 경로도 헐렁하게 뽑히고, `_choose_obstacles()` 는 그 경로가 스친 칸을 전부 비워 두므로
# 넓은 여유 통로가 남는다. 그러면 "1번이 나가야 2번이 나간다"가 아니라 "2번이 알아서 돌아
# 나간다"가 되어 순차 의존이 체감되지 않는다.
# 그래서 마지막에 `_squeeze()` 로 **막아도 여전히 풀리는 칸을 전부 막는다**. 남는 빈 칸은
# 어느 하나를 더 막아도 풀리지 않는 칸뿐이므로, 뒤 순번 고양이는 앞 고양이가 비운 자리를
# 여유 없이 써야 나갈 수 있다.
#
# 실측(7×9, 고양이 4): 빈 칸 20.2 → 4.0 칸. 몸 길이를 5~12 로 늘리고 `total_length_ratio`
# 를 0.65 로 올리면 2 칸까지 내려간다. "빈 공간이 거의 없는" 판은 이 조합에서 나온다.

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
# 시도마다 시드를 흩어 놓기 위한 소수. 연속한 시드는 비슷한 맵을 낸다.
const SEED_STRIDE := 7919
# 한 고양이를 벽으로 몇 번까지 되돌릴 수 있는가. 벽 세우기 루프의 종료 조건이기도 하다.
const WALL_REUSE_LIMIT := 2
# 벽 후보를 길목까지 옮길 자세를 찾는 BFS 의 자세 수 상한.
const WALL_SEARCH_BUDGET := 4000


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
	# 앞 순번 고양이의 구멍이 닫힌 자리를 지나가려는 힘. 닫힌 구멍 길을 쓰는 경로는
	# "그 고양이가 먼저 나가야만 열린다"는 강한 순차 의존을 만든다.
	var vacated_hole_bias: float = 3.0
	# 첫 흡입까지 "다른 고양이를 치워야 하는" 최소 수. 자기 이동은 드래그 한 번에 몇 칸이든
	# 끌리므로 세지 않는다. 한 마리가 빠지는 순간 난이도가 급감하므로 첫 탈출을 비싸게
	# 만드는 하한이다. 이 값이 나오도록 첫 탈출 고양이의 길목에 벽 고양이를 세운다.
	# 1 = 드래그 한 번으로 나가는 고양이가 없음. 2~3부터 생성 실패가 가파르게 늘어난다.
	var min_first_escape_moves: int = 1
	# 구멍을 흩뿌리는 대신 안쪽 분할선 위에 관문처럼 늘어놓을 확률. 판이 구멍 벽으로
	# 갈라져 반대편으로 가려면 닫힌 구멍 자리를 지나야 하므로 깊은 사슬이 훨씬 잘 나온다.
	var hole_line_chance: float = 0.5
	# 실측 의존 고양이(누군가 먼저 나가야 하는 고양이)의 최소 마릿수. 0 = 검사 안 함.
	# 최대 의미 있는 값은 cat_count - 1 이다 (첫 탈출 고양이는 구조상 자유).
	var min_dependent_cats: int = 0
	# 두 번째 이후 탈출까지 치워야 하는 드래그 하한. 0 = 검사 안 함.
	# **거르기만 한다** — 이 값을 만족하는 판을 만들어 내는 장치는 없다. 왜 없는지는
	# `_plant_first_escape_walls()` 주석에 실측과 함께 적었다. 실측상 1 로 걸면 검증까지
	# 온 시도의 10%쯤만 통과하므로 `max_attempts` 를 크게 잡아야 한다.
	var min_later_escape_moves: int = 0
	# 막아도 여전히 풀리는 빈 칸을 전부 장애물로 채운다. 파일 머리 주석 참조.
	# 검증을 통과한 판에만 돌지만 칸마다 오토솔버를 한 번 돌리므로 생성이 몇 배 느려진다.
	var squeeze_free_cells: bool = false
	# 여유 판정용 탐색 예산. 예산 안에 못 풀면 "필요한 칸"으로 보고 비워 둔다(보수적).
	var squeeze_node_budget: int = 20000
	# 같은 끝으로 계속 뻗으려는 힘. 없으면 역주행이 제자리에서 펄럭인다.
	var straight_bias: float = 2.0
	var probe_tries: int = 4
	var probe_moves: int = 8
	# 얼음 기믹. 첫 탈출 구멍(앞서 나가는 고양이가 없는 구멍)을 뺀 나머지 구멍마다 이 확률로
	# 얼음을 덮는다. 0 = 얼음 없음.
	var ice_chance: float = 0.0
	# 얼음 숫자의 상한. 0 = "이 구멍이 풀이에서 쓰이기 전까지 빠지는 고양이 수"를 상한으로
	# 쓴다. 그 수를 넘으면 기록된 풀이에서 얼음이 제때 안 열려 맵이 안 풀린다.
	var ice_number_max: int = 0


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
		# σ_k 가 정방향으로 움직이는 시점에는 σ_0..σ_{k-1} 이 이미 나가 그 구멍들이 닫혀
		# 빈 칸이 된 상태다. 그 판을 정확히 재현하려고 걷는 동안만 앞 순번 구멍을 치운다.
		# 이렇게 열린 자리를 지나는 경로는 앞 고양이의 탈출 없이는 성립하지 않으므로
		# 그 자체가 순차 의존의 키가 된다.
		var vacated: Dictionary = {}
		for j in range(k):
			vacated[holes[j]["cell"] as Vector2i] = true
			board.holes.erase(holes[j]["cell"])
		# 첫 탈출 고양이(k=0)를 뺀 전원은 의존을 반드시 하나 이상 만들어야 한다:
		# 시작 몸으로 뒤 순번의 경로를 막거나(그들이 나를 기다림), 앞 순번 구멍 자리를
		# 지나거나(내가 앞 순번을 기다림). 이게 없으면 그 고양이는 독립적으로 나가 버린다.
		var plan: Dictionary = _reverse_build_cat(
			config, rng, board, k, holes[k], later_path_cells, lengths[k], vacated, k > 0
		)
		for j in range(k):
			board.add_hole(holes[j]["cell"], int(holes[j]["color"]))
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

	# 고양이별 단독 산책을 이어 붙인 풀이라, 아무도 안 치우고 나가는 고양이가 생긴다.
	# 그 길목마다 다른 고양이를 벽으로 되돌려 세우고 비키는 수순을 풀이에 끼워 넣는다.
	# **장애물을 깐 다음이어야 한다** — 허허벌판에서는 모두가 혼자 탈출 가능으로 판정돼
	# 벽 후보가 바닥나고, 벽의 되돌리기도 장애물을 피해 걸어야 재생이 성립한다.
	if config.min_first_escape_moves > 0 and config.cat_count > 1:
		var walled: Dictionary = _plant_first_escape_walls(config, rng, board, plans, solution)
		if not bool(walled["ok"]):
			return {
				"ok": false, "reason": "첫 탈출 가로막이를 세우지 못했다: %s" % walled["reason"],
			}
		solution = walled["solution"]

	var verdict: Dictionary = _verify(config, rng, board, solution)
	if not bool(verdict["ok"]):
		return verdict

	# 여유 제거는 검증을 통과한 판에만 돌린다 — 칸마다 오토솔버를 돌리므로 실패할 판에
	# 쓰기엔 너무 비싸다. 판이 바뀌었으니 지표를 다시 재고, 이번에는 의존 사슬을 요구하지
	# 않는다: 사슬 측정 모델은 "뒤 순번 고양이가 시작 자리에 얼어 있다"를 가정하는데
	# 여유가 없는 판은 뒤 순번도 비켜 줘야 나가는 판이라 그 가정이 성립하지 않는다.
	# 사슬 자체는 위에서 이미 요구했고, 장애물 추가는 `can_escape_alone` 을 단조 감소만
	# 시키므로 의존을 없애지는 못한다(측정만 못 하게 된다).
	if config.squeeze_free_cells:
		solution = _squeeze(config, rng, board, solution)
		verdict = _verify(config, rng, board, solution, false)
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
			"early_clearing": verdict["early_clearing"],
		},
	}
	# 얼음은 풀이가 확정된 뒤에 배치한다. "이 구멍이 처음 쓰이기 전까지 빠지는 고양이 수"를
	# 상한으로 삼으므로 최종 풀이(스퀴즈·벽 삽입까지 반영된)를 기준으로 재야 한다.
	var ice: Dictionary = _assign_ice(config, rng, board, solution)
	for hole in holes:
		level["holes"].append({
			"grid_pos": hole["cell"],
			"color_id": int(hole["color"]),
			"ice_count": int(ice.get(hole["cell"], 0)),
		})
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
	if rng.randf() < config.hole_line_chance:
		var lined: Array = _place_holes_on_lines(config, rng)
		if not lined.is_empty():
			return lined
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


# 구멍을 안쪽 분할선(세로/가로 1~2줄)에 간격 2로 늘어놓는다. 판이 "하나씩 열리는 관문
# 벽"으로 갈라져, 반대편으로 건너가려면 이미 닫힌 구멍 자리를 지나는 수밖에 없다.
# 흩뿌리기보다 닫힌 구멍 의존(깊은 사슬)이 훨씬 잘 생긴다. 자리가 안 나오면 빈 배열을
# 돌려주고 호출부가 흩뿌리기로 폴백한다.
func _place_holes_on_lines(config: Config, rng: RandomNumberGenerator) -> Array:
	var vertical: bool = rng.randf() < 0.5
	var span: int = config.grid_size.y if vertical else config.grid_size.x
	var breadth: int = config.grid_size.x if vertical else config.grid_size.y
	if breadth < 4 or span < 3:
		return []

	# 한 줄에 들어가는 자리 수(간격 2). 모자라면 두 줄에 나눈다. 줄 사이도 2 이상 벌려
	# 체비셰프 거리 2 규칙을 지킨다.
	var per_line: int = (span + 1) / 2
	var line_total: int = 1 if per_line >= config.cat_count else 2
	if line_total == 2 and breadth < 5:
		return []
	var first: int = rng.randi_range(1, breadth - 2 - (2 if line_total == 2 else 0))
	var lines: Array[int] = [first]
	if line_total == 2:
		lines.append(rng.randi_range(first + 2, breadth - 2))

	var candidates: Array[Vector2i] = []
	for line_pos in lines:
		for offset in range(rng.randi_range(0, 1), span, 2):
			candidates.append(
				Vector2i(line_pos, offset) if vertical else Vector2i(offset, line_pos)
			)
	if candidates.size() < config.cat_count:
		return []
	_shuffle(candidates, rng)
	var placed: Array = []
	for index in config.cat_count:
		placed.append({
			"cell": candidates[index],
			"color": index % maxi(config.color_count, 1),
		})
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
	length: int,
	vacated: Dictionary,
	require_crossing: bool = false
) -> Dictionary:
	var target_steps: int = rng.randi_range(config.reverse_steps_min, config.reverse_steps_max)
	var best: Dictionary = {}
	var best_score: int = -1
	# 교차 없는 걷기 중 최선. 판이 꽉 차 교차 걷기가 아예 안 나올 때의 폴백이다 —
	# 교차 여부의 최종 판정은 검증(의존 고양이 하한)이 실측으로 한다.
	var fallback_walk: Dictionary = {}
	var fallback_score: int = -1

	for restart in config.walk_restarts:
		var absorbed: Array[Vector2i] = _make_absorbed_body(rng, board, hole, length)
		if absorbed.is_empty():
			continue
		var walk: Dictionary = _random_reverse_walk(
			config, rng, board, cat_id, int(hole["color"]), absorbed, target_steps,
			later_path_cells, vacated
		)
		var steps: int = (walk["moves"] as Array).size()
		if steps < config.reverse_steps_min:
			continue
		# 시작 몸은 게임 시작 시점에 존재하므로, 그때는 아직 열려 있는(나중에야 닫힐)
		# 구멍 칸을 밟고 있으면 안 된다. 경로가 지나는 것은 되지만 시작 자세는 안 된다.
		var starts_on_vacated: bool = false
		for cell in (walk["start_body"] as Array[Vector2i]):
			if vacated.has(cell):
				starts_on_vacated = true
				break
		if starts_on_vacated:
			continue
		# 시작 몸이 자기 구멍 코앞이면 새는 길이 짧아 벽으로 막기도 어렵다. 다만 세게 걸면
		# 역주행 대부분이 여기서 죽으므로 "코앞"(거리 2 미만)만 거른다. 나머지는 벽 세우기와
		# 첫 탈출 검증이 책임진다.
		if config.min_first_escape_moves > 0 \
				and board.escape_distance(walk["start_body"], int(hole["color"])) < 2:
			continue
		# 뽑는 기준은 걸음 수가 아니라 **의존을 몇 개 만드는가**다. 시작 몸이 뒤 순번
		# 고양이의 경로를 막는 칸 수 + 닫힌 구멍 자리를 지나는 칸 수(앞 순번이 나가야만
		# 열리는 길이므로 더 강한 의존이라 가중치 2). 걸음 수는 동점만 가른다.
		var blocked: int = 0
		for cell in (walk["start_body"] as Array[Vector2i]):
			if later_path_cells.has(cell):
				blocked += 1
		var corridor: int = 0
		for cell in (walk["path_cells"] as Dictionary):
			if vacated.has(cell):
				corridor += 1
		var score: int = (blocked + corridor * 2) * 1000 + steps
		# 교차 우선: 의존을 하나도 안 만드는 걷기는 폴백으로만 둔다. 첫 탈출 고양이는 예외.
		if require_crossing and blocked == 0 and corridor == 0:
			if score > fallback_score:
				fallback_score = score
				fallback_walk = walk
			continue
		if score > best_score:
			best_score = score
			best = walk
		if (blocked > 0 or corridor > 0) and steps >= target_steps:
			break
	return best if not best.is_empty() else fallback_walk


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
	later_path_cells: Dictionary,
	vacated: Dictionary,
	require_absorb_trigger: bool = true
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
		# (벽 되돌리기는 흡입으로 끝나지 않으므로 이 제한이 필요 없다.)
		var allowed_sides: Array = (
			[1] if moves.is_empty() and require_absorb_trigger else [0, 1]
		)
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
				# 닫힌 구멍 자리를 지나는 수를 선호한다. 이 길은 앞 순번 고양이가
				# 나가야만 열리므로 지나기만 해도 순차 의존이 생긴다.
				if vacated.has(extension):
					weight += config.vacated_hole_bias
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


# ---------------------------------------------------------------- 첫 탈출 가로막이

# 역설계는 σ_k 의 경로를 "σ_{k+1}.. 이 시작 자리에 있는 판"에서 뽑으므로, 그 경로는 뒤 순번
# 고양이를 **절대 건드리지 않는다**. 즉 기록된 풀이는 "고양이별 단독 산책"을 이어 붙인 것이고,
# t=0 에 아무도 안 치우고 드래그 한 번에 나가는 고양이가 생긴다.
#
# 그래서 가장 싼 첫 탈출 수순(목격자)을 찾아 그 길목에 다른 고양이를 벽으로 세우고, 벽이
# 비키는 수순을 **풀이 맨 앞**에 붙인다. 지표(`early_escape_costs`)는 시작 판을 재므로 벽이
# 언제 비키는지는 지표와 무관하고, 맨 앞이 제약이 가장 작다 — 벽은 그때까지만 새 자리에 서
# 있으면 되고 뒤에 이어지는 기록 풀이는 벽이 제자리로 돌아온 뒤에 돌기 때문이다.
# **늦게 세운 벽이 먼저 비킨다** — 새 벽의 수순이 앞에 삽입되므로 순서가 저절로 맞는다. 각
# 벽의 이사 경로는 "그때까지 세운 벽이 전부 새 자리에 있는 판"에서 찾고 재생도 그 역순으로
# 돌기 때문이다. 같은 고양이를 `WALL_REUSE_LIMIT` 번까지 다시 세워도 같은 논증이다.
#
# ## 두 번째 이후 탈출은 왜 이 방식으로 못 조이는가 (실측)
#
# 같은 루프를 "앞 고양이가 빠진 판"에도 돌려 봤지만 수렴하지 않는다. 2번째 탈출을 비싸게
# 만들려면 **남은 고양이 전원**이 각각 남을 치워야 하게 만들어야 하는데, 벽을 하나 세울 때마다
# 그 고양이가 원래 있던 칸이 비어 새로운 싼 탈출이 열려서 첫 탈출 조건이 다시 깨진다. 벽을
# 고양이 수의 두 배까지 세워도 두 조건이 서로를 무너뜨리며 제자리를 돈다(수율 0).
# ponytail: 그래서 `min_later_escape_moves` 는 벽을 세우지 않고 검증에서 거르기만 한다.
# 제대로 고치려면 역설계 자체가 σ_k 의 경로 중간에 뒤 순번 고양이를 밀어내는 수를 끼워 넣어야
# 한다(= 계획이 고양이별로 분리되지 않는 구조). 그건 이 파일의 골격을 바꾸는 일이다.
func _plant_first_escape_walls(
	config: Config,
	rng: RandomNumberGenerator,
	board: PuzzleState,
	plans: Array,
	solution: Array[Dictionary]
) -> Dictionary:
	var solver := LevelSolver.new()
	var wall_uses: Dictionary = {}
	var current: Array[Dictionary] = solution
	var planted: int = 0
	var guard: int = config.cat_count * WALL_REUSE_LIMIT
	while true:
		var witness: Dictionary = solver.first_escape_witness(
			board, config.min_first_escape_moves
		)
		if int(witness["clearing"]) >= config.min_first_escape_moves:
			break
		if planted >= guard:
			return {
				"ok": false, "solution": current,
				"reason": "벽을 %d개 세워도 첫 탈출 하한을 못 맞췄다" % guard,
			}
		var escaper: int = int(witness["cat_id"])
		# 막을 칸: 목격 수순에서 치워지는 고양이의 **양 끝이 움직일 수 있는 빈 칸 전부**.
		# 드래그 도착 칸만 막으면 다른 방향으로 비켜 버린다 — 아예 못 움직이게 핀으로
		# 고정해야 "초록을 치우려면 핑크부터"가 강제된다.
		# 치우는 드래그가 아예 없으면(혼자 탈출) 탈출 경로 자체를 막는다.
		var block_cells: Dictionary = {}
		for move in (witness["moves"] as Array):
			var mover: int = int(move["cat_id"])
			if mover == escaper:
				continue
			for end_cell in PuzzleState.ends_of(board.body_of(mover)):
				for dir in DIRS:
					if board.is_free_cell(end_cell + dir):
						block_cells[end_cell + dir] = true
		if block_cells.is_empty():
			block_cells = solver.solo_escape_route(board, escaper)
		if block_cells.is_empty():
			return {"ok": false, "solution": current, "reason": "막을 길목이 없다"}
		var walled: Array[Dictionary] = _build_wall(
			rng, board, plans, escaper, block_cells, wall_uses, current
		)
		if walled.is_empty():
			return {
				"ok": false, "solution": current,
				"reason": "길목 %d칸을 막을 벽이 없다 (세운 벽 %d개)" % [
					block_cells.size(), planted,
				],
			}
		current = walled
		planted += 1
	return {"ok": true, "solution": current, "reason": ""}


# target 이 새는 길(route)을 덮는 시작 자세가 나올 때까지 벽 후보를 옮겨 본다.
# 성공하면 그 고양이의 시작 몸을 새 자세로 바꾸고, 비키는 수순을 앞에 붙인 새 풀이를
# 돌려준다. 실패하면 빈 배열.
func _build_wall(
	rng: RandomNumberGenerator,
	board: PuzzleState,
	plans: Array,
	target: int,
	route: Dictionary,
	wall_uses: Dictionary,
	solution: Array[Dictionary]
) -> Array[Dictionary]:
	var candidates: Array[int] = []
	for other in board.cat_ids():
		if int(other) != target and int(wall_uses.get(other, 0)) < WALL_REUSE_LIMIT:
			candidates.append(int(other))
	_shuffle(candidates, rng)
	# 자기 자신이 새는 벽밖에 없을 때 마지막에 쓰는 차선책.
	var fallback: Dictionary = {}

	for wall_id in candidates:
		var work: PuzzleState = board.clone()
		var old_body: Array[Vector2i] = work.body_of(wall_id)
		var color: int = work.color_of(wall_id)
		var best: Dictionary = _wall_relocation(work, wall_id, color, old_body, route)
		if best.is_empty():
			continue

		board.remove_cat(wall_id)
		board.add_cat(wall_id, color, best["start_body"])
		# 세운 벽이 자기 자신은 새지 않는 후보(예: 구멍 관문 뒤에 갇힘)를 우선한다.
		# 벽이 새면 그 벽을 막을 벽이 또 필요해 연쇄가 안 닫히는 일이 잦다.
		if not LevelSolver.new().solo_escape_route(board, wall_id).is_empty() \
				and fallback.is_empty():
			# 새는 벽이지만 다른 후보가 다 실패하면 쓸 수 있게 적어 둔다.
			fallback = {"wall_id": wall_id, "color": color, "walk": best}
			board.remove_cat(wall_id)
			board.add_cat(wall_id, color, old_body)
			continue
		return _commit_wall(plans, wall_uses, solution, wall_id, best)

	if not fallback.is_empty():
		var wall_id: int = int(fallback["wall_id"])
		var walk: Dictionary = fallback["walk"]
		board.remove_cat(wall_id)
		board.add_cat(wall_id, int(fallback["color"]), walk["start_body"])
		return _commit_wall(plans, wall_uses, solution, wall_id, walk)
	return [] as Array[Dictionary]


# 벽 후보를 시작 자리에서 길목까지 옮긴다. 무작위 역주행으로는 길목에 닿는 자세가 거의
# 안 나온다 — 막아야 할 칸이 판 반대쪽일 수 있고, 무작위 걷기는 그쪽으로 갈 이유가 없다.
# 그래서 **몸 배치 BFS** 로 실제 도달 가능한 자세만 전부 훑고, 그중 길목을 가장 많이 덮는
# 자세를 고른다. 겹치는 칸이 많을수록 벽을 치우는 데 손이 더 많이 간다.
#
# 한 칸 이동은 항상 되돌릴 수 있으므로(`level_solver.gd` 머리 논증), 찾은 경로를 뒤집으면
# 그게 곧 "벽이 제자리로 비키는" 정방향 수순이다. 중간 자세가 짝 구멍에 닿으면 되돌리는
# 드래그 도중에 빨려 들어가므로 그런 자세는 버린다.
# 반환: {"start_body", "moves", "path_cells"} 또는 닿을 수 없으면 빈 Dictionary.
func _wall_relocation(
	board: PuzzleState,
	cat_id: int,
	color_id: int,
	old_body: Array[Vector2i],
	route: Dictionary
) -> Dictionary:
	var work: PuzzleState = board
	var bodies: Array = [old_body]
	var parents: Array[int] = [-1]
	var visited: Dictionary = {PuzzleState.body_key(old_body): true}
	var best: int = -1
	var best_overlap: int = 0
	var head: int = 0
	while head < bodies.size() and bodies.size() < WALL_SEARCH_BUDGET:
		var body: Array[Vector2i] = bodies[head]
		work.set_cat_body(cat_id, body)
		for move in work.moves_for(cat_id):
			var next_body: Array[Vector2i] = PuzzleState.body_after(
				body, move["from_end_cell"], move["to_cell"]
			)
			if next_body.is_empty():
				continue
			var next_key: String = PuzzleState.body_key(next_body)
			if visited.has(next_key):
				continue
			visited[next_key] = true
			if work.body_touches_paired_hole(next_body, color_id):
				continue
			bodies.append(next_body)
			parents.append(head)
			var overlap: int = 0
			for cell in next_body:
				if route.has(cell):
					overlap += 1
			if overlap > best_overlap:
				best_overlap = overlap
				best = bodies.size() - 1
		head += 1
	work.set_cat_body(cat_id, old_body)
	if best < 0:
		return {}

	# 부모를 되짚으면 [W, ..., old_body] 다. 이웃한 두 자세 사이의 정방향 수를 이어 붙인다.
	var chain: Array = []
	var cursor: int = best
	while cursor >= 0:
		chain.append(bodies[cursor])
		cursor = parents[cursor]
	var moves: Array[Dictionary] = []
	var path_cells: Dictionary = {}
	for index in range(chain.size() - 1):
		moves.append(_move_between(cat_id, chain[index], chain[index + 1]))
		for cell in (chain[index] as Array):
			path_cells[cell] = true
	for cell in (chain[chain.size() - 1] as Array):
		path_cells[cell] = true
	return {"start_body": chain[0], "moves": moves, "path_cells": path_cells}


# 한 칸 차이인 두 자세 사이의 수. 새로 생긴 칸이 앞쪽이면 앞끝이 움직인 것이다
# (`PuzzleState.body_after()` 의 역).
static func _move_between(
	cat_id: int, from_body: Array, to_body: Array
) -> Dictionary:
	if not from_body.has(to_body[0]):
		return {"cat_id": cat_id, "from_end_cell": from_body[0], "to_cell": to_body[0]}
	return {
		"cat_id": cat_id,
		"from_end_cell": from_body[from_body.size() - 1],
		"to_cell": to_body[to_body.size() - 1],
	}


# 벽 하나를 확정한다: 시작 자세를 갈아 끼우고, 비키는 수순을 풀이 맨 앞에 붙인다.
func _commit_wall(
	plans: Array,
	wall_uses: Dictionary,
	solution: Array[Dictionary],
	wall_id: int,
	walk: Dictionary
) -> Array[Dictionary]:
	plans[wall_id]["start_body"] = walk["start_body"]
	# 비키는 길도 이 고양이의 경로다. 나중에 이 고양이를 막을 때 함께 봐야 한다.
	for cell in (walk["path_cells"] as Dictionary):
		(plans[wall_id]["path_cells"] as Dictionary)[cell] = true
	wall_uses[wall_id] = int(wall_uses.get(wall_id, 0)) + 1
	var spliced: Array[Dictionary] = []
	spliced.append_array(walk["moves"])
	spliced.append_array(solution)
	return spliced



# ---------------------------------------------------------------- 얼음 사후 주입

# 얼음을 사후에 꽂아도 안전한 이유 (장애물과 같은 논증의 변형):
#
# 얼음은 "고양이 N 마리가 빠질 때까지 이 구멍의 흡입을 막는" 상태 기믹이다. 기록된 풀이는
# 얼음 없는 모델에서 뽑혔으므로, 각 구멍은 **그 짝 고양이가 처음 구멍에 인접하는 수**에서
# 정확히 흡입된다(인접하면 강제 흡입이니 그보다 늦게 인접해 대기하는 상태가 없다). 그러니
# 그 구멍의 얼음 숫자를 "그 흡입 이전까지 빠진 고양이 수" 이하로 두면, 그 수에 도달했을 때
# 얼음이 이미 깨져 있어 같은 수에서 그대로 흡입된다. 즉 얼음을 켜도 기록된 풀이의 모든 흡입이
# 같은 순간에 일어나 재생이 바뀌지 않는다. 첫 구멍(이전 흡입 0)은 얼음을 못 씌운다.
func _assign_ice(
	config: Config, rng: RandomNumberGenerator, board: PuzzleState, solution: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	if config.ice_chance <= 0.0:
		return result
	var before: Dictionary = _escaped_before(board, solution)
	for hole_cell in before:
		var cap: int = int(before[hole_cell])
		if cap < 1:
			continue
		if rng.randf() >= config.ice_chance:
			continue
		var high: int = cap if config.ice_number_max <= 0 else mini(cap, config.ice_number_max)
		result[hole_cell] = rng.randi_range(1, high)
	return result


# 각 구멍이 처음 흡입에 쓰이기 직전까지 빠진 고양이 수. 최종 풀이를 재생하며 흡입마다 카운트를
# 올린다. 구멍은 흡입될 때 `holes` 에서 지워지므로, 지워진 구멍을 그 순간 카운트로 기록한다.
func _escaped_before(start_state: PuzzleState, solution: Array[Dictionary]) -> Dictionary:
	var work: PuzzleState = start_state.clone()
	var escaped: int = 0
	var before: Dictionary = {}
	for move in solution:
		var holes_before: Array = work.holes.keys()
		var result: Dictionary = work.apply_move(move)
		if bool(result["absorbed"]):
			for hole_cell in holes_before:
				if not work.holes.has(hole_cell):
					before[hole_cell] = escaped
			escaped += 1
	return before


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

	# 장애물에 둘러싸여 플레이 영역에서 도달할 수 없게 된 빈 칸은 마저 장애물로 채운다.
	# 그런 공간은 쓸모가 없는데 플레이어 눈에는 가야 할 곳처럼 보여 혼란만 준다.
	# 채우는 칸도 풀이가 밟지 않는 칸이므로 사후 주입의 안전성 논증이 그대로 성립한다.
	var reachable: Dictionary = touched.duplicate()
	var frontier: Array = touched.keys()
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for dir in DIRS:
			var next: Vector2i = cell + dir
			if reachable.has(next) or chosen.has(next):
				continue
			if next.x < 0 or next.y < 0 or next.x >= config.grid_size.x or next.y >= config.grid_size.y:
				continue
			reachable[next] = true
			frontier.append(next)
	for cell in free_cells:
		if not chosen.has(cell) and not reachable.has(cell):
			chosen[cell] = true

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


# ---------------------------------------------------------------- 여유 칸 제거

# 남은 빈 칸을 하나씩 막아 보고, 막아도 여전히 풀리면 막은 채로 둔다.
#
# `_choose_obstacles()` 는 기록된 풀이가 **밟지 않은** 칸만 막는다. 풀이가 스쳐 지난 넓은
# 통로는 그대로 남고, 그 통로가 곧 "앞 고양이가 안 나가도 돌아 나갈 수 있는" 여유다.
# 여기서는 풀이가 밟는 칸까지 후보로 넣는다. 막아서 못 풀게 되면 진짜 통로였으니 되돌리고,
# 여전히 풀리면 여유였으니 막은 채 둔다. 끝나면 어느 칸을 더 막아도 안 풀리는 판이 된다.
#
# 막은 칸을 밟던 옛 수순은 무효이므로 기록된 풀이를 오토솔버가 새로 찾은 수순으로 갈아탄다.
# 예산 안에 못 찾으면 필요한 칸으로 보고 비워 둔다 — 오탐이 아니라 여유가 덜 깎이는 쪽이다.
#
# ponytail: 빈 칸마다 solve 한 번씩 도는 탐욕법이라 순서에 따라 결과가 달라지고 최소도
# 아니다. 최소 여유가 필요해지면 막힌 칸 조합을 되짚는 탐색으로 올린다.
func _squeeze(
	config: Config,
	rng: RandomNumberGenerator,
	board: PuzzleState,
	solution: Array[Dictionary]
) -> Array[Dictionary]:
	var solver := LevelSolver.new()
	var candidates: Array[Vector2i] = []
	for y in config.grid_size.y:
		for x in config.grid_size.x:
			var cell := Vector2i(x, y)
			if board.is_free_cell(cell):
				candidates.append(cell)
	_shuffle(candidates, rng)

	var kept: Array[Dictionary] = solution
	for cell in candidates:
		board.add_obstacle(cell)
		var solved: Dictionary = solver.solve(board, config.squeeze_node_budget)
		if bool(solved["found"]):
			kept = solved["moves"]
		else:
			board.obstacles.erase(cell)
	return kept


# ---------------------------------------------------------------- 검증

func _verify(
	config: Config,
	rng: RandomNumberGenerator,
	state: PuzzleState,
	solution: Array[Dictionary],
	require_dependency: bool = true
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
	if require_dependency and depth < config.min_chain_depth:
		return {"ok": false, "reason": "의존 사슬 깊이가 %d 뿐이다 (%d 이상 필요)" % [depth, config.min_chain_depth]}

	# 의존 고양이 하한. "최대한 많은 고양이가 잠겨 있어야 한다"의 실측 검사다.
	if require_dependency and config.min_dependent_cats > 0:
		var dependent: Dictionary = {}
		for edge in graph.edge_list():
			dependent[int(edge[0])] = true
		if dependent.size() < config.min_dependent_cats:
			return {
				"ok": false,
				"reason": "의존 고양이가 %d마리뿐이다 (%d마리 이상 필요)" % [
					dependent.size(), config.min_dependent_cats,
				],
			}

	# 첫 탈출 하한. 어떤 수순으로든 "다른 고양이를 치우는 수"가 이보다 적게 첫 흡입이
	# 나오면 버린다. 자기 이동은 드래그 한 번에 몇 칸이든 끌리므로 세지 않는다.
	if config.min_first_escape_moves > 0:
		var clearing: int = solver.clearing_moves_to_first_escape(
			state, config.min_first_escape_moves
		)
		if clearing < config.min_first_escape_moves:
			return {
				"ok": false,
				"reason": "첫 탈출까지 치우는 수가 %d수뿐이다 (%d수 이상 필요)" % [
					clearing, config.min_first_escape_moves,
				],
			}

	var probe: Dictionary = solver.random_play_probe(
		state, config.probe_tries, config.probe_moves, rng, config.solver_node_budget
	)
	if not bool(probe["ok"]):
		return {"ok": false, "reason": "무작위 플레이 후 풀리지 않았다: %s" % probe["reason"]}

	# 초반 탈출 비용 실측. 고양이가 빠질수록 판이 급격히 쉬워지므로 난이도 채점은
	# 사슬 깊이가 아니라 이 값(1·2번째 탈출까지 치우는 드래그 수)을 지배 항으로 쓴다.
	# 상한(limit)을 하한보다 낮게 두면 값이 잘려 무조건 실패하므로 하한까지 올려 준다.
	var early_clearing: Array[int] = solver.early_escape_costs(
		state, 3, maxi(4, config.min_later_escape_moves)
	)
	if config.min_later_escape_moves > 0:
		for index in range(1, early_clearing.size()):
			if early_clearing[index] < config.min_later_escape_moves:
				return {
					"ok": false,
					"reason": "%d번째 탈출까지 치우는 수가 %d수뿐이다 (%d수 이상 필요)" % [
						index + 1, early_clearing[index], config.min_later_escape_moves,
					],
				}

	return {
		"ok": true,
		"graph": graph,
		"solver_moves": (solved["moves"] as Array).size(),
		"solver_nodes": int(solved["nodes"]),
		"early_clearing": early_clearing,
	}


# ---------------------------------------------------------------- 유틸

# 시드가 같으면 결과가 같아야 하므로 `Array.shuffle()`(전역 RNG)을 쓰지 않는다.
func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var swap_with: int = rng.randi_range(0, index)
		var carried = items[index]
		items[index] = items[swap_with]
		items[swap_with] = carried
