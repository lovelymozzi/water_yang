@tool
extends Control

# 스테이지 통합 관리 어드민.
#
#   좌: stage_*.json 목록 (지표 요약)
#   중: 선택 스테이지의 맵 미리보기 (고양이/구멍/장애물)
#   우: 생성 파라미터 + 일괄 생성 / 선택 재생성
#   하: 난이도 곡선 (점 클릭 = 스테이지 선택)
#
# 생성 로직은 새로 만들지 않는다 — MapGenerator 와 stage_batch_generator.generate_stage()
# 를 그대로 호출한다. 파라미터 의미와 램프 규칙은 stage_batch_generator.gd 머리 주석 참조.

const StageBatch := preload("res://scripts/stage_batch_generator.gd")
const LEVELS_DIR := "res://resources/levels"
# 스테이지로 쓰지 않을 맵의 격리 폴더. main_scene 은 LEVELS_DIR 만 읽으므로 여기 있는
# 파일은 플레이에 안 나온다. 삭제·복원은 파일을 지우거나 되옮기는 것으로 한다.
const ARCHIVE_DIR := "res://resources/levels_archive"

var _stage_paths: PackedStringArray = PackedStringArray()
var _levels: Array[Dictionary] = []
var _selected: int = -1
# 선택 재생성을 누를 때마다 시드를 밀어 다른 변형을 얻는다.
var _reroll: int = 0
var _palette: PackedColorArray = PackedColorArray()

var _list: ItemList
var _info: Label
var _status: Label
var _preview: StagePreview
var _curve: DifficultyCurve
var _spins: Dictionary = {}


# 난이도 = 초반 탈출이 얼마나 비싼가. 고양이가 빠질수록 몸+구멍만큼 공간이 열려 뒤쪽
# 사슬이 아무리 깊어도 급락하므로, 1·2번째 탈출까지 치우는 드래그 수(실측)가 지배 항이다.
# 사슬 깊이는 채점에 넣지 않는다.
# ponytail: 가중치 100/50/20 은 휴리스틱. 플레이 데이터가 쌓이면 클리어율로 교정한다.
static func difficulty_of(level: Dictionary) -> float:
	var stats: Dictionary = level.get("stats", {})
	var early: Array = stats.get("early_clearing", [])
	var weights: Array[float] = [100.0, 50.0, 20.0]
	var score: float = 0.5 * float(stats.get("solution_length", 0))
	for index in mini(early.size(), weights.size()):
		score += weights[index] * float(early[index])
	return score


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_palette = _load_palette()
	_build_ui()
	_refresh()


