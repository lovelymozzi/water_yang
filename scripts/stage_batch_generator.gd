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
#   grid=7x9          보드 크기
#   cats=3..6         고양이 수 (범위 가능)
#   chain=2..4        의존 사슬 깊이 최소치 (범위 가능, 고양이 수를 넘지 않게 잘린다)
#   len_min=5         몸 길이 하한
#   len_max=12        몸 길이 상한
#   pack=0.65         고양이 몸이 빈 칸 중 차지하는 비율 상한. 길고 꽉 찬 몸일수록 서로의
#                     탈출로를 물어 빈 공간이 사라진다. 0.7 을 넘기면 역주행이 막혀 실패한다.
#   steps_min=5       고양이 한 마리의 역주행 걸음 하한
#   steps_max=12      역주행 걸음 상한
#   obstacle=0.7..1.0   풀이가 안 밟는 칸 중 장애물로 채우는 비율 (범위 가능, 스테이지 램프.
#                       1.0 이면 통로만 남아 "비켜주기"가 사라지고 의존이 실제로 강제된다)
#   dep_slack=2       독립(의존 없는) 고양이 허용 마릿수. 의존 고양이 하한 = 고양이 수 - 이 값.
#                     첫 탈출 고양이는 구조상 독립이므로 1 미만은 무의미하다.
#   hole_line=0.5     구멍을 분할선 관문으로 늘어놓을 확률 (0=흩뿌리기만, 1=관문만)
#   first_min=1       첫 흡입까지 "다른 고양이를 치워야 하는" 최소 수.
#                     1 = 드래그 한 번으로 나가는 고양이 없음. 2~3부터 실패가 가파르다.
#   squeeze=1         막아도 여전히 풀리는 빈 칸을 전부 장애물로 채운다 (여유 제거).
#                     빈 공간이 사라져 뒤 순번 고양이가 앞 고양이가 비운 자리를 여유 없이
#                     써야만 나갈 수 있게 된다. 생성이 몇 배 느려진다. 0 = 끈다.
#   later_min=0       두 번째 이후 탈출까지 치워야 하는 최소 수. **거르기만 한다** —
#                     생성기가 이 조건을 만들어 내지는 못한다(map_generator.gd 의
#                     `_plant_first_escape_walls()` 주석 참조). 1 로 걸면 수율이 10%쯤으로
#                     떨어지므로 attempts 를 크게 잡아야 한다.
#   colors=20         색 팔레트 크기 (LevelManager.pair_colors 와 맞춘다)
#   attempts=120      스테이지당 생성 재시도 상한
#   out=res://resources/levels   저장 폴더 (기존 파일은 건드리지 않고 뒤 순번으로 추가)

const STAGE_SEED_STRIDE := 100003
# 같은 스테이지가 첫 시드로 실패했을 때 흔들어 보는 횟수. 그래도 안 되면 사슬 깊이를 낮춘다.
const SEED_RETRIES := 6


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
	var chain_range: Vector2i = _parse_range(str(params.get("chain", "2..4")))
	var obstacle_range: Vector2 = _parse_float_range(str(params.get("obstacle", "0.7..1.0")))
	var out_dir: String = str(params.get("out", "res://resources/levels"))

	var start_number: int = next_stage_number(out_dir)
	print("[스테이지 생성] %d개 (stage_%03d 부터) / 시드 %d / 보드 %s / 고양이 %s / 사슬 %s → %s" % [
		count, start_number, base_seed, grid, cats_range, chain_range, out_dir,
	])

	var generator := MapGenerator.new()
	var made: int = 0
	var started: int = Time.get_ticks_msec()

	for index in count:
		var stage_number: int = start_number + index
		var cat_count: int = ramp(cats_range, index, count)
		var chain_depth: int = mini(ramp(chain_range, index, count), cat_count)
		# 장애물 비율은 실수 램프라 여기서 풀어서 스테이지별 값으로 넘긴다.
		var stage_params: Dictionary = params.duplicate()
		stage_params["obstacle"] = rampf(obstacle_range, index, count)

		# 시드 보폭은 배치 내 순번이 아니라 **전역 스테이지 순번**을 쓴다. 같은 시드로
		# 이어서 돌려도 이전 배치와 같은 맵을 다시 만들지 않게 하기 위해서다.
		var level: Dictionary = generate_stage(
			generator, stage_params, base_seed, grid, stage_number - 1, cat_count, chain_depth
		)
		if level.is_empty():
			push_error("스테이지 %d 생성 실패 — 여기서 중단한다" % stage_number)
			quit(1)
			return

		var path: String = "%s/stage_%03d.json" % [out_dir, stage_number]
		var error: Error = LevelLayoutWriter.save_json(level, path)
		if error != OK:
			push_error("저장 실패 %s (%d)" % [path, error])
			quit(1)
			return
		made += 1
		print("  stage_%03d: 고양이 %d / 사슬 %d / 풀이 %d수 / 시드 %d" % [
			stage_number,
			cat_count,
			int(level["dependency"]["chain_depth"]),
			int(level["stats"]["solution_length"]),
			int(level["seed"]),
		])

	print("[스테이지 생성] %d개 완료 / %dms" % [made, Time.get_ticks_msec() - started])
	quit()


# 스테이지 순번에 따라 [a..b] 를 선형으로 램프한다. 1스테이지가 a, 마지막이 b.
static func ramp(value_range: Vector2i, index: int, count: int) -> int:
	var t: float = float(index) / float(count - 1) if count > 1 else 0.0
	return int(round(lerp(float(value_range.x), float(value_range.y), t)))


static func rampf(value_range: Vector2, index: int, count: int) -> float:
	var t: float = float(index) / float(count - 1) if count > 1 else 0.0
	return lerpf(value_range.x, value_range.y, t)


# 스테이지 하나. 첫 시드가 실패하면 시드를 흔들어 보고, 그래도 안 되면 사슬 깊이를
# 한 단계씩 낮춰서라도 반드시 풀리는 맵을 낸다 (낮췄으면 로그에 남긴다).
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
	for depth in range(chain_depth, 0, -1):
		for retry in SEED_RETRIES:
			var config := MapGenerator.default_config()
			config.base_seed = base_seed + index * STAGE_SEED_STRIDE + retry * 37
			config.grid_size = grid
			config.cat_count = cat_count
			config.color_count = int(params.get("colors", 20))
			config.body_length_min = int(params.get("len_min", 5))
			config.body_length_max = int(params.get("len_max", 12))
			config.total_length_ratio = float(params.get("pack", 0.65))
			config.reverse_steps_min = int(params.get("steps_min", 5))
			config.reverse_steps_max = int(params.get("steps_max", 12))
			config.min_chain_depth = depth
			config.obstacle_fill_ratio = float(params.get("obstacle", 0.55))
			config.hole_line_chance = float(params.get("hole_line", 0.5))
			config.min_first_escape_moves = int(params.get("first_min", 1))
			config.min_later_escape_moves = int(params.get("later_min", 0))
			config.squeeze_free_cells = int(params.get("squeeze", 1)) != 0
			config.min_dependent_cats = maxi(cat_count - int(params.get("dep_slack", 2)), 0)
			config.max_attempts = int(params.get("attempts", 120))
			config.ice_chance = float(params.get("ice", 0.0))
			config.ice_number_max = int(params.get("ice_max", 0))

			var level: Dictionary = generator.generate(config)
			if bool(level["ok"]):
				if depth < chain_depth:
					print("  (스테이지 %d: 사슬 깊이를 %d → %d 로 낮춰서 성공)" % [
						index + 1, chain_depth, depth,
					])
				return level
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
