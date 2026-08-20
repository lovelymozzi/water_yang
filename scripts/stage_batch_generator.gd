extends SceneTree

# 스테이지 배치 생성기. 검증된 레벨 N개를 만들어 stage_001.json 부터 순번으로 저장한다.
# main_scene 이 플레이 시 이 파일들을 1번부터 차례로 읽는다.
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
#   len_min=3         몸 길이 하한
#   len_max=8         몸 길이 상한
#   steps_min=5       고양이 한 마리의 역주행 걸음 하한
#   steps_max=12      역주행 걸음 상한
#   obstacle=0.55     풀이가 안 밟는 칸 중 장애물로 채우는 비율
#   colors=20         색 팔레트 크기 (LevelManager.pair_colors 와 맞춘다)
#   attempts=120      스테이지당 생성 재시도 상한
#   out=res://resources/levels   저장 폴더 (기존 stage_*.json 은 지우고 새로 쓴다)

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
	var out_dir: String = str(params.get("out", "res://resources/levels"))

	print("[스테이지 생성] %d개 / 시드 %d / 보드 %s / 고양이 %s / 사슬 %s → %s" % [
		count, base_seed, grid, cats_range, chain_range, out_dir,
	])
	_remove_old_stages(out_dir)

	var generator := MapGenerator.new()
	var made: int = 0
	var started: int = Time.get_ticks_msec()

	for index in count:
		var t: float = float(index) / float(count - 1) if count > 1 else 0.0
		var cat_count: int = int(round(lerp(float(cats_range.x), float(cats_range.y), t)))
		var chain_depth: int = mini(
			int(round(lerp(float(chain_range.x), float(chain_range.y), t))), cat_count
		)

		var level: Dictionary = _generate_stage(
			generator, params, base_seed, grid, index, cat_count, chain_depth
		)
		if level.is_empty():
			push_error("스테이지 %d 생성 실패 — 여기서 중단한다" % (index + 1))
			quit(1)
			return

		var path: String = "%s/stage_%03d.json" % [out_dir, index + 1]
		var error: Error = LevelLayoutWriter.save_json(level, path)
		if error != OK:
			push_error("저장 실패 %s (%d)" % [path, error])
			quit(1)
			return
		made += 1
		print("  stage_%03d: 고양이 %d / 사슬 %d / 풀이 %d수 / 시드 %d" % [
			index + 1,
			cat_count,
			int(level["dependency"]["chain_depth"]),
			int(level["stats"]["solution_length"]),
			int(level["seed"]),
		])

	print("[스테이지 생성] %d개 완료 / %dms" % [made, Time.get_ticks_msec() - started])
	quit()


# 스테이지 하나. 첫 시드가 실패하면 시드를 흔들어 보고, 그래도 안 되면 사슬 깊이를
# 한 단계씩 낮춰서라도 반드시 풀리는 맵을 낸다 (낮췄으면 로그에 남긴다).
func _generate_stage(
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
			config.body_length_min = int(params.get("len_min", 3))
			config.body_length_max = int(params.get("len_max", 8))
			config.reverse_steps_min = int(params.get("steps_min", 5))
			config.reverse_steps_max = int(params.get("steps_max", 12))
			config.min_chain_depth = depth
			config.obstacle_fill_ratio = float(params.get("obstacle", 0.55))
			config.max_attempts = int(params.get("attempts", 120))

			var level: Dictionary = generator.generate(config)
			if bool(level["ok"]):
				if depth < chain_depth:
					print("  (스테이지 %d: 사슬 깊이를 %d → %d 로 낮춰서 성공)" % [
						index + 1, chain_depth, depth,
					])
				return level
	return {}


# 갯수를 줄여 다시 만들었을 때 옛 파일이 뒤에 붙어 재생되지 않도록 전부 지우고 시작한다.
func _remove_old_stages(out_dir: String) -> void:
	var dir: DirAccess = DirAccess.open(out_dir)
	if dir == null:
		return
	for file_name in dir.get_files():
		if file_name.begins_with("stage_") and file_name.ends_with(".json"):
			dir.remove(file_name)


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


# "3..6" → (3, 6), "4" → (4, 4)
func _parse_range(value: String) -> Vector2i:
	if value.contains(".."):
		var parts: PackedStringArray = value.split("..")
		return Vector2i(int(parts[0]), int(parts[1]))
	var single: int = int(value)
	return Vector2i(single, single)
