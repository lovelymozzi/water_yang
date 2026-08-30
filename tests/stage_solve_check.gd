extends SceneTree

# 저장된 스테이지 파일을 오토솔버로 풀어 본다. "이 맵 해가 없는 것 같다"를 판정하는 도구다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/stage_solve_check.gd \
#       -- stage=res://resources/levels/stage_010.json budget=400000
#
# 인자 없이 돌리면 `resources/levels` 의 stage_*.json 전부를 본다.
# 검사 순서 (앞이 깨지면 뒤는 볼 필요가 없다):
#   1. 시작 배치 규칙 (짝 구멍 인접 등)
#   2. 파일에 기록된 풀이가 그대로 재생되는지
#   3. 기록과 무관하게 오토솔버가 스스로 푸는지

const LEVELS_DIR := "res://resources/levels"


func _initialize() -> void:
	var params: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		var split: int = arg.find("=")
		if split > 0:
			params[arg.substr(0, split)] = arg.substr(split + 1)

	var paths: Array[String] = []
	if params.has("stage"):
		paths.append(str(params["stage"]))
	else:
		var dir: DirAccess = DirAccess.open(LEVELS_DIR)
		if dir != null:
			var names: Array[String] = []
			for file_name in dir.get_files():
				if file_name.begins_with("stage_") and file_name.ends_with(".json"):
					names.append(file_name)
			names.sort()
			for file_name in names:
				paths.append("%s/%s" % [LEVELS_DIR, file_name])

	var budget: int = int(params.get("budget", 400000))
	for path in paths:
		_check(path, budget)
	quit()


func _check(path: String, budget: int) -> void:
	var level: Dictionary = LevelLayoutWriter.load_json(path)
	if level.is_empty():
		print("%s: 읽지 못했다" % path)
		return
	var label: String = path.get_file().get_basename()
	var state: PuzzleState = LevelLayoutWriter.to_puzzle_state(level)

	var problems: Array[String] = state.start_layout_problems()
	if not problems.is_empty():
		print("%s: ✗ 시작 배치 위반 %s" % [label, problems])
		return

	# 기록된 풀이 재생.
	var replay: PuzzleState = state.clone()
	var recorded: Array = level.get("solution", [])
	var broke_at: int = -1
	for index in recorded.size():
		if not bool(replay.apply_move(recorded[index])["moved"]):
			broke_at = index
			break
	var replay_note: String = ""
	if broke_at >= 0:
		replay_note = "기록 풀이 %d/%d 수에서 끊김 %s" % [
			broke_at, recorded.size(), recorded[broke_at],
		]
		var broken_move: Dictionary = recorded[broke_at]
		var broken_cat: int = int(broken_move["cat_id"])
		print("    끊김 직전: cat=%d color=%d nested=%s body=%s target=%s holes=%s cats=%s" % [
			broken_cat,
			replay.color_of(broken_cat),
			replay.nested_colors_of(broken_cat),
			replay.body_of(broken_cat),
			broken_move["to_cell"],
			replay.holes,
			replay.cats,
		])
	elif not replay.is_solved():
		replay_note = "기록 풀이를 다 재생했는데 고양이 %s 가 남음" % [replay.cat_ids()]
	else:
		replay_note = "기록 풀이 %d수 재생 OK" % recorded.size()

	# 기록과 무관한 독립 풀이.
	var started: int = Time.get_ticks_msec()
	var solved: Dictionary = LevelSolver.new().solve(state, budget)
	var elapsed: int = Time.get_ticks_msec() - started
	if bool(solved["found"]):
		print("%s: ✓ 풀린다 (%d수, 노드 %d, %dms) / %s" % [
			label, (solved["moves"] as Array).size(), int(solved["nodes"]), elapsed, replay_note,
		])
		return

	print("%s: ✗ 오토솔버가 못 풀었다 — %s (노드 %d, %dms) / %s" % [
		label, solved["reason"], int(solved["nodes"]), elapsed, replay_note,
	])
	# 누가 갇혔는지까지 짚어 준다. 혼자서도, 앞 고양이가 다 나간 뒤에도 못 나가는 고양이가
	# 있으면 그 고양이가 원인이다.
	var solver := LevelSolver.new()
	for cat_id in state.cat_ids():
		var gone: Array[int] = []
		for other in state.cat_ids():
			if int(other) != int(cat_id):
				gone.append(int(other))
		if not solver.can_escape_alone(state, int(cat_id), gone):
			print("    고양이 %d: 판을 혼자 다 써도 구멍에 닿지 못한다 (구조적으로 갇혔다)" % cat_id)
