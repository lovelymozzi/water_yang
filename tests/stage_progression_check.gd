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
	var drag_controller: Node = _main.get_node("DragController")
	drag_controller._unhandled_input(InputEventMouseMotion.new())
	drag_controller._unhandled_input(InputEventKey.new())
	var first_touch := InputEventScreenTouch.new()
	drag_controller._unhandled_input(first_touch)
	_expect(not _main._stage_timer_running, "이동·키보드·터치 해제가 타이머를 시작했다")
	first_touch.pressed = true
	drag_controller._unhandled_input(first_touch)
	var first_touch_time: float = _main._stage_time_left
	_main._process(0.125)
	_expect(_main._stage_timer_running and _main._stage_time_left < first_touch_time,
		"빈 곳을 한 번 터치해도 타이머가 시작되지 않는다")
	for input_kind in ["mouse", "hud", "hidden", "paused"]:
		_main._stage_timer_running = false
		_main._stage_timer_waiting_for_touch = true
		_main.visible = input_kind != "hidden"
		get_tree().paused = input_kind == "paused"
		if input_kind == "mouse":
			var mouse_press := InputEventMouseButton.new()
			mouse_press.button_index = MOUSE_BUTTON_LEFT
			mouse_press.pressed = true
			drag_controller._unhandled_input(mouse_press)
		else:
			_main._on_host_message("stage_touch", {})
		_expect(_main._stage_timer_running == (input_kind == "mouse" or input_kind == "hud"),
			"첫 터치 처리 상태가 다르다: " + input_kind)
		get_tree().paused = false
		_main.show()
	_main._on_host_message("stage_touch", {})
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
	# 시간 초과 뒤 20초를 받는 Retry도 추가 터치 없이 재개되어야 한다.
	_main._stage_timer_stop_until_msec = Time.get_ticks_msec() + 10000
	_main._on_host_message("continue_stage", {"timeLimitSeconds": 20})
	_expect(is_equal_approx(_main._stage_time_left, 20.0) and not _main._stage_timer_running,
		"20초 Retry의 준비 상태 또는 지급 시간이 다르다")
	UiBridge.host_resume.emit()
	for tick in 40:
		_main._process(0.125)
	print("[20초 Retry] 추가 입력 없이 5초 후 남은 시간: %.3f" % _main._stage_time_left)
	_expect(not _main._stage_timer_waiting_for_touch and _main._stage_timer_running
		and is_equal_approx(_main._stage_time_left, 15.0), "20초 Retry가 터치 없이 카운트다운하지 않는다")
	_expect(_main._stage_timer_stop_until_msec == 0, "20초 Retry에 이전 시간정지가 남았다")
	_main._on_host_force_quit("")
	# Retry skips first-touch waiting; initialization still waits for host start/resume.
	var initial_paths: PackedStringArray = _main._stage_paths
	_main._stage_paths = PackedStringArray()
	_main._stage_timer_stop_until_msec = Time.get_ticks_msec() + 10000
	_main._on_host_initialize({"stage": 1, "config": {"startTimerImmediately": true}})
	_expect(not _main._stage_timer_running, "Retry 초기화 중 호스트 시작 전에 타이머가 돌았다")
	_expect(not _main._stage_timer_waiting_for_touch, "Retry가 첫 터치를 다시 기다린다")
	_expect(_main._stage_timer_stop_until_msec == 0, "Retry에 이전 시간정지 효과가 남았다")
	_main._on_host_start()
	var retry_time: float = _main._stage_time_left
	_main._process(0.125)
	_expect(_main._stage_timer_running and _main._stage_time_left < retry_time,
		"Retry 후 입력 없이 타이머가 감소하지 않는다")
	UiBridge.host_pause.emit("settings")
	var paused_time: float = _main._stage_time_left
	_main._process(0.125)
	_expect(is_equal_approx(_main._stage_time_left, paused_time), "설정창에서 Retry 타이머가 멈추지 않는다")
	UiBridge.host_resume.emit()
	_main._process(0.125)
	_expect(_main._stage_time_left < paused_time, "설정창을 닫은 뒤 Retry 타이머가 재개되지 않는다")
	_main._on_host_force_quit("")
	_main._on_host_initialize({"stage": 1, "config": {"startTimerImmediately": true}})
	UiBridge.host_resume.emit()
	_expect(_main._stage_timer_running, "일시정지된 세션의 Retry에서 타이머가 재개되지 않는다")
	_main._on_host_force_quit("")
	_main._on_host_initialize({"stage": 2, "config": {}})
	_main._on_host_start()
	UiBridge.host_pause.emit("settings")
	UiBridge.host_resume.emit()
	var untouched_time: float = _main._stage_time_left
	_main._process(0.125)
	_expect(_main._stage_timer_waiting_for_touch and not _main._stage_timer_running
		and is_equal_approx(_main._stage_time_left, untouched_time), "새 스테이지의 첫 조작 대기가 사라졌다")
	_main._on_host_force_quit("")
	_main._stage_paths = initial_paths
	# 실제 지연 보드 재로드까지 거쳐도 Retry의 즉시 시작 정책을 유지해야 한다.
	_main._on_host_initialize({"stage": 1, "config": {"startTimerImmediately": true}})
	UiBridge.host_resume.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var reloaded_time: float = _main._stage_time_left
	_main._process(0.125)
	_expect(_main._stage_timer_running and not _main._stage_timer_waiting_for_touch
		and _main._stage_time_left < reloaded_time, "보드 재로드 후 Retry가 첫 터치를 다시 기다린다")
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
	# 맵 순번 대신 실제 난이도로 중간/어려움 검사 대상을 고른다.
	var timer_stages := {150.0: -1, 300.0: -1}
	for index in paths.size():
		var stage: Dictionary = LevelLayoutWriter.load_json(paths[index])
		var score: int = int(stage.get("stats", {}).get("difficulty_score", 0))
		if score > 35 and score <= 70 and timer_stages[150.0] == -1:
			timer_stages[150.0] = index
		if score > 70 and timer_stages[300.0] == -1:
			timer_stages[300.0] = index
	for seconds in timer_stages:
		var index: int = timer_stages[seconds]
		_expect(index >= 0, "%d초 제한 시간 검사용 스테이지가 없다" % seconds)
		if index >= 0:
			_main._load_stage(index)
			_expect(is_equal_approx(_main._stage_time_left, seconds), "%d초 제한 시간이 다르다" % seconds)


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