# ---------------------------------------------------------------- UI 구성

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	# ---- 좌: 목록
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 300
	split.add_child(left)

	var refresh := Button.new()
	refresh.text = "새로고침"
	refresh.pressed.connect(_refresh)
	left.add_child(refresh)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_stage_selected)
	left.add_child(_list)

	# ---- 중: 미리보기. 스크롤 컨테이너(우)가 폭을 요구해도 미리보기가 1px 로 짜부라지지
	# 않게 최소 크기를 못 박는다. HSplit 은 이 최소값 아래로는 못 줄인다.
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size.x = 380
	split.add_child(center)

	_info = Label.new()
	_info.text = "스테이지를 선택하세요"
	center.add_child(_info)

	_preview = StagePreview.new()
	_preview.palette = _palette
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(360, 360)
	center.add_child(_preview)

	# ---- 우: 파라미터 + 버튼 (항목이 많아 세로로 넘치므로 스크롤 컨테이너에 넣는다)
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size.x = 300
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right_scroll)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)

	var params_grid := GridContainer.new()
	params_grid.columns = 2
	right.add_child(params_grid)

	_add_spin(params_grid, "count", "스테이지 수", 1, 200, 1, 10)
	_add_spin(params_grid, "seed", "기본 시드", 0, 999999, 1, 1)
	_add_spin(params_grid, "grid_w", "보드 가로", 3, 16, 1, 7)
	_add_spin(params_grid, "grid_h", "보드 세로", 3, 16, 1, 9)
	_add_spin(params_grid, "cats_min", "고양이 (1스테이지)", 2, 8, 1, 3)
	_add_spin(params_grid, "cats_max", "고양이 (마지막)", 2, 8, 1, 6)
	_add_spin(params_grid, "len_min", "몸 길이 하한", 2, 16, 1, 5)
	_add_spin(params_grid, "len_max", "몸 길이 상한", 2, 16, 1, 12)
	_add_spin(params_grid, "pack", "몸이 채우는 비율", 0.2, 0.8, 0.05, 0.65,
		"고양이 몸이 빈 칸 중 차지하는 비율 상한. 넘으면 몸을 깎는다.\n길고 꽉 찬 몸일수록 서로의 탈출로를 물어 빈 공간이 사라진다.\n0.7 을 넘기면 역주행이 막혀 생성이 통째로 실패한다.")
	_add_spin(params_grid, "steps_min", "고양이당 이동 수 하한", 1, 24, 1, 5,
		"고양이 한 마리를 시작 위치에서 구멍까지 보내는 데 필요한 이동 수의 최소치.\n생성기가 구멍에서 거꾸로 걸어 나오며 맵을 만들기 때문에 이 값이 곧 풀이 길이의 뼈대다.\n올리면 맵이 어려워지고, 생성 실패도 늘어난다.")
	_add_spin(params_grid, "steps_max", "고양이당 이동 수 상한", 1, 32, 1, 12,
		"고양이 한 마리의 이동 수 최대치. 하한~상한 사이에서 마리마다 무작위로 뽑는다.")
	_add_spin(params_grid, "obstacle_min", "장애물 비율 (1스테이지)", 0.0, 1.0, 0.05, 0.7,
		"판 전체가 아니라 '풀이가 한 번도 밟지 않는 칸' 중 장애물로 채우는 비율.\n고양이·구멍·이동 경로 칸은 절대 장애물이 되지 않는다.\n스테이지 순번에 따라 (1스테이지)→(마지막) 으로 선형 램프한다.")
	_add_spin(params_grid, "obstacle_max", "장애물 비율 (마지막)", 0.0, 1.0, 0.05, 1.0,
		"높을수록 우회로가 사라져 풀이가 유일해에 가까워지고,\n1.0이면 통로만 남아 '비켜주기'가 사라지고 의존이 실제로 강제된다.")
	_add_spin(params_grid, "dep_slack", "독립 고양이 허용", 1, 6, 1, 2,
		"의존 없이 나갈 수 있는 고양이를 몇 마리까지 허용하는가.\n의존 고양이 하한 = 고양이 수 - 이 값 (실측 검증).\n첫 탈출 고양이는 구조상 독립이라 1 미만은 무의미. 낮출수록 생성 실패가 늘어난다.")
	_add_spin(params_grid, "hole_line", "구멍 관문 배치 확률", 0.0, 1.0, 0.05, 0.5,
		"구멍을 흩뿌리는 대신 안쪽 분할선 위에 관문처럼 늘어놓을 확률.\n판이 구멍 벽으로 갈라져, 반대편으로 가려면 앞 고양이가 나가\n닫힌 구멍 자리를 지나야 한다 = 깊은 의존 사슬이 잘 나온다.")
	_add_spin(params_grid, "first_min", "첫 탈출까지 치우는 수", 0, 6, 1, 1,
		"첫 고양이가 빠지기 전에 '다른 고양이'를 최소 몇 번 움직여야 하는가.\n자기 이동은 드래그 한 번에 몇 칸이든 끌리므로 세지 않는다.\n1 = 드래그 한 번으로 바로 나가는 고양이 없음. 2~3부터 생성 실패가 가파르게 늘어난다.")
	_add_spin(params_grid, "squeeze", "여유 칸 제거", 0, 1, 1, 1,
		"막아도 여전히 풀리는 빈 칸을 전부 장애물로 채운다.\n빈 공간이 사라져 '앞 고양이가 비운 자리'를 여유 없이 써야만 뒤 고양이가 나갈 수 있다.\n칸마다 오토솔버를 한 번 돌리므로 생성이 몇 배 느려진다.")
	_add_spin(params_grid, "later_min", "2번째 이후 탈출 치우는 수", 0, 6, 1, 0,
		"두 번째·세 번째 탈출 전에 '다른 고양이'를 최소 몇 번 움직여야 하는가.\n여유 칸 제거와 짝. 2~3 이면 '1번이 나간 공간을 100% 써야 2번이 나가는' 맵만 통과한다.\n첫 탈출은 위의 '첫 탈출까지 치우는 수'가 따로 본다. 올릴수록 생성 실패가 가파르다.")
	_add_spin(params_grid, "ice", "얼음 확률", 0.0, 1.0, 0.05, 0.0,
		"첫 탈출 구멍을 뺀 구멍마다 이 확률로 얼음을 덮는다.\n얼음 구멍은 고양이 N마리가 빠질 때까지 잠기고, N은 '그 구멍이 풀이에서\n쓰이기 전까지 빠지는 고양이 수' 이하로만 잡혀 풀이가 그대로 성립한다.\n1.0 = 자격 있는 모든 구멍에 얼음. 0 = 얼음 없음.")
	_add_spin(params_grid, "ice_max", "얼음 숫자 상한", 0, 8, 1, 0,
		"얼음 위 숫자의 상한. 0 = 풀이상 안전한 최댓값(그 구멍이 쓰이기 전까지 빠지는\n고양이 수)을 그대로 쓴다. 작게 잡으면 얼음이 더 빨리 깨진다.")
	_add_spin(params_grid, "attempts", "재시도 상한", 1, 400, 1, 120)

	var batch := Button.new()
	batch.text = "일괄 생성 (뒤에 추가)"
	batch.tooltip_text = "기존 스테이지는 건드리지 않고 가장 큰 순번 + 1 부터 이어 붙인다.\n전부 새로 만들려면 levels 폴더를 비우고 누르면 된다."
	batch.pressed.connect(_on_batch_generate)
	right.add_child(batch)

	var regen := Button.new()
	regen.text = "선택 스테이지 재생성"
	regen.pressed.connect(_on_regenerate_selected)
	right.add_child(regen)

	var archive := Button.new()
	archive.text = "선택 스테이지 아카이브"
	archive.tooltip_text = "levels_archive/ 로 옮겨 스테이지에서 뺀다. 파일은 남는다.\n복원 = 파일을 levels/ 로 되옮기기, 완전 삭제 = 파일 지우기."
	archive.pressed.connect(_on_archive_selected)
	right.add_child(archive)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)

	# ---- 하: 난이도 곡선
	_curve = DifficultyCurve.new()
	_curve.custom_minimum_size.y = 150
	_curve.stage_clicked.connect(_select_stage)
	root.add_child(_curve)


