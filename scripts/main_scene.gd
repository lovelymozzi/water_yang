extends Node3D

# 이 시간을 넘긴 프레임은 로그에 상태와 함께 남긴다. 프리즈 원인을 좁히기 위한 계측이다.
const FRAME_STALL_WARNING_SECONDS := 0.25
const DRAG_CONTROLLER_SCRIPT = preload("res://scripts/drag_controller.gd")
const ITEM_REMOVE_TEXTURE = preload("res://src/assets/item_over.png")
const ITEM_MOVE_ARROW_TEXTURE = preload("res://src/assets/arrow.png")
const ITEM_TARGET_BOB_HEIGHT := 0.18
const ITEM_TARGET_BOB_SECONDS := 0.46
const ITEM_TARGET_SCALE := 1.13

# `stage_batch_generator.gd` 가 stage_001.json 부터 순번으로 저장하는 폴더.
# 파일이 하나라도 있으면 플레이는 1스테이지부터 차례로 진행한다.
const STAGE_LEVELS_DIR := "res://resources/levels"
# StageAdmin 이 "이 스테이지 플레이"로 시작 스테이지를 건네는 1회용 파일.
const DEV_STAGE_HANDOFF_PATH := "user://dev_start_stage.txt"
const STAGE_ADVANCE_DELAY_SECONDS := 1.4
const DEFAULT_STAGE_TIME_SECONDS := 60.0
const TIMEOUT_WARNING_SECONDS := 10.0
const ICE_DISSOLVE_PEAK := 0.522

# 개발용 시작 스테이지 (1부터). Inspector 에서 바꾸거나 실행 인자 `-- stage=10` 으로
# 덮어쓴다. 특정 스테이지만 다시 플레이해 볼 때 쓴다. 범위를 넘으면 마지막 스테이지다.
@export_range(1, 999) var start_stage: int = 1

@onready var level_manager: LevelManager = $LevelManager
@onready var clear_label: Label = $CanvasLayer/ClearLabel
@onready var ice_overlay: MeshInstance3D = $Camera3D/IceDissolveMesh
@onready var ice_snow_top: GPUParticles3D = $Camera3D/IceDissolveSnowTop
@onready var ice_snow_bottom: GPUParticles3D = $Camera3D/IceDissolveSnowBottom
@onready var timeout_warning_material := $CanvasLayer/TimeoutWarningOverlay.material as ShaderMaterial

