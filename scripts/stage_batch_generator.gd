extends SceneTree

# 스테이지 배치 생성기. 검증된 레벨 N개를 만들어 **기존 스테이지 뒤에 이어 붙인다**
# (가장 큰 순번 + 1 부터). main_scene 은 폴더의 stage_*.json 을 정렬해 차례로 읽으므로,
# 폴더가 곧 스테이지 목록이다:
#   - 맵을 지우고 싶으면 파일을 지우면 된다 (순번에 구멍이 나도 순서대로 잘 돈다)
#   - 스테이지에서 빼되 보관하고 싶으면 levels_archive/ 로 옮긴다 (어드민의 아카이브 버튼)
#   - 전부 새로 만들고 싶으면 폴더를 비우고 돌리면 된다
#
#   /Applications/Godot.app/Contents/MacOS/Godot --headless \
#       --script scripts/stage_batch_generator.gd -- count=10 seed=1
#
# 파라미터는 전부 `--` 뒤에 key=value 로 준다. 범위형(a..b)은 스테이지 순번에 따라
# 선형으로 램프한다 — 1스테이지가 a, 마지막 스테이지가 b. 그래서 뒤로 갈수록 어려워진다.
#
#   count=10          만들 스테이지 수
#   seed=1            기본 시드 (스테이지마다 큰 소수 보폭으로 흩어진다)
#   grid=7x9          보드 크기의 **중심값**. 스테이지마다 가로·세로를 각각 ±2 에서 흔든다
#                     (7x9 → 5..9 x 7..11). 그 뒤 그라운드 룰로 세로 ≥ 가로+1 이 되게
#                     보정하므로, 흔들린 결과가 6x6 이면 6x7 로 올라간다. 기준(9x10)보다
#                     큰 판은 게임에서 타일을 줄여 담으므로 칸 수 상한은 없다.
#   cats=3..6         고양이 수 (범위 가능)
#   chain=0           의존 사슬 깊이 최소치 (범위 가능). **기본 0 = 검사 안 함** — 이 값은
#                     "나머지가 전원 시작 자리에 얼어 있다"는 가정에서 재므로 실제 난이도와
#                     상관이 없다(실측 상관 0.24). 난이도는 score 로 본다.
#   score=0           난이도 점수 하한 (범위 가능, 스테이지 램프). 0 = 검사 안 함.
#                     `LevelSolver.difficulty_breakdown()` = 탈출별 드래그 비용 + 공간 압박 + 긴 몸 제약.
#                     참고로 기존 55스테이지가 88, 가장 어려웠던 36스테이지가 121 이다.
#   diff_limit=8      난이도 채점용 탈출 비용 상한. 낮추면 빠르지만 어려운 판끼리 구분이 안 된다.
#   len_min=3         몸 길이 하한
#   len_max=6         몸 길이 상한
#                     ⚠ 길이는 후반 난이도를 **깎는다**: 한 마리가 빠지면 몸+구멍만큼 칸이
#                     열리므로(길이 6 이면 7칸) 뒤 순번 고양이는 허허벌판에서 논다. 짧게 여럿이
#                     탈출당 열리는 칸이 적어 후반이 덜 헐렁하다.
#   pack=0.7          고양이 몸이 빈 칸 중 차지하는 비율 상한. 몸이 짧아진 만큼 올려 잡는다.
#   steps_min=5       고양이 한 마리의 역주행 걸음 하한
#   steps_max=12      역주행 걸음 상한
#   obstacle=0.7..1.0   풀이가 안 밟는 칸 중 장애물로 채우는 비율 (범위 가능, 스테이지 램프.
#                       1.0 이면 통로만 남아 "비켜주기"가 사라지고 의존이 실제로 강제된다)
#   dep_slack=99      독립(의존 없는) 고양이 허용 마릿수. 의존 고양이 하한 = 고양이 수 - 이 값.
#                     **기본 99 = 검사 안 함** (chain 과 같은 이유로 소프트 채점에 맡긴다).
#   hole_line=0.5     구멍을 분할선 관문으로 늘어놓을 확률 (0=흩뿌리기만, 1=관문만)
#   첫 탈출 치우기=1  사용자 입력 없이 1로 고정한다. 높은 하한에서 반복되던 벽 배치 실패와
#                     재시도 부하를 줄이되, 바로 탈출 가능한 판은 계속 제외한다.
#   squeeze=1         막아도 여전히 풀리는 빈 칸을 전부 장애물로 채운다 (여유 제거).
#                     빈 공간이 사라져 뒤 순번 고양이가 앞 고양이가 비운 자리를 여유 없이
#                     써야만 나갈 수 있게 된다. 생성이 몇 배 느려진다. 0 = 끈다.
#   squeeze_budget=20000  여유 판정 한 칸당 탐색 예산. **여유 제거가 생성 시간의 99%다**
#                     (실측: 4마리 3중첩 7x9 에서 한 판 71초 중 71초). 막으면 안 되는 칸은
#                     예산을 다 태우고서야 판정되므로, 낮추면 그만큼 빨라지고 대신 보수적으로
#                     (막을 수 있었던 칸을 비워 둔 채) 끝난다. 3중첩처럼 레이어가 많은 판은
#                     4000 정도가 실용적이다.
#   later_min=0       두 번째 이후 탈출까지 치워야 하는 최소 수. **거르기만 한다** —
#   jitter=1          보드 크기 흔들기 사용 여부. 분석 배치에서 고정 크기가 필요하면 0.
#                     생성기가 이 조건을 만들어 내지는 못한다(map_generator.gd 의
#                     `_plant_first_escape_walls()` 주석 참조). 1 로 걸면 수율이 10%쯤으로
#                     떨어지므로 attempts 를 크게 잡아야 한다.
#   ── 기믹 ─────────────────────────────────────────────────────────────
#   기믹 확률은 전부 실수 범위 램프다(0.0..0.6 처럼). 마릿수·개수가 아니라 확률인 이유는
#   판마다 고양이·구멍 수가 다르기 때문 — 확률이면 판 크기에 맞춰 저절로 비례한다.
#   배치 순서는 **기믹마다 따로** 잡는다. 하한을 0 으로 두면 앞 스테이지엔 안 나오다가
#   뒤로 갈수록 잦아지고, 서로 다른 구간을 주면 기믹이 하나씩 소개된다:
#       nested2=0..0.5 ice=0..0.8   →  중첩이 먼저 붙고 얼음이 나중에 짙어진다
#
#   nested_mode=two   중첩 방식. `two` = 선택된 고양이 전부 2중첩,
#                     `mixed` = 2중첩과 3중첩을 마릿수 차이 1 이하로 혼합,
#                     `three` = 선택된 고양이 전부 3중첩(색·구멍을 마리당 2개 더 쓴다).
#   nested2=0.7       고양이가 중첩 대상이 될 목표 비율 (범위 가능, 스테이지 램프).
#                     첫 탈출 고양이는 100% 중첩하고 나머지 확률을 보정하므로, 0.7이면
#                     판 전체 기대값이 70%(10마리면 약 7마리)다. 0이면 중첩을 완전히 끈다.
#                     mixed에서 3중첩은 색·구멍을 두 개씩 더 쓰므로 colors가 모자라면 버린다.
#   ice=0.0           구멍마다 얼음을 씌워 볼 확률 (범위 가능, 스테이지 램프).
#                     얼음은 "N마리 빠질 때까지 이 구멍은 안 열린다"는 진짜 제약이라 의존 사슬을 늘린다. 다만 이미 그만큼 의존이
#                     실측된 구멍에는 아무것도 못 막으므로 자동으로 건너뛴다.
#   ice_max=0         얼음 숫자 상한 (범위 가능, 스테이지 램프).
#                     0 = 그 구멍이 쓰이기 직전까지의 탈출 수를 상한으로.
#                     같은 숫자는 판에 하나만 나오고, 늦게 쓰이는 구멍이 큰 숫자를 가져간다.
#   colors=20         색 팔레트 크기 (LevelManager.pair_colors 와 맞춘다)
#   attempts=120      스테이지당 생성 재시도 상한
#   out=res://resources/levels   저장 폴더 (기존 파일은 건드리지 않고 뒤 순번으로 추가)