func _add_spin(
	parent: Node, key: String, label_text: String,
	min_value: float, max_value: float, step: float, value: float,
	tooltip: String = ""
) -> void:
	var label := Label.new()
	label.text = label_text
	label.tooltip_text = tooltip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.tooltip_text = tooltip
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	_spins[key] = spin


# ---------------------------------------------------------------- 목록/선택

func _refresh() -> void:
	_stage_paths = PackedStringArray()
	_levels.clear()
	var dir: DirAccess = DirAccess.open(LEVELS_DIR)
	if dir != null:
		var names: Array[String] = []
		for file_name in dir.get_files():
			if file_name.begins_with("stage_") and file_name.ends_with(".json"):
				names.append(file_name)
		names.sort()
		for file_name in names:
			_stage_paths.append("%s/%s" % [LEVELS_DIR, file_name])

	_list.clear()
	var difficulties := PackedFloat32Array()
	for path in _stage_paths:
		var level: Dictionary = LevelLayoutWriter.load_json(path)
		_levels.append(level)
		var score: float = difficulty_of(level)
		difficulties.append(score)
		_list.add_item("%s   고양이%d 난이도 %.0f" % [
			path.get_file().get_basename(),
			(level.get("cats", []) as Array).size(),
			score,
		])
	_curve.values = difficulties
	_curve.queue_redraw()

	if _stage_paths.is_empty():
		_selected = -1
		_info.text = "스테이지 없음 — 일괄 생성으로 시작"
		_preview.level = {}
		_preview.queue_redraw()
	else:
		_select_stage(clampi(_selected, 0, _stage_paths.size() - 1))


func _on_stage_selected(index: int) -> void:
	_select_stage(index)


