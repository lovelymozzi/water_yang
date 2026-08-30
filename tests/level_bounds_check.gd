extends SceneTree

const LevelBounds = preload("res://scripts/level_bounds.gd")

# 외곽 빈 행·열 제거가 배치와 정답 수순을 같은 좌표계로 옮기는지 확인한다.
func _initialize() -> void:
	var level: Dictionary = {
		"grid_size": Vector2i(7, 6),
		"holes": [{"grid_pos": Vector2i(4, 2), "color_id": 0}],
		"obstacles": [{"grid_pos": Vector2i(1, 1), "block_size": Vector2i(3, 2)}],
		"cats": [{"body_cells": [Vector2i(2, 2), Vector2i(2, 3)], "color_id": 0}],
		"solution": [{
			"cat_id": 0, "from_end_cell": Vector2i(2, 2), "to_cell": Vector2i(2, 1),
		}],
	}
	LevelBounds.trim_unused_border(level)
	_expect(level["grid_size"] == Vector2i(3, 3), "경계 상자가 3x3이 아니다: %s" % level["grid_size"])
	_expect(level["cats"][0]["body_cells"] == [Vector2i(0, 1), Vector2i(0, 2)], "고양이 좌표가 안 옮겨졌다")
	_expect(level["holes"][0]["grid_pos"] == Vector2i(2, 1), "구멍 좌표가 안 옮겨졌다")
	_expect(level["obstacles"][0]["grid_pos"] == Vector2i(0, 0), "장애물 좌표가 안 옮겨졌다")
	_expect(level["obstacles"][0]["block_size"] == Vector2i(2, 2), "경계 밖 장애물이 잘리지 않았다")
	_expect(level["solution"][0]["from_end_cell"] == Vector2i(0, 1), "풀이 출발 좌표가 안 옮겨졌다")
	_expect(level["solution"][0]["to_cell"] == Vector2i(0, 0), "풀이 도착 좌표가 안 옮겨졌다")
	_check_generated_level()
	_check_saved_stage("res://resources/levels/stage_060.json", Vector2i(4, 8))
	_check_saved_stage("res://resources/levels/stage_064.json", Vector2i(7, 10))
	print("LEVEL BOUNDS CHECK: PASS")
	quit()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error("LEVEL BOUNDS CHECK: %s" % message)
		quit(1)


func _check_generated_level() -> void:
	var config := MapGenerator.default_config()
	config.base_seed = 4242
	config.grid_size = Vector2i(7, 9)
	config.cat_count = 5
	config.color_count = 20
	config.body_length_min = 3
	config.body_length_max = 6
	config.total_length_ratio = 0.7
	config.min_chain_depth = 0
	config.min_dependent_cats = 0
	config.min_first_escape_moves = 1
	config.obstacle_fill_ratio = 0.85
	config.max_attempts = 10
	var level: Dictionary = MapGenerator.new().generate(config)
	_expect(bool(level["ok"]), "생성된 맵을 얻지 못했다")
	var state := PuzzleState.create(level["grid_size"])
	for entry in level["holes"]:
		state.add_hole(entry["grid_pos"], int(entry["color_id"]))
	for entry in level["obstacles"]:
		for cell in PuzzleState.cells_of_block(entry):
			state.add_obstacle(cell)
	for index in (level["cats"] as Array).size():
		state.add_cat(index, int(level["cats"][index]["color_id"]), level["cats"][index]["body_cells"])
	for move in level["solution"]:
		_expect(bool(state.apply_move(move)["moved"]), "자른 맵에서 풀이가 끊겼다: %s" % move)
	_expect(state.is_solved(), "자른 맵의 풀이 클리어로 끝나지 않는다")


func _check_saved_stage(path: String, expected_size: Vector2i) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "%s을 열 수 없다" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	_expect(parsed is Dictionary, "%s JSON이 아니다" % path)
	var data: Dictionary = parsed
	var level: Dictionary = {
		"grid_size": _cell(data["grid_size"]), "holes": [], "obstacles": [], "cats": [], "solution": [],
	}
	for entry in data["holes"]:
		level["holes"].append({"grid_pos": _cell(entry["grid_pos"]), "color_id": int(entry["color_id"])})
	for entry in data["obstacles"]:
		level["obstacles"].append({"grid_pos": _cell(entry["grid_pos"]), "block_size": _cell(entry["block_size"])})
	for entry in data["cats"]:
		var body: Array[Vector2i] = []
		for cell in entry["body_cells"]:
			body.append(_cell(cell))
		level["cats"].append({"body_cells": body, "color_id": int(entry["color_id"])})
	for move in data["solution"]:
		level["solution"].append({
			"cat_id": int(move["cat_id"]),
			"from_end_cell": _cell(move["from_end_cell"]),
			"to_cell": _cell(move["to_cell"]),
		})
	LevelBounds.trim_unused_border(level)
	_expect(level["grid_size"] == expected_size, "%s 트림 결과 %s (기대 %s)" % [path, level["grid_size"], expected_size])


func _cell(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))