var _stall_reports := 0
var _stage_paths: PackedStringArray = PackedStringArray()
# -1 은 스테이지 모드가 아니라는 뜻 (씬 손 배치나 시드 테스트 플레이).
var _stage_index: int = -1
var _stage_label: Label
var _stage_time_left := DEFAULT_STAGE_TIME_SECONDS
var _stage_timer_running := false
var _stage_timer_waiting_for_touch := false
var _stage_timer_stop_until_msec := 0
var _last_reported_seconds := -1
var _requested_stage_index := 0
# 어드민 인계 파일에서 읽은 시작 스테이지 (1부터). 0 = 인계 없음.
var _dev_stage_handoff: int = 0
# 재현용. 스테이지 파일에 함께 저장된 정답 수순과 그 재생 상태다.
var _stage_solution: Array = []
var _replay_button: Button
var _replay_index := -1
# 지금 수를 이미 눌렀는지. 누른 뒤에는 커밋될 때까지 프레임을 넘겨 줘야 한다.
var _replay_issued := false
var _ice_overlay_tween: Tween
var _drag_controller: DragController
var _obstacle_item_targets: Node3D
var _cat_item_targets: Node3D


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
	# WebGL Compatibility renders glow through lower-resolution buffers than
	# the native Forward+ renderer. Keeping the native values there spreads
	# the glow into the cat silhouettes, so restrict it to the brightest FX.
	if OS.has_feature("web"):
		runtime_environment.tonemap_exposure = 1.0
		runtime_environment.glow_hdr_threshold = 0.65
		runtime_environment.glow_intensity = 0.35
		runtime_environment.glow_strength = 0.25
		runtime_environment.glow_bloom = 0.0
	var world_environment := WorldEnvironment.new()
	world_environment.name = "RuntimeWorldEnvironment"
	world_environment.environment = runtime_environment
	add_child(world_environment)

	ice_overlay.hide()
	ice_snow_top.hide()
	ice_snow_bottom.hide()
	var ice_material := ice_overlay.get_active_material(0) as ShaderMaterial
	if ice_material == null:
		push_error("IceOverlay requires a ShaderMaterial")
	else:
		ice_material.set_shader_parameter("dissolve_amount", 0.0)

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
	UiBridge.host_pause.connect(func(_reason: String):
		_stage_timer_running = false
	)
	UiBridge.host_resume.connect(func(): _stage_timer_running = not _stage_timer_waiting_for_touch)
	UiBridge.host_force_quit.connect(_on_host_force_quit)
	UiBridge.host_message.connect(_on_host_message)

	# 드래그 입력은 별도 노드가 전담한다. 헤드리스 검증에서 이벤트를 직접 주입하기 쉽다.
	_drag_controller = DRAG_CONTROLLER_SCRIPT.new()
	_drag_controller.name = "DragController"
	_drag_controller.level_manager = level_manager
	_drag_controller.input_received.connect(func():
		if _stage_timer_waiting_for_touch:
			_stage_timer_waiting_for_touch = false
			_stage_timer_running = true
	)
	_drag_controller.obstacle_selected.connect(_on_obstacle_selected)
	_drag_controller.cat_selected.connect(_on_cat_selected)
	add_child(_drag_controller)
	_obstacle_item_targets = Node3D.new()
	_obstacle_item_targets.name = "ObstacleItemTargets"
	add_child(_obstacle_item_targets)
	_cat_item_targets = Node3D.new()
	_cat_item_targets.name = "CatItemTargets"
	add_child(_cat_item_targets)

	print("[boot] 로그 파일 위치: ", ProjectSettings.globalize_path("user://logs/"))

	# 인계 파일은 스테이지 모드 여부와 **무관하게** 여기서 먼저 먹어 치운다. 조건 안에서만
	# 읽으면 generate_on_play 가 켜져 있을 때 파일이 남아, 다음 평범한 실행이 엉뚱한
	# 스테이지에서 시작한다.
	_dev_stage_handoff = _consume_dev_stage_handoff()
	_setup_stage_label()
	_setup_replay_button()
	if _stage_mode_allowed():
		_stage_paths = _list_stage_files()
		if not _stage_paths.is_empty():
			# LevelManager 가 자기 _ready 의 씬 배치 처리를 끝낸 뒤에 갈아 끼운다.
			call_deferred(
				"_load_stage", clampi(_dev_start_stage() - 1, 0, _stage_paths.size() - 1)
			)


func _process(delta: float) -> void:
	if _replay_index >= 0:
		_advance_replay()

	if _stage_timer_running and Time.get_ticks_msec() >= _stage_timer_stop_until_msec:
		_stage_time_left = maxf(0.0, _stage_time_left - delta)
		var seconds_left := ceili(_stage_time_left)
		if seconds_left != _last_reported_seconds:
			_last_reported_seconds = seconds_left
			UiBridge.post_hud({"timeLeft": _format_stage_timer(seconds_left)})
		if seconds_left == 0:
			_stage_timer_running = false
			if UiBridge.is_hosted:
				UiBridge.post_progress({"outcome": "fail", "score": 0})

	var warning_strength := 0.0
	if _stage_timer_running:
		var urgency := clampf((TIMEOUT_WARNING_SECONDS - _stage_time_left) / TIMEOUT_WARNING_SECONDS, 0.0, 1.0)
		warning_strength = urgency * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012))
	timeout_warning_material.set_shader_parameter("strength", warning_strength)

	# 멈춘 프레임을 그 시점의 상태와 함께 기록한다. 로그가 없으면 원인을 좁힐 수 없다.
	if delta < FRAME_STALL_WARNING_SECONDS or _stall_reports >= 40:
		return
	_stall_reports += 1
	push_warning("[stall] 프레임 %.0fms" % (delta * 1000.0))