func _select_stage(index: int) -> void:
	if index < 0 or index >= _levels.size():
		return
	_selected = index
	_list.select(index)
	_curve.selected = index
	_curve.queue_redraw()

	var level: Dictionary = _levels[index]
	var stats: Dictionary = level.get("stats", {})
	_info.text = "%s · 고양이 %d · 풀이 %d수 · 장애물 %d칸 · 난이도 %.0f · 시드 %d" % [
		_stage_paths[index].get_file().get_basename(),
		(level.get("cats", []) as Array).size(),
		int(stats.get("solution_length", 0)),
		int(stats.get("obstacle_cells", 0)),
		difficulty_of(level),
		int(level.get("seed", 0)),
	]
	_preview.level = level
	_preview.queue_redraw()


# ---------------------------------------------------------------- 생성

func _params_dict(index: int, count: int) -> Dictionary:
	var t: float = float(index) / float(count - 1) if count > 1 else 0.0
	return {
		"colors": _palette.size(),
		"len_min": int(_spins["len_min"].value),
		"len_max": int(_spins["len_max"].value),
		"steps_min": int(_spins["steps_min"].value),
		"steps_max": int(_spins["steps_max"].value),
		"obstacle": lerpf(
			float(_spins["obstacle_min"].value), float(_spins["obstacle_max"].value), t
		),
		"hole_line": float(_spins["hole_line"].value),
		"first_min": int(_spins["first_min"].value),
			"squeeze": int(_spins["squeeze"].value),
			"later_min": int(_spins["later_min"].value),
		"dep_slack": int(_spins["dep_slack"].value),
		"attempts": int(_spins["attempts"].value),
		"ice": float(_spins["ice"].value),
		"ice_max": int(_spins["ice_max"].value),
	}


func _grid_size() -> Vector2i:
	return Vector2i(int(_spins["grid_w"].value), int(_spins["grid_h"].value))


# 기존 스테이지 뒤에 이어 붙인다 (가장 큰 순번 + 1 부터). 램프(고양이 수·사슬 깊이·장애물)는
# 이번 배치 안에서만 적용된다 — 파라미터를 바꿔 가며 여러 배치를 쌓는 것이 양산 흐름이다.
func _on_batch_generate() -> void:
	var count: int = int(_spins["count"].value)
	var base_seed: int = int(_spins["seed"].value)
	var cats_range := Vector2i(int(_spins["cats_min"].value), int(_spins["cats_max"].value))
	var grid: Vector2i = _grid_size()
	var start_number: int = StageBatch.next_stage_number(LEVELS_DIR)

	var generator := MapGenerator.new()
	# ponytail: 에디터 스레드에서 동기 생성. 스테이지 사이에 한 프레임 양보해 상태 표시만
	# 갱신한다. 수백 스테이지가 느려지면 WorkerThreadPool 로 옮긴다.
	for index in count:
		var stage_number: int = start_number + index
		_status.text = "생성 중 stage_%03d (%d / %d) ..." % [stage_number, index + 1, count]
		await get_tree().process_frame
		var cat_count: int = StageBatch.ramp(cats_range, index, count)
		# 사슬 깊이는 난이도 채점에 안 쓴다. 그래도 의존 자체는 있는 편이 좋으니 "가능한 한
		# 깊게(=고양이 수)"로 시작해 안 나오면 1까지 자동으로 낮춘다(generate_stage 가 처리).
		var chain_depth: int = cat_count
		# 시드 보폭은 전역 순번을 쓴다. 같은 시드로 이어 돌려도 이전 배치와 같은 맵이 안 나온다.
		var level: Dictionary = StageBatch.generate_stage(
			generator, _params_dict(index, count), base_seed, grid,
			stage_number - 1, cat_count, chain_depth
		)
		if level.is_empty():
			_status.text = "stage_%03d 생성 실패 — 중단" % stage_number
			_refresh()
			return
		var error: Error = LevelLayoutWriter.save_json(
			level, "%s/stage_%03d.json" % [LEVELS_DIR, stage_number]
		)
		if error != OK:
			_status.text = "저장 실패 stage_%03d (%d)" % [stage_number, error]
			return
	_status.text = "%d개 추가 완료 (stage_%03d ~ stage_%03d)" % [
		count, start_number, start_number + count - 1,
	]
	_refresh()
	EditorInterface.get_resource_filesystem().scan()