# 중첩 방식 이름 → 3중첩 비율. `MapGenerator.Config.nested_three_ratio` 에 그대로 넣는다.
const NESTED_THREE_RATIO := {"two": 0.0, "mixed": 0.5, "three": 1.0}
const NESTED_MODE_LABEL := {"two": "2중첩만", "mixed": "2+3중첩 혼합", "three": "3중첩만"}

const STAGE_SEED_STRIDE := 100003
# 보드 크기 흔들기용 별도 보폭. 맵 시드와 섞이면 크기와 배치가 같이 움직여 규칙성이 생긴다.
const GRID_SEED_STRIDE := 7919
func _initialize() -> void:
	var params: Dictionary = _parse_args(OS.get_cmdline_user_args())
	var count: int = int(params.get("count", 10))
	if count < 1:
		push_error("count 는 1 이상이어야 한다 (받은 값: %d)" % count)
		quit(1)
		return

	var base_seed: int = int(params.get("seed", 1))
	var grid: Vector2i = _parse_grid(str(params.get("grid", "7x9")))
	var cats_range: Vector2i = _parse_range(str(params.get("cats", "3..6")))
	var chain_range: Vector2i = _parse_range(str(params.get("chain", "0")))
	# 기믹은 난이도와 따로 램프한다 — 기믹마다 자기 구간을 줘서 등장 순서를 잡는다.
	var nested_range: Vector2 = _parse_float_range(str(params.get("nested2", "0.7")))
	var nested_mode: String = str(params.get("nested_mode", "two"))
	if not NESTED_THREE_RATIO.has(nested_mode):
		push_error("nested_mode 는 two, mixed, three 중 하나여야 한다 (받은 값: %s)" % nested_mode)
		quit(1)
		return
	var ice_range: Vector2 = _parse_float_range(str(params.get("ice", "0.0")))
	var ice_max_range: Vector2i = _parse_range(str(params.get("ice_max", "0")))
	var score_range: Vector2i = _parse_range(str(params.get("score", "0")))
	var obstacle_range: Vector2 = _parse_float_range(str(params.get("obstacle", "0.7..1.0")))
	var out_dir: String = str(params.get("out", "res://resources/levels"))

	var start_number: int = next_stage_number(out_dir)
	print("[스테이지 생성] %d개 (stage_%03d 부터) / 시드 %d / 보드 %s / 고양이 %s / 난이도하한 %s → %s" % [
		count, start_number, base_seed, grid, cats_range, score_range, out_dir,
	])

	var generator := MapGenerator.new()
	var started: int = Time.get_ticks_msec()
	var made: int = 0

	for index in count:
		var stage_number: int = start_number + index
		var cat_count: int = ramp(cats_range, index, count)
		var chain_depth: int = mini(ramp(chain_range, index, count), cat_count)
		# 장애물 비율은 실수 램프라 여기서 풀어서 스테이지별 값으로 넘긴다.
		var stage_params: Dictionary = params.duplicate()
		stage_params["obstacle"] = rampf(obstacle_range, index, count)
		# 난이도 하한도 실수 램프처럼 스테이지별 값으로 풀어서 넘긴다.
		stage_params["score"] = ramp(score_range, index, count)
		stage_params["nested2"] = rampf(nested_range, index, count)
		stage_params["ice"] = rampf(ice_range, index, count)
		stage_params["ice_max"] = ramp(ice_max_range, index, count)
		var stage_grid: Vector2i = grid
		if int(params.get("jitter", 1)) != 0:
			stage_grid = jitter_grid(grid, base_seed + stage_number * GRID_SEED_STRIDE)

		# 시드 보폭은 배치 내 순번이 아니라 **전역 스테이지 순번**을 쓴다. 같은 시드로
		# 이어서 돌려도 이전 배치와 같은 맵을 다시 만들지 않게 하기 위해서다.
		var level: Dictionary = generate_stage(
			generator, stage_params, base_seed, stage_grid, stage_number - 1, cat_count, chain_depth
		)
		if level.is_empty():
			push_error("스테이지 %d 생성 실패 — 여기서 중단한다" % stage_number)
			quit(1)
			return

		# **한 개 만들 때마다 바로 저장한다.** 중간에 끊겨도 그때까지 만든 것은 남는다.
		# 난이도 순으로 줄 세우는 것은 생성 때 하지 않는다 — 게임이 완성된 뒤 전체 맵을
		# 놓고 한 번에 배당하는 별도 작업이다. 그 재료로 `stats.difficulty_score` 를
		# 파일마다 적어 둔다(어드민 난이도 곡선이 같은 값을 읽는다).
		var path: String = "%s/stage_%03d.json" % [out_dir, stage_number]
		var error: Error = LevelLayoutWriter.save_json(level, path)
		if error != OK:
			push_error("저장 실패 %s (%d)" % [path, error])
			quit(1)
			return
		made += 1
		print("  stage_%03d: 보드 %dx%d / 고양이 %d / 난이도 %d / 탈출비용 %s / 풀이 %d수 / 시드 %d" % [
			stage_number,
			int(level["grid_size"].x),
			int(level["grid_size"].y),
			cat_count,
			score_of(level),
			level["stats"]["early_clearing"],
			int(level["stats"]["solution_length"]),
			int(level["seed"]),
		])

	print("[스테이지 생성] %d개 완료 / %dms" % [made, Time.get_ticks_msec() - started])
	quit()


