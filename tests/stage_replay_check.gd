extends SceneTree

# 저장된 스테이지의 정답 재현이 **실제 게임에서** 끝까지 도는지 본다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --script tests/stage_replay_check.gd \
#       -- stage=10
#
# 재생 로직을 여기서 다시 쓰지 않는다 — `main_scene.gd` 의 "정답 재현" 버튼이 부르는
# 그 코드를 그대로 눌러 본다. 그래서 이 검사가 통과하면 에디터에서 버튼을 눌렀을 때도
# 같은 결과가 나온다. 고양이를 움직이는 것은 `CatEntity._process()` 이므로 프레임을
# 그냥 흘려보내며 기다린다.
#
# `stage_solve_check.gd` 는 모델(`PuzzleState`)에서 풀리는지를 보고, 이쪽은 그 풀이가
# 진짜 게임 규칙에서도 도는지를 본다. 둘이 갈라지면 모델이 게임을 잘못 복제한 것이다.

const FRAME_GUARD := 20000

var _scene: Node
var _frames := 0
var _stage_number := 10
var _started := false
var _failures: Array[String] = []
var _seen_index := -99
var _model: PuzzleState
var _applied := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("stage="):
			_stage_number = int(arg.substr(6))
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	# LevelManager 가 씬 배치 처리를 끝낼 시간을 준다.
	if _frames < 10:
		return false

	if not _started:
		_started = true
		# `--script` 로 돌면 main_scene 이 스테이지 모드를 켜지 않으므로 목록을 직접 넣는다.
		_scene.set("_stage_paths", _stage_files())
		var paths: PackedStringArray = _scene.get("_stage_paths")
		if paths.is_empty():
			_failures.append("resources/levels 에 stage_*.json 이 없다")
			return _report()
		var index: int = clampi(_stage_number - 1, 0, paths.size() - 1)
		_scene.call("_load_stage", index)
		if (_scene.get("_stage_solution") as Array).is_empty():
			_failures.append("%s 에 기록된 풀이가 없다" % paths[index])
			return _report()
		# 버튼이 실제로 떠 있는지도 본다 — 아래는 그 버튼이 부르는 코드를 직접 부른다.
		var button: Button = _scene.get_node_or_null("CanvasLayer/ReplayButton") as Button
		if button == null or not button.visible:
			_failures.append("정답 재현 버튼이 화면에 없다")
			return _report()
		_model = LevelLayoutWriter.to_puzzle_state(
			LevelLayoutWriter.load_json(paths[index])
		)
		_scene.call("_on_replay_pressed")
		if int(_scene.get("_replay_index")) < 0:
			_failures.append("재현이 시작되지 않았다")
			return _report()
		return false

	# 커밋된 수마다 모델을 나란히 돌려 몸을 대조한다. 게임과 모델이 갈라지는 첫 지점이
	# 곧 `PuzzleState` 가 게임 규칙을 잘못 복제한 자리다.
	var now: int = int(_scene.get("_replay_index"))
	if now != _seen_index:
		_seen_index = now
		if now >= 0:
			_sync_model(now)
	# 재현이 끝나면 `_replay_index` 가 -1 로 돌아온다.
	if int(_scene.get("_replay_index")) >= 0:
		if _frames < FRAME_GUARD:
			return false
		_failures.append(
			"%d프레임 안에 재현이 끝나지 않았다 (%d번째 수에서 멈춤)"
			% [FRAME_GUARD, int(_scene.get("_replay_index")) + 1]
		)
		return _report()

	var manager: LevelManager = _scene.get_node("LevelManager")
	var solution: Array = _scene.get("_stage_solution")
	if not manager.get_cats().is_empty():
		_failures.append(
			"재현이 끝났는데 고양이 %d마리가 남았다" % manager.get_cats().size()
		)
	else:
		print("[재현] 스테이지 %d: %d수를 눌러 전원 탈출 (%d프레임)" % [
			_stage_number, solution.size(), _frames,
		])
	return _report()


# 모델을 `committed` 수까지 진행시키고 게임과 대조한다.
func _sync_model(committed: int) -> void:
	var solution: Array = _scene.get("_stage_solution")
	var cats_root: Node = _scene.get_node("LevelManager/LayoutCats")
	while _applied < committed and _applied < solution.size():
		var move: Dictionary = solution[_applied]
		if not bool(_model.apply_move(move)["moved"]):
			_failures.append("%d번째 수를 모델이 거부했다: %s" % [_applied + 1, move])
			return
		_applied += 1
	for cat_id in _model.cat_ids():
		var cat: CatEntity = cats_root.get_node_or_null("Cat_%d" % cat_id) as CatEntity
		if cat == null or not is_instance_valid(cat):
			_failures.append(
				"%d수 시점: 모델에는 고양이 %d 가 있는데 게임에서 사라졌다" % [committed, cat_id]
			)
			return
		if not _same_body(cat.body_cells, _model.body_of(int(cat_id))):
			_failures.append(
				"%d수 시점 고양이 %d 의 몸이 갈라졌다: 게임 %s, 모델 %s"
				% [committed, cat_id, cat.body_cells, _model.body_of(int(cat_id))]
			)
			return


func _same_body(actual: Array[Vector2i], expected: Array[Vector2i]) -> bool:
	if actual == expected:
		return true
	var flipped: Array[Vector2i] = expected.duplicate()
	flipped.reverse()
	return actual == flipped


func _stage_files() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open("res://resources/levels")
	if dir == null:
		return paths
	var names: Array[String] = []
	for file_name in dir.get_files():
		if file_name.begins_with("stage_") and file_name.ends_with(".json"):
			names.append(file_name)
	names.sort()
	for file_name in names:
		paths.append("res://resources/levels/" + file_name)
	return paths


func _report() -> bool:
	if _failures.is_empty():
		print("STAGE REPLAY: PASS")
	else:
		print("STAGE REPLAY: FAIL (%d)" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
	return true
