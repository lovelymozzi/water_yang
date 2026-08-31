extends SceneTree

# 재배치가 (1) 기믹 첫 등장을 지키고 (2) 난이도를 퐁당퐁당으로 놓는지 본다.
const StageArranger := preload("res://scripts/stage_arranger.gd")


func _initialize() -> void:
	# 점수 10..80 짜리 8판. 3·6번 판에 얼음, 7번 판에 2중첩을 심는다.
	var levels: Array = []
	for index in 8:
		levels.append(_level((index + 1) * 10, index in [2, 5], index == 6))

	var order: Array[int] = StageArranger.arrange(levels, {"ice": 4, "nested2": 7})
	_expect(order.size() == 8, "판 수가 %d 로 바뀌었다" % order.size())
	var seen: Dictionary = {}
	for index in order:
		seen[index] = true
	_expect(seen.size() == 8, "재배치가 판을 잃거나 중복시켰다")

	var appearances: Dictionary = StageArranger.first_appearances(levels, order)
	_expect(int(appearances["ice"]) >= 4, "얼음이 %d 스테이지에 나왔다" % appearances["ice"])
	_expect(int(appearances["nested2"]) >= 7, "2중첩이 %d 스테이지에 나왔다" % appearances["nested2"])

	# 퐁당퐁당: 짝수 자리는 쉬운 절반, 홀수 자리는 어려운 절반에서 온다. 기믹 게이트에
	# 걸린 자리는 예외이므로 "대부분"만 본다.
	var alternating: int = 0
	for position in order.size():
		var easy_half: bool = LevelSolver.stored_difficulty_score(levels[order[position]]["stats"]) <= 40
		if easy_half == (position % 2 == 0):
			alternating += 1
	_expect(alternating >= 6, "교대 배치가 %d/8 자리에서만 맞았다" % alternating)

	# 게이트가 없으면 정확히 E0 H0 E1 H1 ... 이어야 한다.
	var plain: Array[int] = StageArranger.arrange(levels, {})
	_expect(plain == [0, 4, 1, 5, 2, 6, 3, 7], "게이트 없는 퐁당퐁당이 %s 다" % [plain])

	_check_nested_depth_gates()
	_check_teaching_run()
	_check_six_cycle()
	_check_apply_order()
	print("STAGE ARRANGE CHECK: PASS")
	quit()


# 첫 등장 자리부터 TEACH_FOLLOW_UP + 1 판은 그 기믹 판으로만 채운다.
func _check_teaching_run() -> void:
	var levels: Array = []
	for index in 12:
		levels.append(_level((index + 1) * 10, index >= 6, false))
	var order: Array[int] = StageArranger.arrange(levels, {"ice": 5})
	var run: int = StageArranger.TEACH_FOLLOW_UP + 1
	for offset in run:
		var position: int = 4 + offset
		_expect(
			StageArranger.gimmicks_of(levels[order[position]]).has("ice"),
			"%d 스테이지에 얼음이 없다" % (position + 1)
		)
	for position in 4:
		_expect(
			not StageArranger.gimmicks_of(levels[order[position]]).has("ice"),
			"얼음이 %d 스테이지에 먼저 나왔다" % (position + 1)
		)
	var filled: Dictionary = StageArranger.teaching_fill(levels, order, {"ice": 5})
	_expect(filled["ice"] == [run, run], "연습 구간이 %s 다" % [filled["ice"]])

	# 기믹 판이 모자라면 연습 구간을 짧게 끝내고 자리는 채운다.
	var scarce: Array = []
	for index in 12:
		scarce.append(_level((index + 1) * 10, index == 11, false))
	var short_order: Array[int] = StageArranger.arrange(scarce, {"ice": 5})
	_expect(short_order.size() == 12, "판 수가 %d 로 바뀌었다" % short_order.size())
	var short_filled: Dictionary = StageArranger.teaching_fill(scarce, short_order, {"ice": 5})
	_expect(short_filled["ice"] == [1, run], "모자란 연습 구간이 %s 다" % [short_filled["ice"]])


