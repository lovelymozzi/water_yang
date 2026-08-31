class_name LevelSolver
extends RefCounted

# 오토솔버. `PuzzleState` 위에서만 돌고 노드/렌더를 전혀 건드리지 않는다.
#
# ## 데드락이 없다는 것의 근거 (이 솔버의 범위를 정하는 논증)
#
# 1. **한 칸 이동은 항상 되돌릴 수 있다.** 끝 `e` 를 칸 `c` 로 옮긴 뒤 반대쪽 끝을 방금 비운
#    칸으로 옮기면 원래 상태다. 그 칸은 자기가 비운 칸이라 비어 있고, 장애물·구멍일 수 없으며,
#    되돌아간 상태는 원래 흡입이 걸리지 않은 상태였으므로 흡입도 새로 걸리지 않는다.
# 2. **흡입은 되돌릴 수 없지만 칸을 비우기만 한다.** 고양이가 사라지고 그 구멍도 함께
#    닫히는데, 둘 다 막힌 칸을 여는 순수 감산이다. 닫힌 구멍은 그 고양이만 쓰던 것이므로
#    남은 고양이의 풀이를 절대 없애지 않는다.
#
# 3. **얼음은 위 두 항을 깨지 않는다.** 잠금은 `escaped_count` 에만 달렸고 그 값은 단조
#    증가하므로 얼음은 열리기만 한다. 1의 되돌리기는 흡입이 없는 수에만 쓰이므로 잠금 상태를
#    바꾸지 않고, 2는 잠금을 푸는 쪽으로만 움직인다.
#
# ⇒ **시작 상태가 풀리면 도달 가능한 모든 상태도 풀린다.** 그래서 이 솔버는 최소 수순을
# 구하지 않는다. 고양이 4마리 × 63칸이면 상태공간이 폭발하는데 데드락 논증이 있으므로 필요도
# 없다. 난이도는 각 탈출까지 다른 고양이로 손을 옮기는 최소 횟수로 따로 측정한다.
# `random_play_probe()` 는 위 논증의 경험적 뒷받침일 뿐이다.

const DEFAULT_NODE_BUDGET := 40000
# f = g + 가중치 × h. 최적해가 목표가 아니므로 가중치를 크게 줘서 목표 쪽으로 강하게 끈다.
const HEURISTIC_WEIGHT := 4


# 우선순위 큐. 정렬 배열로 매번 넣으면 O(n) 이라 탐색이 죽는다.
class MinHeap:
	extends RefCounted

	var _data: Array = []

	func size() -> int:
		return _data.size()

	func is_empty() -> bool:
		return _data.is_empty()

	# 같은 우선순위에서는 늦게 넣은 것을 먼저 꺼낸다(`-sequence`). 깊이 우선 성향이
	# 붙어 목표까지 훨씬 빨리 내려간다.
	func push(priority: int, sequence: int, payload: int) -> void:
		_data.append([priority, -sequence, payload])
		var index: int = _data.size() - 1
		while index > 0:
			var parent: int = (index - 1) / 2
			if _less(_data[index], _data[parent]):
				var swap: Array = _data[parent]
				_data[parent] = _data[index]
				_data[index] = swap
				index = parent
			else:
				break

	func pop() -> int:
		var top: Array = _data[0]
		var last: Array = _data.pop_back()
		if not _data.is_empty():
			_data[0] = last
			var index: int = 0
			while true:
				var left: int = index * 2 + 1
				var right: int = left + 1
				var smallest: int = index
				if left < _data.size() and _less(_data[left], _data[smallest]):
					smallest = left
				if right < _data.size() and _less(_data[right], _data[smallest]):
					smallest = right
				if smallest == index:
					break
				var swap: Array = _data[smallest]
				_data[smallest] = _data[index]
				_data[index] = swap
				index = smallest
		return int(top[2])

	static func _less(a: Array, b: Array) -> bool:
		if int(a[0]) != int(b[0]):
			return int(a[0]) < int(b[0])
		return int(a[1]) < int(b[1])


