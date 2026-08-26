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
	var now := Time.get_ticks_msec()
	_scene._on_host_message("item.timestop", {})
	_scene._on_host_message("item.timestop", {})
	assert(_scene._stage_timer_stop_until_msec >= now + 19900)
	var overlay = _scene.get_node("Camera3D/IceDissolveMesh") as MeshInstance3D
	assert(overlay.visible)
	var material := overlay.get_active_material(0) as ShaderMaterial
	assert(material != null)
	assert(float(material.get_shader_parameter("side_edge_size")) > 0.0)
	assert(float(material.get_shader_parameter("vertical_edge_size")) > float(material.get_shader_parameter("side_edge_size")))
	assert(float(material.get_shader_parameter("edge_gap")) >= 0.0)
	assert(float(material.get_shader_parameter("cartoon_edge_sharpness")) >= 1.0)
	var snow = _scene.get_node("Camera3D/IceDissolveSnow") as GPUParticles3D
	assert(snow.visible and snow.emitting)
	assert(snow.local_coords)
	var time_before: float = _scene._stage_time_left
	_scene._process(10.0)
	assert(is_equal_approx(_scene._stage_time_left, time_before))
	_scene._stage_timer_stop_until_msec = 0
	_scene._process(1.0)
	assert(_scene._stage_time_left < time_before)
	print("TIMESTOP OVERLAY CHECK: PASS")
	return true