# 6주기 [쉬움 쉬움 어려움 쉬움 쉬움 매우어려움]: 12판이면 쉬움 8 / 어려움 2 / 매우어려움 2 로
# 갈리고, 자리 3·6·9·12 (1부터)에만 위 두 띠가 온다.
func _check_six_cycle() -> void:
	var levels: Array = []
	for index in 12:
		levels.append(_level((index + 1) * 10, false, false))
	var steps: Array[int] = StageArranger.pattern_steps("six")
	var order: Array[int] = StageArranger.arrange(levels, {}, steps)
	# 점수 = (원본 인덱스 + 1) * 10 이므로 원본 인덱스가 곧 난이도 등수다.
	_expect(order == [0, 1, 8, 2, 3, 10, 4, 5, 9, 6, 7, 11], "6주기 배치가 %s 다" % [order])
	var spikes: Array[int] = [order[5], order[11]]
	_expect(spikes == [10, 11], "매우어려움 자리에 %s 가 왔다" % [spikes])

	var warmup_levels: Array = []
	for index in 60:
		warmup_levels.append(_level((index + 1) * 10, false, false))
	var warmup_order: Array[int] = StageArranger.arrange(
		warmup_levels, {}, StageArranger.pattern_steps("warmup_six"),
		int(StageArranger.PATTERNS["warmup_six"]["warmup"])
	)
	_expect(warmup_order.slice(0, 30) == range(30), "1~30이 쉬운 띠의 오름차순이 아니다")
	_expect(warmup_order[30] == 30 and warmup_order[32] == 50 and warmup_order[35] == 55,
		"31스테이지부터 6주기가 시작되지 않았다: %s" % [warmup_order.slice(30, 36)])


# 파일 이름 바꿔치기까지 실제로 해 본다 — 임시 이름을 안 거치면 서로 덮어쓴다.
func _check_apply_order() -> void:
	var dir_path: String = ProjectSettings.globalize_path("user://arrange_apply_test")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var names: PackedStringArray = PackedStringArray(["stage_004.json", "stage_007.json", "stage_010.json"])
	var paths: PackedStringArray = PackedStringArray()
	for index in names.size():
		var path: String = "%s/%s" % [dir_path, names[index]]
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"mark": index}))
		file.close()
		paths.append(path)

	var failed: String = StageArranger.apply_order(dir_path, paths, [2, 0, 1] as Array[int])
	_expect(failed.is_empty(), "이름 바꾸기 실패: %s" % failed)
	var expected: Array[int] = [2, 0, 1]
	for position in expected.size():
		var path: String = "%s/stage_%03d.json" % [dir_path, position + 1]
		_expect(FileAccess.file_exists(path), "%s 가 없다" % path)
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		_expect(int(data["mark"]) == expected[position], "stage_%03d 에 %s 가 왔다" % [position + 1, data])
	for position in expected.size():
		DirAccess.remove_absolute("%s/stage_%03d.json" % [dir_path, position + 1])
	DirAccess.remove_absolute(dir_path)


func _level(score: int, ice: bool, nested: bool, depth: int = 1) -> Dictionary:
	var nested_ids: Array = []
	if nested:
		nested_ids = [1] if depth <= 1 else [1, 2]
	return {
		"stats": {"difficulty_score": score},
		"holes": [{"ice_count": 2 if ice else 0}],
		"cats": [{"nested_color_ids": nested_ids}],
	}


# 3중첩 판은 2중첩 게이트가 아니라 3중첩 게이트만 받는다.
func _check_nested_depth_gates() -> void:
	var levels: Array = []
	for index in 8:
		# 3·6번 판에 2중첩, 7번 판에 3중첩.
		levels.append(_level((index + 1) * 10, false, index in [2, 5, 6], 2 if index == 6 else 1))
	_expect(not StageArranger.gimmicks_of(levels[6]).has("nested2"),
		"3중첩만 든 판이 2중첩으로도 잡힌다")
	_expect(StageArranger.gimmicks_of(levels[6]).has("nested3"), "3중첩이 안 잡힌다")
	_expect(StageArranger.gimmicks_of(levels[2]).has("nested2"), "2중첩이 안 잡힌다")
	_expect(not StageArranger.gimmicks_of(levels[2]).has("nested3"),
		"2중첩 판이 3중첩으로도 잡힌다")

	var order: Array[int] = StageArranger.arrange(levels, {"nested2": 3, "nested3": 7})
	var appearances: Dictionary = StageArranger.first_appearances(levels, order)
	_expect(int(appearances["nested2"]) >= 3, "2중첩이 %d 스테이지에 나왔다" % appearances["nested2"])
	_expect(int(appearances["nested3"]) >= 7, "3중첩이 %d 스테이지에 나왔다" % appearances["nested3"])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		push_error("STAGE ARRANGE CHECK: %s" % message)
		quit(1)