# 실측 난이도 점수. 예전 파일에는 없는 값이라 그때는 탈출 비용에서 다시 잰다.
static func score_of(level: Dictionary) -> int:
	return LevelSolver.stored_difficulty_score(level.get("stats", {}))


# 스테이지 순번에 따라 [a..b] 를 선형으로 램프한다. 1스테이지가 a, 마지막이 b.
static func ramp(value_range: Vector2i, index: int, count: int) -> int:
	var t: float = float(index) / float(count - 1) if count > 1 else 0.0
	return int(round(lerp(float(value_range.x), float(value_range.y), t)))


# 보드 크기 흔들기. 배치 안이 전부 같은 크기면 판이 단조로워진다. 가로·세로를 각각 ±2 에서
# 흔든다. 시드는 스테이지 순번에서 뽑으므로 같은 시드로 다시 돌리면 같은 크기가 나온다.
# 그라운드 룰(`shape_grid`)은 여기서 안 건다 — 수동 입력에도 걸려야 하므로 생성 직전에 건다.
static func jitter_grid(grid: Vector2i, seed_value: int) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Vector2i(grid.x + rng.randi_range(-2, 2), grid.y + rng.randi_range(-2, 2))


# 그라운드 룰: **세로는 항상 가로보다 최소 1 크다.** 세로가 더 길어야 화면 비율에 맞는다.
# 흔들기든 수동 입력이든 모든 경로가 생성 직전에 이 보정을 거친다.
#
# 칸 수 상한은 여기서 안 건다 — 기준(9x10)보다 큰 판은 `LevelManager.fitted_tile_size()` 가
# 타일을 줄여 같은 자리에 담는다. 판을 잘라 내는 대신 그리드만 축소하는 쪽이다.
static func shape_grid(grid: Vector2i) -> Vector2i:
	var width: int = maxi(grid.x, 3)
	return Vector2i(width, maxi(grid.y, width + 1))


