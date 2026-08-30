class_name LevelBounds
extends RefCounted

# 레벨의 외곽에서 게임에 한 번도 쓰이지 않는 행·열을 잘라 낸다.
#
# 시작 배치만 보고 자르면 정답 수순이 잠깐 쓰는 외곽 칸을 지울 수 있다. 그래서 고양이·구멍과 기록된
# 풀이의 출발/도착 칸을 전부 포함한 경계 상자를 쓴다. 외곽에만 있는 장애물은 보드 경계가 같은 차단
# 역할을 하므로 경계를 넓히지 않으며, 경계에 걸친 장애물만 남는 보드 안쪽으로 잘라 둔다.
# 좌표를 함께 평행이동하므로, 같은 풀이가 더 작은 보드에서도 그대로 재생된다.
static func trim_unused_border(level: Dictionary) -> Dictionary:
	if not level.has("grid_size"):
		return level
	var grid_size: Vector2i = level["grid_size"]
	if grid_size.x <= 0 or grid_size.y <= 0:
		return level

	var used: Dictionary = {}
	for entry in level.get("holes", []):
		_mark(used, entry.get("grid_pos", Vector2i(-1, -1)), grid_size)
	for cat in level.get("cats", []):
		for cell in cat.get("body_cells", []):
			_mark(used, cell, grid_size)
	for move in level.get("solution", []):
		_mark(used, move.get("from_end_cell", Vector2i(-1, -1)), grid_size)
		_mark(used, move.get("to_cell", Vector2i(-1, -1)), grid_size)

	if used.is_empty():
		return level
	var minimum := Vector2i(grid_size.x - 1, grid_size.y - 1)
	var maximum := Vector2i.ZERO
	for cell_value in used:
		var cell: Vector2i = cell_value
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	if minimum == Vector2i.ZERO and maximum == grid_size - Vector2i.ONE:
		return level

	var original_obstacles: Array = level.get("obstacles", [])
	level["grid_size"] = maximum - minimum + Vector2i.ONE
	for entry in level.get("holes", []):
		entry["grid_pos"] = Vector2i(entry["grid_pos"]) - minimum
	level["obstacles"] = _clip_obstacles(original_obstacles, minimum, maximum)
	for cat in level.get("cats", []):
		var translated_body: Array[Vector2i] = []
		for cell in cat.get("body_cells", []):
			translated_body.append(Vector2i(cell) - minimum)
		cat["body_cells"] = translated_body
	for move in level.get("solution", []):
		move["from_end_cell"] = Vector2i(move["from_end_cell"]) - minimum
		move["to_cell"] = Vector2i(move["to_cell"]) - minimum
	return level


static func _clip_obstacles(entries: Array, minimum: Vector2i, maximum: Vector2i) -> Array:
	var clipped: Array = []
	for entry in entries:
		var origin: Vector2i = entry.get("grid_pos", Vector2i(-1, -1))
		var block_size: Vector2i = entry.get("block_size", Vector2i.ZERO)
		if block_size.x <= 0 or block_size.y <= 0:
			continue
		var end: Vector2i = origin + block_size - Vector2i.ONE
		var start: Vector2i = Vector2i(maxi(origin.x, minimum.x), maxi(origin.y, minimum.y))
		var finish: Vector2i = Vector2i(mini(end.x, maximum.x), mini(end.y, maximum.y))
		if start.x > finish.x or start.y > finish.y:
			continue
		clipped.append({
			"grid_pos": start - minimum,
			"block_size": finish - start + Vector2i.ONE,
		})
	return clipped


static func _mark(used: Dictionary, cell: Vector2i, grid_size: Vector2i) -> void:
	if cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y:
		used[cell] = true
