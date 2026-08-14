extends SceneTree

const OUTPUT_PATH := "user://main_scene_shadow_render.png"

var _frames := 0


func _initialize() -> void:
	var scene := load("res://scenes/main_scene.tscn") as PackedScene
	if scene == null:
		push_error("Failed to load main_scene.tscn")
		quit(1)
		return
	root.add_child(scene.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 24:
		var image := root.get_texture().get_image()
		if image != null:
			image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
			print("MAIN SCENE SHADOW RENDER:", ProjectSettings.globalize_path(OUTPUT_PATH))
		quit()
		return true
	return false