static func rampf(value_range: Vector2, index: int, count: int) -> float:
	var t: float = float(index) / float(count - 1) if count > 1 else 0.0
	return lerpf(value_range.x, value_range.y, t)


# 스테이지 하나. 첫 탈출 치우기는 1로 고정하고, 사슬 깊이만 단계적으로 낮춰서 풀리는 맵을 낸다.
# 2~3 이상의 첫 탈출 벽은 벽 후보 부족과 중첩 솔버 재실행을 반복시켜 생성 부하가 급증하므로
# 양산 경로에서는 더 이상 입력이나 완화 대상으로 받지 않는다.
# static 인 이유: 에디터 어드민(addons/stage_admin)이 같은 로직을 그대로 쓴다.
static func generate_stage(
	generator: MapGenerator,
	params: Dictionary,
	base_seed: int,
	grid: Vector2i,
	index: int,
	cat_count: int,
	chain_depth: int
) -> Dictionary:
	var stage_started: int = Time.get_ticks_msec()
	var nested_mode: String = str(params.get("nested_mode", "two"))
	var nested_mode_label: String = NESTED_MODE_LABEL.get(nested_mode, "2중첩만")
	print("[스테이지 생성] stage_%03d 생성 시작 / 보드 %dx%d / 고양이 %d / 중첩 %s %.0f%%" % [
		index + 1, shape_grid(grid).x, shape_grid(grid).y, cat_count,
		nested_mode_label, clampf(float(params.get("nested2", 0.7)), 0.0, 1.0) * 100.0,
	])
	var first_min: int = 1
	# 완화 사다리 (사슬 깊이, 첫 탈출 하한). 첫 탈출 하한은 모든 단계에서 1이다.
	var ladder: Array[Vector2i] = []
	for depth in range(chain_depth, -1, -1):
		ladder.append(Vector2i(depth, first_min))

	# MapGenerator.generate() 자체가 시도마다 시드를 바꾸므로 바깥 seed retry 는 중복이다.
	# attempts 를 사다리 전체의 실제 총예산으로 나누며, 합계가 입력값을 절대 넘지 않는다.
	var remaining_attempts: int = maxi(int(params.get("attempts", 120)), 1)
	var remaining_steps: int = ladder.size()
	for step_index in ladder.size():
		if remaining_attempts <= 0:
			break
		var step: Vector2i = ladder[step_index]
		var attempt_budget: int = maxi(
			floori(float(remaining_attempts) / float(remaining_steps)), 1
		)
		remaining_attempts -= attempt_budget
		remaining_steps -= 1

		var config := MapGenerator.default_config()
		config.base_seed = base_seed + index * STAGE_SEED_STRIDE + step_index * 37
		config.grid_size = shape_grid(grid)
		config.cat_count = cat_count
		config.nested_two_chance = clampf(float(params.get("nested2", 0.7)), 0.0, 1.0)
		config.nested_three_ratio = float(NESTED_THREE_RATIO.get(nested_mode, 0.0))
		config.color_count = int(params.get("colors", 20))
		config.body_length_min = int(params.get("len_min", 3))
		config.body_length_max = int(params.get("len_max", 6))
		config.total_length_ratio = float(params.get("pack", 0.7))
		config.reverse_steps_min = int(params.get("steps_min", 5))
		config.reverse_steps_max = int(params.get("steps_max", 12))
		config.min_chain_depth = step.x
		config.obstacle_fill_ratio = float(params.get("obstacle", 0.55))
		config.hole_line_chance = float(params.get("hole_line", 0.5))
		config.min_first_escape_moves = step.y
		config.min_later_escape_moves = int(params.get("later_min", 0))
		config.squeeze_free_cells = int(params.get("squeeze", 1)) != 0
		config.squeeze_node_budget = int(params.get("squeeze_budget", 20000))
		config.min_dependent_cats = maxi(cat_count - int(params.get("dep_slack", 99)), 0)
		config.max_attempts = attempt_budget
		config.ice_chance = float(params.get("ice", 0.0))
		config.ice_number_max = int(params.get("ice_max", 0))
		config.difficulty_limit = int(params.get("diff_limit", 8))
		config.min_difficulty_score = int(params.get("score", 0))

		var level: Dictionary = generator.generate(config)
		if bool(level["ok"]):
			if step.x < chain_depth:
				print("  (스테이지 %d: 사슬 깊이 %d → %d 로 낮춰서 성공, 첫 탈출 하한은 1 고정)" % [
					index + 1, chain_depth, step.x,
				])
			print("[스테이지 생성] stage_%03d 생성 완료 / %dms" % [
				index + 1, Time.get_ticks_msec() - stage_started,
			])
			return level
	print("[스테이지 생성] stage_%03d 생성 실패 / %dms" % [
		index + 1, Time.get_ticks_msec() - stage_started,
	])
	return {}


