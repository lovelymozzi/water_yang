extends SceneTree

# 생성기가 2중첩 레이어까지 포함해 실제 풀이를 다시 찾고, 그 수순이 끝까지 재생되는지 검사한다.
func _initialize() -> void:
	var config := MapGenerator.default_config()
	config.base_seed = 17631
	config.grid_size = Vector2i(7, 9)
	config.cat_count = 3
	config.nested_two_count = 1
	config.color_count = 4
	config.body_length_min = 3
	config.body_length_max = 4
	config.reverse_steps_min = 3
	config.reverse_steps_max = 6
	config.min_chain_depth = 0
	config.min_first_escape_moves = 0
	config.hole_line_chance = 0.0
	config.obstacle_fill_ratio = 0.35
	config.max_attempts = 30
	config.solver_node_budget = 60000

	var level: Dictionary = MapGenerator.new().generate(config)
	_expect(bool(level.get("ok", false)), "2중첩 맵 생성 실패: %s" % level.get("reason", ""))
	var nested_cats: int = 0
	for cat in level["cats"]:
		if not (cat.get("nested_color_ids", []) as Array).is_empty():
			nested_cats += 1
	_expect(nested_cats == 1, "2중첩 고양이 수가 %d다" % nested_cats)

	# LevelLayoutWriter는 런타임 LevelManager 의존도까지 불러오므로, 이 헤드리스 모델
	# 검사에서는 생성 Dictionary를 직접 되돌린다.
	var state := PuzzleState.create(level["grid_size"])
	for hole in level["holes"]:
		state.add_hole(hole["grid_pos"], int(hole["color_id"]))
	for block in level["obstacles"]:
		for cell in PuzzleState.cells_of_block(block):
			state.add_obstacle(cell)
	for cat_id in range((level["cats"] as Array).size()):
		var cat: Dictionary = level["cats"][cat_id]
		var nested: Array[int] = []
		nested.assign(cat.get("nested_color_ids", []))
		state.add_cat(cat_id, int(cat["color_id"]), cat["body_cells"], nested)
	var absorbed: int = 0
	for move in level["solution"]:
		var step: Dictionary = state.apply_move(move)
		_expect(bool(step["moved"]), "기록 풀이가 끊겼다: %s" % move)
		if bool(step["absorbed"]):
			absorbed += 1
	_expect(state.is_solved(), "2중첩 풀이 뒤 고양이가 남았다")
	_expect(absorbed == 4, "탈출 이벤트가 %d번이다 (물리 3 + 안쪽 1이어야 함)" % absorbed)
	print("NESTED GENERATOR CHECK: PASS")
	quit()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error("NESTED GENERATOR CHECK: %s" % message)
		quit(1)