# 풀이 하나를 찾는다. 최적해가 아니다. 반환값:
#   {"found": bool, "moves": Array[Dictionary], "nodes": int, "reason": String}
func solve(state: PuzzleState, node_budget: int = DEFAULT_NODE_BUDGET) -> Dictionary:
	var start: PuzzleState = state.clone()
	if start.is_solved():
		return {"found": true, "moves": [], "nodes": 0, "reason": "이미 풀린 상태"}

	# 최초 레벨의 인접 배치 오류는 PuzzleState.start_layout_problems() 가 검사한다. solve()는
	# 무작위 플레이 뒤의 중간 상태에도 쓰이므로 여기서 같은 검사를 하면, 움직이지 않은 반대쪽
	# 끝이 구멍 옆을 스친 정상 상태까지 "잘못된 시작 배치"로 거부하게 된다.

	# 노드마다 {state, g, parent, move} 를 담는다. 경로는 parent 로 되짚는다.
	var nodes: Array = [{"state": start, "g": 0, "parent": -1, "move": {}}]
	var visited: Dictionary = {start.key(): 0}
	var heap := MinHeap.new()
	var sequence: int = 0
	heap.push(_heuristic(start), sequence, 0)

	var expanded: int = 0
	while not heap.is_empty():
		if expanded >= node_budget:
			return {
				"found": false,
				"moves": [],
				"nodes": expanded,
				"reason": "노드 예산 %d 를 넘겼다" % node_budget,
			}
		var index: int = heap.pop()
		var node: Dictionary = nodes[index]
		var current: PuzzleState = node["state"]
		var g: int = int(node["g"])
		expanded += 1

		for move in _ordered_moves(current):
			var next_state: PuzzleState = current.clone()
			var result: Dictionary = next_state.apply_move(move)
			if not bool(result["moved"]):
				continue
			if next_state.is_solved():
				nodes.append({"state": next_state, "g": g + 1, "parent": index, "move": move})
				return {
					"found": true,
					"moves": _rebuild_moves(nodes, nodes.size() - 1),
					"nodes": expanded,
					"reason": "",
				}
			var next_key: String = next_state.key()
			var seen: Variant = visited.get(next_key)
			if seen != null and int(seen) <= g + 1:
				continue
			visited[next_key] = g + 1
			nodes.append({"state": next_state, "g": g + 1, "parent": index, "move": move})
			sequence += 1
			heap.push(
				g + 1 + HEURISTIC_WEIGHT * _heuristic(next_state), sequence, nodes.size() - 1
			)

	return {"found": false, "moves": [], "nodes": expanded, "reason": "탐색이 고갈됐다"}


