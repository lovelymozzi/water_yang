class_name LevelDependencyGraph
extends RefCounted

# 레벨의 탈출 순서 의존성. 간선 `u → v` 는 **"u가 탈출하려면 v가 먼저 나가야 한다"** 는 뜻이다.
#
# 이 퍼즐의 재미는 A → B → C 순서 강제(소프트락)에서 나온다. 손 배치로는 그 의존성이
# 실제로 강제되는지 알 수 없으므로, 생성기가 의도한 간선과 솔버가 실측한 간선을 따로 만들어
# 대조한다. 난이도 지표는 `longest_chain_depth()` 다 (3 이면 A → B → C).
#
# **순환은 곧 소프트락이다.** u → v, v → u 면 둘 다 상대가 먼저 나가기를 기다리므로 아무도
# 나갈 수 없다. 생성기는 순환이 나온 맵을 즉시 버린다.

var nodes: Array[int] = []
# u -> {v: true}
var _edges: Dictionary = {}


func add_node(id: int) -> void:
	if nodes.has(id):
		return
	nodes.append(id)
	nodes.sort()
	_edges[id] = {}


func add_edge(from_id: int, to_id: int) -> void:
	if from_id == to_id:
		return
	add_node(from_id)
	add_node(to_id)
	_edges[from_id][to_id] = true


func has_edge(from_id: int, to_id: int) -> bool:
	return _edges.has(from_id) and _edges[from_id].has(to_id)


func dependencies_of(id: int) -> Array[int]:
	var result: Array[int] = []
	if _edges.has(id):
		for target in _edges[id]:
			result.append(int(target))
	result.sort()
	return result


func edge_list() -> Array:
	var list: Array = []
	for from_id in nodes:
		for to_id in dependencies_of(from_id):
			list.append([from_id, to_id])
	return list


func edge_count() -> int:
	var total: int = 0
	for from_id in _edges:
		total += (_edges[from_id] as Dictionary).size()
	return total


# 의존성을 만족하는 탈출 순서. 순환이 있으면 빈 배열이다 (칸 순서를 정할 수 없다).
# v 가 u 보다 먼저 나와야 하므로, 간선이 없는 노드부터 꺼내는 것이 곧 순서다.
func topological_order() -> Array[int]:
	var remaining: Dictionary = {}
	for id in nodes:
		remaining[id] = dependencies_of(id)

	var order: Array[int] = []
	while not remaining.is_empty():
		var ready: Array[int] = []
		for id in remaining:
			var blocked: bool = false
			for dependency in remaining[id]:
				if remaining.has(dependency):
					blocked = true
					break
			if not blocked:
				ready.append(int(id))
		if ready.is_empty():
			# 남은 노드가 서로를 기다린다 = 순환.
			return []
		ready.sort()
		for id in ready:
			order.append(id)
			remaining.erase(id)
	return order


func has_cycle() -> bool:
	return topological_order().size() != nodes.size()


# 가장 긴 의존 사슬의 **노드 수**. 3 이면 A → B → C 가 강제된다는 뜻이다.
# 순환이 있으면 0 을 돌려준다 (사슬 길이를 말할 수 없는 상태다).
func longest_chain_depth() -> int:
	if has_cycle():
		return 0
	var depth_cache: Dictionary = {}
	var best: int = 0
	for id in nodes:
		best = maxi(best, _depth_from(id, depth_cache))
	return best


func _depth_from(id: int, cache: Dictionary) -> int:
	if cache.has(id):
		return int(cache[id])
	# 순환이 없다는 것을 위에서 확인했으므로 재귀가 끝난다.
	var best: int = 1
	for dependency in dependencies_of(id):
		best = maxi(best, 1 + _depth_from(dependency, cache))
	cache[id] = best
	return best


# 사슬 깊이를 만든 실제 경로 하나. 리포트에 "2 → 1 → 0" 처럼 찍기 위한 것이다.
func longest_chain() -> Array[int]:
	if has_cycle():
		return []
	var best: Array[int] = []
	for id in nodes:
		var chain: Array[int] = _chain_from(id, {})
		if chain.size() > best.size():
			best = chain
	return best


func _chain_from(id: int, visiting: Dictionary) -> Array[int]:
	if visiting.has(id):
		return []
	visiting[id] = true
	var best: Array[int] = []
	for dependency in dependencies_of(id):
		var chain: Array[int] = _chain_from(dependency, visiting)
		if chain.size() > best.size():
			best = chain
	visiting.erase(id)
	var result: Array[int] = [id]
	result.append_array(best)
	return result


func describe() -> String:
	if nodes.is_empty():
		return "의존성 없음 (노드 0개)"
	var lines: Array[String] = []
	for id in nodes:
		var deps: Array[int] = dependencies_of(id)
		if deps.is_empty():
			lines.append("고양이 %d: 의존 없음 (먼저 나갈 수 있다)" % id)
		else:
			lines.append("고양이 %d → %s 가 먼저 나가야 한다" % [id, deps])
	var chain: Array[int] = longest_chain()
	if chain.size() >= 2:
		var arrows: Array[String] = []
		for id in chain:
			arrows.append(str(id))
		lines.append("최장 사슬(깊이 %d): %s" % [chain.size(), " → ".join(arrows)])
	if has_cycle():
		lines.append("⚠️ 순환이 있다 = 아무도 먼저 나갈 수 없다 = 소프트락")
	return "\n".join(lines)