# 다음에 쓸 스테이지 순번 = 기존 파일의 가장 큰 순번 + 1. 파일이 없으면 1.
# 중간에 지워져 순번에 구멍이 나도 메꾸지 않는다 — 재사용하면 아카이브에 있던 같은 이름과
# 헷갈리고, 게임은 정렬 순서로 돌기 때문에 구멍이 있어도 아무 문제가 없다.
static func next_stage_number(out_dir: String) -> int:
	var dir: DirAccess = DirAccess.open(out_dir)
	if dir == null:
		return 1
	var highest: int = 0
	for file_name in dir.get_files():
		if file_name.begins_with("stage_") and file_name.ends_with(".json"):
			highest = maxi(highest, int(file_name.get_basename().trim_prefix("stage_")))
	return highest + 1


func _parse_args(args: PackedStringArray) -> Dictionary:
	var params: Dictionary = {}
	for arg in args:
		var split: int = arg.find("=")
		if split <= 0:
			push_warning("무시한 인자: %s (key=value 형식이 아니다)" % arg)
			continue
		params[arg.substr(0, split)] = arg.substr(split + 1)
	return params


func _parse_grid(value: String) -> Vector2i:
	var parts: PackedStringArray = value.split("x")
	if parts.size() != 2:
		push_warning("grid 형식이 아니다 (%s), 7x9 를 쓴다" % value)
		return Vector2i(7, 9)
	return Vector2i(maxi(int(parts[0]), 3), maxi(int(parts[1]), 3))


# "0.55..0.9" → (0.55, 0.9), "0.55" → (0.55, 0.55)
static func _parse_float_range(value: String) -> Vector2:
	if value.contains(".."):
		var parts: PackedStringArray = value.split("..")
		return Vector2(float(parts[0]), float(parts[1]))
	var single: float = float(value)
	return Vector2(single, single)


# "3..6" → (3, 6), "4" → (4, 4)
func _parse_range(value: String) -> Vector2i:
	if value.contains(".."):
		var parts: PackedStringArray = value.split("..")
		return Vector2i(int(parts[0]), int(parts[1]))
	var single: int = int(value)
	return Vector2i(single, single)
