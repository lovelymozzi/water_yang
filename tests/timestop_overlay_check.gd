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
	_scene._stage_timer_waiting_for_touch = true
	var initial_overlay = _scene.get_node("Camera3D/IceDissolveMesh") as MeshInstance3D
	assert(not initial_overlay.visible)
	assert(not (_scene.get_node("Camera3D/IceDissolveSnowTop") as GPUParticles3D).visible)
	assert(not (_scene.get_node("Camera3D/IceDissolveSnowBottom") as GPUParticles3D).visible)
	var now := Time.get_ticks_msec()
	_scene._on_host_message("item.timestop", {})
	assert(_scene._stage_timer_running)
	assert(not _scene._stage_timer_waiting_for_touch)
	_scene._on_host_message("item.timestop", {})
	assert(_scene._stage_timer_stop_until_msec >= now + 19900)
	var overlay = _scene.get_node("Camera3D/IceDissolveMesh") as MeshInstance3D
	assert(overlay.visible)
	var material := overlay.get_active_material(0) as ShaderMaterial
	assert(material != null)
	assert(float(material.get_shader_parameter("side_edge_size")) > 0.0)
	assert(float(material.get_shader_parameter("vertical_edge_size")) > float(material.get_shader_parameter("side_edge_size")))
	assert(float(material.get_shader_parameter("vertical_edge_curve")) > 0.0)
	assert(float(material.get_shader_parameter("edge_gap")) >= 0.0)
	assert(float(material.get_shader_parameter("cartoon_edge_sharpness")) >= 1.0)
	assert(material.get_shader_parameter("fractal_noise_texture") != null)
	assert(float(material.get_shader_parameter("inner_frost_size")) >= 0.12)
	assert(material.get_shader_parameter("overlay_texture") != null)
	assert(int(material.get_shader_parameter("texture_blend_mode")) in [0, 1])
	for snow_name in ["IceDissolveSnowTop", "IceDissolveSnowBottom"]:
		var snow = _scene.get_node("Camera3D/%s" % snow_name) as GPUParticles3D
		assert(snow.visible and snow.emitting and snow.local_coords)
		var snow_process := snow.process_material as ParticleProcessMaterial
		assert(snow_process != null)
		assert(snow_process.scale_min <= snow_process.scale_max)
		assert(snow_process.angular_velocity_min > 0.0 and snow_process.angular_velocity_max > snow_process.angular_velocity_min)
		var snow_mesh := snow.draw_pass_1 as QuadMesh
		assert(snow_mesh != null and snow_mesh.size.x <= 0.181)
		var snow_material := snow_mesh.material as ShaderMaterial
		assert(snow_material != null)
		assert(float(snow_material.get_shader_parameter("rotation_speed")) > 0.0)
		assert(float(snow_material.get_shader_parameter("flicker_speed")) > 0.0)
	var time_before: float = _scene._stage_time_left
	_scene._process(10.0)
	assert(is_equal_approx(_scene._stage_time_left, time_before))
	_scene._stage_timer_stop_until_msec = 0
	_scene._process(1.0)
	assert(_scene._stage_time_left < time_before)
	print("TIMESTOP OVERLAY CHECK: PASS")
	return true