func _on_level_cleared() -> void:
	_stage_timer_running = false
	if UiBridge.is_hosted:
		UiBridge.post_progress({"outcome": "clear", "score": 0})
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
	if not visible:
		return
	var config: Dictionary = stage_data.get("config", {})
	var requested: int = int(stage_data.get("stage", 1))
	if not UiBridge.is_hosted:
		# 스탠드얼론 부트의 stage 는 항상 1인 스텁이라, 개발용 시작 스테이지가 우선한다.
		requested = maxi(requested, _dev_start_stage())
	_requested_stage_index = max(0, requested - 1)
	_stage_time_left = maxf(1.0, float(config.get("timeLimitSeconds", DEFAULT_STAGE_TIME_SECONDS)))
	_stage_timer_running = false
	_stage_timer_waiting_for_touch = false
	_stage_timer_stop_until_msec = 0
	_last_reported_seconds = -1
	_clear_item_targets(_obstacle_item_targets)
	_clear_item_targets(_cat_item_targets)
	_drag_controller.cancel_item_selection()
	UiBridge.post_hud({"timeLeft": _format_stage_timer(ceili(_stage_time_left))})
	if not _stage_paths.is_empty():
		call_deferred("_load_stage", min(_requested_stage_index, _stage_paths.size() - 1))


func _on_host_start() -> void:
	_stage_timer_running = false
	_stage_timer_waiting_for_touch = true
	_stage_timer_stop_until_msec = 0


func _on_host_force_quit(_reason: String) -> void:
	_stage_timer_running = false
	_stage_timer_waiting_for_touch = false
	_stage_timer_stop_until_msec = 0
	_clear_item_targets(_obstacle_item_targets)
	_clear_item_targets(_cat_item_targets)
	_drag_controller.cancel_item_selection()


func _on_host_message(topic: String, payload) -> void:
	if topic == "continue_stage":
		_stage_time_left = maxf(1.0, float(payload.get("timeLimitSeconds", DEFAULT_STAGE_TIME_SECONDS)))
		_stage_timer_running = false
		_stage_timer_waiting_for_touch = true
		_stage_timer_stop_until_msec = 0
		_last_reported_seconds = -1
		_clear_item_targets(_obstacle_item_targets)
		_clear_item_targets(_cat_item_targets)
		UiBridge.post_hud({"timeLeft": _format_stage_timer(ceili(_stage_time_left))})
		return
	if topic == "item.cancel":
		var cancelled_item := str(payload.get("item", ""))
		_clear_item_targets(_obstacle_item_targets)
		_clear_item_targets(_cat_item_targets)
		_drag_controller.cancel_item_selection()
		if cancelled_item == "remove" or cancelled_item == "move":
			UiBridge.post_progress({"itemRejected": cancelled_item})
		return
	if topic.begins_with("item.") and _stage_timer_waiting_for_touch:
		_stage_timer_waiting_for_touch = false
		_stage_timer_running = true
	if topic == "item.remove":
		if level_manager.get_obstacle_cells().is_empty():
			UiBridge.post_progress({"itemRejected": "remove"})
			return
		_show_obstacle_item_targets()
		_drag_controller.begin_obstacle_selection()
		return
	if topic == "item.timestop":
		if not _stage_timer_running:
			UiBridge.post_progress({"itemRejected": "timestop"})
			return
		var now := Time.get_ticks_msec()
		_stage_timer_stop_until_msec = maxi(_stage_timer_stop_until_msec, now) + 10000
		_on_host_message("use_ice", {"duration": float(_stage_timer_stop_until_msec - now) / 1000.0})
		UiBridge.post_progress({"itemUsed": "timestop"})
		return
	if topic == "item.move":
		if not _show_cat_item_targets():
			UiBridge.post_progress({"itemRejected": "move"})
			return
		_drag_controller.begin_cat_selection()
		return
	if topic != "use_ice":
		return
	if _ice_overlay_tween != null:
		_ice_overlay_tween.kill()
	var material := ice_overlay.get_active_material(0) as ShaderMaterial
	if material == null:
		push_error("IceOverlay requires a ShaderMaterial")
		return
	var duration := maxf(0.95, float(payload.get("duration", 1.4)))
	if UiBridge.is_hosted:
		UiBridge.post_progress({"sfx": "ice-freezing"})
	ice_overlay.visible = true
	for snow in [ice_snow_top, ice_snow_bottom]:
		snow.show()
		snow.emitting = true
		snow.restart()
	material.set_shader_parameter("dissolve_amount", 0.0)
	_ice_overlay_tween = create_tween()
	_ice_overlay_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_ice_overlay_tween.tween_property(material, "shader_parameter/dissolve_amount", ICE_DISSOLVE_PEAK, 0.25)
	_ice_overlay_tween.tween_interval(duration - 0.95)
	_ice_overlay_tween.tween_property(material, "shader_parameter/dissolve_amount", 0.0, 0.7)
	_ice_overlay_tween.tween_callback(func():
		if UiBridge.is_hosted:
			UiBridge.post_progress({"sfx": "ice-freezing"})
	)
	_ice_overlay_tween.tween_callback(ice_overlay.hide)
	_ice_overlay_tween.tween_callback(ice_snow_top.hide)
	_ice_overlay_tween.tween_callback(ice_snow_bottom.hide)


