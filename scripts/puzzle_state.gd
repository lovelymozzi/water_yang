class_name PuzzleState
extends RefCounted

# 노드 없는 퍼즐 규칙 모델. 생성기와 오토솔버가 수만 번 상태를 복제하며 탐색하므로
# FBX·셰이더·스켈레톤을 들고 있는 `CatEntity` 를 그대로 쓸 수 없다.
#
# **이 파일의 유일한 임무는 실제 게임 규칙을 정확히 복제하는 것이다.** 어긋나면
# "생성기는 풀린다는데 게임에서는 안 풀린다"가 된다. 그래서 각 함수 주석에 대응하는
# 원본 함수를 적어 두고, `tests/puzzle_state_parity_check.gd` 가 실제 노드와 대조한다.
#
# 복제한 규칙 (자세한 근거는 2_맵생성기.md):
#   - 새로 점유하는 칸 조건: 보드 안 + 장애물 아님 + 구멍 아님 + 다른 고양이 아님 +
#     자기 몸 아님(뒤끝 포함). `CatEntity.can_enter()` 와 `_can_slide_into()` 가 같은 집합이라
#     전진·후진을 구분할 필요가 없고, 원자 이동은 "두 끝 중 하나를 인접한 빈 칸으로" 하나뿐이다.
#   - 흡입은 방금 움직인 끝(리드)이 짝 색 구멍과 4방향 인접할 때만 걸린다.
#     반대쪽 끝이 스친 것은 흡입이 아니다.
#   - 구멍은 경로가 아니다. 단, 고양이를 다 삼킨 구멍은 함께 닫혀 평범한 빈 칸이 되고
#     그 뒤로는 다른 고양이가 지나갈 수 있다. (`LevelManager._close_hole()` 대응)

const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
# 짝 구멍이 없어 닿을 수 없는 거리. 솔버 휴리스틱이 그쪽을 피하도록 크게 잡는다.
const UNREACHABLE_DISTANCE := 1000

var grid_size: Vector2i = Vector2i(7, 9)
# Vector2i -> true
var obstacles: Dictionary = {}
# Vector2i -> color_id
var holes: Dictionary = {}
# cat_id -> {"color": int, "cells": Array[Vector2i], "nested_colors": Array[int]}.
# nested_colors 는 겉에서 안쪽 순서다. 겉 색이 빠지면 같은 몸으로 다음 색 고양이가 남는다.
# cells[0] 과 cells[-1] 이 두 끝이다.
# 실제 게임의 `body_cells` 는 `_flip_lead()` 가 뒤집으므로 여기서 인덱스 0 이 리드라는 뜻은 아니다.
var cats: Dictionary = {}

# 기믹 확장 지점 (cell -> 규칙 배열). 지금은 항상 비어 있다.
#
# ⚠️ 기믹을 나중에 만들 때 반드시 지킬 것: **기믹은 역설계 루프 안에서 함께 되돌려야 한다.**
# 역설계가 끝난 맵에 기믹을 사후 주입하면 기록된 풀이가 무효가 되어 풀이 없는 맵이 될 수 있다.
# 장애물만 사후 주입이 안전한 이유는 "칸을 뺏는 순수 감산"이라 풀이가 밟지 않는 칸에만 놓으면
# 기록된 수순이 그대로 유효하기 때문이다. 상태를 바꾸는 기믹에는 그 논증이 성립하지 않는다.
var gimmicks: Dictionary = {}

