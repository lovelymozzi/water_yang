extends SceneTree

const OUTPUT_PATH := "user://shadertoy_dissolve.png"
const SOURCE_OUTPUT_PATH := "user://shadertoy_dissolve_source.png"

var _scene: Node
var _frames := 0


func _initialize() -> void:
	_scene = (load("res://tests/shadertoy_dissolve_test.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		var image := root.get_texture().get_image()
		image.save_png(OUTPUT_PATH)
		var source := (_scene.get_node("SubViewport") as SubViewport).get_texture().get_image()
		source.save_png(SOURCE_OUTPUT_PATH)
		print("[shadertoy-dissolve] ", ProjectSettings.globalize_path(OUTPUT_PATH))
		print("[shadertoy-dissolve-source] ", ProjectSettings.globalize_path(SOURCE_OUTPUT_PATH))
		quit()
	return false