func _rebuild_moves(nodes: Array, index: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var current: int = index
	while current > 0:
		var node: Dictionary = nodes[current]
		moves.push_front(node["move"])
		current = int(node["parent"])
	return moves


# 남은 고양이가 각자 짝 구멍 옆칸까지 가야 하는 거리의 합. 거리 계산은
# `PuzzleState.escape_distance()` 하나만 쓴다.
func _heuristic(state: PuzzleState) -> int:
	var total: int = 0
	for cat_id in state.cat_ids():
		var color: int = state.color_of(cat_id)
		total += state.escape_distance(state.body_of(cat_id), color)
		# 중첩 레이어를 빼면 3중첩 판에서 h 가 실제 거리의 1/3 이 되어 A* 가 다익스트라로
		# 무너진다(실측: 4마리 3중첩이 노드 예산 40000 을 60초씩 태우고 전부 실패).
		# 안쪽 고양이는 겉 구멍 옆에서 시작해 자기 구멍까지 다시 걸으므로 그 몫을 더한다.
		for next_color in state.nested_colors_of(cat_id):
			total += state.hole_gap(color, next_color)
			color = next_color
	return total


# 탈출 쪽으로 가까워지는 수를 먼저 펼친다. 기록된 풀이가 존재하므로 이 정렬만으로 충분히 빠르다.
func _ordered_moves(state: PuzzleState) -> Array[Dictionary]:
	var scored: Array = []
	for move in state.legal_moves():
		var cat_id: int = int(move["cat_id"])
		var next_cells: Array[Vector2i] = PuzzleState.body_after(
			state.body_of(cat_id), move["from_end_cell"], move["to_cell"]
		)
		if next_cells.is_empty():
			continue
		scored.append([state.escape_distance(next_cells, state.color_of(cat_id)), move])
	scored.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var ordered: Array[Dictionary] = []
	for entry in scored:
		ordered.append(entry[1])
	return ordered


# ---------------------------------------------------------------- 의존성 실측

# 다른 고양이를 전부 제자리에 고정한 채 이 고양이 혼자 탈출할 수 있는지. `ignored_ids` 에
# 넣은 고양이는 이미 나간 것으로 본다.
#
# 한 마리만 움직이므로 상태공간이 "그 고양이의 몸 배치" 뿐이다(길이 3~4면 수천 개).
# **A → B → C 가 진짜 강제되는지의 근거가 이 함수다.** u 가 혼자서는 못 나가는데 v 를 빼면
# 나갈 수 있다면 간선 u → v 는 실측된 것이다.
func can_escape_alone(
	state: PuzzleState, cat_id: int, ignored_ids: Array[int] = []
) -> bool:
	var work: PuzzleState = state.clone()
	for ignored in ignored_ids:
		if ignored != cat_id and work.cats.has(ignored):
			var ignored_color: int = work.color_of(ignored)
			work.remove_cat(ignored)
			# 이미 나간 고양이의 구멍은 닫혀 빈 칸이 된 상태다. 이것을 빼먹으면
			# "닫힌 구멍 자리를 지나야만 나갈 수 있는" 의존성을 실측하지 못한다.
			work.remove_holes_of_color(ignored_color)
			# 나간 만큼 얼음도 녹아 있어야 한다. 이 한 줄이 얼음 의존성("N마리 빠질 때까지
			# 이 구멍은 안 열린다")을 실측 가능하게 만든다.
			work.escaped_count += 1
	if not work.cats.has(cat_id):
		# 이미 나간 고양이는 탈출 가능으로 본다.
		return true

	var color_id: int = work.color_of(cat_id)
	var start_body: Array[Vector2i] = work.body_of(cat_id)
	if work.body_touches_paired_hole(start_body, color_id):
		# 시작부터 인접 = 레벨 설계 오류지만, 탈출 가능 여부만 묻는 질문에는 참이다.
		return true

	var visited: Dictionary = {PuzzleState.body_key(start_body): true}
	var queue: Array = [start_body]
	while not queue.is_empty():
		var body: Array[Vector2i] = queue.pop_front()
		work.set_cat_body(cat_id, body)
		for move in work.moves_for(cat_id):
			var next_body: Array[Vector2i] = PuzzleState.body_after(
				body, move["from_end_cell"], move["to_cell"]
			)
			if next_body.is_empty():
				continue
			if work.body_touches_paired_hole(next_body, color_id):
				return true
			var next_key: String = PuzzleState.body_key(next_body)
			if visited.has(next_key):
				continue
			visited[next_key] = true
			queue.append(next_body)
	return false


# 계획된 탈출 순서를 근거로 실측 의존성 그래프를 만든다.
#
# σ_k 가 움직이는 시점의 판은 "σ_0..σ_{k-1} 은 사라졌고 σ_{k+1}.. 은 아직 제자리"다.
# 그 판에서 σ_j(j<k) 하나만 되돌려 놓았을 때 σ_k 가 못 나가면 간선 σ_k → σ_j 다.
func build_dependency_graph(
	state: PuzzleState, escape_order: Array[int]
) -> LevelDependencyGraph:
	var graph := LevelDependencyGraph.new()
	for cat_id in escape_order:
		graph.add_node(cat_id)

	for order_index in escape_order.size():
		var cat_id: int = escape_order[order_index]
		var gone: Array[int] = []
		for earlier in range(order_index):
			gone.append(escape_order[earlier])
		# 앞 순번이 다 나간 판에서는 나갈 수 있어야 한다. 아니면 계획 자체가 깨진 것이다.
		if not can_escape_alone(state, cat_id, gone):
			continue
		for blocker in gone:
			var kept: Array[int] = []
			for other in gone:
				if other != blocker:
					kept.append(other)
			# blocker 하나만 제자리로 돌려놓았을 때 못 나가면 그 blocker 가 진짜 장애물이다.
			if not can_escape_alone(state, cat_id, kept):
				graph.add_edge(cat_id, blocker)
	return graph


# 혼자(다른 고양이 전부 제자리) 탈출할 수 있으면 그 탈출이 쓸고 지나가는 칸 전부를,
# 못 하면 빈 Dictionary 를 돌려준다. 첫 탈출 가로막이가 "실제로 새는 길" 위에 벽을
# 세울 때 쓴다 — 기록된 풀이 경로만 막으면 BFS 가 샛길로 빠져나간다.
func solo_escape_route(state: PuzzleState, cat_id: int) -> Dictionary:
	var work: PuzzleState = state.clone()
	if not work.cats.has(cat_id):
		return {}
	var color_id: int = work.color_of(cat_id)
	var start_body: Array[Vector2i] = work.body_of(cat_id)
	if work.body_touches_paired_hole(start_body, color_id):
		return _cells_union([start_body])

	var bodies: Array = [start_body]
	var parents: Array[int] = [-1]
	var visited: Dictionary = {PuzzleState.body_key(start_body): true}
	var head: int = 0
	while head < bodies.size():
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
			if work.body_touches_paired_hole(next_body, color_id):
				# 흡입 자세에서 시작 자세까지 부모 사슬을 되짚어 쓸고 간 칸을 모은다.
				var chain: Array = [next_body]
				var cursor: int = head
				while cursor >= 0:
					chain.append(bodies[cursor])
					cursor = parents[cursor]
				return _cells_union(chain)
			visited[next_key] = true
			bodies.append(next_body)
			parents.append(head)
		head += 1
	return {}


static func _cells_union(bodies: Array) -> Dictionary:
	var cells: Dictionary = {}
	for body in bodies:
		for cell in body:
			cells[cell] = true
	return cells


# ---------------------------------------------------------------- 첫 탈출까지 치우는 수

# 첫 흡입까지 "치워야 하는" 최소 드래그 수. 탈출하는 고양이 자신의 이동과, 방금 끌던
# 고양이를 이어서 끄는 것(드래그 지속)은 세지 않는다 — 게임은 드래그 한 번으로 몇 칸이든
# 어떤 모양으로든 끌 수 있으므로, **다른 고양이로 손을 옮기는 횟수**만이 체감 난이도다.
#
# 비용 0, 1, ... 순서로 전 고양이를 함께 깊게 만든다. 한 고양이를 limit 끝까지 먼저 훑으면
# 뒤 ID 고양이가 0수에 바로 나가는데도 앞 ID 고양이의 거대한 상태공간을 먼저 소진한다.
# 모든 고양이가 공유하는 node_budget 안에서 드래그 < limit 인 최소값만 찾는다.
func clearing_moves_to_first_escape(
	state: PuzzleState, limit: int, node_budget: int = DEFAULT_NODE_BUDGET
) -> int:
	var witness: Dictionary = first_escape_witness(state, limit, node_budget)
	return int(witness["clearing"]) if bool(witness["complete"]) else -1


# 가장 싼 첫 탈출의 목격 수순. complete=false 는 예산 안에서 최소값을 증명하지 못했다는 뜻이다.
# 예산 초과를 "limit 이상"으로 둔갑시키면 느린 판이 어려운 판으로 오채점되므로 구분한다.
func first_escape_witness(
	state: PuzzleState, limit: int, node_budget: int = DEFAULT_NODE_BUDGET
) -> Dictionary:
	if limit <= 0:
		return {"clearing": 0, "cat_id": -1, "moves": [], "complete": true, "nodes": 0}
	var remaining_budget: int = maxi(node_budget, 0)
	var expanded_total: int = 0
	# probe_limit=1 은 비용 0만, 2는 비용 0~1만 본다. 앞 단계에서 더 싼 탈출이 없음을
	# 전 고양이에 대해 증명했으므로 이번 단계에서 처음 찾은 수순이 전역 최소다.
	for probe_limit in range(1, limit + 1):
		for cat_id in state.cat_ids():
			if remaining_budget <= 0:
				return {
					"clearing": limit, "cat_id": -1, "moves": [],
					"complete": false, "nodes": expanded_total,
				}
			var probe: Dictionary = _clearing_moves_for(
				state, int(cat_id), probe_limit, remaining_budget
			)
			var expanded: int = int(probe["nodes"])
			expanded_total += expanded
			remaining_budget -= expanded
			if not bool(probe["complete"]):
				return {
					"clearing": limit, "cat_id": -1, "moves": [],
					"complete": false, "nodes": expanded_total,
				}
			if int(probe["clearing"]) < probe_limit:
				return {
					"clearing": int(probe["clearing"]),
					"cat_id": int(cat_id),
					"moves": probe["moves"],
					"complete": true,
					"nodes": expanded_total,
				}
	return {
		"clearing": limit, "cat_id": -1, "moves": [],
		"complete": true, "nodes": expanded_total,
	}


func _clearing_moves_for(
	state: PuzzleState, cat_id: int, limit: int, node_budget: int
) -> Dictionary:
	if limit <= 0:
		return {"clearing": 0, "moves": [], "complete": true, "nodes": 0}
	var start: PuzzleState = state.clone()
	# 노드: {state, last(마지막으로 움직인 고양이, -1=없음), parent, move}. 수순 복원용.
	var nodes: Array = [{"state": start, "last": -1, "parent": -1, "move": {}}]
	var visited: Dictionary = {_drag_key(start, -1): true}
	var frontier: Array = [0]
	var expanded: int = 0

	for cost in limit:
		# 비용 0 층: cat_id 자신의 수 + 직전에 끌던 고양이를 이어 끄는 수.
		var closure: Array = []
		while not frontier.is_empty():
			var index: int = frontier.pop_back()
			closure.append(index)
			if expanded >= node_budget:
				return {"clearing": limit, "moves": [], "complete": false, "nodes": expanded}
			expanded += 1
			var node: Dictionary = nodes[index]
			var current: PuzzleState = node["state"]
			var last: int = int(node["last"])
			# 비용 0인 고양이만 생성한다. legal_moves() 전부를 만든 뒤 버리면 매 노드마다
			# 움직이지도 않을 나머지 고양이까지 순회한다.
			var free_moves: Array[Dictionary] = current.moves_for(cat_id)
			if last >= 0 and last != cat_id:
				free_moves.append_array(current.moves_for(last))
			for move in free_moves:
				var mover: int = int(move["cat_id"])
				var next_state: PuzzleState = current.clone()
				var result: Dictionary = next_state.apply_move(move)
				if not bool(result["moved"]):
					continue
				if bool(result["absorbed"]):
					if mover == cat_id:
						nodes.append({"state": next_state, "last": mover, "parent": index, "move": move})
						return {
							"clearing": cost, "moves": _rebuild_moves(nodes, nodes.size() - 1),
							"complete": true, "nodes": expanded,
						}
					# 다른 고양이 먼저 빠진 가지는 이미 "cat_id의 첫 탈출" 경로가
					# 아니다. 그 고양이 목표인 탐색이 올바른 비용으로 따로 찾는다.
					continue
				var next_key: String = _drag_key(next_state, mover)
				if visited.has(next_key):
					continue
				visited[next_key] = true
				nodes.append({"state": next_state, "last": mover, "parent": index, "move": move})
				frontier.append(nodes.size() - 1)

		# 비용 +1: 다른 고양이로 손을 옮긴다.
		if cost + 1 >= limit:
			break
		for index in closure:
			var node: Dictionary = nodes[index]
			var current: PuzzleState = node["state"]
			var last: int = int(node["last"])
			for mover_value in current.cat_ids():
				var mover: int = int(mover_value)
				if mover == cat_id or mover == last:
					continue
				for move in current.moves_for(mover):
					var next_state: PuzzleState = current.clone()
					var result: Dictionary = next_state.apply_move(move)
					if not bool(result["moved"]):
						continue
					# 비용 고양이 먼저 탈출했으므로 cat_id의 첫 탈출 가지가 아니다.
					if bool(result["absorbed"]):
						continue
					var next_key: String = _drag_key(next_state, mover)
					if visited.has(next_key):
						continue
					visited[next_key] = true
					nodes.append({"state": next_state, "last": mover, "parent": index, "move": move})
					frontier.append(nodes.size() - 1)
	return {"clearing": limit, "moves": [], "complete": true, "nodes": expanded}


static func _drag_key(state: PuzzleState, last_cat: int) -> String:
	return "%d|%s" % [last_cat, state.key()]


# 앞에서부터 `escapes`마리를 빼내는 데 드는 실측 드래그 수 목록. [첫 탈출 치우기 수,
# 그 직후 상태에서 둘째 탈출 치우기 수, ...]. 각 값은 limit 에서 잘린다.
# 고양이가 빠질수록 몸+구멍만큼 공간이 열려 난이도가 급락하므로, **초반 탈출이 얼마나
# 비싼가**가 판의 실질 난이도다. 난이도 채점이 이 목록을 쓴다.
#
# `escapes = 0` 이면 남은 고양이 전원까지 잰다. 앞 3마리만 재면 뒤쪽이 전부 1드래그인 판과
# 뒤쪽도 비싼 판이 같은 점수를 받아 채점이 구분을 못 한다.
func early_escape_costs(
	state: PuzzleState, escapes: int = 3, limit: int = 4,
	node_budget: int = DEFAULT_NODE_BUDGET
) -> Array[int]:
	var costs: Array[int] = []
	var work: PuzzleState = state.clone()
	var escape_count: int = escapes
	if escape_count <= 0:
		escape_count = state.cats.size()
		for cat_id in state.cat_ids():
			escape_count += state.nested_colors_of(int(cat_id)).size()
	for index in escape_count:
		if work.cats.is_empty():
			break
		# **뒤로 갈수록 상한을 함께 줄인다.** 상한이 곧 0-1 BFS 의 깊이라 비용이 상한에
		# 지수로 붙는데, 채점 가중치는 `DIFFICULTY_DECAY` 로 감쇠하므로 5번째 탈출의
		# 1드래그 차이는 점수에 0.2 밖에 기여하지 않는다. 정밀하게 잴 값이 아니다.
		# (전 탈출을 상한 8 로 재면 생성이 수십 배 느려져 실용적이지 않다.)
		var step_limit: int = maxi(
			1, int(round(float(limit) * pow(DIFFICULTY_DECAY, float(index))))
		)
		var witness: Dictionary = first_escape_witness(work, step_limit, node_budget)
		if not bool(witness["complete"]):
			costs.append(-1)
			break
		costs.append(int(witness["clearing"]))
		if int(witness["cat_id"]) < 0:
			break  # limit 안에 탈출이 없다 — 뒤는 더 비싸므로 여기서 그친다.
		for move in (witness["moves"] as Array):
			work.apply_move(move)
	return costs


# 난이도 점수. `early_escape_costs()` 벡터 하나에서 뽑는다 — 이게 유일한 채점 기준이다.
#
# **의존 사슬 깊이(`chain_depth`)는 쓰지 않는다.** 그 값은 "나머지 고양이가 전원 시작 자리에
# 얼어 있다"는 가정에서 재므로 실제 플레이와 상관이 없다(생성된 52스테이지 실측 상관 0.24).
# 반면 이 벡터는 실제 판에서 손을 몇 번 옮겨야 한 마리가 빠지는가라 체감 난이도 그 자체다.
#
# 뒤로 갈수록 가중치를 `DIFFICULTY_DECAY` 배로 깎는다. 한 마리가 빠질 때마다 몸+구멍만큼
# 칸이 열려 판이 급격히 헐렁해지므로(실측: 빈 칸 3 → 10 → 17 → 24), 같은 드래그 수라도
# 초반 것이 훨씬 어렵다.
#
# ponytail: 감쇠율 0.7 과 ×10 스케일은 휴리스틱이다. 플레이 데이터가 쌓이면 클리어율로 교정한다.
const DIFFICULTY_DECAY := 0.7


static func difficulty_score(costs: Array) -> int:
	var total: float = 0.0
	var weight: float = 1.0
	for cost in costs:
		if int(cost) < 0:
			return -1
		total += float(cost) * weight
		weight *= DIFFICULTY_DECAY
	return int(round(total * 10.0))


static func stored_difficulty_score(stats: Dictionary) -> int:
	return int(stats["difficulty_score"]) if stats.has("difficulty_score") \
		else difficulty_score(stats.get("early_clearing", []))


# 탈출 순서 외에도 시작 시점의 여유 공간과 긴 몸 제약을 같은 기준으로 보정한다.
static func difficulty_breakdown(state: PuzzleState, costs: Array) -> Dictionary:
	var base_score: int = difficulty_score(costs)
	var board_cells: int = state.grid_size.x * state.grid_size.y
	var open_cells: int = 0
	for y in state.grid_size.y:
		for x in state.grid_size.x:
			if state.is_free_cell(Vector2i(x, y)):
				open_cells += 1
	var long_body_excess: int = 0
	var max_body_length: int = 0
	for cat_id in state.cat_ids():
		var length: int = state.body_of(int(cat_id)).size()
		max_body_length = maxi(max_body_length, length)
		long_body_excess += maxi(length - 5, 0)
	var open_ratio: float = float(open_cells) / float(board_cells)
	var space_score: int = roundi(clampf((0.20 - open_ratio) / 0.20, 0.0, 1.0) * 15.0)
	var body_score: int = mini(long_body_excess, 15)
	return {
		"base_score": base_score,
		"open_cells": open_cells,
		"board_cells": board_cells,
		"open_ratio": open_ratio,
		"max_body_length": max_body_length,
		"long_body_excess": long_body_excess,
		"space_score": space_score,
		"body_score": body_score,
		"difficulty_score": -1 if base_score < 0 else base_score + space_score + body_score,
	}


# ---------------------------------------------------------------- 데드락 샘플링

# 무작위로 몇 수 둔 뒤에도 여전히 풀리는지 본다. 위 가역성 논증의 경험적 뒷받침이다.
# 실패하면 그 시드를 그대로 돌려주므로 재현할 수 있다.
func random_play_probe(
	state: PuzzleState,
	tries: int,
	moves_per_try: int,
	rng: RandomNumberGenerator,
	node_budget: int = DEFAULT_NODE_BUDGET
) -> Dictionary:
	for attempt in tries:
		var work: PuzzleState = state.clone()
		var played: Array[Dictionary] = []
		for step in moves_per_try:
			if work.is_solved():
				break
			var moves: Array[Dictionary] = work.legal_moves()
			if moves.is_empty():
				break
			var move: Dictionary = moves[rng.randi_range(0, moves.size() - 1)]
			work.apply_move(move)
			played.append(move)
		if work.is_solved():
			continue
		var result: Dictionary = solve(work, node_budget)
		if not bool(result["found"]):
			return {
				"ok": false,
				"attempt": attempt,
				"played": played,
				"reason": result["reason"],
			}
	return {"ok": true, "attempt": -1, "played": [], "reason": ""}
