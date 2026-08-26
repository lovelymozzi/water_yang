extends SceneTree

const OUTPUT_PATH := "user://timestop_snow.png"

var _scene: Node
var _frames := 0


func _initialize() -> void:
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_scene._stage_timer_running = true
		_scene._on_host_message("item.timestop", {})
	if _frames == 30:
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		print("[timestop snow] ", ProjectSettings.globalize_path(OUTPUT_PATH))
	return _frames > 32
