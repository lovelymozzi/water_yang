extends SceneTree

# 얼음 잠금이 `PuzzleState` 에 제대로 들어갔는지, 그리고 **이미 저장된 스테이지들이 얼음을 켠
# 채로도 여전히 풀리는지** 확인한다.
#
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/ice_lock_check.gd
#
# 두 번째가 본론이다: 얼음 숫자가 그 구멍이 쓰이는 시점의 탈출 수보다 크면 게임에서 구멍이
# 안 열려 클리어가 불가능한 스테이지가 된다. 생성기가 그런 값을 못 내게 되어 있지만,
# 저장된 파일은 옛 생성기가 만든 것일 수 있으므로 파일을 직접 재생해 본다.


func _initialize() -> void:
	var failures: Array[String] = []
	failures.append_array(_check_lock_rule())
	failures.append_array(_check_saved_levels("res://resources/levels"))
	if failures.is_empty():
		print("[얼음 검사] 통과")
		quit()
		return
	for line in failures:
		print("  실패: %s" % line)
	print("[얼음 검사] %d건 실패" % failures.size())
	quit(1)


# 잠긴 구멍은 흡입을 걸지 않고, 다른 고양이가 빠지면 열린다.
func _check_lock_rule() -> Array[String]:
	var problems: Array[String] = []
	var state := PuzzleState.create(Vector2i(5, 5))
	state.add_hole(Vector2i(0, 0), 1)
	state.add_hole(Vector2i(4, 4), 2)
	state.add_ice(Vector2i(0, 0), 1)
	var iced_body: Array[Vector2i] = [Vector2i(0, 2), Vector2i(0, 3)]
	var free_body: Array[Vector2i] = [Vector2i(4, 1), Vector2i(4, 2)]
	state.add_cat(0, 1, iced_body)
	state.add_cat(1, 2, free_body)

	# 얼음(1)이 아직 안 깨졌으니 구멍 옆에 붙어도 흡입되지 않는다.
	var blocked: Dictionary = state.apply_move({
		"cat_id": 0, "from_end_cell": Vector2i(0, 2), "to_cell": Vector2i(0, 1),
	})
	if bool(blocked["absorbed"]):
		problems.append("잠긴 구멍인데 흡입이 걸렸다")

	# 다른 고양이가 빠지면 얼음이 깨진다.
	state.apply_move({"cat_id": 1, "from_end_cell": Vector2i(4, 2), "to_cell": Vector2i(4, 3)})
	if state.cats.has(1):
		problems.append("자유 고양이가 안 빠졌다 (검사 자체가 무효)")
	elif state.is_hole_locked(Vector2i(0, 0)):
		problems.append("한 마리 빠졌는데 얼음이 안 깨졌다")
	else:
		# 붙었다 떨어졌다 다시 붙는다. 흡입은 방금 움직인 끝에서만 걸리므로 재접근이 필요하다.
		state.apply_move({"cat_id": 0, "from_end_cell": Vector2i(0, 2), "to_cell": Vector2i(1, 2)})
		var opened: Dictionary = state.apply_move({
			"cat_id": 0, "from_end_cell": Vector2i(0, 2), "to_cell": Vector2i(0, 1),
		})
		if not bool(opened["absorbed"]):
			problems.append("얼음이 깨졌는데도 흡입이 안 걸렸다")
	return problems


# 저장된 스테이지를 얼음까지 얹은 판으로 복원해 기록된 풀이를 재생한다.
func _check_saved_levels(dir_path: String) -> Array[String]:
	var problems: Array[String] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return ["%s 를 열 수 없다" % dir_path]
	var files: PackedStringArray = dir.get_files()
	files.sort()
	var checked: int = 0
	for file_name in files:
		if not (file_name.begins_with("stage_") and file_name.ends_with(".json")):
			continue
		var text: String = FileAccess.get_file_as_string("%s/%s" % [dir_path, file_name])
		var data: Variant = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			problems.append("%s: JSON 을 읽을 수 없다" % file_name)
			continue
		checked += 1
		var problem: String = _replay(data as Dictionary)
		if not problem.is_empty():
			problems.append("%s: %s" % [file_name, problem])
	print("[얼음 검사] 스테이지 %d개 재생" % checked)
	return problems


func _replay(data: Dictionary) -> String:
	var state := PuzzleState.create(_to_cell(data["grid_size"]))
	for block in data.get("obstacles", []):
		for cell in PuzzleState.cells_of_block({
			"grid_pos": _to_cell(block["grid_pos"]), "block_size": _to_cell(block["block_size"]),
		}):
			state.add_obstacle(cell)
	for hole in data["holes"]:
		var cell: Vector2i = _to_cell(hole["grid_pos"])
		state.add_hole(cell, int(hole["color_id"]))
		state.add_ice(cell, int(hole.get("ice_count", 0)))
	for index in (data["cats"] as Array).size():
		var cat: Dictionary = data["cats"][index]
		var body: Array[Vector2i] = []
		for raw in cat["body_cells"]:
			body.append(_to_cell(raw))
		state.add_cat(index, int(cat["color_id"]), body)

	for move in data["solution"]:
		var result: Dictionary = state.apply_move({
			"cat_id": int(move["cat_id"]),
			"from_end_cell": _to_cell(move["from_end_cell"]),
			"to_cell": _to_cell(move["to_cell"]),
		})
		if not bool(result["moved"]):
			return "기록된 풀이가 %s 에서 끊겼다 (얼음이 구멍을 막고 있을 수 있다)" % [move]
	if not state.is_solved():
		return "풀이를 다 재생했는데 고양이 %d마리가 남았다 = 얼음이 안 열린다" % state.cats.size()
	return ""


func _to_cell(raw: Variant) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))
