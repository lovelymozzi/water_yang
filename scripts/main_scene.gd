extends Node3D

@onready var level_manager: LevelManager = $LevelManager
@onready var clear_label: Label = $CanvasLayer/ClearLabel


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


func _on_level_cleared() -> void:
	clear_label.text = "LEVEL CLEAR!"
	clear_label.visible = true
	clear_label.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(clear_label, "modulate:a", 1.0, 0.35)