func _show_obstacle_item_targets() -> void:
	_clear_item_targets(_obstacle_item_targets)
	for cell in level_manager.get_obstacle_cells():
		var target := Sprite3D.new()
		target.texture = ITEM_REMOVE_TEXTURE
		target.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		target.pixel_size = 0.00392
		target.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		target.no_depth_test = true
		target.position = level_manager.grid_to_world(
			cell, LevelManager.TILE_HEIGHT + level_manager.obstacle_fbx_height + 0.35
		)
		_obstacle_item_targets.add_child(target)
		_animate_item_target(target)


func _clear_item_targets(targets: Node3D) -> void:
	if targets == null:
		return
	for target in targets.get_children():
		targets.remove_child(target)
		target.queue_free()


func _animate_item_target(target: Node3D) -> void:
	var base_y := target.position.y
	var base_scale := target.scale
	var bob := create_tween().bind_node(target).set_loops()
	bob.tween_property(target, "position:y", base_y + ITEM_TARGET_BOB_HEIGHT, ITEM_TARGET_BOB_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(target, "position:y", base_y - ITEM_TARGET_BOB_HEIGHT * 0.45, ITEM_TARGET_BOB_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(target, "position:y", base_y, ITEM_TARGET_BOB_SECONDS * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var squash := create_tween().bind_node(target).set_loops()
	squash.tween_property(target, "scale", base_scale * ITEM_TARGET_SCALE, ITEM_TARGET_BOB_SECONDS * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	squash.tween_property(target, "scale", base_scale, ITEM_TARGET_BOB_SECONDS * 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_obstacle_selected(cell: Vector2i) -> void:
	if level_manager.remove_obstacle(cell):
		UiBridge.post_progress({"itemUsed": "remove", "sfx": "digging"})
	_clear_item_targets(_obstacle_item_targets)


func _show_cat_item_targets() -> bool:
	_clear_item_targets(_cat_item_targets)
	for cat in level_manager.get_cats():
		if cat.is_absorbing() or level_manager.get_open_hole_for_color(cat.color_id) == null:
			continue
		var arrow := Sprite3D.new()
		arrow.texture = ITEM_MOVE_ARROW_TEXTURE
		arrow.pixel_size = 0.008
		arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		arrow.no_depth_test = true
		arrow.position = level_manager.grid_to_world(
			cat.get_head_cell() + Vector2i.UP, level_manager.cat_world_y + 0.35
		) + Vector3(0.0, 0.0, level_manager.fitted_tile_size() * 0.25)
		_cat_item_targets.add_child(arrow)
		_animate_item_target(arrow)
	return not _cat_item_targets.get_children().is_empty()


func _on_cat_selected(cat: CatEntity) -> void:
	var hole: Variant = level_manager.get_open_hole_for_color(cat.color_id)
	if hole != null and cat.clear_with_item(hole as Vector2i):
		UiBridge.post_progress({"itemUsed": "move"})
	else:
		UiBridge.post_progress({"itemRejected": "move"})
	_clear_item_targets(_cat_item_targets)


func _format_stage_timer(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


# ---------------------------------------------------------------- 스테이지 진행

# 스테이지 모드를 켜면 안 되는 경우 둘: `--script` 는 검증 하네스라 손 배치를 전제하고,
# MapGenerator 의 generate_on_play 는 시드 테스트 플레이라 그쪽이 판을 가져야 한다.
# 개발용 시작 스테이지 (1부터). 우선순위는 어드민 인계 > 실행 인자 `-- stage=N` > Inspector.
func _dev_start_stage() -> int:
	if _dev_stage_handoff > 0:
		return _dev_stage_handoff
	var requested: int = start_stage
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("stage="):
			requested = int(arg.substr(6))
	return requested


# StageAdmin 의 "이 스테이지 플레이"가 남긴 1회용 인계 파일. 에디터 플러그인은 실행에
# 인자를 넘길 수 없어서 파일로 건넨다. **읽는 즉시 지운다** — 남으면 다음 실행이 계속
# 그 스테이지에서 시작해 버린다. 없으면 0.
func _consume_dev_stage_handoff() -> int:
	if not FileAccess.file_exists(DEV_STAGE_HANDOFF_PATH):
		return 0
	var file: FileAccess = FileAccess.open(DEV_STAGE_HANDOFF_PATH, FileAccess.READ)
	var value: int = 0
	if file != null:
		value = int(file.get_as_text().strip_edges())
		file.close()
	DirAccess.remove_absolute(DEV_STAGE_HANDOFF_PATH)
	return value


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
	_stage_solution = level.get("solution", [])
	clear_label.visible = false
	_stage_label.text = "STAGE %d / %d" % [index + 1, _stage_paths.size()]
	_stage_label.visible = true
	# 정답이 함께 저장된 스테이지에서만 재현 버튼을 띄운다.
	_replay_button.visible = not _stage_solution.is_empty()
	_replay_button.text = "정답 재현 (%d수)" % _stage_solution.size()
	if UiBridge.is_hosted:
		UiBridge.post_progress({"stage": index + 1})
	print("[스테이지] %d/%d 시작 (%s)" % [index + 1, _stage_paths.size(), path])


# ---------------------------------------------------------------- 정답 재현

# 스테이지 파일의 `solution` 을 실제 고양이에게 눌러 넣어 정답을 눈으로 보여 준다.
#
# **자동 재생용 별도 경로를 만들지 않는다.** 사람이 드래그할 때와 똑같이
# `begin_drag()` → `request_path_to()` 만 쓰고, 움직이는 것은 `CatEntity._process()` 의
# `advance()` 가 한다. 그래서 재현이 성공한다는 것은 곧 그 수순을 사람이 따라 해도
# 클리어된다는 뜻이다. (헤드리스 버전은 `tests/stage_replay_check.gd`.)
#
# 한 프레임에 한 수만 밀어 넣고, 리드가 목표 칸에 도착할 때까지 기다린다. 몰아서 넣으면
# `begin_drag()` 가 이전 수의 큐를 지워 버려 수순이 어긋난다.
func _setup_replay_button() -> void:
	_replay_button = Button.new()
	_replay_button.name = "ReplayButton"
	_replay_button.text = "정답 재현"
	_replay_button.visible = false
	_replay_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_replay_button.offset_left = -132.0
	_replay_button.offset_top = 24.0
	_replay_button.offset_right = -24.0
	_replay_button.offset_bottom = 64.0
	_replay_button.pressed.connect(_on_replay_pressed)
	$CanvasLayer.add_child(_replay_button)


func _on_replay_pressed() -> void:
	if _stage_index < 0 or _stage_solution.is_empty():
		return
	# 판을 시작 상태로 되돌리고 다음 프레임부터 누른다. 다시 심은 고양이 노드가
	# `_ready` 를 지나야 드래그를 받을 수 있다.
	_load_stage(_stage_index)
	_replay_index = 0
	_replay_issued = false
	_replay_button.disabled = true
	print("[재현] 스테이지 %d 정답 %d수 재생 시작" % [_stage_index + 1, _stage_solution.size()])


func _advance_replay() -> void:
	if _replay_index >= _stage_solution.size():
		_stop_replay("%d수 재생 완료" % _stage_solution.size())
		return
	var move: Dictionary = _stage_solution[_replay_index]
	var cat: CatEntity = _find_replay_cat(int(move["cat_id"]))

	if not _replay_issued:
		if cat == null:
			_stop_replay(
				"%d번째 수: 고양이 %d 가 이미 나갔다" % [_replay_index + 1, int(move["cat_id"])]
			)
			return
		# 움직일 끝이 뒤끝이면 리드를 그쪽으로 넘긴다. 앞끝이면 잔여 큐만 비운다.
		cat.begin_drag(move["from_end_cell"])
		if cat.body_cells.is_empty() or cat.body_cells[0] != move["from_end_cell"]:
			_stop_replay(
				"%d번째 수: 고양이 %d 의 끝이 %s 가 아니다 (몸 %s)" % [
					_replay_index + 1, int(move["cat_id"]),
					move["from_end_cell"], cat.body_cells,
				]
			)
			return
		cat.request_path_to(move["to_cell"])
		_replay_issued = true
		return

	# 이 수가 흡입으로 끝나면 고양이가 사라진다. 그건 실패가 아니라 그 수의 성공이다.
	# 흡입 연출이 끝날 때까지(노드가 해제될 때까지) 기다린 뒤 다음 수로 넘어간다.
	if cat == null:
		_replay_index += 1
		_replay_issued = false
		return
	if cat.is_absorbing():
		return
	if cat.is_blocked():
		_stop_replay("%d번째 수가 막혔다: 고양이 %d → %s" % [
			_replay_index + 1, int(move["cat_id"]), move["to_cell"],
		])
		return
	if cat.body_cells[0] != move["to_cell"]:
		return
	_replay_index += 1
	_replay_issued = false


# 흡입이 끝나 노드가 해제된 고양이는 null 이다. 그 상태로 다음 수가 그 고양이를
# 가리키면 수순이 어긋난 것이므로 조용히 넘기지 않는다.
func _find_replay_cat(cat_id: int) -> CatEntity:
	var cats_root: Node = level_manager.get_node_or_null("LayoutCats")
	if cats_root == null:
		return null
	var cat: CatEntity = cats_root.get_node_or_null("Cat_%d" % cat_id) as CatEntity
	if is_instance_valid(cat):
		return cat
	# 중첩 고양이는 겉껍질이 사라진 뒤 Cat_<id>Inner(3중첩이면 InnerInner)로 남는다.
	# 기록된 풀이의 cat_id는 같은 논리 고양이를 계속 가리키므로, 살아 있는 안쪽을 찾는다.
	var prefix: String = "Cat_%dInner" % cat_id
	for child in cats_root.get_children():
		if child is CatEntity and String(child.name).begins_with(prefix) and is_instance_valid(child):
			return child as CatEntity
	return null


func _stop_replay(reason: String) -> void:
	_replay_index = -1
	_replay_issued = false
	_replay_button.disabled = false
	print("[재현] ", reason)


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
