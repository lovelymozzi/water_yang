extends Node

# 스테이지 진행 검사. main_scene 을 띄워 stage_001.json 로드가 실제 보드에 반영되는지,
# 스테이지 파일 목록이 순번대로 잡히는지 본다.
#   /Applications/Godot.app/Contents/MacOS/Godot --headless res://tests/stage_progression_check.tscn
#
# UiBridge 오토로드를 쓰는 main_scene 이므로 --script 대신 씬으로 실행한다.

var _main: Node
var _frames: int = 0
var _failures: Array[String] = []
var _stage_loaded: bool = false


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main_scene.tscn")
	_main = scene.instantiate()
	add_child(_main)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 20:
		_run_checks()
	if _frames == 40:
		_report()
		set_process(false)


func _run_checks() -> void:
	_expect(_main._format_stage_timer(60) == "01:00", "1분 타이머 표시가 01:00이 아니다")
	_expect(_main._format_stage_timer(0) == "00:00", "0초 타이머 표시가 00:00이 아니다")
	_expect(
		_main.get_node_or_null("CanvasLayer/TimeoutWarningOverlay") != null,
		"타임아웃 경고 오버레이가 없다"
	)
	var warning_material: ShaderMaterial = _main.get_node(
		"CanvasLayer/TimeoutWarningOverlay"
	).material
	_main._stage_time_left = 5.0
	_main._stage_timer_running = true
	_main._process(0.0)
	_expect(
		float(warning_material.get_shader_parameter("strength")) > 0.0,
		"5초 남았을 때 타임아웃 경고가 켜지지 않았다"
	)
	_main._stage_timer_running = false
	_main._process(0.0)
	_expect(
		is_zero_approx(float(warning_material.get_shader_parameter("strength"))),
		"타이머가 멈췄는데 타임아웃 경고가 남아 있다"
	)
	_main._on_host_start()
	_expect(not _main._stage_timer_running, "첫 터치 전 타이머가 시작됐다")
	var first_touch := InputEventScreenTouch.new()
	first_touch.pressed = true
	(_main.get_node("DragController") as Node)._unhandled_input(first_touch)
	_expect(not _main._stage_timer_running, "빈 곳 터치가 타이머를 시작했다")
	var manager: LevelManager = _main.level_manager
	var camera: Camera3D = _main.get_viewport().get_camera_3d()
	_expect(not manager.get_cats().is_empty() and camera != null, "타이머 입력 검사용 고양이 또는 카메라가 없다")
	if not manager.get_cats().is_empty() and camera != null:
		var cat: CatEntity = manager.get_cats()[0]
		first_touch.position = camera.unproject_position(
			manager.grid_to_world(cat.get_lead_cell(), manager.cat_world_y)
		)
		(_main.get_node("DragController") as Node)._unhandled_input(first_touch)
		_expect(_main._stage_timer_running, "첫 보드 조작 뒤 타이머가 시작되지 않았다")
	_main._on_host_force_quit("")
	var paths: PackedStringArray = _main._list_stage_files()
	_expect(paths.size() == 237, "스테이지 파일 수가 237개가 아니다: %d" % paths.size())
	for index in paths.size():
		_expect(
			paths[index].ends_with("stage_%03d.json" % (index + 1)),
			"스테이지 %d 경로가 순번과 다르다: %s" % [index + 1, paths[index]]
		)

	if paths.is_empty():
		return
	var level: Dictionary = LevelLayoutWriter.load_json(paths[0])
	_expect(not level.is_empty(), "stage_001 JSON 을 읽지 못했다")
	if level.is_empty():
		return

	_main._stage_paths = paths
	_main._load_stage(0)
	_stage_loaded = true

	manager = _main.level_manager
	var expected_cats: int = (level["cats"] as Array).size()
	var expected_holes: int = (level["holes"] as Array).size()
	_expect(
		manager.get_cats().size() == expected_cats,
		"고양이 수가 다르다: 보드 %d / JSON %d" % [manager.get_cats().size(), expected_cats]
	)
	_expect(
		manager.get_hole_cells().size() == expected_holes,
		"구멍 수가 다르다: 보드 %d / JSON %d" % [manager.get_hole_cells().size(), expected_holes]
	)
	_expect(
		int(_main._stage_index) == 0,
		"스테이지 인덱스가 0이 아니다: %d" % int(_main._stage_index)
	)
	_expect(
		(_main._stage_label as Label).visible,
		"스테이지 라벨이 보이지 않는다"
	)
	_expect(is_equal_approx(_main._stage_time_left, 60.0), "쉬움 스테이지의 제한 시간이 1분이 아니다")
	_main._load_stage(1)
	_expect(is_equal_approx(_main._stage_time_left, 150.0), "중간 스테이지의 제한 시간이 2분 30초가 아니다")
	_main._load_stage(235)
	_expect(is_equal_approx(_main._stage_time_left, 300.0), "어려움 스테이지의 제한 시간이 5분이 아니다")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("[스테이지 검사] 통과 (로드됨: %s)" % _stage_loaded)
	else:
		for failure in _failures:
			printerr("[스테이지 검사] 실패: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
