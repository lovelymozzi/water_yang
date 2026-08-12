class_name LevelSolver
extends RefCounted

# 오토솔버. `PuzzleState` 위에서만 돌고 노드/렌더를 전혀 건드리지 않는다.
#
# ## 데드락이 없다는 것의 근거 (이 솔버의 범위를 정하는 논증)
#
# 1. **한 칸 이동은 항상 되돌릴 수 있다.** 끝 `e` 를 칸 `c` 로 옮긴 뒤 반대쪽 끝을 방금 비운
#    칸으로 옮기면 원래 상태다. 그 칸은 자기가 비운 칸이라 비어 있고, 장애물·구멍일 수 없으며,
#    되돌아간 상태는 원래 흡입이 걸리지 않은 상태였으므로 흡입도 새로 걸리지 않는다.
# 2. **흡입은 되돌릴 수 없지만 칸을 비우기만 한다.** 고양이는 서로에게 장애물일 뿐이므로
#    한 마리가 사라지는 것은 남은 고양이의 풀이를 절대 없애지 않는다.
#
# ⇒ **시작 상태가 풀리면 도달 가능한 모든 상태도 풀린다.** 그래서 이 솔버는 최소 수순을
# 구하지 않는다. 고양이 4마리 × 63칸이면 상태공간이 폭발하는데 데드락 논증이 있으므로 필요도
# 없다. 난이도 지표는 기록된 풀이 길이와 의존 사슬 깊이로 대신한다.
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

	# 시작부터 짝 구멍에 인접한 배치는 흡입되지 않는다(레벨 설계 오류). 솔버가 그 배치를
	# 흡입된 것으로 착각하지 않게 여기서 먼저 걸러 준다.
	if not start.cats_touching_paired_hole().is_empty():
		return {
			"found": false,
			"moves": [],
			"nodes": 0,
			"reason": "시작부터 짝 구멍에 인접한 고양이가 있다: %s" % [start.cats_touching_paired_hole()],
		}

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
		total += state.escape_distance(state.body_of(cat_id), state.color_of(cat_id))
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
		if ignored != cat_id:
			work.remove_cat(ignored)
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
