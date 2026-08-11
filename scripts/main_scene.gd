extends Node3D

# 이 시간을 넘긴 프레임은 로그에 상태와 함께 남긴다. 프리즈 원인을 좁히기 위한 계측이다.
const FRAME_STALL_WARNING_SECONDS := 0.25
const DRAG_CONTROLLER_SCRIPT = preload("res://scripts/drag_controller.gd")

@onready var level_manager: LevelManager = $LevelManager
@onready var clear_label: Label = $CanvasLayer/ClearLabel

var _stall_reports := 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.98, 0.90, 0.78, 1.0))

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

	# 드래그 입력은 별도 노드가 전담한다. 헤드리스 검증에서 이벤트를 직접 주입하기 쉽다.
	var drag_controller: Node = DRAG_CONTROLLER_SCRIPT.new()
	drag_controller.name = "DragController"
	drag_controller.level_manager = level_manager
	add_child(drag_controller)

	print("[boot] 로그 파일 위치: ", ProjectSettings.globalize_path("user://logs/"))


func _process(delta: float) -> void:
	# 멈춘 프레임을 그 시점의 상태와 함께 기록한다. 로그가 없으면 원인을 좁힐 수 없다.
	if delta < FRAME_STALL_WARNING_SECONDS or _stall_reports >= 40:
		return
	_stall_reports += 1
	push_warning("[stall] 프레임 %.0fms" % (delta * 1000.0))


func _on_level_cleared() -> void:
	clear_label.text = "LEVEL CLEAR!"
	clear_label.visible = true
	clear_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(clear_label, "modulate:a", 1.0, 0.35)
