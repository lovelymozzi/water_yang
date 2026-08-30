extends SceneTree

# 생성 비용 프로파일. "맵 한 개가 왜 이렇게 오래 걸리는가"를 조건별로 쪼개 잰다.
#   Godot --headless --script tests/generator_profile.gd
#
# 조건 하나씩만 바꿔 가며 `generate()` 를 돌리고 소요 시간과 성공 여부를 찍는다.
# 회귀 검사가 아니라 진단용이므로 PASS/FAIL 을 내지 않는다.

const CASES: Array[Dictionary] = [
	{"name": "기준(first1 chain0 squeeze0)", "first": 1, "chain": 0, "squeeze": false},
	{"name": "first2", "first": 2, "chain": 0, "squeeze": false},
	{"name": "first3", "first": 3, "chain": 0, "squeeze": false},
	{"name": "squeeze만", "first": 1, "chain": 0, "squeeze": true},
	{"name": "first3 + squeeze (배치 기본값)", "first": 3, "chain": 0, "squeeze": true},
	# 몸 길이를 되돌려 본다. 짧은 몸은 잘 빠져나가 벽으로 세울 후보가 약해진다는 가설.
	{"name": "first2 + 긴몸(5~12)", "first": 2, "chain": 0, "squeeze": false, "len": Vector2i(5, 12)},
	{"name": "first3 + 긴몸(5~12)", "first": 3, "chain": 0, "squeeze": false, "len": Vector2i(5, 12)},
	{"name": "first3 + 긴몸 + 고양이6", "first": 3, "chain": 0, "squeeze": false, "len": Vector2i(5, 12), "cats": 6},
]


func _initialize() -> void:
	var generator := MapGenerator.new()
	print("[프로파일] 고양이 5 / 보드 7x9 / 몸 3~6 / attempts 10")
	for case_data in CASES:
		var config := MapGenerator.default_config()
		config.base_seed = 4242
		config.grid_size = Vector2i(7, 9)
		config.cat_count = int(case_data.get("cats", 5))
		config.color_count = 20
		var lengths: Vector2i = case_data.get("len", Vector2i(3, 6))
		config.body_length_min = lengths.x
		config.body_length_max = lengths.y
		config.total_length_ratio = 0.7
		config.min_chain_depth = int(case_data["chain"])
		config.min_dependent_cats = 0
		config.min_first_escape_moves = int(case_data["first"])
		config.squeeze_free_cells = bool(case_data["squeeze"])
		config.obstacle_fill_ratio = 0.85
		config.max_attempts = 10

		var started: int = Time.get_ticks_msec()
		var level: Dictionary = generator.generate(config)
		var elapsed: int = Time.get_ticks_msec() - started
		var ok: bool = bool(level["ok"])
		print("  %-34s %6dms  %s  (시도당 %dms)" % [
			case_data["name"],
			elapsed,
			"성공" if ok else "10회 전부 실패",
			elapsed / 10,
		])
		if not ok:
			# 실패 사유의 분포가 곧 "어느 조건에서 죽는가"다.
			var reasons: Dictionary = {}
			for line in (level["failures"] as Array):
				var reason: String = str(line).get_slice(": ", 1)
				reasons[reason] = int(reasons.get(reason, 0)) + 1
			for reason in reasons:
				print("      %d회: %s" % [int(reasons[reason]), reason])
	quit()