# 선택 스테이지를 levels_archive/ 로 옮긴다. 스테이지 목록에서는 빠지지만 파일은 남아,
# 되살리고 싶으면 파일을 levels/ 로 되옮기면 된다. 완전 삭제는 폴더에서 파일을 지우면 된다.
func _on_archive_selected() -> void:
	if _selected < 0:
		_status.text = "아카이브할 스테이지를 먼저 선택"
		return
	var path: String = _stage_paths[_selected]
	var dir: DirAccess = DirAccess.open(LEVELS_DIR)
	if dir == null:
		_status.text = "levels 폴더를 열지 못했다"
		return
	dir.make_dir_recursive(ARCHIVE_DIR)
	# 아카이브에는 순번이 다른 배치의 같은 순번과 겹칠 수 있으니 시드를 붙여 유일하게 만든다.
	var level: Dictionary = _levels[_selected]
	var archived: String = "%s/%s_seed%d.json" % [
		ARCHIVE_DIR, path.get_file().get_basename(), int(level.get("seed", 0)),
	]
	var error: Error = dir.rename(path, archived)
	if error != OK:
		_status.text = "아카이브 실패 (%d)" % error
		return
	_status.text = "%s → %s" % [path.get_file(), archived.trim_prefix("res://resources/")]
	_refresh()
	EditorInterface.get_resource_filesystem().scan()


func _on_regenerate_selected() -> void:
	if _selected < 0:
		_status.text = "재생성할 스테이지를 먼저 선택"
		return
	var index: int = _selected
	var count: int = maxi(_stage_paths.size(), 1)
	var cats_range := Vector2i(int(_spins["cats_min"].value), int(_spins["cats_max"].value))
	var cat_count: int = StageBatch.ramp(cats_range, index, count)
	var chain_depth: int = cat_count

	_reroll += 1
	_status.text = "스테이지 %d 재생성 중 (변형 %d)..." % [index + 1, _reroll]
	await get_tree().process_frame

	var level: Dictionary = StageBatch.generate_stage(
		MapGenerator.new(), _params_dict(index, count),
		int(_spins["seed"].value) + _reroll * 1009,
		_grid_size(), index, cat_count, chain_depth
	)
	if level.is_empty():
		_status.text = "스테이지 %d 재생성 실패 — 파라미터를 완화해 보세요" % (index + 1)
		return
	var error: Error = LevelLayoutWriter.save_json(level, _stage_paths[index])
	if error != OK:
		_status.text = "저장 실패 (%d)" % error
		return
	_status.text = "stage_%03d 교체 완료 (시드 %d)" % [index + 1, int(level["seed"])]
	_refresh()
	EditorInterface.get_resource_filesystem().scan()


# ---------------------------------------------------------------- 팔레트

# 게임과 같은 색을 쓰기 위해 LevelManager 의 기본 pair_colors 를 빌린다.
func _load_palette() -> PackedColorArray:
	var script: GDScript = load("res://scripts/level_manager.gd")
	if script != null:
		var instance: Object = script.new()
		var colors: Variant = instance.get("pair_colors")
		if instance is Node:
			(instance as Node).free()
		if colors is PackedColorArray and not (colors as PackedColorArray).is_empty():
			return colors
	# 못 읽으면 황금비 색상환으로 대체한다. 어드민 표시용이라 근사면 충분하다.
	var fallback := PackedColorArray()
	for index in 20:
		fallback.append(Color.from_hsv(fmod(index * 0.618, 1.0), 0.55, 0.9))
	return fallback


# ---------------------------------------------------------------- 미리보기

