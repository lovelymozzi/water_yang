extends SceneTree

# 중첩의 논리 모델이 게임과 같이 "겉 탈출 뒤 같은 몸의 안쪽 고양이"로 바뀌는지 검사한다.
func _initialize() -> void:
	var state := PuzzleState.create(Vector2i(6, 4))
	state.add_hole(Vector2i(4, 1), 0)
	state.add_hole(Vector2i(4, 3), 1)
	state.add_cat(0, 0, [Vector2i(2, 1), Vector2i(1, 1)], [1])
	var result: Dictionary = state.apply_move({
		"cat_id": 0, "from_end_cell": Vector2i(2, 1), "to_cell": Vector2i(3, 1),
	})
	_expect(bool(result["moved"]) and bool(result["absorbed"]), "겉고양이 탈출이 실패했다")
	_expect(state.cats.has(0), "겉고양이 빠진 뒤 안쪽 고양이가 생기지 않았다")
	_expect(state.color_of(0) == 1, "안쪽 색이 전달되지 않았다")
	_expect(state.body_of(0) == [Vector2i(3, 1), Vector2i(2, 1)], "안쪽 고양이의 몸이 현 자리에 남지 않았다")
	_expect(not state.holes.has(Vector2i(4, 1)), "겉 구멍이 닫히지 않았다")
	print("NESTED PUZZLE STATE CHECK: PASS")
	quit()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error("NESTED PUZZLE STATE CHECK: %s" % message)
		quit(1)
