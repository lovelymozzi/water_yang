extends SceneTree

# 여유 칸 제거(`MapGenerator.Config.squeeze_free_cells`) 검사.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/squeeze_check.gd
#
# 같은 시드로 끄고/켜고 만들어 대조한다. 검사하는 것:
#   1. 켠 쪽이 빈 칸이 더 적다 (여유가 실제로 깎였다)
#   2. 켠 쪽도 기록된 풀이가 그대로 재생되고 다 풀린다 (여유를 깎으면서 풀이를 잃지 않았다)
#   3. 켠 쪽 판에서 빈 칸을 아무거나 하나 더 막으면 오토솔버가 못 푼다 (남은 칸은 다 통로다)
# 3번이 "1칸의 여유도 없다"의 직접 확인이다.

const SEED_COUNT := 4
const STRIDE := 100003

var _failures: Array[String] = []


func _initialize() -> void:
	var generator := MapGenerator.new()
	var solver := LevelSolver.new()
	var loose_free: int = 0
	var tight_free: int = 0
	var loose_early: Array[int] = [0, 0, 0]
	var tight_early: Array[int] = [0, 0, 0]
	var made: int = 0
	var started: int = Time.get_ticks_msec()

	for index in SEED_COUNT:
		var loose: Dictionary = generator.generate(_config(index, false))
		if not bool(loose["ok"]):
			# 여유 제거와 무관한 생성 실패다(시드 운). 이 시드는 건너뛴다.
			print("  시드 %d 건너뜀: 끄고도 생성 실패" % index)
			continue
		var tight: Dictionary = generator.generate(_config(index, true))
		if not bool(tight["ok"]):
			_failures.append("시드 %d 켜면 생성 실패: %s" % [index, tight["reason"]])
			continue
		made += 1

		var loose_state: PuzzleState = LevelLayoutWriter.to_puzzle_state(loose)
		var tight_state: PuzzleState = LevelLayoutWriter.to_puzzle_state(tight)
		var loose_count: int = _free_cells(loose_state).size()
		var tight_count: int = _free_cells(tight_state).size()
		loose_free += loose_count
		tight_free += tight_count
		_accumulate(loose_early, loose["stats"]["early_clearing"])
		_accumulate(tight_early, tight["stats"]["early_clearing"])

		# 1. 여유가 깎였다.
		_expect(
			tight_count < loose_count,
			"시드 %d 빈 칸이 안 줄었다 (끔 %d → 켬 %d)" % [index, loose_count, tight_count]
		)

		# 2. 기록된 풀이가 그대로 재생된다.
		var replay: PuzzleState = tight_state.clone()
		var broken: bool = false
		for move in tight["solution"]:
			if not bool(replay.apply_move(move)["moved"]):
				_failures.append("시드 %d 기록된 풀이가 %s 에서 끊겼다" % [index, move])
				broken = true
				break
		if not broken:
			_expect(replay.is_solved(), "시드 %d 풀이를 다 재생했는데 고양이가 남았다" % index)

		# 3. 남은 빈 칸은 전부 통로다 — 하나만 더 막아도 못 푼다.
		for cell in _free_cells(tight_state):
			var blocked: PuzzleState = tight_state.clone()
			blocked.add_obstacle(cell)
			_expect(
				not bool(solver.solve(blocked, 20000)["found"]),
				"시드 %d 는 %s 를 더 막아도 풀린다 (여유가 남았다)" % [index, cell]
			)

	if made > 0:
		print("[여유 제거] %d개 / 빈 칸 평균 %.1f → %.1f / 조기탈출 %s → %s / %dms" % [
			made,
			float(loose_free) / float(made),
			float(tight_free) / float(made),
			_average(loose_early, made),
			_average(tight_early, made),
			Time.get_ticks_msec() - started,
		])
	_report()
	quit()


func _config(index: int, squeeze: bool) -> MapGenerator.Config:
	var config := MapGenerator.default_config()
	config.base_seed = index * STRIDE
	config.squeeze_free_cells = squeeze
	return config


# 고양이·구멍·장애물이 아닌 칸. 이 수가 곧 판에 남은 여유의 크기다.
func _free_cells(state: PuzzleState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in state.grid_size.y:
		for x in state.grid_size.x:
			if state.is_free_cell(Vector2i(x, y)):
				cells.append(Vector2i(x, y))
	return cells


static func _accumulate(totals: Array[int], values: Array) -> void:
	for index in mini(totals.size(), values.size()):
		totals[index] += int(values[index])


static func _average(totals: Array[int], count: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for value in totals:
		result.append(snappedf(float(value) / float(count), 0.1))
	return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("[여유 제거] 통과")
		return
	for failure in _failures:
		push_error(failure)
	print("[여유 제거] 실패 %d건" % _failures.size())
