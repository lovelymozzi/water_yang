extends Node3D

# 이 시간을 넘긴 프레임은 로그에 상태와 함께 남긴다. 프리즈 원인을 좁히기 위한 계측이다.
const FRAME_STALL_WARNING_SECONDS := 0.25
const DRAG_CONTROLLER_SCRIPT = preload("res://scripts/drag_controller.gd")

# `stage_batch_generator.gd` 가 stage_001.json 부터 순번으로 저장하는 폴더.
# 파일이 하나라도 있으면 플레이는 1스테이지부터 차례로 진행한다.
const STAGE_LEVELS_DIR := "res://resources/levels"
const STAGE_ADVANCE_DELAY_SECONDS := 1.4
const DEFAULT_STAGE_TIME_SECONDS := 60.0

@onready var level_manager: LevelManager = $LevelManager
@onready var clear_label: Label = $CanvasLayer/ClearLabel

var _stall_reports := 0
var _stage_paths: PackedStringArray = PackedStringArray()
# -1 은 스테이지 모드가 아니라는 뜻 (씬 손 배치나 시드 테스트 플레이).
var _stage_index: int = -1
var _stage_label: Label
var _stage_time_left := DEFAULT_STAGE_TIME_SECONDS
var _stage_timer_running := false
var _last_reported_seconds := -1
var _requested_stage_index := 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.98, 0.90, 0.78, 1.0))
	# The editor viewport has its own preview environment, but the Play View
	# does not inherit it. Define the runtime environment explicitly so the
	# toon rim and bright cat highlights keep the same soft, bloomed finish.
	var runtime_environment := Environment.new()
	runtime_environment.background_mode = Environment.BG_COLOR
	runtime_environment.background_color = Color(0.40, 0.48, 0.42, 1.0)
	runtime_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	runtime_environment.ambient_light_color = Color(0.63, 0.72, 0.66, 1.0)
	runtime_environment.ambient_light_energy = 0.42
	runtime_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	runtime_environment.tonemap_exposure = 1.08
	runtime_environment.tonemap_white = 1.35
	runtime_environment.glow_enabled = true
	runtime_environment.glow_normalized = true
	runtime_environment.glow_hdr_threshold = 0.25
	runtime_environment.glow_hdr_scale = 2.0
	runtime_environment.glow_intensity = 0.85
	runtime_environment.glow_strength = 0.72
	runtime_environment.glow_bloom = 0.18
	var world_environment := WorldEnvironment.new()
	world_environment.name = "RuntimeWorldEnvironment"
	world_environment.environment = runtime_environment
	add_child(world_environment)

	clear_label.visible = false
	clear_label.text = ""
	clear_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	clear_label.offset_left = 0.0
	clear_label.offset_top = 0.0
	clear_label.offset_right = 0.0
	clear_label.offset_bottom = 0.0
	clear_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clear_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clear_label.add_theme_font_size_override("font_size", 42)
	clear_label.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0, 1.0))
	clear_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	level_manager.level_cleared.connect(_on_level_cleared)
	UiBridge.host_initialize.connect(_on_host_initialize)
	UiBridge.host_start.connect(_on_host_start)
	UiBridge.host_force_quit.connect(_on_host_force_quit)

	# 드래그 입력은 별도 노드가 전담한다. 헤드리스 검증에서 이벤트를 직접 주입하기 쉽다.
	var drag_controller: Node = DRAG_CONTROLLER_SCRIPT.new()
	drag_controller.name = "DragController"
	drag_controller.level_manager = level_manager
	add_child(drag_controller)

	print("[boot] 로그 파일 위치: ", ProjectSettings.globalize_path("user://logs/"))

	_setup_stage_label()
	if _stage_mode_allowed():
		_stage_paths = _list_stage_files()
		if not _stage_paths.is_empty():
			# LevelManager 가 자기 _ready 의 씬 배치 처리를 끝낸 뒤에 갈아 끼운다.
			call_deferred("_load_stage", 0)


