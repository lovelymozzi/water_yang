extends SceneTree

# 생성기가 2+3중첩 혼합 레이어까지 포함해 실제 풀이를 다시 찾고, 끝까지 재생하는지 검사한다.
func _initialize() -> void:
	var config := MapGenerator.default_config()
	config.base_seed = 17631
	config.grid_size = Vector2i(7, 9)
	# 혼합 + 확률 1.0 = 전원 중첩. 2마리면 2중첩/3중첩 한 마리씩이라 총 5색·5탈출이다.
	config.cat_count = 2
	config.nested_two_chance = 1.0
	config.nested_three_ratio = 0.5
	config.color_count = 5
	config.body_length_min = 3
	config.body_length_max = 4
	config.reverse_steps_min = 3
	config.reverse_steps_max = 6
	config.min_chain_depth = 0
	# 혼합 레이어 생성·풀이만 격리한다. 첫 탈출 벽은 별도 생성 단계라 여기서는 끈다.
	config.min_first_escape_moves = 0
	config.hole_line_chance = 0.0
	config.obstacle_fill_ratio = 0.35
	config.max_attempts = 30
	config.solver_node_budget = 60000

	var level: Dictionary = MapGenerator.new().generate(config)
	_expect(bool(level.get("ok", false)), "혼합 중첩 맵 생성 실패: %s" % level.get("reason", ""))
	var nested_cats: int = 0
	var nested_two: int = 0
	var nested_three: int = 0
	for cat in level["cats"]:
		var depth: int = (cat.get("nested_color_ids", []) as Array).size()
		if depth > 0:
			nested_cats += 1
		if depth == 1:
			nested_two += 1
		elif depth == 2:
			nested_three += 1
	_expect(nested_cats == 2, "중첩 고양이 수가 %d다" % nested_cats)
	_expect(nested_two == 1, "2중첩 고양이 수가 %d다" % nested_two)
	_expect(nested_three == 1, "3중첩 고양이 수가 %d다" % nested_three)
	_expect(int(level["stats"]["nested_two_cats"]) == 1, "통계의 2중첩 수가 다르다")
	_expect(int(level["stats"]["nested_three_cats"]) == 1, "통계의 3중첩 수가 다르다")
	_expect(not (level["cats"][0].get("nested_color_ids", []) as Array).is_empty(),
		"설계상 첫 탈출 고양이(cat_id 0)가 중첩이 아니다")
	var actual_first: int = int((level["escape_order"] as Array)[0])
	_expect(not (level["cats"][actual_first].get("nested_color_ids", []) as Array).is_empty(),
		"최종 풀이의 첫 탈출 고양이가 중첩이 아니다")

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
	_expect(state.is_solved(), "혼합 중첩 풀이 뒤 고양이가 남았다")
	_expect(absorbed == 5, "탈출 이벤트가 %d번이다 (2중첩 2회 + 3중첩 3회여야 함)" % absorbed)
	print("NESTED GENERATOR CHECK: PASS")
	quit()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error("NESTED GENERATOR CHECK: %s" % message)
		quit(1)
