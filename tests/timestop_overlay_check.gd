extends SceneTree

var _scene: Node
var _frames := 0


func _initialize() -> void:
	_scene = (load("res://scenes/main_scene.tscn") as PackedScene).instantiate()
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 10:
		return false
	_scene._stage_timer_running = true
	_scene._on_host_message("item.timestop", {})
	_scene._on_host_message("item.timestop", {})
	assert(is_equal_approx(_scene._stage_timer_stop_remaining, 20.0))
	assert(_scene.get_node("CanvasLayer/IceOverlay").visible)
	print("TIMESTOP OVERLAY CHECK: PASS")
	return true