func _process(delta: float) -> void:
	if _stage_timer_running:
		_stage_time_left = maxf(0.0, _stage_time_left - delta)
		var seconds_left := ceili(_stage_time_left)
		if seconds_left != _last_reported_seconds:
			_last_reported_seconds = seconds_left
			UiBridge.post_hud({"timeLeft": _format_stage_timer(seconds_left)})
		if seconds_left == 0:
			_stage_timer_running = false
			if UiBridge.is_hosted:
				UiBridge.post_end("fail", 0)

	# 멈춘 프레임을 그 시점의 상태와 함께 기록한다. 로그가 없으면 원인을 좁힐 수 없다.
	if delta < FRAME_STALL_WARNING_SECONDS or _stall_reports >= 40:
		return
	_stall_reports += 1
	push_warning("[stall] 프레임 %.0fms" % (delta * 1000.0))


func _on_level_cleared() -> void:
	_stage_timer_running = false
	if UiBridge.is_hosted:
		UiBridge.post_end("clear", 0)
	var has_next: bool = _stage_index >= 0 and _stage_index + 1 < _stage_paths.size()
	if _stage_index < 0:
		clear_label.text = "LEVEL CLEAR!"
	elif has_next:
		clear_label.text = "STAGE %d CLEAR!" % (_stage_index + 1)
	else:
		clear_label.text = "ALL CLEAR!"
	clear_label.visible = true
	clear_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(clear_label, "modulate:a", 1.0, 0.35)

	if has_next and not UiBridge.is_hosted:
		var next_index: int = _stage_index + 1
		get_tree().create_timer(STAGE_ADVANCE_DELAY_SECONDS).timeout.connect(
			_load_stage.bind(next_index)
		)


func _on_host_initialize(stage_data: Dictionary) -> void:
	var config: Dictionary = stage_data.get("config", {})
	_requested_stage_index = max(0, int(stage_data.get("stage", 1)) - 1)
	_stage_time_left = maxf(1.0, float(config.get("timeLimitSeconds", DEFAULT_STAGE_TIME_SECONDS)))
	_stage_timer_running = false
	_last_reported_seconds = -1
	UiBridge.post_hud({"timeLeft": _format_stage_timer(ceili(_stage_time_left))})
	if not _stage_paths.is_empty():
		call_deferred("_load_stage", min(_requested_stage_index, _stage_paths.size() - 1))


func _on_host_start() -> void:
	_stage_timer_running = true


func _on_host_force_quit(_reason: String) -> void:
	_stage_timer_running = false


func _format_stage_timer(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


# ---------------------------------------------------------------- 스테이지 진행

# 스테이지 모드를 켜면 안 되는 경우 둘: `--script` 는 검증 하네스라 손 배치를 전제하고,
# MapGenerator 의 generate_on_play 는 시드 테스트 플레이라 그쪽이 판을 가져야 한다.
func _stage_mode_allowed() -> bool:
	if OS.get_cmdline_args().has("--script"):
		return false
	var generator: Node = get_node_or_null("MapGenerator")
	if generator != null and bool(generator.get("generate_on_play")):
		return false
	return true


func _list_stage_files() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(STAGE_LEVELS_DIR)
	if dir == null:
		return paths
	var names: Array[String] = []
	for file_name in dir.get_files():
		if file_name.begins_with("stage_") and file_name.ends_with(".json"):
			names.append(file_name)
	# 파일명이 stage_001 처럼 0채움 순번이라 사전순 = 스테이지 순이다.
	names.sort()
	for file_name in names:
		paths.append(STAGE_LEVELS_DIR + "/" + file_name)
	return paths


func _load_stage(index: int) -> void:
	var path: String = _stage_paths[index]
	var level: Dictionary = LevelLayoutWriter.load_json(path)
	if level.is_empty():
		push_error("스테이지 파일을 읽지 못했다: %s" % path)
		return
	_stage_index = index
	LevelLayoutWriter.apply_to_manager(level_manager, level)
	clear_label.visible = false
	_stage_label.text = "STAGE %d / %d" % [index + 1, _stage_paths.size()]
	_stage_label.visible = true
	print("[스테이지] %d/%d 시작 (%s)" % [index + 1, _stage_paths.size(), path])


func _setup_stage_label() -> void:
	_stage_label = Label.new()
	_stage_label.name = "StageLabel"
	_stage_label.visible = false
	_stage_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_stage_label.offset_top = 28.0
	_stage_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_label.add_theme_font_size_override("font_size", 30)
	_stage_label.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0, 1.0))
	$CanvasLayer.add_child(_stage_label)
