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


# ponytail: 난이도는 생성기가 이미 계산한 지표의 가중합 휴리스틱. 플레이 데이터가 쌓이면
# 실제 클리어율로 가중치를 교정한다.
static func difficulty_of(level: Dictionary) -> float:
	var stats: Dictionary = level.get("stats", {})
	var dependency: Dictionary = level.get("dependency", {})
	var cats: Array = level.get("cats", [])
	return (
		float(stats.get("solution_length", 0))
		+ 4.0 * float(dependency.get("chain_depth", 0))
		+ 2.0 * float(cats.size())
	)


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

	# ---- 중: 미리보기
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(center)

	_info = Label.new()
	_info.text = "스테이지를 선택하세요"
	center.add_child(_info)

	_preview = StagePreview.new()
	_preview.palette = _palette
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(_preview)

	# ---- 우: 파라미터 + 버튼
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 280
	split.add_child(right)

	var params_grid := GridContainer.new()
	params_grid.columns = 2
	right.add_child(params_grid)

	_add_spin(params_grid, "count", "스테이지 수", 1, 200, 1, 10)
	_add_spin(params_grid, "seed", "기본 시드", 0, 999999, 1, 1)
	_add_spin(params_grid, "grid_w", "보드 가로", 3, 16, 1, 7)
	_add_spin(params_grid, "grid_h", "보드 세로", 3, 16, 1, 9)
	_add_spin(params_grid, "cats_min", "고양이 (1스테이지)", 2, 8, 1, 3)
	_add_spin(params_grid, "cats_max", "고양이 (마지막)", 2, 8, 1, 6)
	_add_spin(params_grid, "chain_min", "사슬 깊이 (1스테이지)", 1, 8, 1, 2)
	_add_spin(params_grid, "chain_max", "사슬 깊이 (마지막)", 1, 8, 1, 4)
	_add_spin(params_grid, "len_min", "몸 길이 하한", 2, 12, 1, 3)
	_add_spin(params_grid, "len_max", "몸 길이 상한", 2, 12, 1, 8)
	_add_spin(params_grid, "steps_min", "고양이당 이동 수 하한", 1, 24, 1, 5,
		"고양이 한 마리를 시작 위치에서 구멍까지 보내는 데 필요한 이동 수의 최소치.\n생성기가 구멍에서 거꾸로 걸어 나오며 맵을 만들기 때문에 이 값이 곧 풀이 길이의 뼈대다.\n올리면 맵이 어려워지고, 생성 실패도 늘어난다.")
	_add_spin(params_grid, "steps_max", "고양이당 이동 수 상한", 1, 32, 1, 12,
		"고양이 한 마리의 이동 수 최대치. 하한~상한 사이에서 마리마다 무작위로 뽑는다.")
	_add_spin(params_grid, "obstacle", "장애물 비율", 0.0, 1.0, 0.05, 0.55,
		"판 전체가 아니라 '풀이가 한 번도 밟지 않는 칸' 중 장애물로 채우는 비율.\n고양이·구멍·이동 경로 칸은 절대 장애물이 되지 않는다.\n0 = 미끼 빈 칸 최대(헷갈림), 1 = 정답 경로 외 전부 장애물(경로가 드러남).")
	_add_spin(params_grid, "attempts", "재시도 상한", 1, 400, 1, 120)

	var batch := Button.new()
	batch.text = "일괄 생성 (기존 전체 교체)"
	batch.pressed.connect(_on_batch_generate)
	right.add_child(batch)

	var regen := Button.new()
	regen.text = "선택 스테이지 재생성"
	regen.pressed.connect(_on_regenerate_selected)
	right.add_child(regen)

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
		_list.add_item("%s   고양이%d 사슬%d 난이도 %.0f" % [
			path.get_file().get_basename(),
			(level.get("cats", []) as Array).size(),
			int((level.get("dependency", {}) as Dictionary).get("chain_depth", 0)),
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
	var dependency: Dictionary = level.get("dependency", {})
	_info.text = "%s · 고양이 %d · 사슬 %d · 풀이 %d수 · 장애물 %d칸 · 난이도 %.0f · 시드 %d" % [
		_stage_paths[index].get_file().get_basename(),
		(level.get("cats", []) as Array).size(),
		int(dependency.get("chain_depth", 0)),
		int(stats.get("solution_length", 0)),
		int(stats.get("obstacle_cells", 0)),
		difficulty_of(level),
		int(level.get("seed", 0)),
	]
	_preview.level = level
	_preview.queue_redraw()


# ---------------------------------------------------------------- 생성

func _params_dict() -> Dictionary:
	return {
		"colors": _palette.size(),
		"len_min": int(_spins["len_min"].value),
		"len_max": int(_spins["len_max"].value),
		"steps_min": int(_spins["steps_min"].value),
		"steps_max": int(_spins["steps_max"].value),
		"obstacle": float(_spins["obstacle"].value),
		"attempts": int(_spins["attempts"].value),
	}


func _grid_size() -> Vector2i:
	return Vector2i(int(_spins["grid_w"].value), int(_spins["grid_h"].value))


func _on_batch_generate() -> void:
	var count: int = int(_spins["count"].value)
	var base_seed: int = int(_spins["seed"].value)
	var cats_range := Vector2i(int(_spins["cats_min"].value), int(_spins["cats_max"].value))
	var chain_range := Vector2i(int(_spins["chain_min"].value), int(_spins["chain_max"].value))
	var params: Dictionary = _params_dict()
	var grid: Vector2i = _grid_size()

	StageBatch._remove_old_stages(LEVELS_DIR)
	var generator := MapGenerator.new()
	# ponytail: 에디터 스레드에서 동기 생성. 스테이지 사이에 한 프레임 양보해 상태 표시만
	# 갱신한다. 수백 스테이지가 느려지면 WorkerThreadPool 로 옮긴다.
	for index in count:
		_status.text = "생성 중 %d / %d ..." % [index + 1, count]
		await get_tree().process_frame
		var cat_count: int = StageBatch.ramp(cats_range, index, count)
		var chain_depth: int = mini(StageBatch.ramp(chain_range, index, count), cat_count)
		var level: Dictionary = StageBatch.generate_stage(
			generator, params, base_seed, grid, index, cat_count, chain_depth
		)
		if level.is_empty():
			_status.text = "스테이지 %d 생성 실패 — 중단" % (index + 1)
			_refresh()
			return
		var error: Error = LevelLayoutWriter.save_json(
			level, "%s/stage_%03d.json" % [LEVELS_DIR, index + 1]
		)
		if error != OK:
			_status.text = "저장 실패 stage_%03d (%d)" % [index + 1, error]
			return
	_status.text = "%d개 생성 완료" % count
	_refresh()
	EditorInterface.get_resource_filesystem().scan()


func _on_regenerate_selected() -> void:
	if _selected < 0:
		_status.text = "재생성할 스테이지를 먼저 선택"
		return
	var index: int = _selected
	var count: int = maxi(_stage_paths.size(), 1)
	var cats_range := Vector2i(int(_spins["cats_min"].value), int(_spins["cats_max"].value))
	var chain_range := Vector2i(int(_spins["chain_min"].value), int(_spins["chain_max"].value))
	var cat_count: int = StageBatch.ramp(cats_range, index, count)
	var chain_depth: int = mini(StageBatch.ramp(chain_range, index, count), cat_count)

	_reroll += 1
	_status.text = "스테이지 %d 재생성 중 (변형 %d)..." % [index + 1, _reroll]
	await get_tree().process_frame

	var level: Dictionary = StageBatch.generate_stage(
		MapGenerator.new(), _params_dict(),
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