class StagePreview:
	extends Control

	var level: Dictionary = {}
	var palette: PackedColorArray = PackedColorArray()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.16))
		if level.is_empty():
			return
		var grid: Vector2i = level["grid_size"]
		var cell: float = minf(
			(size.x - 20.0) / float(grid.x), (size.y - 20.0) / float(grid.y)
		)
		var origin: Vector2 = (size - Vector2(grid) * cell) * 0.5

		for y in grid.y:
			for x in grid.x:
				var tone: float = 0.22 if (x + y) % 2 == 0 else 0.25
				draw_rect(
					Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell) * 0.96),
					Color(tone, tone + 0.02, tone)
				)

		# 게임(`_build_obstacle_visuals`)과 같이 칸 단위로 그린다. 덩어리를 한 사각형으로
		# 그리면 타일 간격(0.96 배)과 어긋나 여러 칸짜리만 그리드에서 벗어나 보인다.
		for entry in level.get("obstacles", []):
			for obstacle_cell in PuzzleState.cells_of_block(entry):
				draw_rect(
					Rect2(
						origin + Vector2(obstacle_cell as Vector2i) * cell,
						Vector2(cell, cell) * 0.96
					),
					Color(0.45, 0.42, 0.4)
				)

		for entry in level.get("holes", []):
			var center: Vector2 = origin + (Vector2(entry["grid_pos"] as Vector2i) + Vector2(0.5, 0.5)) * cell
			draw_circle(center, cell * 0.38, Color(0.05, 0.05, 0.06))
			draw_arc(center, cell * 0.38, 0.0, TAU, 24, _color_of(int(entry["color_id"])), cell * 0.08)
			# 얼음 구멍은 하늘색 사각형 + 숫자로 표시한다.
			var ice_count: int = int(entry.get("ice_count", 0))
			if ice_count > 0:
				var box: float = cell * 0.72
				draw_rect(
					Rect2(center - Vector2(box, box) * 0.5, Vector2(box, box)),
					Color(0.55, 0.85, 0.95, 0.85)
				)
				draw_string(
					get_theme_default_font(), center + Vector2(-cell * 0.16, cell * 0.18),
					str(ice_count), HORIZONTAL_ALIGNMENT_LEFT, -1, int(cell * 0.5),
					Color(0.09, 0.28, 0.44)
				)

		for entry in level.get("cats", []):
			var body: Array = entry["body_cells"]
			var color: Color = _color_of(int(entry["color_id"]))
			var points := PackedVector2Array()
			for body_cell in body:
				points.append(origin + (Vector2(body_cell as Vector2i) + Vector2(0.5, 0.5)) * cell)
			if points.size() >= 2:
				draw_polyline(points, color, cell * 0.55)
			for point in points:
				draw_circle(point, cell * 0.27, color)
			# 머리(트리거 끝)는 흰 점으로 구분한다.
			draw_circle(points[0], cell * 0.12, Color.WHITE)

	func _color_of(color_id: int) -> Color:
		if palette.is_empty():
			return Color.MAGENTA
		return palette[color_id % palette.size()]


# ---------------------------------------------------------------- 난이도 곡선

class DifficultyCurve:
	extends Control

	signal stage_clicked(index: int)

	var values: PackedFloat32Array = PackedFloat32Array()
	var selected: int = -1

	const MARGIN := 24.0

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.11, 0.13))
		draw_string(
			get_theme_default_font(), Vector2(8, 16), "난이도 곡선",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.7)
		)
		if values.size() < 1:
			return
		var high: float = 1.0
		for value in values:
			high = maxf(high, value)

		var points := PackedVector2Array()
		for index in values.size():
			points.append(_point_at(index, high))
		if points.size() >= 2:
			draw_polyline(points, Color(0.45, 0.7, 1.0), 2.0)
		for index in points.size():
			var is_selected: bool = index == selected
			draw_circle(points[index], 6.0 if is_selected else 4.0,
				Color.YELLOW if is_selected else Color(0.45, 0.7, 1.0))
			draw_string(
				get_theme_default_font(), points[index] + Vector2(-8, -10),
				str(int(values[index])), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.8, 0.8, 0.8)
			)

	func _point_at(index: int, high: float) -> Vector2:
		var x_step: float = (
			(size.x - MARGIN * 2.0) / float(maxi(values.size() - 1, 1))
		)
		return Vector2(
			MARGIN + x_step * index,
			size.y - MARGIN - (values[index] / high) * (size.y - MARGIN * 2.0)
		)

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
			return
		var high: float = 1.0
		for value in values:
			high = maxf(high, value)
		for index in values.size():
			if _point_at(index, high).distance_to(click.position) < 12.0:
				stage_clicked.emit(index)
				return