# 얼음 기믹. cell -> 이 구멍이 열리기까지 필요한 누적 탈출 수. 잠긴 구멍에는 흡입이 걸리지
# 않는다. (`LevelManager._hole_ice_counts` / `is_hole_locked()` 대응)
#
# 얼음은 위 경고의 예외다. 잠금은 **탈출 수에 대해 단조로만 풀리므로**(`escaped_count` 는
# 단조 증가, 잠금은 한 번 풀리면 다시 안 잠긴다) 흡입과 마찬가지로 "칸을 여는 순수 감산"이고,
# 따라서 솔버의 데드락 없음 논증이 그대로 성립한다. 사후 주입이 안전한 조건은 하나뿐이다:
# **숫자 ≤ 그 구멍이 기록된 풀이에서 쓰이기 직전까지의 탈출 수**. `MapGenerator._assign_ice()`.
var ice: Dictionary = {}
# 지금까지 빠진 고양이 수. 얼음 해제 판정에만 쓴다 (`LevelManager._escaped_count`).
var escaped_count: int = 0

# 점유 역인덱스. Vector2i -> cat_id. 매 이동마다 전체 순회를 하지 않기 위한 캐시다.
var _occupancy: Dictionary = {}


static func create(size: Vector2i) -> PuzzleState:
	var state := PuzzleState.new()
	state.grid_size = size
	return state


# ---------------------------------------------------------------- 배치

func add_obstacle(cell: Vector2i) -> void:
	obstacles[cell] = true


func add_hole(cell: Vector2i, color_id: int) -> void:
	holes[cell] = color_id


func add_ice(cell: Vector2i, count: int) -> void:
	if count > 0:
		ice[cell] = count


func add_cat(
	cat_id: int, color_id: int, cells: Array[Vector2i], nested_colors: Array[int] = []
) -> void:
	cats[cat_id] = {
		"color": color_id,
		"cells": cells.duplicate(),
		"nested_colors": nested_colors.duplicate(),
	}
	for cell in cells:
		_occupancy[cell] = cat_id


func remove_cat(cat_id: int) -> void:
	if not cats.has(cat_id):
		return
	for cell in cats[cat_id]["cells"]:
		_occupancy.erase(cell)
	cats.erase(cat_id)


func cat_ids() -> Array:
	var ids: Array = cats.keys()
	ids.sort()
	return ids


func body_of(cat_id: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if cats.has(cat_id):
		cells.assign(cats[cat_id]["cells"])
	return cells


func color_of(cat_id: int) -> int:
	return int(cats[cat_id]["color"]) if cats.has(cat_id) else -1


func nested_colors_of(cat_id: int) -> Array[int]:
	var colors: Array[int] = []
	if cats.has(cat_id):
		colors.assign(cats[cat_id].get("nested_colors", []))
	return colors


func set_cat_nested_colors(cat_id: int, colors: Array[int]) -> void:
	if cats.has(cat_id):
		cats[cat_id]["nested_colors"] = colors.duplicate()


# 몸을 통째로 갈아 끼운다. 한 마리만 움직이는 탐색(`LevelSolver.can_escape_alone()`)에서
# 상태를 매번 복제하지 않기 위한 창구다. 점유 역인덱스를 함께 맞춘다.
func set_cat_body(cat_id: int, cells: Array[Vector2i]) -> void:
	if not cats.has(cat_id):
		return
	for cell in cats[cat_id]["cells"]:
		_occupancy.erase(cell)
	cats[cat_id]["cells"] = cells.duplicate()
	for cell in cells:
		_occupancy[cell] = cat_id


# 몸의 두 끝. 흡입 판정과 이동 생성이 모두 "두 끝"만 보므로 그 목록을 여기 한 곳에서 낸다.
# 1칸 몸은 두 끝이 같은 칸이다.
static func ends_of(cells: Array) -> Array[Vector2i]:
	var ends: Array[Vector2i] = []
	if cells.is_empty():
		return ends
	ends.append(cells[0])
	if cells.size() > 1:
		ends.append(cells[cells.size() - 1])
	return ends


# 끝 `from_end_cell` 을 `to_cell` 로 옮긴 뒤의 몸. 끝이 아니면 빈 배열이다.
# 반대쪽 끝이 한 칸 빠지므로 몸 길이는 항상 그대로다.
static func body_after(
	cells: Array, from_end_cell: Vector2i, to_cell: Vector2i
) -> Array[Vector2i]:
	var next_cells: Array[Vector2i] = []
	if cells.is_empty():
		return next_cells
	if cells[0] == from_end_cell:
		next_cells.append(to_cell)
		next_cells.append_array(cells.slice(0, cells.size() - 1))
	elif cells[cells.size() - 1] == from_end_cell:
		next_cells.assign(cells.slice(1))
		next_cells.append(to_cell)
	return next_cells


# ---------------------------------------------------------------- 조회 (LevelManager 대응)

# `LevelManager.is_inside_grid()`
func is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_size.x and cell.y >= 0 and cell.y < grid_size.y


func is_hole(cell: Vector2i) -> bool:
	return holes.has(cell)


# `LevelManager.get_hole_color_id()`
func hole_color(cell: Vector2i) -> int:
	return int(holes[cell]) if holes.has(cell) else -1


# `LevelManager.color_ids_pair()`. 한쪽이 와일드카드(-1)면 아무 색과도 짝이다.
static func color_ids_pair(cat_color_id: int, hole_color_id: int) -> bool:
	if cat_color_id < 0 or hole_color_id < 0:
		return true
	return cat_color_id == hole_color_id


# 얼음으로 아직 잠겨 있는 구멍인지. `LevelManager.is_hole_locked()`.
func is_hole_locked(cell: Vector2i) -> bool:
	return int(ice.get(cell, 0)) > escaped_count


# `LevelManager.adjacent_hole()`. 4방향만 본다. 대각선은 걸리지 않는다.
# 얼음으로 잠긴 구멍은 없는 것으로 본다 — 실제 게임의 `adjacent_hole()` 과 같은 규칙이다.
func adjacent_paired_hole(cell: Vector2i, color_id: int) -> Variant:
	for dir in DIRS:
		var neighbour: Vector2i = cell + dir
		if not is_hole(neighbour):
			continue
		if is_hole_locked(neighbour):
			continue
		if not color_ids_pair(color_id, hole_color(neighbour)):
			continue
		return neighbour
	return null


# `LevelManager.is_cell_blocked_for()`. 자기 몸은 여기서 보지 않는다.
func is_blocked_for(cat_id: int, cell: Vector2i) -> bool:
	if not is_inside(cell):
		return true
	if obstacles.has(cell):
		return true
	# 구멍은 경로로 쓰지 않는다. 흡입은 인접 판정으로만 일어난다.
	if holes.has(cell):
		return true
	var owner_id: Variant = _occupancy.get(cell)
	return owner_id != null and int(owner_id) != cat_id


# `CatEntity.can_enter()` == `CatEntity._can_slide_into()`. 뒤끝 칸도 막힌다.
func can_enter(cat_id: int, cell: Vector2i) -> bool:
	if is_blocked_for(cat_id, cell):
		return false
	return not (cats.has(cat_id) and (cats[cat_id]["cells"] as Array).has(cell))


# 어떤 고양이도 놓일 수 없는 칸인지. 역설계에서 "빈 칸" 판정에 쓴다.
func is_free_cell(cell: Vector2i) -> bool:
	if not is_inside(cell):
		return false
	return not obstacles.has(cell) and not holes.has(cell) and not _occupancy.has(cell)


func is_solved() -> bool:
	return cats.is_empty()


# 이 몸이 지금 흡입되는 자세인지. **흡입에 관한 판정은 전부 이 함수 하나를 거친다** —
# 실제 흡입 처리, 시작 배치 검증, 역설계의 조기 흡입 가드, 솔버의 목표 판정이 모두 같은
# 기준을 써야 한다. 갈라지면 생성기와 게임이 다른 규칙으로 도는 것이다.
func body_touches_paired_hole(cells: Array, color_id: int) -> bool:
	for end_cell in ends_of(cells):
		if adjacent_paired_hole(end_cell, color_id) != null:
			return true
	return false


# 이 몸이 짝 구멍 옆칸까지 가야 하는 남은 칸 수. 흡입은 인접하면 걸리므로 맨해튼 거리 - 1 이다.
# 짝 구멍이 없으면 나갈 수 없으므로 큰 값을 낸다(솔버 휴리스틱이 그쪽을 피한다).
# **얼음은 일부러 무시한다** — 잠긴 구멍까지 1000 으로 치면 얼음이 풀리기 전 모든 상태의 h 가
# 같아져 A* 가 방향을 잃는다. 낙관적으로 재는 편이 탐색에 낫고, 목표 판정은 어차피 실제 흡입
# 규칙(`adjacent_paired_hole`)이 한다.
func escape_distance(cells: Array, color_id: int) -> int:
	var best: int = UNREACHABLE_DISTANCE
	for hole_cell in holes:
		if not color_ids_pair(color_id, hole_color(hole_cell)):
			continue
		for end_cell in ends_of(cells):
			var distance: int = (
				absi(end_cell.x - hole_cell.x) + absi(end_cell.y - hole_cell.y) - 1
			)
			best = mini(best, maxi(distance, 0))
	return best


# 장애물 한 덩어리(`{grid_pos, block_size}`)가 덮는 칸. `ObstacleMarker.get_cells()` 와 같은
# 규칙이며(좌상단에서 +x, +y 로 뻗는다), 생성기와 출력기가 이 함수 하나를 쓴다.
static func cells_of_block(block: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var origin: Vector2i = block["grid_pos"]
	var size: Vector2i = block["block_size"]
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	return cells


# ---------------------------------------------------------------- 이동

# 원자 이동은 "두 끝 중 하나를 인접한 빈 칸으로" 하나뿐이다.
#
# 이동을 끝 인덱스(0/1)가 아니라 **칸**으로 표현하는 것이 중요하다. 실제 게임은
# `_flip_lead()` 가 `body_cells` 를 뒤집으므로 인덱스로 기록하면 재생 때 어긋난다.
func moves_for(cat_id: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	if not cats.has(cat_id):
		return moves
	var cells: Array = cats[cat_id]["cells"]
	if cells.size() < 2:
		return moves
	for end_cell in ends_of(cells):
		for dir in DIRS:
			var target: Vector2i = end_cell + dir
			if not can_enter(cat_id, target):
				continue
			moves.append({
				"cat_id": cat_id,
				"from_end_cell": end_cell,
				"to_cell": target,
			})
	return moves


func legal_moves() -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	for cat_id in cat_ids():
		moves.append_array(moves_for(cat_id))
	return moves


# 몸을 한 칸 밀고 흡입을 해소한다. 반환값은 {"moved": bool, "absorbed": bool}.
func apply_move(move: Dictionary) -> Dictionary:
	var cat_id: int = int(move["cat_id"])
	if not cats.has(cat_id):
		return {"moved": false, "absorbed": false}

	var cells: Array = cats[cat_id]["cells"]
	var from_end_cell: Vector2i = move["from_end_cell"]
	var to_cell: Vector2i = move["to_cell"]
	if not can_enter(cat_id, to_cell):
		return {"moved": false, "absorbed": false}

	var next_cells: Array[Vector2i] = body_after(cells, from_end_cell, to_cell)
	if next_cells.is_empty():
		# 끝이 아닌 칸을 움직이라는 요청이다. 기록이 어긋난 것이므로 조용히 넘기지 않는다.
		push_error("PuzzleState: %s 는 고양이 %d 의 끝이 아니다 (%s)" % [from_end_cell, cat_id, cells])
		return {"moved": false, "absorbed": false}

	for cell in cells:
		_occupancy.erase(cell)
	for cell in next_cells:
		_occupancy[cell] = cat_id
	cats[cat_id]["cells"] = next_cells

	# 기믹 훅. 지금은 아무것도 하지 않는다. 위 `gimmicks` 주석의 경고를 함께 볼 것.
	_apply_gimmicks_on_commit(cat_id)

	# 흡입 판정은 셀 중앙에서 커밋하는 이 순간에만 한다(`CatEntity._finish_step()`).
	# 움직인 고양이만 보면 된다. 고양이가 사라지는 것은 칸을 비우기만 하므로 다른 고양이의
	# 인접 관계를 새로 만들지 않는다.
	var absorbed: bool = _resolve_absorption(cat_id, to_cell)
	return {"moved": true, "absorbed": absorbed}


# `CatEntity._try_begin_absorb()`. 흡입은 **방금 움직인 끝**(리드)에서만 걸린다. 이 모델의
# 한 수는 "끝 하나를 잡아 한 칸 끈다"이므로 움직인 끝이 곧 리드다. 반대쪽 끝이 스친 것은
# 흡입이 아니다. 반대쪽 끝이 인접해 있으면 그 끝을 잡는 것만으로 넣을 수 있지만, 모델에는
# "제자리 잡기" 수가 없으므로 솔버는 그 지름길 없이 푼다(보수적).
func _resolve_absorption(cat_id: int, moved_end_cell: Vector2i) -> bool:
	if not cats.has(cat_id):
		return false
	var hole_cell: Variant = adjacent_paired_hole(moved_end_cell, int(cats[cat_id]["color"]))
	if hole_cell != null:
		var escaped_cells: Array[Vector2i] = body_of(cat_id)
		var nested_colors: Array[int] = nested_colors_of(cat_id)
		remove_cat(cat_id)
		# 한 마리 빠질 때마다 모든 얼음의 남은 수가 1 준다 (`LevelManager.on_cat_escaped()`).
		escaped_count += 1
		# 고양이를 다 삼킨 구멍은 함께 닫힌다. 닫힌 자리는 평범한 빈 칸이 되어 다른
		# 고양이가 지나갈 수 있다. `LevelManager._close_hole()` 와 같은 규칙이어야 한다.
		holes.erase(hole_cell)
		# 실제 CatEntity._spawn_inner_cat()와 같다: 겉껍질이 빠진 같은 자리에서 다음 색
		# 고양이가 즉시 점유를 넘겨받는다. 같은 cat_id를 유지하면 저장된 풀이도 계속 이 id를
		# 가리킬 수 있고, 런타임 재현은 Cat_<id>Inner를 찾아 이어서 움직인다.
		if not nested_colors.is_empty():
			var remaining: Array[int] = []
			remaining.assign(nested_colors.slice(1))
			add_cat(cat_id, nested_colors[0], escaped_cells, remaining)
		return true
	return false


# 이 색과 짝인 구멍을 전부 치운다. 의존성 실측(`LevelSolver.can_escape_alone`)이
# "이미 나간 고양이"의 구멍을 닫을 때 쓴다. 색이 고양이:구멍 1:1 이라는 전제가 있다
# (생성기 기본 설정이 보장하며, 색이 겹치는 수제 맵에서는 과하게 치울 수 있다).
func remove_holes_of_color(color_id: int) -> void:
	for cell in holes.keys():
		if int(holes[cell]) == color_id:
			holes.erase(cell)


# 기믹 커밋 훅. 기믹이 생기면 여기서 상태를 바꾸고, **같은 규칙을 MapGenerator 의 역주행에도
# 반대 방향으로 넣어야 한다.** 한쪽만 넣으면 생성기가 만든 풀이가 게임에서 재생되지 않는다.
func _apply_gimmicks_on_commit(_cat_id: int) -> void:
	pass


# 어느 끝이든 짝 구멍에 인접한 고양이 목록. 시작 배치 검증에 쓴다.
# `DEVELOPMENT_RULES.md` — 레벨 시작부터 인접한 배치는 흡입되지 않으며 설계 오류로 본다.
func cats_touching_paired_hole() -> Array[int]:
	var touching: Array[int] = []
	for cat_id in cat_ids():
		if body_touches_paired_hole(cats[cat_id]["cells"], int(cats[cat_id]["color"])):
			touching.append(cat_id)
	return touching


# ---------------------------------------------------------------- 복제와 해시

func clone() -> PuzzleState:
	var copy := PuzzleState.new()
	copy.grid_size = grid_size
	# 보드도 복제한다. 공유하면 사본에 장애물을 하나 더 놓는 순간 원본까지 바뀐다.
	copy.obstacles = obstacles.duplicate()
	copy.holes = holes.duplicate()
	copy.gimmicks = gimmicks.duplicate()
	copy.ice = ice.duplicate()
	copy.escaped_count = escaped_count
	copy.cats = {}
	for cat_id in cats:
		copy.cats[cat_id] = {
			"color": cats[cat_id]["color"],
			"cells": (cats[cat_id]["cells"] as Array).duplicate(),
			"nested_colors": (cats[cat_id].get("nested_colors", []) as Array).duplicate(),
		}
	copy._occupancy = _occupancy.duplicate()
	return copy


# 몸 하나의 정규 키. 뒤집은 몸은 물리적으로 같은 배치이므로 두 표현 중 사전순으로 작은 쪽을
# 쓴다. **이 정규화가 없으면 같은 상태를 두 번 탐색한다.** 전치 테이블과 한 마리 BFS 가 같은
# 함수를 쓴다.
static func body_key(cells: Array) -> String:
	var forward: String = _cells_to_string(cells)
	var reversed_cells: Array = cells.duplicate()
	reversed_cells.reverse()
	var backward: String = _cells_to_string(reversed_cells)
	return forward if forward <= backward else backward


# 판 전체의 정규 키. 얼음 상태는 넣지 않는다 — 같은 뿌리에서 뻗은 상태끼리는 남은 고양이
# 집합이 곧 탈출 수라 `escaped_count` 가 여기서 유도된다.
func key() -> String:
	var parts: Array[String] = []
	for cat_id in cat_ids():
		parts.append("%d:%d:%s:%s" % [
			cat_id,
			int(cats[cat_id]["color"]),
			body_key(cats[cat_id]["cells"]),
			cats[cat_id].get("nested_colors", []),
		])
	return "|".join(parts)


static func _cells_to_string(cells: Array) -> String:
	var text: String = ""
	for cell in cells:
		text += "%d,%d;" % [cell.x, cell.y]
	return text


# ---------------------------------------------------------------- 검증

# 시작 배치가 규칙을 지키는지. 문제를 사람이 읽을 문장으로 돌려준다.
func start_layout_problems() -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for cat_id in cat_ids():
		var cells: Array = cats[cat_id]["cells"]
		if cells.size() < 2:
			problems.append("고양이 %d 의 몸이 %d칸이다 (최소 2칸)" % [cat_id, cells.size()])
			continue
		for index in cells.size():
			var cell: Vector2i = cells[index]
			if not is_inside(cell):
				problems.append("고양이 %d 의 %s 가 보드 밖이다" % [cat_id, cell])
			if obstacles.has(cell):
				problems.append("고양이 %d 의 %s 가 장애물과 겹친다" % [cat_id, cell])
			if holes.has(cell):
				problems.append("고양이 %d 의 %s 가 구멍 칸이다" % [cat_id, cell])
			if seen.has(cell):
				problems.append("고양이 %d 와 %d 가 %s 에서 겹친다" % [cat_id, int(seen[cell]), cell])
			seen[cell] = cat_id
			if index > 0:
				var step: Vector2i = cell - cells[index - 1]
				if absi(step.x) + absi(step.y) != 1:
					problems.append(
						"고양이 %d 의 몸이 %s → %s 에서 끊겼다" % [cat_id, cells[index - 1], cell]
					)
			if cells.find(cell) != index:
				problems.append("고양이 %d 의 몸이 %s 에서 자기와 교차한다" % [cat_id, cell])
	for cat_id in cats_touching_paired_hole():
		problems.append(
			"고양이 %d 가 시작부터 짝 구멍에 인접해 있다 (레벨 설계 오류)" % cat_id
		)
	return problems
